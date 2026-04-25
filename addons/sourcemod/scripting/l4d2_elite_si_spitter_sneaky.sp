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
#define ELITE_SUBTYPE_SPITTER_SNEAKY 32

#define SNEAKY_MAX_SPITS 3

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvCloakFadeAlpha;
ConVar g_cvCloakActiveDuration;
ConVar g_cvCloakCooldown;
ConVar g_cvSpitCooldown;

bool g_bHasEliteApi;
bool g_bTrackedSneaky[MAXPLAYERS + 1];
bool g_bCloaked[MAXPLAYERS + 1];
float g_fCloakUntil[MAXPLAYERS + 1];
float g_fNextCloakAt[MAXPLAYERS + 1];
float g_fNextSpitAt[MAXPLAYERS + 1];
int g_iSpitsRemaining[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Spitter Sneaky",
	author = "OpenCode",
	description = "Sneaky subtype module for elite Spitter bots.",
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
	g_cvEnable               = CreateConVar("l4d2_elite_si_spitter_sneaky_enable",          "1",    "0=Off, 1=On.",                                                                    FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvCloakFadeAlpha       = CreateConVar("l4d2_elite_si_spitter_sneaky_cloak_alpha",      "102",  "Render alpha while cloaked (102 ~= 60% fade).",                                   FCVAR_NOTIFY, true, 0.0, true, 255.0);
	g_cvCloakActiveDuration  = CreateConVar("l4d2_elite_si_spitter_sneaky_cloak_duration",   "5.0",  "Duration in seconds of each cloak window.",                                       FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvCloakCooldown        = CreateConVar("l4d2_elite_si_spitter_sneaky_cloak_cooldown",   "8.0",  "Cooldown in seconds after cloak ends before next cloak can start.",               FCVAR_NOTIFY, true, 1.0, true, 60.0);
	g_cvSpitCooldown         = CreateConVar("l4d2_elite_si_spitter_sneaky_spit_cooldown",    "3.0",  "Cooldown in seconds between each of the 3 manual acid spits.",                   FCVAR_NOTIFY, true, 0.5, true, 30.0);

	CreateConVar("l4d2_elite_si_spitter_sneaky_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_spitter_sneaky");

	HookEvent("player_hurt",   Event_PlayerHurt,   EventHookMode_Post);
	HookEvent("round_start",   Event_RoundReset,   EventHookMode_PostNoCopy);
	HookEvent("round_end",     Event_RoundReset,   EventHookMode_PostNoCopy);

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
	SDKHook(client, SDKHook_PreThinkPost,  OnThink);
	SDKHook(client, SDKHook_OnTakeDamage,  OnTakeDamage);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnThink);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
		return;

	ResetClientState(client);
	g_bTrackedSneaky[client] = (zclass == ZC_SPITTER && subtype == ELITE_SUBTYPE_SPITTER_SNEAKY);

	if (g_bTrackedSneaky[client])
	{
		// Bắt đầu với cloak ngay khi spawn
		EnterCloak(client, GetGameTime());
		g_iSpitsRemaining[client] = SNEAKY_MAX_SPITS;
		g_fNextSpitAt[client]     = GetGameTime() + 2.0;
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	bool wasSneaky = g_bTrackedSneaky[client];
	ResetClientState(client);
	if (wasSneaky)
		RestoreVisual(client);
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bTrackedSneaky[i])
			RestoreVisual(i);
		ResetClientState(i);
	}
}

// Khi bị survivor hit → break cloak nếu đang cloaked
public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
		return;

	int victim   = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (!IsSneakySpitter(victim) || !IsValidAliveSurvivor(attacker))
		return;

	if (!g_bCloaked[victim])
		return;

	BreakCloak(victim);
}

