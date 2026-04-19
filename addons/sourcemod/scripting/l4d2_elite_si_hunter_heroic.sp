#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.2.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_HUNTER_HEROIC 34

#define GAMEDATA_FILE "l4d_pipebomb_shove"
#define PARTICLE_FUSE "weapon_pipebomb_fuse"
#define PARTICLE_LIGHT "weapon_pipebomb_blinking_light"

ConVar g_cvEnable;
ConVar g_cvFuseTime;
ConVar g_cvExplosionDamage;
ConVar g_cvExplosionRadius;
ConVar g_cvDropOffset;
ConVar g_cvEnginePipeFuse;

Handle g_hSdkActivatePipe;

bool g_bFuseSwitching;
bool g_bTrackedHeroic[MAXPLAYERS + 1];
bool g_bHasPipeAvailable[MAXPLAYERS + 1];
bool g_bPipeAttached[MAXPLAYERS + 1];
int g_iPinnedVictim[MAXPLAYERS + 1];
int g_iPinnedHunter[MAXPLAYERS + 1];
int g_iActivePipeRef[MAXPLAYERS + 1];

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
	LoadPipebombSdkCall();

	g_cvEnable = CreateConVar("l4d2_elite_si_hunter_heroic_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFuseTime = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_fuse", "3.0", "Fuse time in seconds before Heroic Hunter pipebomb explodes.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvExplosionDamage = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_damage", "220.0", "Explosion damage dealt by Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 1.0, true, 1000.0);
	g_cvExplosionRadius = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_radius", "320.0", "Explosion radius of Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvDropOffset = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_drop_offset", "28.0", "Offset used when dropping the Heroic Hunter pipebomb near the pinned target.", FCVAR_NOTIFY, true, 0.0, true, 200.0);

	CreateConVar("l4d2_elite_si_hunter_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hunter_heroic");

	g_cvEnginePipeFuse = FindConVar("pipe_bomb_timer_duration");
	if (g_cvEnginePipeFuse == null)
	{
		SetFailState("Missing required ConVar: pipe_bomb_timer_duration");
	}
	g_cvEnginePipeFuse.AddChangeHook(ConVarChanged_PipeFuse);

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

	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client, true);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client, true);
}

public void OnEntityDestroyed(int entity)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_iActivePipeRef[client] != 0 && EntRefToEntIndex(g_iActivePipeRef[client]) == entity)
		{
			g_iActivePipeRef[client] = 0;
			g_bPipeAttached[client] = false;
		}
	}
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetClientState(client, true);
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

	ResetClientState(client, true);
}

public void ConVarChanged_PipeFuse(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (g_bFuseSwitching)
	{
		return;
	}
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
		ResetClientState(client, true);
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

	if (!g_bHasPipeAvailable[hunter] || GetActivePipeEntity(hunter) != INVALID_ENT_REFERENCE)
	{
		return;
	}

	AttachPipeToHunter(hunter);
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
	if (!g_bPipeAttached[hunter])
	{
		return;
	}

	float origin[3];
	GetBombDropOrigin(hunter, victim, origin);
	ReleaseActivePipeToGround(hunter, origin);
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
	ReclaimPipeBomb(hunter);
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
		ResetClientState(client, true);
		return;
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);
	origin[2] += 6.0;

	int pipe = GetActivePipeEntity(client);
	if (pipe != INVALID_ENT_REFERENCE)
	{
		ReleaseActivePipeToGround(client, origin);
		return;
	}

	if (!g_bHasPipeAvailable[client])
	{
		ResetClientState(client, true);
		return;
	}

	int entity = CreatePipeBombProjectile(client, origin);
	if (entity != INVALID_ENT_REFERENCE)
	{
		g_iActivePipeRef[client] = EntIndexToEntRef(entity);
		g_bHasPipeAvailable[client] = false;
		g_bPipeAttached[client] = false;
	}
}

void LoadPipebombSdkCall()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "gamedata/%s.txt", GAMEDATA_FILE);
	if (!FileExists(path))
	{
		SetFailState("Missing required file: %s", path);
	}

	GameData gameData = LoadGameConfigFile(GAMEDATA_FILE);
	if (gameData == null)
	{
		SetFailState("Failed to load gamedata: %s", GAMEDATA_FILE);
	}

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CPipeBombProjectile_Create"))
	{
		delete gameData;
		SetFailState("Could not load CPipeBombProjectile_Create signature.");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkActivatePipe = EndPrepSDKCall();
	delete gameData;

	if (g_hSdkActivatePipe == null)
	{
		SetFailState("Could not prep CPipeBombProjectile_Create.");
	}
}

