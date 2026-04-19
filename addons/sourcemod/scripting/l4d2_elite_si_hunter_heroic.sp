#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_HUNTER_HEROIC 34

#define PARTICLE_FUSE "weapon_pipebomb_fuse"
#define PARTICLE_LIGHT "weapon_pipebomb_blinking_light"

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvFuseTime;
ConVar g_cvExplosionDamage;
ConVar g_cvExplosionRadius;
ConVar g_cvDropOffset;

bool g_bHasEliteApi;
bool g_bTrackedHeroic[MAXPLAYERS + 1];
bool g_bHasPipeInHand[MAXPLAYERS + 1];
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

	MarkNativeAsOptional("EliteSI_IsElite");
	MarkNativeAsOptional("EliteSI_GetSubtype");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_hunter_heroic_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFuseTime = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_fuse", "3.0", "Fuse time in seconds before Heroic Hunter pipebomb explodes.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvExplosionDamage = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_damage", "220.0", "Explosion damage dealt by Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 1.0, true, 1000.0);
	g_cvExplosionRadius = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_radius", "320.0", "Explosion radius of Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvDropOffset = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_drop_offset", "28.0", "Ground offset used when dropping the Heroic Hunter pipebomb near the target.", FCVAR_NOTIFY, true, 0.0, true, 200.0);

	CreateConVar("l4d2_elite_si_hunter_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hunter_heroic");

	HookEvent("lunge_pounce", Event_LungePounce, EventHookMode_Post);
	HookEvent("pounce_end", Event_PounceEnd, EventHookMode_Post);
	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerReset, EventHookMode_Post);
	HookEvent("player_team", Event_PlayerReset, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();
	ResetAllState();
}

public void OnMapStart()
{
	ResetAllState();
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
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
}

public void OnEntityDestroyed(int entity)
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (g_iActivePipeRef[client] == EntIndexToEntRef(entity))
		{
			g_iActivePipeRef[client] = 0;
		}
	}
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetClientState(client);
	g_bTrackedHeroic[client] = (zclass == ZC_HUNTER && subtype == ELITE_SUBTYPE_HUNTER_HEROIC);
	g_bHasPipeInHand[client] = g_bTrackedHeroic[client];
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetClientState(client);
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

public void Event_PlayerReset(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0)
	{
		ResetClientState(client);
	}
}

public void Event_LungePounce(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("victim"));
	int hunter = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHeroicHunter(hunter, true) || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	g_iPinnedVictim[hunter] = victim;
	g_iPinnedHunter[victim] = hunter;

	if (g_bHasPipeInHand[hunter] && GetActivePipeEntity(hunter) == INVALID_ENT_REFERENCE)
	{
		DropPipeBombNearVictim(hunter, victim);
	}
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
}

public void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int hunter = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHeroicHunter(hunter, true))
	{
		return;
	}

	int victim = g_iPinnedVictim[hunter];
	if (!IsValidAliveSurvivor(victim))
	{
		return;
	}

	ReleaseHeroicPounce(hunter, victim);
	ReclaimPipeBomb(hunter);
}

void ReleaseHeroicPounce(int hunter, int victim)
{
	if (victim > 0 && victim <= MaxClients)
	{
		g_iPinnedHunter[victim] = 0;
	}
	g_iPinnedVictim[hunter] = 0;

	float vec[3] = {0.0, 0.0, 260.0};
	TeleportEntity(hunter, NULL_VECTOR, NULL_VECTOR, vec);
}

void ReclaimPipeBomb(int hunter)
{
	int entity = GetActivePipeEntity(hunter);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}

	g_iActivePipeRef[hunter] = 0;
	g_bHasPipeInHand[hunter] = true;
}

void DropPipeBombNearVictim(int hunter, int victim)
{
	float pos[3];
	GetClientAbsOrigin(victim, pos);
	pos[0] += g_cvDropOffset.FloatValue;
	pos[2] += 6.0;

	float ang[3] = {0.0, 0.0, 0.0};
	float vel[3] = {0.0, 0.0, 0.0};
	int pipe = L4D_PipeBombPrj(hunter, pos, ang, false, vel, vel);
	if (pipe <= MaxClients || !IsValidEntity(pipe))
	{
		return;
	}

	g_iActivePipeRef[hunter] = EntIndexToEntRef(pipe);
	g_bHasPipeInHand[hunter] = false;

	SetEntPropFloat(pipe, Prop_Data, "m_DmgRadius", g_cvExplosionRadius.FloatValue);
	SetEntPropFloat(pipe, Prop_Data, "m_flDamage", g_cvExplosionDamage.FloatValue);
	SetEntityMoveType(pipe, MOVETYPE_FLYGRAVITY);
	SetEntPropEnt(pipe, Prop_Send, "m_hOwnerEntity", hunter);

	CreateParticle(pipe, 0);
	CreateParticle(pipe, 1);
	CreateTimer(g_cvFuseTime.FloatValue, Timer_DetonatePipeBomb, EntIndexToEntRef(pipe), TIMER_FLAG_NO_MAPCHANGE);
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

public Action Timer_DetonatePipeBomb(Handle timer, int pipeRef)
{
	int pipe = EntRefToEntIndex(pipeRef);
	if (pipe != INVALID_ENT_REFERENCE && IsValidEntity(pipe))
	{
		L4D_DetonateProjectile(pipe);
	}

	return Plugin_Stop;
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

	int entity = GetActivePipeEntity(client);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}

	g_bTrackedHeroic[client] = false;
	g_bHasPipeInHand[client] = false;
	g_iPinnedVictim[client] = 0;
	g_iPinnedHunter[client] = 0;
	g_iActivePipeRef[client] = 0;
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

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_HUNTER)
	{
		g_bTrackedHeroic[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedHeroic[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_HUNTER_HEROIC;
	if (g_bTrackedHeroic[client] && GetActivePipeEntity(client) == INVALID_ENT_REFERENCE)
	{
		g_bHasPipeInHand[client] = true;
	}
}