public void OnThink(int client)
{
	if (!IsSneakySpitter(client))
		return;

	float now = GetGameTime();

	// Cloak cycle
	if (g_bCloaked[client])
	{
		if (now >= g_fCloakUntil[client])
			BreakCloak(client);
	}
	else if (now >= g_fNextCloakAt[client] && g_fNextCloakAt[client] > 0.0)
	{
		EnterCloak(client, now);
	}

	// Spit cycle: 3 lần, mỗi lần cách nhau spit_cooldown giây
	// Chỉ spit khi không đang cloaked
	if (!g_bCloaked[client] && g_iSpitsRemaining[client] > 0 && now >= g_fNextSpitAt[client])
	{
		TryFireSpit(client, now);
	}

	// Lock native spit ability để AI không tự spit thêm
	LockNativeSpit(client, now);
}

// Chặn bullet damage khi đang cloaked
public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!IsSneakySpitter(victim) || damage <= 0.0 || !g_bCloaked[victim])
		return Plugin_Continue;

	if ((damageType & DMG_BULLET) != 0)
	{
		damage = 0.0;
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

// ── Helpers ──────────────────────────────────────────────────────────────────

void EnterCloak(int client, float now)
{
	g_bCloaked[client]    = true;
	g_fCloakUntil[client] = now + g_cvCloakActiveDuration.FloatValue;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, 120, 255, 180, g_cvCloakFadeAlpha.IntValue);
}

void BreakCloak(int client)
{
	g_bCloaked[client]    = false;
	g_fCloakUntil[client] = 0.0;
	// Cooldown phải > cloak duration để tránh tàng hình liên tục
	g_fNextCloakAt[client] = GetGameTime() + g_cvCloakCooldown.FloatValue;
	RestoreVisual(client);
}

void RestoreVisual(int client)
{
	if (!IsClientInGame(client) || GetClientTeam(client) != TEAM_INFECTED)
		return;
	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
		return;

	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, 120, 255, 180, 255);
}

void LockNativeSpit(int client, float now)
{
	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (IsValidEntity(ability))
		SetEntPropFloat(ability, Prop_Send, "m_timestamp", now + 9999.0);
}

void TryFireSpit(int client, float now)
{
	int target = FindClosestSurvivor(client, 2000.0);
	if (target <= 0)
	{
		g_fNextSpitAt[client] = now + 0.5;
		return;
	}

	float selfOrigin[3];
	float targetPos[3];
	GetClientAbsOrigin(client, selfOrigin);
	GetClientAbsOrigin(target, targetPos);
	selfOrigin[2] += 40.0;

	float dir[3];
	MakeVectorFromPoints(selfOrigin, targetPos, dir);
	NormalizeVector(dir, dir);
	ScaleVector(dir, 650.0);

	float ang[3];
	GetVectorAngles(dir, ang);
	L4D2_SpitterPrj(client, selfOrigin, ang, dir);

	g_iSpitsRemaining[client]--;
	g_fNextSpitAt[client] = now + g_cvSpitCooldown.FloatValue;

	// Hết 3 lần → reset lại chu kỳ sau cloak tiếp theo
	if (g_iSpitsRemaining[client] <= 0)
	{
		g_iSpitsRemaining[client] = 0;
		// Sẽ reset lại khi cloak tiếp theo kết thúc
	}
}

int FindClosestSurvivor(int client, float maxDistance)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	int closest = 0;
	float closestDist = maxDistance;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidAliveSurvivor(i))
			continue;

		float pos[3];
		GetClientAbsOrigin(i, pos);
		float dist = GetVectorDistance(origin, pos);
		if (dist < closestDist)
		{
			closestDist = dist;
			closest = i;
		}
	}

	return closest;
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
		return;

	g_bTrackedSneaky[client]   = false;
	g_bCloaked[client]         = false;
	g_fCloakUntil[client]      = 0.0;
	g_fNextCloakAt[client]     = 0.0;
	g_fNextSpitAt[client]      = 0.0;
	g_iSpitsRemaining[client]  = 0;
}

bool IsSneakySpitter(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;
	if (!IsPlayerAlive(client))
		return false;
	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
		return false;
	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
		return false;
	return g_bTrackedSneaky[client];
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
		SyncTrackedSubtypeForClient(i);
}

void SyncTrackedSubtypeForClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return;
	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
	{
		g_bTrackedSneaky[client] = false;
		return;
	}
	if (!g_bHasEliteApi)
		return;

	g_bTrackedSneaky[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SPITTER_SNEAKY;
}
