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

#define ELITE_SUBTYPE_TANK_EXPLOSIVE 39

#define EXPLOSIVE_ATTRIBUTION_WINDOW 4.0
#define EXPLOSIVE_CAUSE_NONE 0
#define EXPLOSIVE_CAUSE_BLAST 1

#define MAXENTITIES 2048

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvExplosionDamage;
ConVar g_cvExplosionRadius;
ConVar g_cvShakeAmplitude;
ConVar g_cvShakeFrequency;
ConVar g_cvShakeDuration;
ConVar g_cvShakeRadius;
ConVar g_cvDirectHitBonusDamage;

bool g_bHasEliteApi;
bool g_bTrackedExplosive[MAXPLAYERS + 1];

// Rock tracking (entity-indexed)
bool g_bIsExplosiveRock[MAXENTITIES + 1];
int  g_iRockOwner[MAXENTITIES + 1];
bool g_bRockDetonated[MAXENTITIES + 1];

// Attribution
int   g_iLastExplosiveOwner[MAXPLAYERS + 1];
int   g_iLastExplosiveCause[MAXPLAYERS + 1];
float g_fLastExplosiveDamageAt[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Tank Explosive",
	author = "OpenCode",
	description = "Explosive subtype module for elite Tank bots. Rocks explode on impact with AOE damage and screen shake.",
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

	CreateNative("EliteSI_TankExplosive_GetRecentDamageCause", Native_GetRecentDamageCause);
	CreateNative("EliteSI_TankExplosive_GetRecentDamageAttacker", Native_GetRecentDamageAttacker);

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable             = CreateConVar("l4d2_elite_si_tank_explosive_enable",           "1",    "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvExplosionDamage    = CreateConVar("l4d2_elite_si_tank_explosive_damage",            "30.0", "AOE explosion damage dealt to survivors.", FCVAR_NOTIFY, true, 0.0, true, 500.0);
	g_cvExplosionRadius    = CreateConVar("l4d2_elite_si_tank_explosive_radius",            "350.0","Explosion damage radius.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvShakeAmplitude     = CreateConVar("l4d2_elite_si_tank_explosive_shake_amplitude",   "16.0", "Screen shake amplitude.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvShakeFrequency     = CreateConVar("l4d2_elite_si_tank_explosive_shake_frequency",   "1.5",  "Screen shake frequency.", FCVAR_NOTIFY, true, 0.0, true, 50.0);
	g_cvShakeDuration      = CreateConVar("l4d2_elite_si_tank_explosive_shake_duration",    "1.0",  "Screen shake duration in seconds.", FCVAR_NOTIFY, true, 0.0, true, 10.0);
	g_cvShakeRadius        = CreateConVar("l4d2_elite_si_tank_explosive_shake_radius",      "600.0","Screen shake radius.", FCVAR_NOTIFY, true, 50.0, true, 3000.0);
	g_cvDirectHitBonusDamage = CreateConVar("l4d2_elite_si_tank_explosive_direct_hit_bonus","15.0", "Extra damage when rock directly hits a survivor.", FCVAR_NOTIFY, true, 0.0, true, 500.0);

	CreateConVar("l4d2_elite_si_tank_explosive_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_tank_explosive");

	HookEvent("round_start",    Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end",      Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost",   Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win",     Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();
	ResetAllState();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			OnClientPutInServer(i);
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
		RefreshEliteState();
}

public void OnMapStart()
{
	PrecacheSound("ambient/explosions/explode_1.wav", true);
	PrecacheParticle("gas_explosion_main");
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_OnTakeDamage, OnSurvivorTakeDamage);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnSurvivorTakeDamage);
}

// ============================================================================
// Elite system forwards
// ============================================================================

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedExplosive[client] = (zclass == ZC_TANK && subtype == ELITE_SUBTYPE_TANK_EXPLOSIVE);
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedExplosive[client] = false;
}

// ============================================================================
// Events
// ============================================================================

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

// ============================================================================
// Entity tracking
// ============================================================================

public void OnEntityCreated(int entity, const char[] classname)
{
	if (entity < 0)
		return;

	if (StrEqual(classname, "tank_rock"))
		RequestFrame(OnTankRockNextFrame, EntIndexToEntRef(entity));
}

