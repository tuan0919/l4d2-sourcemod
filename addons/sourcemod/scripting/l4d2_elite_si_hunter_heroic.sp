#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.3.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_HUNTER_HEROIC 34

#define MODEL_PIPEBOMB "models/w_models/weapons/w_eq_pipebomb.mdl"
#define PARTICLE_FUSE "weapon_pipebomb_fuse"
#define PARTICLE_LIGHT "weapon_pipebomb_blinking_light"
#define SOUND_BEEP "weapons/hegrenade/beep.wav"
#define SOUND_EXPLODE "weapons/hegrenade/explode5.wav"
#define EXPLOSION_SPRITE "materials/sprites/zerogxplode.vmt"

ConVar g_cvEnable;
ConVar g_cvFuseTime;
ConVar g_cvExplosionDamage;
ConVar g_cvExplosionRadius;
ConVar g_cvDropOffset;
ConVar g_cvBeepInterval;

bool g_bTrackedHeroic[MAXPLAYERS + 1];
bool g_bHasPipeAvailable[MAXPLAYERS + 1];
bool g_bBombArmed[MAXPLAYERS + 1];
int g_iPinnedVictim[MAXPLAYERS + 1];
int g_iPinnedHunter[MAXPLAYERS + 1];
int g_iBombSerial[MAXPLAYERS + 1];

int g_iHandBombRef[MAXPLAYERS + 1];
int g_iHandFuseRef[MAXPLAYERS + 1];
int g_iHandLightRef[MAXPLAYERS + 1];
int g_iWorldBombRef[MAXPLAYERS + 1];
int g_iWorldFuseRef[MAXPLAYERS + 1];
int g_iWorldLightRef[MAXPLAYERS + 1];

int g_iExplosionSprite = -1;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Hunter Heroic",
	author = "OpenCode",
	description = "Heroic subtype module for elite Hunter bots.",
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

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_hunter_heroic_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFuseTime = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_fuse", "3.0", "Fuse time in seconds before Heroic Hunter pipebomb explodes.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvExplosionDamage = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_damage", "220.0", "Explosion damage dealt by Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 1.0, true, 1000.0);
	g_cvExplosionRadius = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_radius", "320.0", "Explosion radius of Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvDropOffset = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_drop_offset", "28.0", "Offset used when dropping the Heroic Hunter pipebomb near the pinned target.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvBeepInterval = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_beep_interval", "0.75", "Interval in seconds between Heroic Hunter pipebomb beeps.", FCVAR_NOTIFY, true, 0.1, true, 5.0);

	CreateConVar("l4d2_elite_si_hunter_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hunter_heroic");

	HookEvent("lunge_pounce", Event_LungePounce, EventHookMode_Post);
	HookEvent("pounce_end", Event_PounceEnd, EventHookMode_Post);
	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);

	PrecacheAssets();
	ResetAllState();
}

public void OnMapStart()
{
	PrecacheAssets();
	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client, true, false);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client, true, false);
}

public void OnEntityDestroyed(int entity)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (EntRefMatches(g_iHandBombRef[client], entity))
		{
			g_iHandBombRef[client] = 0;
		}
		if (EntRefMatches(g_iHandFuseRef[client], entity))
		{
			g_iHandFuseRef[client] = 0;
		}
		if (EntRefMatches(g_iHandLightRef[client], entity))
		{
			g_iHandLightRef[client] = 0;
		}
		if (EntRefMatches(g_iWorldBombRef[client], entity))
		{
			g_iWorldBombRef[client] = 0;
		}
		if (EntRefMatches(g_iWorldFuseRef[client], entity))
		{
			g_iWorldFuseRef[client] = 0;
		}
		if (EntRefMatches(g_iWorldLightRef[client], entity))
		{
			g_iWorldLightRef[client] = 0;
		}
	}
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetClientState(client, true, false);
	g_bTrackedHeroic[client] = (zclass == ZC_HUNTER && subtype == ELITE_SUBTYPE_HUNTER_HEROIC);
	if (g_bTrackedHeroic[client] && IsClientInGame(client) && IsPlayerAlive(client))
	{
		g_bHasPipeAvailable[client] = true;
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetClientState(client, true, false);
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		ResetClientState(client, true, false);
	}
}

