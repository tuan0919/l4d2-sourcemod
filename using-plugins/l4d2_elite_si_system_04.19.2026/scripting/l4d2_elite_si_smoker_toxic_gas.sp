#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <actions>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_SMOKER 1

#define ELITE_SUBTYPE_SMOKER_TOXIC_GAS 29

#define TOXIC_GAS_INTERVAL 0.5

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvSpeedMultiplier;
ConVar g_cvCloudCooldown;
ConVar g_cvCloudDuration;
ConVar g_cvCloudRadius;
ConVar g_cvCloudDamagePerSecond;
ConVar g_cvHintEnable;
ConVar g_cvHintColor;
ConVar g_cvHintInterval;

bool g_bHasEliteApi;
float g_fNextCloudAt[MAXPLAYERS + 1];
float g_fCloudUntil[MAXPLAYERS + 1];
float g_vecCloudOrigin[MAXPLAYERS + 1][3];
float g_fLastHintAt[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Smoker Toxic Gas",
	author = "OpenCode",
	description = "Toxic Gas subtype module for elite Smoker bots.",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, errMax, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	MarkNativeAsOptional("EliteSI_IsElite");
	MarkNativeAsOptional("EliteSI_GetSubtype");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_smoker_toxic_gas_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSpeedMultiplier = CreateConVar("l4d2_elite_si_smoker_toxic_gas_speed_multiplier", "1.2", "Movement speed multiplier for Toxic Gas smoker bot.", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvCloudCooldown = CreateConVar("l4d2_elite_si_smoker_toxic_gas_cloud_cooldown", "10.0", "Cooldown in seconds before shove-triggered toxic cloud can trigger again.", FCVAR_NOTIFY, true, 0.0, true, 60.0);
	g_cvCloudDuration = CreateConVar("l4d2_elite_si_smoker_toxic_gas_cloud_duration", "8.0", "Duration in seconds for toxic smoke cloud.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvCloudRadius = CreateConVar("l4d2_elite_si_smoker_toxic_gas_cloud_radius", "180.0", "Radius of the toxic smoke cloud.", FCVAR_NOTIFY, true, 50.0, true, 1000.0);
	g_cvCloudDamagePerSecond = CreateConVar("l4d2_elite_si_smoker_toxic_gas_damage_per_second", "3.0", "Damage per second dealt to survivors inside toxic smoke.", FCVAR_NOTIFY, true, 0.1, true, 50.0);
	g_cvHintEnable = CreateConVar("l4d2_elite_si_smoker_toxic_gas_hint_enable", "1", "0=Off, 1=Show instructor hint to survivors taking toxic gas damage.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvHintColor = CreateConVar("l4d2_elite_si_smoker_toxic_gas_hint_color", "80 80 80", "Instructor hint color for toxic gas damage in format 'R G B'.", FCVAR_NOTIFY);
	g_cvHintInterval = CreateConVar("l4d2_elite_si_smoker_toxic_gas_hint_interval", "1.5", "Minimum interval in seconds between toxic gas hints per survivor.", FCVAR_NOTIFY, true, 0.1, true, 10.0);

	CreateConVar("l4d2_elite_si_smoker_toxic_gas_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_smoker_toxic_gas");

	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);

	CreateTimer(TOXIC_GAS_INTERVAL, Timer_ToxicGasThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

	RefreshEliteState();
	ResetAllState();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_PreThinkPost, OnSmokerThinkPost);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnSmokerThinkPost);
}

public void OnMapStart()
{
	ResetAllState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
	}
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

public void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int smoker = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsValidAliveSurvivor(attacker) || !ShouldApplyToxicGas(smoker, true))
	{
		return;
	}

	float now = GetGameTime();
	if (now < g_fNextCloudAt[smoker])
	{
		return;
	}

	ReleaseToxicCloud(smoker, false);
	g_fNextCloudAt[smoker] = now + g_cvCloudCooldown.FloatValue;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int smoker = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplyToxicGas(smoker, false))
	{
		return;
	}

	ReleaseToxicCloud(smoker, true);
	g_fNextCloudAt[smoker] = 0.0;
}

public void OnSmokerThinkPost(int client)
{
	if (!ShouldApplyToxicGas(client, true))
	{
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvSpeedMultiplier.FloatValue);
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 250.0 * g_cvSpeedMultiplier.FloatValue);

	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (IsValidEntity(ability))
	{
		SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + 9999.0);
	}
	}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	if (strncmp(name, "Smoker", 6) != 0 || strcmp(name[6], "Attack") != 0)
	{
		return;
	}

	if (!ShouldApplyToxicGas(actor, false))
	{
		return;
	}

	action.OnCommandAssault = ToxicGas_OnCommandAssault;
	action.OnCommandAttack = ToxicGas_OnCommandAttack;
	action.OnCommandApproachByEntity = ToxicGas_OnCommandApproachByEntity;
	action.ShouldAttack = ToxicGas_ShouldAttack;
	action.ShouldRetreat = ToxicGas_ShouldRetreat;
	action.OnShoved = ToxicGas_OnShoved;
	action.OnKilled = ToxicGas_OnKilled;
	action.OnUpdate = ToxicGas_OnUpdate;
}

