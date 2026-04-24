#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_JOCKEY 5
#define ELITE_SUBTYPE_JOCKEY_JUMPER 36

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvJumpForce;
ConVar g_cvJumpTimeMin;
ConVar g_cvJumpTimeMax;

bool g_bHasEliteApi;
bool g_bRoundLive = true;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Jockey Jumper",
	author = "OpenCode",
	description = "Jumper subtype module for elite Jockey bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_jockey_jumper_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvJumpForce = CreateConVar("l4d2_elite_si_jockey_jumper_force", "450.0", "Upward velocity added to the ridden survivor on each Jumper bounce.", FCVAR_NOTIFY, true, 251.0, true, 1200.0);
	g_cvJumpTimeMin = CreateConVar("l4d2_elite_si_jockey_jumper_time_min", "0.15", "Minimum delay before Jumper bounces again.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvJumpTimeMax = CreateConVar("l4d2_elite_si_jockey_jumper_time_max", "0.45", "Maximum delay before Jumper bounces again.", FCVAR_NOTIFY, true, 0.0, true, 5.0);

	CreateConVar("l4d2_elite_si_jockey_jumper_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_jockey_jumper");

	HookEvent("jockey_ride", Event_JockeyRide, EventHookMode_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);

	RefreshEliteState();
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
}

public void OnMapEnd()
{
	g_bRoundLive = false;
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

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundLive = true;
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundLive = false;
}

void Event_JockeyRide(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bRoundLive || !g_cvEnable.BoolValue)
	{
		return;
	}

	int jockey = GetClientOfUserId(event.GetInt("userid"));
	if (!IsJumperJockey(jockey, true))
	{
		return;
	}

	CreateTimer(GetNextJumpDelay(), Timer_Jump, GetClientUserId(jockey), TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_Jump(Handle timer, int userId)
{
	DoJump(userId);
	return Plugin_Stop;
}

void Frame_DoJump(int userId)
{
	DoJump(userId);
}

void DoJump(int userId)
{
	if (!g_bRoundLive || !g_cvEnable.BoolValue)
	{
		return;
	}

	int jockey = GetClientOfUserId(userId);
	if (!IsJumperJockey(jockey, true))
	{
		return;
	}

	int victim = GetEntPropEnt(jockey, Prop_Send, "m_jockeyVictim");
	if (!IsValidAliveSurvivor(victim) || GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") != jockey)
	{
		return;
	}

	if (GetEntPropEnt(victim, Prop_Send, "m_hGroundEntity") != 0)
	{
		RequestFrame(Frame_DoJump, userId);
		return;
	}

	float velocity[3];
	GetEntPropVector(victim, Prop_Send, "m_vecBaseVelocity", velocity);
	velocity[2] += g_cvJumpForce.FloatValue;
	TeleportEntity(victim, NULL_VECTOR, NULL_VECTOR, velocity);

	CreateTimer(GetNextJumpDelay(), Timer_Jump, userId, TIMER_FLAG_NO_MAPCHANGE);
}

float GetNextJumpDelay()
{
	float minDelay = g_cvJumpTimeMin.FloatValue;
	float maxDelay = g_cvJumpTimeMax.FloatValue;
	if (maxDelay < minDelay)
	{
		return minDelay;
	}

	return GetRandomFloat(minDelay, maxDelay);
}

bool IsJumperJockey(int client, bool requireAlive)
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

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_JOCKEY)
	{
		return false;
	}

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_JOCKEY_JUMPER;
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SURVIVOR;
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
