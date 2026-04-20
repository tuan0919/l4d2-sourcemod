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

#define MAX_TOXIC_CLOUDS 32
#define TOXIC_GAS_ATTRIBUTION_WINDOW 4.0

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvSpeedMultiplier;
ConVar g_cvCloudCooldown;
ConVar g_cvCloudDuration;
ConVar g_cvCloudRadius;
ConVar g_cvCloudDamagePerSecond;
ConVar g_cvDamageInterval;
ConVar g_cvHintEnable;
ConVar g_cvHintColor;
ConVar g_cvHintInterval;

bool g_bHasEliteApi;
bool g_bTrackedToxicGas[MAXPLAYERS + 1];
bool g_bDeathCloudTriggered[MAXPLAYERS + 1];
float g_fNextCloudAt[MAXPLAYERS + 1];
float g_fLastHintAt[MAXPLAYERS + 1];
bool g_bCloudActive[MAX_TOXIC_CLOUDS];
float g_fCloudExpireAt[MAX_TOXIC_CLOUDS];
float g_vecCloudOrigin[MAX_TOXIC_CLOUDS][3];
int g_iCloudOwner[MAX_TOXIC_CLOUDS];
int g_iCloudEntity[MAX_TOXIC_CLOUDS];
int g_iLastGasOwner[MAXPLAYERS + 1];
float g_fLastGasDamageAt[MAXPLAYERS + 1];

#define TOXIC_GAS_CAUSE_NONE 0
#define TOXIC_GAS_CAUSE_CLOUD 1


Handle g_hDamageThinkTimer;

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

	CreateNative("EliteSI_ToxicGas_GetRecentDamageCause", Native_GetRecentDamageCause);
	CreateNative("EliteSI_ToxicGas_GetRecentDamageAttacker", Native_GetRecentDamageAttacker);

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_smoker_toxic_gas_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSpeedMultiplier = CreateConVar("l4d2_elite_si_smoker_toxic_gas_speed_multiplier", "1.2", "Movement speed multiplier for Toxic Gas smoker bot.", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvCloudCooldown = CreateConVar("l4d2_elite_si_smoker_toxic_gas_cloud_cooldown", "10.0", "Cooldown in seconds before shove-triggered toxic cloud can trigger again.", FCVAR_NOTIFY, true, 0.0, true, 60.0);
	g_cvCloudDuration = CreateConVar("l4d2_elite_si_smoker_toxic_gas_cloud_duration", "12.0", "Duration in seconds for toxic smoke cloud.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvCloudRadius = CreateConVar("l4d2_elite_si_smoker_toxic_gas_cloud_radius", "230.0", "Radius of the toxic smoke cloud.", FCVAR_NOTIFY, true, 50.0, true, 1000.0);
	g_cvCloudDamagePerSecond = CreateConVar("l4d2_elite_si_smoker_toxic_gas_damage_per_second", "10.0", "Damage per second dealt to survivors inside toxic smoke.", FCVAR_NOTIFY, true, 0.1, true, 50.0);
	g_cvDamageInterval = CreateConVar("l4d2_elite_si_smoker_toxic_gas_damage_interval", "0.2", "Interval in seconds between toxic smoke damage ticks.", FCVAR_NOTIFY, true, 0.1, true, 5.0);
	g_cvHintEnable = CreateConVar("l4d2_elite_si_smoker_toxic_gas_hint_enable", "1", "0=Off, 1=Show instructor hint to survivors taking toxic gas damage.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvHintColor = CreateConVar("l4d2_elite_si_smoker_toxic_gas_hint_color", "80 80 80", "Instructor hint color for toxic gas damage in format 'R G B'.", FCVAR_NOTIFY);
	g_cvHintInterval = CreateConVar("l4d2_elite_si_smoker_toxic_gas_hint_interval", "1.5", "Minimum interval in seconds between toxic gas hints per survivor.", FCVAR_NOTIFY, true, 0.1, true, 10.0);

	CreateConVar("l4d2_elite_si_smoker_toxic_gas_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_smoker_toxic_gas");

	g_cvEnable.AddChangeHook(OnRelevantConVarChanged);
	g_cvSpeedMultiplier.AddChangeHook(OnRelevantConVarChanged);
	g_cvCloudCooldown.AddChangeHook(OnRelevantConVarChanged);
	g_cvCloudDuration.AddChangeHook(OnRelevantConVarChanged);
	g_cvCloudRadius.AddChangeHook(OnRelevantConVarChanged);
	g_cvCloudDamagePerSecond.AddChangeHook(OnRelevantConVarChanged);
	g_cvDamageInterval.AddChangeHook(OnRelevantConVarChanged);
	g_cvHintEnable.AddChangeHook(OnRelevantConVarChanged);
	g_cvHintColor.AddChangeHook(OnRelevantConVarChanged);
	g_cvHintInterval.AddChangeHook(OnRelevantConVarChanged);

	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);

	RestartDamageThinkTimer();

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
	SyncTrackedSubtypeState();
}

public void OnConfigsExecuted()
{
	RebuildDamageThinkTimer();
}

public void OnRelevantConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_cvDamageInterval || convar == g_cvEnable)
	{
		RebuildDamageThinkTimer();
	}
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_PreThinkPost, OnSmokerThinkPost);
	SDKHook(client, SDKHook_OnTakeDamageAlive, OnSmokerTakeDamageAlive);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnSmokerThinkPost);
	SDKUnhook(client, SDKHook_OnTakeDamageAlive, OnSmokerTakeDamageAlive);
}

