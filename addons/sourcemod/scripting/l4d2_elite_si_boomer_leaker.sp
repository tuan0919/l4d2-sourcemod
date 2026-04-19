#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_BOOMER 2

#define ELITE_SUBTYPE_BOOMER_LEAKER 33

#define MAX_LEAKER_FIRE_PATCHES 24

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvApproachRange;
ConVar g_cvPrepareRange;
ConVar g_cvPrepareDuration;
ConVar g_cvMoveSpeedMultiplier;
ConVar g_cvFirePatchDuration;
ConVar g_cvFirePatchRadius;
ConVar g_cvFirePatchDamagePerSecond;
ConVar g_cvFireDamageInterval;

bool g_bHasEliteApi;
bool g_bTrackedLeaker[MAXPLAYERS + 1];
bool g_bPrepareExplode[MAXPLAYERS + 1];
bool g_bExplosionTriggered[MAXPLAYERS + 1];
float g_fExplodeAt[MAXPLAYERS + 1];

bool g_bPatchActive[MAX_LEAKER_FIRE_PATCHES];
float g_fPatchExpireAt[MAX_LEAKER_FIRE_PATCHES];
float g_vecPatchOrigin[MAX_LEAKER_FIRE_PATCHES][3];
int g_iPatchOwner[MAX_LEAKER_FIRE_PATCHES];

Handle g_hThinkTimer;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Boomer Leaker",
	author = "OpenCode",
	description = "Leaker subtype module for elite Boomer bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_boomer_leaker_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvApproachRange = CreateConVar("l4d2_elite_si_boomer_leaker_approach_range", "900.0", "Max range where Leaker Boomer tries to approach survivors before preparing to explode.", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
	g_cvPrepareRange = CreateConVar("l4d2_elite_si_boomer_leaker_prepare_range", "170.0", "Distance where Leaker Boomer crouches and starts its self-detonation countdown.", FCVAR_NOTIFY, true, 50.0, true, 1000.0);
	g_cvPrepareDuration = CreateConVar("l4d2_elite_si_boomer_leaker_prepare_duration", "2.5", "Seconds Leaker Boomer crouches before self-detonating.", FCVAR_NOTIFY, true, 0.2, true, 10.0);
	g_cvMoveSpeedMultiplier = CreateConVar("l4d2_elite_si_boomer_leaker_speed_multiplier", "1.12", "Movement speed multiplier while Leaker Boomer closes distance.", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvFirePatchDuration = CreateConVar("l4d2_elite_si_boomer_leaker_fire_patch_duration", "10.0", "Duration in seconds of the fire patch created by Leaker Boomer explosions.", FCVAR_NOTIFY, true, 0.5, true, 60.0);
	g_cvFirePatchRadius = CreateConVar("l4d2_elite_si_boomer_leaker_fire_patch_radius", "180.0", "Radius of the Leaker Boomer fire patch.", FCVAR_NOTIFY, true, 32.0, true, 1000.0);
	g_cvFirePatchDamagePerSecond = CreateConVar("l4d2_elite_si_boomer_leaker_fire_patch_damage_per_second", "12.0", "Damage per second dealt by Leaker Boomer fire patches.", FCVAR_NOTIFY, true, 0.1, true, 100.0);
	g_cvFireDamageInterval = CreateConVar("l4d2_elite_si_boomer_leaker_fire_damage_interval", "0.5", "Tick interval in seconds for Leaker Boomer fire patch damage.", FCVAR_NOTIFY, true, 0.1, true, 5.0);

	CreateConVar("l4d2_elite_si_boomer_leaker_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_boomer_leaker");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);

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

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
		SyncTrackedSubtypeState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
	}
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_PreThinkPost, OnLeakerThinkPost);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnLeakerThinkPost);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	ClearPatchOwnerReferences(client);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedLeaker[client] = (zclass == ZC_BOOMER && subtype == ELITE_SUBTYPE_BOOMER_LEAKER);
	g_bPrepareExplode[client] = false;
	g_bExplosionTriggered[client] = false;
	g_fExplodeAt[client] = 0.0;
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedLeaker[client] = false;
	g_bPrepareExplode[client] = false;
	g_bExplosionTriggered[client] = false;
	g_fExplodeAt[client] = 0.0;
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsLeakerBoomer(client, false))
	{
		return;
	}

	CreateLeakerFirePatch(client);
	g_bExplosionTriggered[client] = true;
	}

public void OnLeakerThinkPost(int client)
{
	if (!IsLeakerBoomer(client, true))
	{
		return;
	}

	IgniteEntity(client, 9999.0);

	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (IsValidEntity(ability))
	{
		SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + 9999.0);
	}

	float now = GetGameTime();
	if (g_bPrepareExplode[client])
	{
		SetEntityFlags(client, GetEntityFlags(client) | FL_DUCKING);
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 0.2);
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", 1.0);

		if (!g_bExplosionTriggered[client] && now >= g_fExplodeAt[client])
		{
			g_bExplosionTriggered[client] = true;
			ForcePlayerSuicide(client);
		}
		return;
	}

	TryApproachAndPrime(client, now);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!IsLeakerBoomer(victim, true) || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	if ((damageType & DMG_BURN) != 0)
	{
		damage = 0.0;
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Timer_LeakerThink(Handle timer)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();
	float radius = g_cvFirePatchRadius.FloatValue;
	float damage = g_cvFirePatchDamagePerSecond.FloatValue * g_cvFireDamageInterval.FloatValue;

	for (int patch = 0; patch < MAX_LEAKER_FIRE_PATCHES; patch++)
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

		for (int client = 1; client <= MaxClients; client++)
		{
			if (!IsDamageableLivingPlayer(client))
			{
				continue;
			}

			float origin[3];
			GetClientAbsOrigin(client, origin);
			if (GetVectorDistance(origin, g_vecPatchOrigin[patch]) > radius)
			{
				continue;
			}

			ApplyManagedFireDamage(client, g_iPatchOwner[patch], damage);
		}
	}

	return Plugin_Continue;
}