public void Event_LungePounce(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int hunter = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if (!IsHeroicHunter(hunter, true) || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	ClearPinnedState(hunter);
	g_iPinnedVictim[hunter] = victim;
	g_iPinnedHunter[victim] = hunter;

	if (!g_bHasPipeAvailable[hunter] || g_bBombArmed[hunter])
	{
		return;
	}

	ArmBombOnHunter(hunter);
}

public void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if (victim <= 0 || victim > MaxClients)
	{
		return;
	}

	int hunter = g_iPinnedHunter[victim];
	g_iPinnedHunter[victim] = 0;
	if (hunter <= 0 || hunter > MaxClients)
	{
		return;
	}

	g_iPinnedVictim[hunter] = 0;
	if (GetHandBombEntity(hunter) == INVALID_ENT_REFERENCE)
	{
		return;
	}

	float origin[3];
	GetBombDropOrigin(hunter, victim, origin);
	MoveBombToWorld(hunter, origin);
}

public void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int hunter = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHeroicHunter(hunter, true) || g_iPinnedVictim[hunter] == 0)
	{
		return;
	}

	ClearPinnedState(hunter);
	ResetClientState(hunter, true, true);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ClearPinnedState(client);

	if (!g_cvEnable.BoolValue || !IsHeroicHunter(client, false))
	{
		ResetClientState(client, true, false);
		return;
	}

	if (GetWorldBombEntity(client) != INVALID_ENT_REFERENCE)
	{
		return;
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);
	origin[2] += 6.0;

	if (GetHandBombEntity(client) != INVALID_ENT_REFERENCE)
	{
		MoveBombToWorld(client, origin);
		return;
	}

	if (g_bHasPipeAvailable[client] && !g_bBombArmed[client])
	{
		ArmBombOnDeath(client, origin);
	}
}

void PrecacheAssets()
{
	PrecacheModel(MODEL_PIPEBOMB, true);
	PrecacheSound(SOUND_BEEP, true);
	PrecacheSound(SOUND_EXPLODE, true);
	PrecacheParticle(PARTICLE_FUSE);
	PrecacheParticle(PARTICLE_LIGHT);
	g_iExplosionSprite = PrecacheModel(EXPLOSION_SPRITE, true);
}

void ArmBombOnHunter(int hunter)
{
	CancelBomb(hunter, false);
	if (!CreateHandBombVisual(hunter))
	{
		return;
	}

	g_bHasPipeAvailable[hunter] = false;
	g_bBombArmed[hunter] = true;
	g_iBombSerial[hunter]++;
	StartBombTimers(hunter);
}

void ArmBombOnDeath(int hunter, const float origin[3])
{
	CancelBomb(hunter, false);
	if (!CreateWorldBombVisual(hunter, origin))
	{
		return;
	}

	g_bHasPipeAvailable[hunter] = false;
	g_bBombArmed[hunter] = true;
	g_iBombSerial[hunter]++;
	StartBombTimers(hunter);
}