public void OnMapStart()
{
	ResetAllState();
}

public void OnMapEnd()
{
	g_hDamageThinkTimer = null;
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedToxicGas[client] = (zclass == ZC_SMOKER && subtype == ELITE_SUBTYPE_SMOKER_TOXIC_GAS);
	g_bDeathCloudTriggered[client] = false;
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		g_bTrackedToxicGas[client] = false;
	}
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
	if (!IsValidAliveSurvivor(attacker) || !IsToxicGasSmoker(smoker, true))
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

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidAliveSurvivor(victim))
	{
		return;
	}

	int smoker = victim;
	if (!IsToxicGasSmoker(smoker, false))
	{
		return;
	}

	TryReleaseDeathToxicCloud(smoker);
	g_fNextCloudAt[smoker] = 0.0;
}

public Action OnSmokerTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!IsToxicGasSmoker(victim, true))
	{
		return Plugin_Continue;
	}

	if (g_bDeathCloudTriggered[victim] || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	int currentHealth = GetClientHealth(victim);
	if (currentHealth > 0 && float(currentHealth) <= damage)
	{
		TryReleaseDeathToxicCloud(victim);
	}

	return Plugin_Continue;
}

public void OnSmokerThinkPost(int client)
{
	if (!IsToxicGasSmoker(client, true))
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

	if (!IsToxicGasSmoker(actor, false))
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
	if (!IsToxicGasSmoker(actor, true))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action ToxicGas_OnCommandAttack(any action, int actor, int entity, ActionDesiredResult result)
{
	if (!IsToxicGasSmoker(actor, true))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action ToxicGas_OnCommandApproachByEntity(any action, int actor, int goal, ActionDesiredResult result)
{
	if (!IsToxicGasSmoker(actor, true))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action ToxicGas_ShouldAttack(any action, any nextbot, any knownEntity, QueryResultType &result)
{
	int actor = view_as<int>(nextbot);
	if (!IsToxicGasSmoker(actor, true))
	{
		return Plugin_Continue;
	}

	result = ANSWER_YES;
	return Plugin_Handled;
}

Action ToxicGas_ShouldRetreat(any action, any nextbot, QueryResultType &result)
{
	int actor = view_as<int>(nextbot);
	if (!IsToxicGasSmoker(actor, true))
	{
		return Plugin_Continue;
	}

	result = ANSWER_NO;
	return Plugin_Handled;
}

Action ToxicGas_OnShoved(any action, int actor, int entity, ActionDesiredResult result)
{
	if (!IsToxicGasSmoker(actor, true) || !IsValidAliveSurvivor(entity))
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
	if (!IsToxicGasSmoker(actor, false))
	{
		return Plugin_Continue;
	}

	TryReleaseDeathToxicCloud(actor);
	g_fNextCloudAt[actor] = 0.0;
	return Plugin_Continue;
}

Action ToxicGas_OnUpdate(any action, int actor, float interval, ActionResult result)
{
	if (!IsToxicGasSmoker(actor, true))
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
	float damage = g_cvCloudDamagePerSecond.FloatValue * g_cvDamageInterval.FloatValue;

	for (int cloud = 0; cloud < MAX_TOXIC_CLOUDS; cloud++)
	{
		if (!g_bCloudActive[cloud])
		{
			continue;
		}

		if (g_fCloudExpireAt[cloud] <= now)
		{
			ClearCloud(cloud);
			continue;
		}

		int damageSource = 0;
		bool hasLiveOwner = false;
		int owner = g_iCloudOwner[cloud];
		int cloudEntity = g_iCloudEntity[cloud];
		if (owner > 0 && owner <= MaxClients && IsClientInGame(owner) && IsPlayerAlive(owner))
		{
			damageSource = owner;
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
			if (GetVectorDistance(origin, g_vecCloudOrigin[cloud]) > radius)
			{
				continue;
			}

			ApplyToxicGasDamage(survivor, hasLiveOwner ? damageSource : owner, cloudEntity, damage, now, hasLiveOwner);
			MaybeDisplayGasHint(survivor, now);
		}
	}

	return Plugin_Continue;
}

void RestartDamageThinkTimer()
{
	if (g_hDamageThinkTimer != null)
	{
		return;
	}

	float interval = g_cvDamageInterval.FloatValue;
	if (interval < 0.1)
	{
		interval = 0.1;
	}

	g_hDamageThinkTimer = CreateTimer(interval, Timer_ToxicGasThink, _, TIMER_REPEAT);
}

void RebuildDamageThinkTimer()
{
	if (g_hDamageThinkTimer != null)
	{
		delete g_hDamageThinkTimer;
		g_hDamageThinkTimer = null;
	}

	RestartDamageThinkTimer();
}

void ReleaseToxicCloud(int smoker, bool onDeath)
{
	float origin[3];
	GetClientAbsOrigin(smoker, origin);

	int entity = CreateSmokeParticle(origin, onDeath ? 8.0 : g_cvCloudDuration.FloatValue, smoker);
	CreateToxicCloud(origin, onDeath ? 8.0 : g_cvCloudDuration.FloatValue, smoker, entity);
}

void CreateToxicCloud(const float origin[3], float duration, int owner, int cloudEntity)
{
	int slot = FindAvailableCloudSlot();
	if (slot == -1)
	{
		slot = FindOldestCloudSlot();
		if (slot == -1)
		{
			return;
		}
	}

	g_bCloudActive[slot] = true;
	g_fCloudExpireAt[slot] = GetGameTime() + duration;
	g_vecCloudOrigin[slot] = origin;
	g_iCloudOwner[slot] = owner;
	g_iCloudEntity[slot] = cloudEntity;
}

int FindAvailableCloudSlot()
{
	for (int i = 0; i < MAX_TOXIC_CLOUDS; i++)
	{
		if (!g_bCloudActive[i])
		{
			return i;
		}
	}

	return -1;
}

int FindOldestCloudSlot()
{
	int slot = -1;
	float oldestExpireAt = 999999999.0;

	for (int i = 0; i < MAX_TOXIC_CLOUDS; i++)
	{
		if (!g_bCloudActive[i])
		{
			return i;
		}

		if (g_fCloudExpireAt[i] < oldestExpireAt)
		{
			oldestExpireAt = g_fCloudExpireAt[i];
			slot = i;
		}
	}

	return slot;
}

void ClearCloud(int slot)
{
	if (slot < 0 || slot >= MAX_TOXIC_CLOUDS)
	{
		return;
	}

	g_bCloudActive[slot] = false;
	g_fCloudExpireAt[slot] = 0.0;
	g_iCloudOwner[slot] = 0;
	g_vecCloudOrigin[slot][0] = 0.0;
	g_vecCloudOrigin[slot][1] = 0.0;
	g_vecCloudOrigin[slot][2] = 0.0;
	g_iCloudEntity[slot] = 0;
}

void TryReleaseDeathToxicCloud(int smoker)
{
	if (smoker <= 0 || smoker > MaxClients || g_bDeathCloudTriggered[smoker])
	{
		return;
	}

	g_bDeathCloudTriggered[smoker] = true;
	ReleaseToxicCloud(smoker, true);
}

void ApplyToxicGasDamage(int survivor, int owner, int cloudEntity, float damage, float now, bool ownerAlive)
{
	if (!IsValidAliveSurvivor(survivor) || damage <= 0.0)
	{
		return;
	}

	RecordGasAttribution(survivor, owner, now);

	if (IsPlayerIncapped(survivor))
	{
		ApplyIncappedToxicGasDamage(survivor, owner, cloudEntity, damage);
		return;
	}

	if (ownerAlive)
	{
		int inflictor = (cloudEntity > MaxClients && IsValidEntity(cloudEntity)) ? cloudEntity : owner;
		SDKHooks_TakeDamage(survivor, inflictor, owner, damage);
		return;
	}

	ApplyWorldToxicDamage(survivor, owner, cloudEntity, damage);
}

void ApplyWorldToxicDamage(int survivor, int owner, int cloudEntity, float damage)
{
	if (!IsValidAliveSurvivor(survivor) || damage <= 0.0)
	{
		return;
	}

	int attacker = (owner > 0 && owner <= MaxClients && IsClientInGame(owner)) ? owner : 0;
	int inflictor = (cloudEntity > MaxClients && IsValidEntity(cloudEntity)) ? cloudEntity : 0;

	SDKHooks_TakeDamage(survivor, inflictor, attacker, damage);
}

void ApplyIncappedToxicGasDamage(int survivor, int owner, int cloudEntity, float damage)
{
	int currentHealth = GetClientHealth(survivor);
	if (currentHealth <= 0)
	{
		return;
	}

	int damageInt = RoundToCeil(damage);
	if (damageInt < 1)
	{
		damageInt = 1;
	}

	if (currentHealth <= damageInt)
	{
		int attacker = (owner > 0 && owner <= MaxClients && IsClientInGame(owner)) ? owner : 0;
		int inflictor = (cloudEntity > MaxClients && IsValidEntity(cloudEntity)) ? cloudEntity : 0;
		SDKHooks_TakeDamage(survivor, inflictor, attacker, float(currentHealth));
		return;
	}

	SetEntityHealth(survivor, currentHealth - damageInt);
}

void RecordGasAttribution(int survivor, int owner, float now)
{
	if (!IsValidSurvivorClient(survivor))
	{
		return;
	}

	g_iLastGasOwner[survivor] = owner;
	g_fLastGasDamageAt[survivor] = now;
}

int GetRecentGasOwner(int survivor)
{
	if (!IsValidSurvivorClient(survivor))
	{
		return 0;
	}

	int owner = g_iLastGasOwner[survivor];
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
	{
		return 0;
	}

	if (GetGameTime() - g_fLastGasDamageAt[survivor] > TOXIC_GAS_ATTRIBUTION_WINDOW)
	{
		return 0;
	}

	return owner;
}

public int Native_GetRecentDamageCause(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	if (GetRecentGasOwner(victim) <= 0)
	{
		return TOXIC_GAS_CAUSE_NONE;
	}

	return TOXIC_GAS_CAUSE_CLOUD;
}

public int Native_GetRecentDamageAttacker(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	return GetRecentGasOwner(victim);
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

int CreateSmokeParticle(const float origin[3], float lifetime, int owner)
{
	int entity = CreateEntityByName("info_particle_system");
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return 0;
	}

	DispatchKeyValue(entity, "effect_name", "smoker_smokecloud");
	DispatchKeyValue(entity, "targetname", "elite_smoker_toxic_gas");
	DispatchSpawn(entity);
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", owner);
	TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Start");
	CreateTimer(lifetime, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	
	return entity;
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

	DisplayInstructorHint(survivor, "Toxic gas! Leave the smoke now.", "icon_alert", color);
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
	for (int i = 0; i < MAX_TOXIC_CLOUDS; i++)
	{
		ClearCloud(i);
	}

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

	g_bTrackedToxicGas[client] = false;
	g_bDeathCloudTriggered[client] = false;
	g_fNextCloudAt[client] = 0.0;
	g_fLastHintAt[client] = 0.0;
	g_iLastGasOwner[client] = 0;
	g_fLastGasDamageAt[client] = 0.0;
}

bool IsValidSurvivorClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR;
}

bool IsToxicGasSmoker(int client, bool requireAlive)
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

	if (!g_bTrackedToxicGas[client])
	{
		return false;
	}

	return true;
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

bool IsPlayerIncapped(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1
		&& GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) == 0;
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}

void SyncTrackedSubtypeState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		SyncTrackedSubtypeForClient(i);
	}
}

void SyncTrackedSubtypeForClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SMOKER)
	{
		g_bTrackedToxicGas[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedToxicGas[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SMOKER_TOXIC_GAS;
}
