#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "2.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZC_SPITTER 4
#define ELITE_SUBTYPE_SPITTER_ACID_POOL 31

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvPoolCooldown;

bool g_bHasEliteApi;
bool g_bTrackedAcidPool[MAXPLAYERS + 1];
float g_fNextPoolAt[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Spitter Acid Pool",
	author = "OpenCode",
	description = "Acid Pool subtype module for elite Spitter bots.",
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
	g_cvEnable      = CreateConVar("l4d2_elite_si_spitter_acid_pool_enable",       "1",   "0=Off, 1=On.",                                              FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvPoolCooldown = CreateConVar("l4d2_elite_si_spitter_acid_pool_pool_cooldown", "2.5", "Cooldown in seconds between acid puddles dropped underfoot.", FCVAR_NOTIFY, true, 0.5, true, 30.0);

	CreateConVar("l4d2_elite_si_spitter_acid_pool_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_spitter_acid_pool");

	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end",   Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();

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

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_PreThinkPost, OnThink);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnThink);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
		return;

	ResetClientState(client);
	g_bTrackedAcidPool[client] = (zclass == ZC_SPITTER && subtype == ELITE_SUBTYPE_SPITTER_ACID_POOL);
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedAcidPool[client] = false;
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
		ResetClientState(i);
}

public void OnThink(int client)
{
	if (!g_cvEnable.BoolValue || !IsAcidPoolSpitter(client))
		return;

	float now = GetGameTime();

	// Disable native spit ability — AI sẽ không khạc từ xa
	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (IsValidEntity(ability))
		SetEntPropFloat(ability, Prop_Send, "m_timestamp", now + 9999.0);

	// Rai acid puddle dưới chân theo cooldown
	if (now >= g_fNextPoolAt[client])
	{
		DropAcidUnderfoot(client);
		g_fNextPoolAt[client] = now + g_cvPoolCooldown.FloatValue;
	}
}

void DropAcidUnderfoot(int client)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	float ang[3] = {90.0, 0.0, 0.0};
	float vel[3] = {0.0, 0.0, -100.0};
	int projectile = L4D2_SpitterPrj(client, origin, ang, vel);
	if (projectile <= MaxClients || !IsValidEntity(projectile))
		return;

	L4D_DetonateProjectile(projectile);
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedAcidPool[client] = false;
	g_fNextPoolAt[client]      = 0.0;
}

bool IsAcidPoolSpitter(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;
	if (!IsPlayerAlive(client))
		return false;
	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
		return false;
	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
		return false;
	return g_bTrackedAcidPool[client];
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
	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
	{
		g_bTrackedAcidPool[client] = false;
		return;
	}
	if (!g_bHasEliteApi)
		return;

	g_bTrackedAcidPool[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SPITTER_ACID_POOL;
}