void StartBombTimers(int hunter)
{
	DataPack beepPack = new DataPack();
	beepPack.WriteCell(hunter);
	beepPack.WriteCell(g_iBombSerial[hunter]);
	CreateTimer(g_cvBeepInterval.FloatValue, Timer_BeepBomb, beepPack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);

	DataPack explodePack = new DataPack();
	explodePack.WriteCell(hunter);
	explodePack.WriteCell(g_iBombSerial[hunter]);
	CreateTimer(g_cvFuseTime.FloatValue, Timer_DetonateBomb, explodePack, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action Timer_BeepBomb(Handle timer, DataPack pack)
{
	pack.Reset();
	int hunter = pack.ReadCell();
	int serial = pack.ReadCell();
	if (!IsBombTimerValid(hunter, serial))
	{
		return Plugin_Stop;
	}

	float origin[3];
	if (!GetBombVisualOrigin(hunter, origin))
	{
		return Plugin_Stop;
	}

	EmitAmbientSound(SOUND_BEEP, origin, hunter, SNDLEVEL_RAIDSIREN);
	return Plugin_Continue;
}

public Action Timer_DetonateBomb(Handle timer, DataPack pack)
{
	pack.Reset();
	int hunter = pack.ReadCell();
	int serial = pack.ReadCell();
	if (!IsBombTimerValid(hunter, serial))
	{
		return Plugin_Stop;
	}

	float origin[3];
	if (!GetBombVisualOrigin(hunter, origin))
	{
		CancelBomb(hunter, false);
		return Plugin_Stop;
	}

	CancelBomb(hunter, false);
	DetonateBomb(hunter, origin);
	return Plugin_Stop;
}

bool CreateHandBombVisual(int hunter)
{
	int entity = CreateBombModel();
	if (entity == INVALID_ENT_REFERENCE)
	{
		return false;
	}

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", hunter);
	SetVariantString("rhand");
	AcceptEntityInput(entity, "SetParentAttachment", hunter);
	TeleportEntity(entity, NULL_VECTOR, view_as<float>({90.0, 0.0, 0.0}), NULL_VECTOR);

	g_iHandBombRef[hunter] = EntIndexToEntRef(entity);
	g_iHandFuseRef[hunter] = CreateParticle(entity, PARTICLE_FUSE, "fuse");
	g_iHandLightRef[hunter] = CreateParticle(entity, PARTICLE_LIGHT, "pipebomb_light");
	return true;
}

bool CreateWorldBombVisual(int hunter, const float origin[3])
{
	int entity = CreateBombModel();
	if (entity == INVALID_ENT_REFERENCE)
	{
		return false;
	}

	TeleportEntity(entity, origin, view_as<float>({90.0, 0.0, 0.0}), NULL_VECTOR);
	g_iWorldBombRef[hunter] = EntIndexToEntRef(entity);
	g_iWorldFuseRef[hunter] = CreateParticle(entity, PARTICLE_FUSE, "fuse");
	g_iWorldLightRef[hunter] = CreateParticle(entity, PARTICLE_LIGHT, "pipebomb_light");
	return true;
}

void MoveBombToWorld(int hunter, const float origin[3])
{
	if (!g_bBombArmed[hunter])
	{
		return;
	}

	KillHandVisual(hunter);
	CreateWorldBombVisual(hunter, origin);
}

int CreateBombModel()
{
	int entity = CreateEntityByName("prop_dynamic_override");
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return INVALID_ENT_REFERENCE;
	}

	DispatchKeyValue(entity, "model", MODEL_PIPEBOMB);
	DispatchKeyValue(entity, "solid", "0");
	DispatchSpawn(entity);
	SetEntityMoveType(entity, MOVETYPE_NONE);
	SetEntProp(entity, Prop_Send, "m_nSolidType", 0);
	return entity;
}

int CreateParticle(int target, const char[] effectName, const char[] attachment)
{
	int entity = CreateEntityByName("info_particle_system");
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return 0;
	}

	DispatchKeyValue(entity, "effect_name", effectName);
	DispatchSpawn(entity);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Start");

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", target);
	SetVariantString(attachment);
	AcceptEntityInput(entity, "SetParentAttachment", target);
	return EntIndexToEntRef(entity);
}

void DetonateBomb(int attacker, const float origin[3])
{
	if (g_iExplosionSprite > 0)
	{
		TE_SetupExplosion(origin, g_iExplosionSprite, 1.0, 1, 0, RoundToNearest(g_cvExplosionRadius.FloatValue), 600);
		TE_SendToAll();
	}

	EmitAmbientSound(SOUND_EXPLODE, origin, attacker, SNDLEVEL_RAIDSIREN);

	float radius = g_cvExplosionRadius.FloatValue;
	float baseDamage = g_cvExplosionDamage.FloatValue;
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float survivorOrigin[3];
		GetClientAbsOrigin(survivor, survivorOrigin);
		float distance = GetVectorDistance(origin, survivorOrigin);
		if (distance > radius)
		{
			continue;
		}

		float damageScale = 1.0 - (distance / radius);
		if (damageScale < 0.15)
		{
			damageScale = 0.15;
		}

		SDKHooks_TakeDamage(survivor, attacker, attacker, baseDamage * damageScale, DMG_BLAST);
	}
}

bool GetBombVisualOrigin(int hunter, float origin[3])
{
	int worldBomb = GetWorldBombEntity(hunter);
	if (worldBomb != INVALID_ENT_REFERENCE)
	{
		GetEntPropVector(worldBomb, Prop_Data, "m_vecOrigin", origin);
		return true;
	}

	int handBomb = GetHandBombEntity(hunter);
	if (handBomb != INVALID_ENT_REFERENCE)
	{
		GetEntPropVector(handBomb, Prop_Data, "m_vecOrigin", origin);
		return true;
	}

	if (hunter > 0 && hunter <= MaxClients && IsClientInGame(hunter))
	{
		GetClientAbsOrigin(hunter, origin);
		origin[2] += 40.0;
		return true;
	}

	return false;
}

void GetBombDropOrigin(int hunter, int victim, float origin[3])
{
	if (IsValidAliveSurvivor(victim))
	{
		GetClientAbsOrigin(victim, origin);
	}
	else
	{
		GetClientAbsOrigin(hunter, origin);
	}

	float hunterOrigin[3];
	GetClientAbsOrigin(hunter, hunterOrigin);
	float dir[3];
	MakeVectorFromPoints(hunterOrigin, origin, dir);
	if (NormalizeVector(dir, dir) < 0.001)
	{
		dir[0] = 1.0;
		dir[1] = 0.0;
		dir[2] = 0.0;
	}

	origin[0] += dir[0] * g_cvDropOffset.FloatValue;
	origin[1] += dir[1] * g_cvDropOffset.FloatValue;
	origin[2] += 6.0;
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i, true, false);
	}
}

