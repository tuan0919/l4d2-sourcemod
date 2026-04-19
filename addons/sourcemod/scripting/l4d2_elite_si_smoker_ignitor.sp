#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_SMOKER 1

#define ELITE_SUBTYPE_SMOKER_IGNITOR 30

#define MAX_FIRE_PATCHES 24

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvDebuffDuration;
ConVar g_cvDebuffDamagePerSecond;
ConVar g_cvDebuffInterval;
ConVar g_cvDeathFireDuration;
ConVar g_cvDeathFireRadius;
ConVar g_cvDeathFireDamagePerSecond;
ConVar g_cvHintEnable;
ConVar g_cvHintColor;
ConVar g_cvHintInterval;

bool g_bHasEliteApi;
bool g_bTrackedIgnitor[MAXPLAYERS + 1];
bool g_bDeathFireTriggered[MAXPLAYERS + 1];
float g_fLastHintAt[MAXPLAYERS + 1];
int g_iBurnOwner[MAXPLAYERS + 1];
float g_fBurnExpireAt[MAXPLAYERS + 1];

bool g_bPatchActive[MAX_FIRE_PATCHES];
float g_fPatchExpireAt[MAX_FIRE_PATCHES];
float g_vecPatchOrigin[MAX_FIRE_PATCHES][3];
int g_iPatchOwner[MAX_FIRE_PATCHES];

Handle g_hThinkTimer;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Smoker Ignitor",
	author = "OpenCode",
	description = "Ignitor subtype module for elite Smoker bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_smoker_ignitor_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDebuffDuration = CreateConVar("l4d2_elite_si_smoker_ignitor_burn_duration", "8.0", "Duration in seconds for the burn debuff applied by Ignitor Smoker.", FCVAR_NOTIFY, true, 0.5, true, 60.0);
	g_cvDebuffDamagePerSecond = CreateConVar("l4d2_elite_si_smoker_ignitor_burn_damage_per_second", "4.0", "Damage per second dealt by the Ignitor Smoker burn debuff.", FCVAR_NOTIFY, true, 0.1, true, 50.0);
	g_cvDebuffInterval = CreateConVar("l4d2_elite_si_smoker_ignitor_burn_interval", "0.5", "Interval in seconds between Ignitor Smoker burn damage ticks.", FCVAR_NOTIFY, true, 0.1, true, 5.0);
	g_cvDeathFireDuration = CreateConVar("l4d2_elite_si_smoker_ignitor_death_fire_duration", "10.0", "Duration in seconds for the fire patch spawned on Ignitor Smoker death.", FCVAR_NOTIFY, true, 0.5, true, 60.0);
	g_cvDeathFireRadius = CreateConVar("l4d2_elite_si_smoker_ignitor_death_fire_radius", "180.0", "Radius of the death fire patch.", FCVAR_NOTIFY, true, 32.0, true, 1000.0);
	g_cvDeathFireDamagePerSecond = CreateConVar("l4d2_elite_si_smoker_ignitor_death_fire_damage_per_second", "12.0", "Damage per second dealt by the death fire patch.", FCVAR_NOTIFY, true, 0.1, true, 100.0);
	g_cvHintEnable = CreateConVar("l4d2_elite_si_smoker_ignitor_hint_enable", "1", "0=Off, 1=Show instructor hint to survivors taking Ignitor fire damage.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvHintColor = CreateConVar("l4d2_elite_si_smoker_ignitor_hint_color", "255 140 40", "Instructor hint color for Ignitor fire damage in format 'R G B'.", FCVAR_NOTIFY);
	g_cvHintInterval = CreateConVar("l4d2_elite_si_smoker_ignitor_hint_interval", "1.5", "Minimum interval in seconds between Ignitor fire hints per survivor.", FCVAR_NOTIFY, true, 0.1, true, 10.0);

	CreateConVar("l4d2_elite_si_smoker_ignitor_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_smoker_ignitor");

	HookEvent("tongue_grab", Event_TongueGrab, EventHookMode_Post);
	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();
	ResetAllState();
	RestartThinkTimer();

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

public void OnMapStart()
{
	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_PreThinkPost, OnIgnitorThinkPost);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnIgnitorThinkPost);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	ClearBurnOwnerReferences(client);
	ClearPatchOwnerReferences(client);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedIgnitor[client] = (zclass == ZC_SMOKER && subtype == ELITE_SUBTYPE_SMOKER_IGNITOR);
	g_bDeathFireTriggered[client] = false;
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (IsClientInGame(client) && IsPlayerAlive(client))
	{
		g_bTrackedIgnitor[client] = false;
	}
	ClearBurnOwnerReferences(client);
	ClearPatchOwnerReferences(client);
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

