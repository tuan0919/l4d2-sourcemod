#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_TANK 8

#define ELITE_SUBTYPE_TANK_IGNITOR 38

#define IGNITOR_ATTRIBUTION_WINDOW 4.0
#define IGNITOR_CAUSE_NONE 0
#define IGNITOR_CAUSE_FIRE 1

#define MAXENTITIES 2048

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvFirePatchDuration;
ConVar g_cvRockDamageBonus;

bool g_bHasEliteApi;
bool g_bTrackedIgnitor[MAXPLAYERS + 1];

// Rock tracking
bool g_bIsIgnitorRock[MAXENTITIES + 1];
int g_iRockOwner[MAXENTITIES + 1];
bool g_bRockDetonated[MAXENTITIES + 1];

// Attribution
int g_iLastIgnitorOwner[MAXPLAYERS + 1];
int g_iLastIgnitorCause[MAXPLAYERS + 1];
float g_fLastIgnitorDamageAt[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Tank Ignitor",
	author = "OpenCode",
	description = "Ignitor subtype module for elite Tank bots. Always on fire, immune to burn, throws burning rocks that create infernos on impact.",
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

	CreateNative("EliteSI_TankIgnitor_GetRecentDamageCause", Native_GetRecentDamageCause);
	CreateNative("EliteSI_TankIgnitor_GetRecentDamageAttacker", Native_GetRecentDamageAttacker);

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_tank_ignitor_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFirePatchDuration = CreateConVar("l4d2_elite_si_tank_ignitor_fire_duration", "10.0", "Duration in seconds of the inferno created by burning rock impact.", FCVAR_NOTIFY, true, 0.5, true, 60.0);
	g_cvRockDamageBonus = CreateConVar("l4d2_elite_si_tank_ignitor_rock_damage_bonus", "15.0", "Bonus damage % added to burning rock hits on survivors.", FCVAR_NOTIFY, true, 0.0, true, 200.0);

	CreateConVar("l4d2_elite_si_tank_ignitor_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_tank_ignitor");

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
	SDKHook(client, SDKHook_PreThinkPost, OnIgnitorTankThinkPost);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamageFromRock);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnIgnitorTankThinkPost);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamageFromRock);
}

// ============================================================================
// Forward handlers from core
// ============================================================================

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedIgnitor[client] = (zclass == ZC_TANK && subtype == ELITE_SUBTYPE_TANK_IGNITOR);
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedIgnitor[client] = false;
}

// ============================================================================
// Events
// ============================================================================

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

// ============================================================================
// Tank self-ignite (every think frame)
// ============================================================================

public void OnIgnitorTankThinkPost(int client)
{
	if (!IsIgnitorTank(client, true))
		return;

	IgniteEntity(client, 9999.0);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
}

// ============================================================================
// Entity creation: track rocks + tag infernos
// ============================================================================

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity < 0)
		return;

	if (StrEqual(classname, "tank_rock"))
		RequestFrame(OnTankRockNextFrame, EntIndexToEntRef(entity));
	else if (StrEqual(classname, "inferno"))
		SDKHook(entity, SDKHook_SpawnPost, OnInfernoSpawnPost);
}

public void OnEntityDestroyed(int entity)
{
	if (entity < 0 || entity > MAXENTITIES)
		return;

	g_bIsIgnitorRock[entity] = false;
	g_iRockOwner[entity] = 0;
	g_bRockDetonated[entity] = false;
}

void OnTankRockNextFrame(int entityRef)
{
	if (!g_cvEnable.BoolValue)
		return;

	int entity = EntRefToEntIndex(entityRef);
	if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
		return;

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if (!IsIgnitorTank(owner, true))
		return;

	g_bIsIgnitorRock[entity] = true;
	g_iRockOwner[entity] = owner;
	g_bRockDetonated[entity] = false;

	// Always ignite the rock
	IgniteEntity(entity, 60.0);

	// Block fire damage on rock so it doesn't lose HP
	SDKHook(entity, SDKHook_OnTakeDamage, OnRockTakeDamage);

	// Create inferno on impact
	SDKHook(entity, SDKHook_Touch, OnRockTouch);
}

// ============================================================================
// Rock: block fire self-damage
// ============================================================================

public Action OnRockTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if ((damageType & DMG_BURN) != 0)
	{
		damage = 0.0;
		return Plugin_Changed;
	}

	return Plugin_Continue;
}

// ============================================================================
// Rock: on touch -> create inferno at impact point
// ============================================================================