void ResetClientState(int client, bool killVisuals, bool restorePipe)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (killVisuals)
	{
		CancelBomb(client, restorePipe);
	}

	ClearPinnedState(client);
	g_bTrackedHeroic[client] = false;
	if (!restorePipe)
	{
		g_bHasPipeAvailable[client] = false;
	}
	else
	{
		g_bHasPipeAvailable[client] = IsHeroicHunter(client, true);
	}
	if (!killVisuals)
	{
		g_bBombArmed[client] = false;
	}
	if (!killVisuals)
	{
		g_iBombSerial[client]++;
	}
	if (!restorePipe)
	{
		g_bHasPipeAvailable[client] = false;
	}
	ClearBombRefs(client);
}

void CancelBomb(int hunter, bool restorePipe)
{
	KillHandVisual(hunter);
	KillWorldVisual(hunter);
	g_bBombArmed[hunter] = false;
	g_iBombSerial[hunter]++;
	if (restorePipe && IsHeroicHunter(hunter, true))
	{
		g_bHasPipeAvailable[hunter] = true;
	}
	else if (!restorePipe)
	{
		g_bHasPipeAvailable[hunter] = false;
	}
	ClearBombRefs(hunter);
}

void KillHandVisual(int hunter)
{
	KillRefEntity(g_iHandFuseRef[hunter]);
	KillRefEntity(g_iHandLightRef[hunter]);
	KillRefEntity(g_iHandBombRef[hunter]);
	g_iHandFuseRef[hunter] = 0;
	g_iHandLightRef[hunter] = 0;
	g_iHandBombRef[hunter] = 0;
}

void KillWorldVisual(int hunter)
{
	KillRefEntity(g_iWorldFuseRef[hunter]);
	KillRefEntity(g_iWorldLightRef[hunter]);
	KillRefEntity(g_iWorldBombRef[hunter]);
	g_iWorldFuseRef[hunter] = 0;
	g_iWorldLightRef[hunter] = 0;
	g_iWorldBombRef[hunter] = 0;
}

void ClearBombRefs(int hunter)
{
	g_iHandBombRef[hunter] = 0;
	g_iHandFuseRef[hunter] = 0;
	g_iHandLightRef[hunter] = 0;
	g_iWorldBombRef[hunter] = 0;
	g_iWorldFuseRef[hunter] = 0;
	g_iWorldLightRef[hunter] = 0;
}

void KillRefEntity(int &entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}
	entityRef = 0;
}

bool IsBombTimerValid(int hunter, int serial)
{
	return hunter > 0
		&& hunter <= MaxClients
		&& g_bBombArmed[hunter]
		&& g_iBombSerial[hunter] == serial;
}

int GetHandBombEntity(int hunter)
{
	int entity = EntRefToEntIndex(g_iHandBombRef[hunter]);
	if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
	{
		return INVALID_ENT_REFERENCE;
	}

	return entity;
}

int GetWorldBombEntity(int hunter)
{
	int entity = EntRefToEntIndex(g_iWorldBombRef[hunter]);
	if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
	{
		return INVALID_ENT_REFERENCE;
	}

	return entity;
}

void ClearPinnedState(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	int victim = g_iPinnedVictim[client];
	if (victim > 0 && victim <= MaxClients && g_iPinnedHunter[victim] == client)
	{
		g_iPinnedHunter[victim] = 0;
	}
	g_iPinnedVictim[client] = 0;

	int hunter = g_iPinnedHunter[client];
	if (hunter > 0 && hunter <= MaxClients && g_iPinnedVictim[hunter] == client)
	{
		g_iPinnedVictim[hunter] = 0;
	}
	g_iPinnedHunter[client] = 0;
}

bool IsHeroicHunter(int client, bool requireAlive)
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

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_HUNTER)
	{
		return false;
	}

	return g_bTrackedHeroic[client];
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

bool EntRefMatches(int entityRef, int entity)
{
	return entityRef != 0 && EntRefToEntIndex(entityRef) == entity;
}

void PrecacheParticle(const char[] effectName)
{
	static int table = INVALID_STRING_TABLE;
	if (table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("ParticleEffectNames");
	}

	if (table == INVALID_STRING_TABLE)
	{
		return;
	}

	if (FindStringIndex(table, effectName) == INVALID_STRING_INDEX)
	{
		bool locked = LockStringTables(false);
		AddToStringTable(table, effectName);
		LockStringTables(locked);
	}
}