public void Event_TongueGrab(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("victim"));
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (!IsIgnitorSmoker(attacker, true) || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	ApplyIgnitorBurn(victim, attacker);
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	if ((event.GetInt("type") & DMG_CLUB) == 0)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsIgnitorSmoker(attacker, true) || !IsValidSurvivorClient(victim))
	{
		return;
	}

	ApplyIgnitorBurn(victim, attacker);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidSurvivorClient(victim))
	{
		return;
	}

	if (!IsIgnitorSmoker(victim, false))
	{
		return;
	}

	TryCreateDeathFirePatch(victim);
	}

public void OnIgnitorThinkPost(int client)
{
	if (!IsIgnitorSmoker(client, true))
	{
		return;
	}

	IgniteEntity(client, 9999.0);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	if (GetClientTeam(victim) == TEAM_INFECTED)
	{
		return Plugin_Continue;
	}

	if (GetClientTeam(victim) != TEAM_SURVIVOR)
	{
		return Plugin_Continue;
	}

	if ((damageType & DMG_BURN) != 0 && IsIgnitorSmoker(attacker, false))
	{
		ApplyIgnitorBurn(victim, attacker);
	}

	return Plugin_Continue;
}

public Action Timer_IgnitorThink(Handle timer)
{
	g_hThinkTimer = null;
	RestartThinkTimer();

	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	float burnDamage = g_cvDebuffDamagePerSecond.FloatValue * g_cvDebuffInterval.FloatValue;
	float firePatchDamage = g_cvDeathFireDamagePerSecond.FloatValue * g_cvDebuffInterval.FloatValue;
	float firePatchRadius = g_cvDeathFireRadius.FloatValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		if (g_fBurnExpireAt[survivor] > now && g_iBurnOwner[survivor] > 0)
		{
			ApplyManagedFireDamage(survivor, g_iBurnOwner[survivor], burnDamage);
			MaybeDisplayIgnitorHint(survivor, now, "Ignited! Put out the flames.");
		}
		else if (g_fBurnExpireAt[survivor] > 0.0)
		{
			g_iBurnOwner[survivor] = 0;
			g_fBurnExpireAt[survivor] = 0.0;
		}

		float survivorOrigin[3];
		GetClientAbsOrigin(survivor, survivorOrigin);

		for (int patch = 0; patch < MAX_FIRE_PATCHES; patch++)
		{
			if (!g_bPatchActive[patch])
			{
				continue;
			}

			if (g_fPatchExpireAt[patch] <= now)
			{
				ClearFirePatch(patch);
				continue;
			}

			if (GetVectorDistance(survivorOrigin, g_vecPatchOrigin[patch]) > firePatchRadius)
			{
				continue;
			}

			ApplyManagedFireDamage(survivor, g_iPatchOwner[patch], firePatchDamage);
			MaybeDisplayIgnitorHint(survivor, now, "Fire patch! Move out now.");
		}
	}

	for (int patch = 0; patch < MAX_FIRE_PATCHES; patch++)
	{
		if (g_bPatchActive[patch] && g_fPatchExpireAt[patch] <= now)
		{
			ClearFirePatch(patch);
		}
	}

	return Plugin_Continue;
}

void RestartThinkTimer()
{
	float interval = g_cvDebuffInterval != null ? g_cvDebuffInterval.FloatValue : 0.5;
	if (interval < 0.1)
	{
		interval = 0.1;
	}

	if (g_hThinkTimer != null)
	{
		delete g_hThinkTimer;
	}

	g_hThinkTimer = CreateTimer(interval, Timer_IgnitorThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ApplyIgnitorBurn(int survivor, int smoker)
{
	if (!IsValidSurvivorClient(survivor) || !IsIgnitorSmoker(smoker, false))
	{
		return;
	}

	g_iBurnOwner[survivor] = smoker;
	g_fBurnExpireAt[survivor] = GetGameTime() + g_cvDebuffDuration.FloatValue;
	IgniteEntity(survivor, 1.0);
}

void ApplyManagedFireDamage(int survivor, int owner, float damage)
{
	if (!IsValidAliveSurvivor(survivor) || damage <= 0.0)
	{
		return;
	}

	int attacker = owner;
	if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
	{
		attacker = survivor;
	}

	if (IsPlayerIncapped(survivor))
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
			SDKHooks_TakeDamage(survivor, attacker, attacker, float(currentHealth), DMG_BURN);
			return;
		}

		SetEntityHealth(survivor, currentHealth - damageInt);
		return;
	}

	SDKHooks_TakeDamage(survivor, attacker, attacker, damage, DMG_BURN);
	IgniteEntity(survivor, 1.0);
}