public Action OnRockTouch(int entity, int other)
{
	if (!g_bIsIgnitorRock[entity] || g_bRockDetonated[entity])
		return Plugin_Continue;

	if (!g_cvEnable.BoolValue)
		return Plugin_Continue;

	g_bRockDetonated[entity] = true;

	int owner = g_iRockOwner[entity];
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
		return Plugin_Continue;

	float origin[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", origin);
	origin[2] += 2.0;

	float ang[3] = {90.0, 0.0, 0.0};
	int projectile = L4D_MolotovPrj(owner, origin, ang);
	if (projectile > MaxClients && IsValidEntity(projectile))
		L4D_DetonateProjectile(projectile);

	return Plugin_Continue;
}

// ============================================================================
// Inferno spawn: tag targetname + kill timer
// ============================================================================

public void OnInfernoSpawnPost(int entity)
{
	if (!IsValidEntity(entity))
		return;

	int owner = GetEntPropEnt(entity, Prop_Data, "m_hOwnerEntity");
	if (!IsIgnitorTank(owner, false))
		return;

	DispatchKeyValue(entity, "targetname", "elite_tank_ignitor_fire");

	float duration = g_cvFirePatchDuration.FloatValue;
	if (duration > 0.0)
		CreateTimer(duration, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================================
// Survivor damage: bonus from burning rock + fire attribution
// ============================================================================

public Action OnTakeDamageFromRock(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || damage <= 0.0)
		return Plugin_Continue;

	// Track fire damage from our infernos for attribution
	if ((damageType & DMG_BURN) != 0 && GetClientTeam(victim) == TEAM_SURVIVOR)
	{
		int fireOwner = ResolveIgnitorFireOwner(attacker, inflictor);
		if (fireOwner > 0)
			RecordIgnitorAttribution(victim, fireOwner, IGNITOR_CAUSE_FIRE);
	}

	if (GetClientTeam(victim) != TEAM_SURVIVOR)
		return Plugin_Continue;

	// Bonus damage when hit by a burning ignitor rock
	if (inflictor > MaxClients && inflictor <= MAXENTITIES && g_bIsIgnitorRock[inflictor])
	{
		float bonus = g_cvRockDamageBonus.FloatValue;
		if (bonus > 0.0)
		{
			damage += (damage * bonus / 100.0);
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

// ============================================================================
// Attribution
// ============================================================================

void RecordIgnitorAttribution(int victim, int owner, int cause)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return;

	g_iLastIgnitorOwner[victim] = owner;
	g_iLastIgnitorCause[victim] = cause;
	g_fLastIgnitorDamageAt[victim] = GetGameTime();
}

int GetRecentIgnitorOwner(int victim)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return 0;

	int owner = g_iLastIgnitorOwner[victim];
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
		return 0;

	if (GetGameTime() - g_fLastIgnitorDamageAt[victim] > IGNITOR_ATTRIBUTION_WINDOW)
		return 0;

	return owner;
}

int ResolveIgnitorFireOwner(int attacker, int inflictor)
{
	int owner = ResolveOwnerFromEntity(inflictor);
	if (owner > 0)
		return owner;

	return ResolveOwnerFromEntity(attacker);
}

int ResolveOwnerFromEntity(int entity)
{
	if (!IsValidEdict(entity))
		return 0;

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));
	if (!StrEqual(classname, "inferno") && !StrEqual(classname, "entityflame"))
		return 0;

	char targetname[64];
	GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));

	if (StrEqual(targetname, "elite_tank_ignitor_fire"))
		return GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");

	return 0;
}

// ============================================================================
// Natives
// ============================================================================

public int Native_GetRecentDamageCause(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	if (GetRecentIgnitorOwner(victim) <= 0)
		return IGNITOR_CAUSE_NONE;

	return g_iLastIgnitorCause[victim];
}

public int Native_GetRecentDamageAttacker(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	return GetRecentIgnitorOwner(victim);
}

// ============================================================================
// Timer
// ============================================================================

public Action Timer_KillEntity(Handle timer, int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");

	return Plugin_Stop;
}

// ============================================================================
// State management
// ============================================================================

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
		ResetClientState(i);

	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_bIsIgnitorRock[i] = false;
		g_iRockOwner[i] = 0;
		g_bRockDetonated[i] = false;
	}
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedIgnitor[client] = false;
	g_iLastIgnitorOwner[client] = 0;
	g_iLastIgnitorCause[client] = IGNITOR_CAUSE_NONE;
	g_fLastIgnitorDamageAt[client] = 0.0;
}

// ============================================================================
// Helpers
// ============================================================================

bool IsIgnitorTank(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (GetClientTeam(client) != TEAM_INFECTED)
		return false;

	if (requireAlive && !IsPlayerAlive(client))
		return false;

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_TANK)
		return false;

	return g_bTrackedIgnitor[client];
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}

void SyncTrackedSubtypeState()
{
	for (int i = 1; i <= MaxClients; i++)
		SyncTrackedSubtypeForClient(i);
}

void SyncTrackedSubtypeForClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return;

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_TANK)
	{
		g_bTrackedIgnitor[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
		return;

	g_bTrackedIgnitor[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_TANK_IGNITOR;
}