void AttachPipeToHunter(int hunter)
{
	float origin[3];
	GetClientAbsOrigin(hunter, origin);
	origin[2] += 40.0;

	int entity = CreatePipeBombProjectile(hunter, origin);
	if (entity == INVALID_ENT_REFERENCE)
	{
		return;
	}

	SetEntProp(entity, Prop_Send, "m_nSolidType", 0);
	SetEntityMoveType(entity, MOVETYPE_NONE);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", hunter);
	if (GetRandomInt(0, 1) == 0)
	{
		SetVariantString("rhand");
	}
	else
	{
		SetVariantString("lhand");
	}
	AcceptEntityInput(entity, "SetParentAttachment", hunter);
	TeleportEntity(entity, NULL_VECTOR, view_as<float>({90.0, 0.0, 0.0}), NULL_VECTOR);

	g_iActivePipeRef[hunter] = EntIndexToEntRef(entity);
	g_bHasPipeAvailable[hunter] = false;
	g_bPipeAttached[hunter] = true;
}

int CreatePipeBombProjectile(int owner, const float origin[3])
{
	float ang[3] = {0.0, 0.0, 0.0};
	float vel[3] = {0.0, 0.0, 0.0};

	int restoreFuse = g_cvEnginePipeFuse.IntValue;
	g_bFuseSwitching = true;
	g_cvEnginePipeFuse.SetInt(RoundToNearest(g_cvFuseTime.FloatValue));
	int entity = SDKCall(g_hSdkActivatePipe, origin, ang, vel, vel, owner, 2.0);
	g_cvEnginePipeFuse.SetInt(restoreFuse);
	g_bFuseSwitching = false;

	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return INVALID_ENT_REFERENCE;
	}

	SetEntPropFloat(entity, Prop_Data, "m_DmgRadius", g_cvExplosionRadius.FloatValue);
	SetEntPropFloat(entity, Prop_Data, "m_flDamage", g_cvExplosionDamage.FloatValue);
	CreateParticle(entity, 0);
	CreateParticle(entity, 1);
	return entity;
}

void ReleaseActivePipeToGround(int hunter, const float origin[3])
{
	int entity = GetActivePipeEntity(hunter);
	if (entity == INVALID_ENT_REFERENCE)
	{
		return;
	}

	SetEntityMoveType(entity, MOVETYPE_FLYGRAVITY);
	AcceptEntityInput(entity, "ClearParent");
	TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);
	g_bPipeAttached[hunter] = false;
	g_bHasPipeAvailable[hunter] = false;
}

void ReclaimPipeBomb(int hunter)
{
	int entity = GetActivePipeEntity(hunter);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}

	g_iActivePipeRef[hunter] = 0;
	g_bPipeAttached[hunter] = false;
	if (IsHeroicHunter(hunter, true))
	{
		g_bHasPipeAvailable[hunter] = true;
	}
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

	float hunterPos[3];
	GetClientAbsOrigin(hunter, hunterPos);
	float dir[3];
	MakeVectorFromPoints(hunterPos, origin, dir);
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

void CreateParticle(int target, int type)
{
	int entity = CreateEntityByName("info_particle_system");
	if (entity <= MaxClients || !IsValidEntity(entity))
	{
		return;
	}

	if (type == 0)
	{
		DispatchKeyValue(entity, "effect_name", PARTICLE_FUSE);
	}
	else
	{
		DispatchKeyValue(entity, "effect_name", PARTICLE_LIGHT);
	}

	DispatchSpawn(entity);
	ActivateEntity(entity);
	AcceptEntityInput(entity, "Start");

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", target);
	if (type == 0)
	{
		SetVariantString("fuse");
	}
	else
	{
		SetVariantString("pipebomb_light");
	}
	AcceptEntityInput(entity, "SetParentAttachment", target);
}

int GetActivePipeEntity(int hunter)
{
	int entity = EntRefToEntIndex(g_iActivePipeRef[hunter]);
	if (entity == INVALID_ENT_REFERENCE || !IsValidEntity(entity))
	{
		return INVALID_ENT_REFERENCE;
	}

	return entity;
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i, true);
	}
}

void ResetClientState(int client, bool killPipe)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (killPipe)
	{
		int entity = GetActivePipeEntity(client);
		if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
		{
			AcceptEntityInput(entity, "Kill");
		}
	}

	ClearPinnedState(client);
	g_bTrackedHeroic[client] = false;
	g_bHasPipeAvailable[client] = false;
	g_bPipeAttached[client] = false;
	g_iActivePipeRef[client] = 0;
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