void TryCreateDeathFirePatch(int smoker)
{
	if (smoker <= 0 || smoker > MaxClients || g_bDeathFireTriggered[smoker])
	{
		return;
	}

	g_bDeathFireTriggered[smoker] = true;

	float origin[3];
	GetClientAbsOrigin(smoker, origin);
	origin[2] += 2.0;

	int slot = FindFreeFirePatchSlot();
	if (slot == -1)
	{
		return;
	}

	g_bPatchActive[slot] = true;
	g_fPatchExpireAt[slot] = GetGameTime() + g_cvDeathFireDuration.FloatValue;
	g_iPatchOwner[slot] = smoker;
	g_vecPatchOrigin[slot][0] = origin[0];
	g_vecPatchOrigin[slot][1] = origin[1];
	g_vecPatchOrigin[slot][2] = origin[2];

	CreateGroundFireParticle(origin, g_cvDeathFireDuration.FloatValue);
}

int FindFreeFirePatchSlot()
{
	int slot = -1;
	float oldestExpire = 9999999.0;

	for (int i = 0; i < MAX_FIRE_PATCHES; i++)
	{
		if (!g_bPatchActive[i])
		{
			return i;
		}

		if (g_fPatchExpireAt[i] < oldestExpire)
		{
			oldestExpire = g_fPatchExpireAt[i];
			slot = i;
		}
	}

	return slot;
}

void ClearFirePatch(int slot)
{
	if (slot < 0 || slot >= MAX_FIRE_PATCHES)
	{
		return;
	}

	g_bPatchActive[slot] = false;
	g_fPatchExpireAt[slot] = 0.0;
	g_iPatchOwner[slot] = 0;
	g_vecPatchOrigin[slot][0] = 0.0;
	g_vecPatchOrigin[slot][1] = 0.0;
	g_vecPatchOrigin[slot][2] = 0.0;
}

void CreateGroundFireParticle(const float origin[3], float lifetime)
{
	int entity = CreateEntityByName("info_particle_system");
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return;
	}

	DispatchKeyValue(entity, "effect_name", "gas_explosion_ground_fire");
	DispatchSpawn(entity);
	TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Start");
	CreateTimer(lifetime, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

void MaybeDisplayIgnitorHint(int survivor, float now, const char[] text)
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
		strcopy(color, sizeof(color), "255 140 40");
	}

	DisplayInstructorHint(survivor, text, "icon_fire", color);
}

void DisplayInstructorHint(int target, const char[] text, const char[] icon, const char[] color)
{
	int entity = CreateEntityByName("env_instructor_hint");
	if (entity <= 0)
	{
		return;
	}

	char key[32];
	FormatEx(key, sizeof(key), "hintIgnitor%d", target);
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
	for (int i = 0; i < MAX_FIRE_PATCHES; i++)
	{
		ClearFirePatch(i);
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

	g_bTrackedIgnitor[client] = false;
	g_bDeathFireTriggered[client] = false;
	g_fLastHintAt[client] = 0.0;
	g_iBurnOwner[client] = 0;
	g_fBurnExpireAt[client] = 0.0;
}

void ClearBurnOwnerReferences(int owner)
{
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (g_iBurnOwner[survivor] == owner)
		{
			g_iBurnOwner[survivor] = 0;
		}
	}
}

void ClearPatchOwnerReferences(int owner)
{
	for (int patch = 0; patch < MAX_FIRE_PATCHES; patch++)
	{
		if (g_iPatchOwner[patch] == owner)
		{
			g_iPatchOwner[patch] = 0;
		}
	}
}

bool IsIgnitorSmoker(int client, bool requireAlive)
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

	return g_bTrackedIgnitor[client];
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

bool IsValidSurvivorClient(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR;
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
		g_bTrackedIgnitor[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedIgnitor[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SMOKER_IGNITOR;
}