public void OnEntityDestroyed(int entity)
{
	if (entity < 0 || entity > MAXENTITIES)
		return;

	if (!g_bIsExplosiveRock[entity])
		return;

	// Fallback: rock destroyed without touching anything (timeout/OOB)
	if (!g_bRockDetonated[entity])
	{
		int owner = g_iRockOwner[entity];
		float pos[3];
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
		CreateExplosionAt(pos, owner, -1);
	}

	g_bIsExplosiveRock[entity] = false;
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
	if (!IsExplosiveTank(owner, true))
		return;

	g_bIsExplosiveRock[entity] = true;
	g_iRockOwner[entity] = owner;
	g_bRockDetonated[entity] = false;

	SDKHook(entity, SDKHook_Touch, OnRockTouch);
}

// ============================================================================
// Rock touch → explode
// ============================================================================

public Action OnRockTouch(int rock, int other)
{
	if (!g_bIsExplosiveRock[rock] || g_bRockDetonated[rock])
		return Plugin_Continue;

	if (!g_cvEnable.BoolValue)
		return Plugin_Continue;

	g_bRockDetonated[rock] = true;

	int owner = g_iRockOwner[rock];

	// Direct hit on survivor → explode under their feet
	if (other > 0 && other <= MaxClients && IsClientInGame(other)
		&& GetClientTeam(other) == TEAM_SURVIVOR && IsPlayerAlive(other))
	{
		float pos[3];
		GetClientAbsOrigin(other, pos);
		CreateExplosionAt(pos, owner, other);
	}
	else
	{
		float pos[3];
		GetEntPropVector(rock, Prop_Data, "m_vecAbsOrigin", pos);
		CreateExplosionAt(pos, owner, -1);
	}

	return Plugin_Continue;
}

// ============================================================================
// Explosion
// ============================================================================

void CreateExplosionAt(const float pos[3], int owner, int directHitTarget)
{
	CreateExplosionEffect(pos);
	CreateScreenShake(pos);
	ApplyExplosionDamage(pos, owner, directHitTarget);
}

void CreateExplosionEffect(const float pos[3])
{
	int explosion = CreateEntityByName("env_explosion");
	if (explosion <= 0)
		return;

	DispatchKeyValueInt(explosion, "iMagnitude", 50);
	DispatchKeyValueInt(explosion, "iRadiusOverride", 1);
	DispatchKeyValue(explosion, "spawnflags", "1948");
	DispatchSpawn(explosion);

	float spawnPos[3];
	spawnPos[0] = pos[0];
	spawnPos[1] = pos[1];
	spawnPos[2] = pos[2] + 10.0;
	TeleportEntity(explosion, spawnPos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(explosion, "Explode");

	CreateTimer(0.5, Timer_KillEntity, EntIndexToEntRef(explosion), TIMER_FLAG_NO_MAPCHANGE);

	EmitSoundToAll("ambient/explosions/explode_1.wav", SOUND_FROM_WORLD, SNDCHAN_AUTO, SNDLEVEL_GUNFIRE, SND_NOFLAGS, 1.0, SNDPITCH_NORMAL, -1, spawnPos);

	CreateParticleAt(spawnPos, "gas_explosion_main", 3.0);
}

void CreateScreenShake(const float pos[3])
{
	float amplitude = g_cvShakeAmplitude.FloatValue;
	float frequency = g_cvShakeFrequency.FloatValue;
	float duration  = g_cvShakeDuration.FloatValue;
	float radius    = g_cvShakeRadius.FloatValue;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || GetClientTeam(i) != TEAM_SURVIVOR || !IsPlayerAlive(i))
			continue;

		float eyePos[3];
		GetClientEyePosition(i, eyePos);
		float dist = GetVectorDistance(pos, eyePos);
		if (dist > radius)
			continue;

		float scale = 1.0 - (dist / radius);
		if (scale < 0.1) scale = 0.1;

		ShakeClient(i, amplitude * scale, frequency, duration);
	}
}

void ShakeClient(int client, float amplitude, float frequency, float duration)
{
	Handle msg = StartMessageOne("Shake", client);
	if (msg == null)
		return;

	BfWriteByte(msg, 0);
	BfWriteFloat(msg, amplitude);
	BfWriteFloat(msg, frequency);
	BfWriteFloat(msg, duration);
	EndMessage();
}