Action ToxicGas_OnCommandAssault(any action, int actor, ActionDesiredResult result)
{
	if (!ShouldApplyToxicGas(actor, true))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action ToxicGas_OnCommandAttack(any action, int actor, int entity, ActionDesiredResult result)
{
	if (!ShouldApplyToxicGas(actor, true))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action ToxicGas_OnCommandApproachByEntity(any action, int actor, int goal, ActionDesiredResult result)
{
	if (!ShouldApplyToxicGas(actor, true))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action ToxicGas_ShouldAttack(any action, any nextbot, any knownEntity, QueryResultType &result)
{
	int actor = view_as<int>(nextbot);
	if (!ShouldApplyToxicGas(actor, true))
	{
		return Plugin_Continue;
	}

	result = ANSWER_YES;
	return Plugin_Handled;
}

Action ToxicGas_ShouldRetreat(any action, any nextbot, QueryResultType &result)
{
	int actor = view_as<int>(nextbot);
	if (!ShouldApplyToxicGas(actor, true))
	{
		return Plugin_Continue;
	}

	result = ANSWER_NO;
	return Plugin_Handled;
}

Action ToxicGas_OnShoved(any action, int actor, int entity, ActionDesiredResult result)
{
	if (!ShouldApplyToxicGas(actor, true) || !IsValidAliveSurvivor(entity))
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	if (now >= g_fNextCloudAt[actor])
	{
		ReleaseToxicCloud(actor, false);
		g_fNextCloudAt[actor] = now + g_cvCloudCooldown.FloatValue;
	}

	return Plugin_Continue;
}

Action ToxicGas_OnKilled(any action, int actor, any takedamageinfo, ActionDesiredResult result)
{
	if (!ShouldApplyToxicGas(actor, false))
	{
		return Plugin_Continue;
	}

	ReleaseToxicCloud(actor, true);
	g_fNextCloudAt[actor] = 0.0;
	return Plugin_Continue;
}

Action ToxicGas_OnUpdate(any action, int actor, float interval, ActionResult result)
{
	if (!ShouldApplyToxicGas(actor, true))
	{
		return Plugin_Continue;
	}

	TryApproachClosestSurvivor(actor);
	return Plugin_Continue;
}

public Action Timer_ToxicGasThink(Handle timer)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	float radius = g_cvCloudRadius.FloatValue;
	float damage = g_cvCloudDamagePerSecond.FloatValue * TOXIC_GAS_INTERVAL;

	for (int smoker = 1; smoker <= MaxClients; smoker++)
	{
		if (g_fCloudUntil[smoker] <= now)
		{
			continue;
		}

		int damageSource = 0;
		bool hasLiveOwner = false;
		if (smoker > 0 && smoker <= MaxClients && IsClientInGame(smoker) && IsPlayerAlive(smoker))
		{
			damageSource = smoker;
			hasLiveOwner = true;
		}

		for (int survivor = 1; survivor <= MaxClients; survivor++)
		{
			if (!IsValidAliveSurvivor(survivor))
			{
				continue;
			}

			float origin[3];
			GetClientAbsOrigin(survivor, origin);
			if (GetVectorDistance(origin, g_vecCloudOrigin[smoker]) > radius)
			{
				continue;
			}

			if (hasLiveOwner)
			{
				SDKHooks_TakeDamage(survivor, damageSource, damageSource, damage, DMG_POISON);
			}
			else
			{
				ApplyWorldToxicDamage(survivor, damage);
			}
			MaybeDisplayGasHint(survivor, now);
		}
	}

	return Plugin_Continue;
}

void ReleaseToxicCloud(int smoker, bool onDeath)
{
	float origin[3];
	GetClientAbsOrigin(smoker, origin);
	g_vecCloudOrigin[smoker] = origin;
	g_fCloudUntil[smoker] = GetGameTime() + g_cvCloudDuration.FloatValue;

	CreateSmokeParticle(origin, onDeath ? 8.0 : g_cvCloudDuration.FloatValue);
}

void ApplyWorldToxicDamage(int survivor, float damage)
{
	if (!IsValidAliveSurvivor(survivor) || damage <= 0.0)
	{
		return;
	}

	int currentHealth = GetClientHealth(survivor);
	if (currentHealth <= 1)
	{
		SDKHooks_TakeDamage(survivor, 0, 0, float(currentHealth), DMG_POISON);
		return;
	}

	int damageInt = RoundToCeil(damage);
	if (damageInt < 1)
	{
		damageInt = 1;
	}

	int nextHealth = currentHealth - damageInt;
	if (nextHealth < 1)
	{
		nextHealth = 1;
	}

	SetEntityHealth(survivor, nextHealth);
}

void TryApproachClosestSurvivor(int smoker)
{
	int target = FindClosestSurvivor(smoker);
	if (target <= 0)
	{
		return;
	}

	float smokerOrigin[3];
	float targetOrigin[3];
	GetClientAbsOrigin(smoker, smokerOrigin);
	GetClientAbsOrigin(target, targetOrigin);

	float distance = GetVectorDistance(smokerOrigin, targetOrigin);
	if (distance <= 90.0)
	{
		return;
	}

	float direction[3];
	MakeVectorFromPoints(smokerOrigin, targetOrigin, direction);
	NormalizeVector(direction, direction);

	float speed = 250.0 * g_cvSpeedMultiplier.FloatValue;
	float velocity[3];
	velocity[0] = direction[0] * speed;
	velocity[1] = direction[1] * speed;
	velocity[2] = 0.0;
	TeleportEntity(smoker, NULL_VECTOR, NULL_VECTOR, velocity);
}

int FindClosestSurvivor(int smoker)
{
	float smokerOrigin[3];
	GetClientAbsOrigin(smoker, smokerOrigin);

	int closest = 0;
	float closestDistance = 999999.0;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float survivorOrigin[3];
		GetClientAbsOrigin(survivor, survivorOrigin);
		float distance = GetVectorDistance(smokerOrigin, survivorOrigin);
		if (distance < closestDistance)
		{
			closestDistance = distance;
			closest = survivor;
		}
	}

	return closest;
}

void CreateSmokeParticle(const float origin[3], float lifetime)
{
	int entity = CreateEntityByName("info_particle_system");
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return;
	}

	DispatchKeyValue(entity, "effect_name", "smoker_smokecloud");
	DispatchSpawn(entity);
	TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Start");
	CreateTimer(lifetime, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

void MaybeDisplayGasHint(int survivor, float now)
{
	if (!g_cvHintEnable.BoolValue)
	{
		return;
	}

	if (now - g_fLastHintAt[survivor] < g_cvHintInterval.FloatValue)
	{
		return;
	}

	g_fLastHintAt[survivor] = now;

	char color[32];
	g_cvHintColor.GetString(color, sizeof(color));
	if (color[0] == '\0')
	{
		strcopy(color, sizeof(color), "80 80 80");
	}

	DisplayInstructorHint(survivor, "Toxic gas! Roi khoi lan khoi den ngay.", "icon_alert", color);
}

void DisplayInstructorHint(int target, const char[] text, const char[] icon, const char[] color)
{
	int entity = CreateEntityByName("env_instructor_hint");
	if (entity <= 0)
	{
		return;
	}

	char key[32];
	FormatEx(key, sizeof(key), "hintToxicGas%d", target);
	DispatchKeyValue(target, "targetname", key);
	DispatchKeyValue(entity, "hint_target", key);
	DispatchKeyValue(entity, "hint_static", "false");
	DispatchKeyValue(entity, "hint_timeout", "2.0");
	DispatchKeyValue(entity, "hint_icon_offset", "0.1");
	DispatchKeyValue(entity, "hint_range", "0.1");
	DispatchKeyValue(entity, "hint_nooffscreen", "true");
	DispatchKeyValue(entity, "hint_icon_onscreen", icon);
	DispatchKeyValue(entity, "hint_icon_offscreen", icon);
	DispatchKeyValue(entity, "hint_forcecaption", "true");
	DispatchKeyValue(entity, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(entity, "hint_instance_type", "0");
	DispatchKeyValue(entity, "hint_color", color);
	DispatchKeyValue(entity, "hint_caption", text);

	DispatchSpawn(entity);
	AcceptEntityInput(entity, "ShowHint", target);
	CreateTimer(2.0, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillEntity(Handle timer, int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}

	return Plugin_Stop;
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i);
	}
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_fNextCloudAt[client] = 0.0;
	g_fCloudUntil[client] = 0.0;
	g_fLastHintAt[client] = 0.0;
	g_vecCloudOrigin[client][0] = 0.0;
	g_vecCloudOrigin[client][1] = 0.0;
	g_vecCloudOrigin[client][2] = 0.0;
}

bool ShouldApplyToxicGas(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SMOKER)
	{
		return false;
	}

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SMOKER_TOXIC_GAS;
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
