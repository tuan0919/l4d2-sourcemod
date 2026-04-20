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
#define LEAKER_ATTRIBUTION_WINDOW 4.0
#define LEAKER_CAUSE_NONE 0
#define LEAKER_CAUSE_FIRE 1

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvApproachRange;
ConVar g_cvPrepareRange;
ConVar g_cvPrepareDuration;
ConVar g_cvMoveSpeedMultiplier;
ConVar g_cvFirePatchDuration;

bool g_bHasEliteApi;
bool g_bTrackedLeaker[MAXPLAYERS + 1];
bool g_bPrepareExplode[MAXPLAYERS + 1];
bool g_bExplosionTriggered[MAXPLAYERS + 1];
float g_fExplodeAt[MAXPLAYERS + 1];
int g_iLastLeakerOwner[MAXPLAYERS + 1];
int g_iLastLeakerCause[MAXPLAYERS + 1];
float g_fLastLeakerDamageAt[MAXPLAYERS + 1];

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

	CreateNative("EliteSI_Leaker_GetRecentDamageCause", Native_GetRecentDamageCause);
	CreateNative("EliteSI_Leaker_GetRecentDamageAttacker", Native_GetRecentDamageAttacker);

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_boomer_leaker_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvApproachRange = CreateConVar("l4d2_elite_si_boomer_leaker_approach_range", "900.0", "Max range where Leaker Boomer tries to approach survivors before preparing to explode.", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
	g_cvPrepareRange = CreateConVar("l4d2_elite_si_boomer_leaker_prepare_range", "170.0", "Distance where Leaker Boomer crouches and starts its self-detonation countdown.", FCVAR_NOTIFY, true, 50.0, true, 1000.0);
	g_cvPrepareDuration = CreateConVar("l4d2_elite_si_boomer_leaker_prepare_duration", "2.5", "Seconds Leaker Boomer crouches before self-detonating.", FCVAR_NOTIFY, true, 0.2, true, 10.0);
	g_cvMoveSpeedMultiplier = CreateConVar("l4d2_elite_si_boomer_leaker_speed_multiplier", "1.12", "Movement speed multiplier while Leaker Boomer closes distance.", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvFirePatchDuration = CreateConVar("l4d2_elite_si_boomer_leaker_fire_patch_duration", "10.0", "Duration in seconds of the inferno created by Leaker Boomer explosions.", FCVAR_NOTIFY, true, 0.5, true, 60.0);

	CreateConVar("l4d2_elite_si_boomer_leaker_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_boomer_leaker");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);

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
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "inferno"))
	{
		SDKHook(entity, SDKHook_SpawnPost, OnInfernoSpawnPost);
	}
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

	CreateLeakerInferno(client);
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
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	if ((damageType & DMG_BURN) != 0)
	{
		int owner = ResolveLeakerFireOwner(attacker, inflictor);
		if (owner > 0)
		{
			RecordLeakerAttribution(victim, owner, LEAKER_CAUSE_FIRE);
		}
	}

	if (!IsLeakerBoomer(victim, true))
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

void CreateLeakerInferno(int owner)
{
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
	{
		return;
	}

	float origin[3];
	GetClientAbsOrigin(owner, origin);
	origin[2] += 2.0;

	float ang[3] = {90.0, 0.0, 0.0};
	int projectile = L4D_MolotovPrj(owner, origin, ang);
	if (projectile <= MaxClients || !IsValidEntity(projectile))
	{
		return;
	}

	L4D_DetonateProjectile(projectile);
}

public void OnInfernoSpawnPost(int entity)
{
	if (!IsValidEntity(entity))
	{
		return;
	}

	int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	if (!IsLeakerBoomer(owner, false))
	{
		return;
	}

	float duration = g_cvFirePatchDuration.FloatValue;
	if (duration > 0.0)
	{
		CreateTimer(duration, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	}
}

void RecordLeakerAttribution(int victim, int owner, int cause)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
	{
		return;
	}

	g_iLastLeakerOwner[victim] = owner;
	g_iLastLeakerCause[victim] = cause;
	g_fLastLeakerDamageAt[victim] = GetGameTime();
}

int GetRecentLeakerOwner(int victim)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
	{
		return 0;
	}

	int owner = g_iLastLeakerOwner[victim];
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
	{
		return 0;
	}

	if (GetGameTime() - g_fLastLeakerDamageAt[victim] > LEAKER_ATTRIBUTION_WINDOW)
	{
		return 0;
	}

	return owner;
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

	g_bTrackedLeaker[client] = false;
	g_bPrepareExplode[client] = false;
	g_bExplosionTriggered[client] = false;
	g_fExplodeAt[client] = 0.0;
	g_iLastLeakerOwner[client] = 0;
	g_iLastLeakerCause[client] = LEAKER_CAUSE_NONE;
	g_fLastLeakerDamageAt[client] = 0.0;
}

int ResolveLeakerFireOwner(int attacker, int inflictor)
{
	int owner = ResolveOwnerFromEntity(inflictor);
	if (owner > 0)
	{
		return owner;
	}

	return ResolveOwnerFromEntity(attacker);
}

int ResolveOwnerFromEntity(int entity)
{
	if (!IsValidEdict(entity))
	{
		return 0;
	}

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (!StrEqual(classname, "inferno") && !StrEqual(classname, "entityflame"))
	{
		return 0;
	}

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (!IsLeakerBoomer(owner, false))
	{
		owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
		if (!IsLeakerBoomer(owner, false))
		{
			return 0;
		}
	}

	return owner;
}

bool IsLeakerBoomer(int client, bool requireAlive)
{
	if (requireAlive && (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client)))
	{
		return false;
	}

	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	return g_bTrackedLeaker[client];
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

public int Native_GetRecentDamageCause(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	if (GetRecentLeakerOwner(victim) <= 0)
	{
		return LEAKER_CAUSE_NONE;
	}

	return g_iLastLeakerCause[victim];
}

public int Native_GetRecentDamageAttacker(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	return GetRecentLeakerOwner(victim);
}