public Action L4D_OnVomitedUpon(int victim, int &attacker, bool &boomerExplosion)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!IsLeakerBoomer(attacker, false))
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

void RestartThinkTimer()
{
	if (g_hThinkTimer != null)
	{
		return;
	}

	float interval = g_cvFireDamageInterval != null ? g_cvFireDamageInterval.FloatValue : 0.5;
	if (interval < 0.1)
	{
		interval = 0.1;
	}

	g_hThinkTimer = CreateTimer(interval, Timer_LeakerThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void TryApproachAndPrime(int client, float now)
{
	int target = FindClosestSurvivor(client, g_cvApproachRange.FloatValue);
	if (target <= 0)
	{
		return;
	}

	float selfOrigin[3];
	float targetOrigin[3];
	GetClientAbsOrigin(client, selfOrigin);
	GetClientAbsOrigin(target, targetOrigin);

	float distance = GetVectorDistance(selfOrigin, targetOrigin);
	if (distance <= g_cvPrepareRange.FloatValue)
	{
		g_bPrepareExplode[client] = true;
		g_fExplodeAt[client] = now + g_cvPrepareDuration.FloatValue;
		return;
	}

	float direction[3];
	MakeVectorFromPoints(selfOrigin, targetOrigin, direction);
	NormalizeVector(direction, direction);

	float speed = 210.0 * g_cvMoveSpeedMultiplier.FloatValue;
	float velocity[3];
	velocity[0] = direction[0] * speed;
	velocity[1] = direction[1] * speed;
	velocity[2] = 0.0;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvMoveSpeedMultiplier.FloatValue);
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);
}

void ApplyManagedFireDamage(int client, int owner, float damage)
{
	if (!IsDamageableLivingPlayer(client) || damage <= 0.0)
	{
		return;
	}

	int attacker = owner;
	if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker))
	{
		attacker = client;
	}

	if (IsPlayerIncapped(client))
	{
		int currentHealth = GetClientHealth(client);
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
			SDKHooks_TakeDamage(client, attacker, attacker, float(currentHealth), DMG_BURN);
			return;
		}

		SetEntityHealth(client, currentHealth - damageInt);
		return;
	}

	SDKHooks_TakeDamage(client, attacker, attacker, damage, DMG_BURN);
	IgniteEntity(client, 1.0);
}

void CreateLeakerFirePatch(int owner)
{
	float origin[3];
	GetClientAbsOrigin(owner, origin);
	origin[2] += 2.0;

	int slot = FindFreeFirePatchSlot();
	if (slot == -1)
	{
		return;
	}

	g_bPatchActive[slot] = true;
	g_fPatchExpireAt[slot] = GetGameTime() + g_cvFirePatchDuration.FloatValue;
	g_iPatchOwner[slot] = owner;
	g_vecPatchOrigin[slot][0] = origin[0];
	g_vecPatchOrigin[slot][1] = origin[1];
	g_vecPatchOrigin[slot][2] = origin[2];

	CreateGroundFireParticle(origin, g_cvFirePatchDuration.FloatValue);
}

int FindFreeFirePatchSlot()
{
	int slot = -1;
	float oldestExpire = 9999999.0;

	for (int i = 0; i < MAX_LEAKER_FIRE_PATCHES; i++)
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
	if (slot < 0 || slot >= MAX_LEAKER_FIRE_PATCHES)
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
	for (int i = 0; i < MAX_LEAKER_FIRE_PATCHES; i++)
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

	g_bTrackedLeaker[client] = false;
	g_bPrepareExplode[client] = false;
	g_bExplosionTriggered[client] = false;
	g_fExplodeAt[client] = 0.0;
}

void ClearPatchOwnerReferences(int owner)
{
	for (int patch = 0; patch < MAX_LEAKER_FIRE_PATCHES; patch++)
	{
		if (g_iPatchOwner[patch] == owner)
		{
			g_iPatchOwner[patch] = 0;
		}
	}
}

bool IsLeakerBoomer(int client, bool requireAlive)
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

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_BOOMER)
	{
		return false;
	}

	return g_bTrackedLeaker[client];
}

bool IsDamageableLivingPlayer(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& IsPlayerAlive(client)
		&& (GetClientTeam(client) == TEAM_SURVIVOR || GetClientTeam(client) == TEAM_INFECTED);
}

bool IsPlayerIncapped(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1
		&& GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) == 0;
}

int FindClosestSurvivor(int client, float maxDistance)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	int closest = 0;
	float closestDistance = maxDistance;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float targetOrigin[3];
		GetClientAbsOrigin(survivor, targetOrigin);
		float distance = GetVectorDistance(origin, targetOrigin);
		if (distance < closestDistance)
		{
			closestDistance = distance;
			closest = survivor;
		}
	}

	return closest;
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

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_BOOMER)
	{
		g_bTrackedLeaker[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedLeaker[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_BOOMER_LEAKER;
}