void ApplyExplosionDamage(const float pos[3], int owner, int directHitTarget)
{
	float damage = g_cvExplosionDamage.FloatValue;
	float radius = g_cvExplosionRadius.FloatValue;
	float bonus  = g_cvDirectHitBonusDamage.FloatValue;

	int attacker = (owner > 0 && owner <= MaxClients && IsClientInGame(owner)) ? owner : 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != TEAM_SURVIVOR || !IsPlayerAlive(i))
			continue;

		float survivorPos[3];
		GetClientAbsOrigin(i, survivorPos);
		float dist = GetVectorDistance(pos, survivorPos);
		if (dist > radius)
			continue;

		float scale = 1.0 - (dist / radius);
		if (scale < 0.15) scale = 0.15;

		float dmg = damage * scale;
		if (i == directHitTarget && bonus > 0.0)
			dmg += bonus;

		if (dmg <= 0.0)
			continue;

		int inflictor = (attacker > 0) ? attacker : i;
		SDKHooks_TakeDamage(i, inflictor, inflictor, dmg, DMG_BLAST);

		// Record attribution
		if (attacker > 0)
			RecordExplosiveAttribution(i, attacker, EXPLOSIVE_CAUSE_BLAST);
	}
}

// ============================================================================
// Attribution
// ============================================================================

void RecordExplosiveAttribution(int victim, int owner, int cause)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return;

	g_iLastExplosiveOwner[victim]    = owner;
	g_iLastExplosiveCause[victim]    = cause;
	g_fLastExplosiveDamageAt[victim] = GetGameTime();
}

int GetRecentExplosiveOwner(int victim)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return 0;

	int owner = g_iLastExplosiveOwner[victim];
	if (owner <= 0 || owner > MaxClients || !IsClientInGame(owner))
		return 0;

	if (GetGameTime() - g_fLastExplosiveDamageAt[victim] > EXPLOSIVE_ATTRIBUTION_WINDOW)
		return 0;

	return owner;
}

// Track blast damage for attribution (in case engine routes it differently)
public Action OnSurvivorTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
		return Plugin_Continue;

	if (GetClientTeam(victim) != TEAM_SURVIVOR)
		return Plugin_Continue;

	if ((damageType & DMG_BLAST) == 0)
		return Plugin_Continue;

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)
		&& GetClientTeam(attacker) == TEAM_INFECTED
		&& IsExplosiveTank(attacker, false))
	{
		RecordExplosiveAttribution(victim, attacker, EXPLOSIVE_CAUSE_BLAST);
	}

	return Plugin_Continue;
}

// ============================================================================
// Natives
// ============================================================================

public int Native_GetRecentDamageCause(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	if (GetRecentExplosiveOwner(victim) <= 0)
		return EXPLOSIVE_CAUSE_NONE;

	return g_iLastExplosiveCause[victim];
}

public int Native_GetRecentDamageAttacker(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	return GetRecentExplosiveOwner(victim);
}

// ============================================================================
// Helpers
// ============================================================================

bool IsExplosiveTank(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
		return false;

	if (requireAlive && !IsPlayerAlive(client))
		return false;

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_TANK)
		return false;

	return g_bTrackedExplosive[client];
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
		g_bTrackedExplosive[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
		return;

	g_bTrackedExplosive[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_TANK_EXPLOSIVE;
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
		ResetClientState(i);

	for (int i = 0; i <= MAXENTITIES; i++)
	{
		g_bIsExplosiveRock[i] = false;
		g_iRockOwner[i] = 0;
		g_bRockDetonated[i] = false;
	}
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedExplosive[client]      = false;
	g_iLastExplosiveOwner[client]    = 0;
	g_iLastExplosiveCause[client]    = EXPLOSIVE_CAUSE_NONE;
	g_fLastExplosiveDamageAt[client] = 0.0;
}

// ============================================================================
// Particle / Timer
// ============================================================================

void CreateParticleAt(const float pos[3], const char[] particleName, float killDelay)
{
	int particle = CreateEntityByName("info_particle_system");
	if (particle <= 0)
		return;

	DispatchKeyValue(particle, "effect_name", particleName);
	DispatchSpawn(particle);
	ActivateEntity(particle);
	TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(particle, "Start");

	if (killDelay > 0.0)
		CreateTimer(killDelay, Timer_KillEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

void PrecacheParticle(const char[] particleName)
{
	int table = FindStringTable("ParticleEffectNames");
	if (table == INVALID_STRING_TABLE)
		return;

	if (FindStringIndex(table, particleName) == INVALID_STRING_INDEX)
		AddToStringTable(table, particleName);
}

public Action Timer_KillEntity(Handle timer, int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");

	return Plugin_Stop;
}
