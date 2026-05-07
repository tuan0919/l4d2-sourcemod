#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_HUNTER_TARGET_SWITCH 26

enum
{
	HUNTER_ACTION_NONE = 0,
	HUNTER_ACTION_RELEASE,
	HUNTER_ACTION_MOVE,
	HUNTER_ACTION_ATTACK
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvCheckInterval;
ConVar g_cvReleaseDelay;
ConVar g_cvRetargetRange;
ConVar g_cvLeapSpeed;

bool g_bHasEliteApi;

int g_iPinnedVictim[MAXPLAYERS + 1];
int g_iPinnedHunter[MAXPLAYERS + 1];
int g_iHunterAction[MAXPLAYERS + 1];
int g_iHunterTick[MAXPLAYERS + 1];
float g_fActionStartedAt[MAXPLAYERS + 1];
float g_fLastCheckAt[MAXPLAYERS + 1];
float g_vecAttackVelocity[MAXPLAYERS + 1][3];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Hunter Target Switch",
	author = "OpenCode",
	description = "Target Switch subtype module for elite Hunter bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_hunter_target_switch_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvCheckInterval = CreateConVar("l4d2_elite_si_hunter_target_switch_check_interval", "0.2", "Interval in seconds between incap retarget checks.", FCVAR_NOTIFY, true, 0.05, true, 1.0);
	g_cvReleaseDelay = CreateConVar("l4d2_elite_si_hunter_target_switch_release_delay", "0.1", "Delay before hunter re-arms after releasing an incapacitated victim.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvRetargetRange = CreateConVar("l4d2_elite_si_hunter_target_switch_retarget_range", "600.0", "Max range to look for a new standing survivor target.", FCVAR_NOTIFY, true, 50.0, true, 3000.0);
	g_cvLeapSpeed = CreateConVar("l4d2_elite_si_hunter_target_switch_leap_speed", "800.0", "Launch speed when retargeting to a new survivor.", FCVAR_NOTIFY, true, 100.0, true, 3000.0);

	CreateConVar("l4d2_elite_si_hunter_target_switch_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hunter_target_switch");

	HookEvent("lunge_pounce", Event_LungePounce, EventHookMode_Post);
	HookEvent("pounce_end", Event_PounceEnd, EventHookMode_Post);
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

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
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
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplySubtype(attacker, true) || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	g_iPinnedVictim[attacker] = victim;
	g_iPinnedHunter[victim] = attacker;
	g_iHunterAction[attacker] = HUNTER_ACTION_NONE;
	g_iHunterTick[attacker] = 0;
	g_fActionStartedAt[attacker] = GetGameTime();
	g_fLastCheckAt[attacker] = 0.0;
	SetEntityMoveType(attacker, MOVETYPE_WALK);
}

public void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if (victim <= 0 || victim > MaxClients)
	{
		return;
	}

	int attacker = g_iPinnedHunter[victim];
	g_iPinnedHunter[victim] = 0;
	if (attacker <= 0 || attacker > MaxClients)
	{
		return;
	}

	g_iPinnedVictim[attacker] = 0;
	if (g_iHunterAction[attacker] == HUNTER_ACTION_NONE)
	{
		StopHunter(attacker);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (g_iHunterAction[client] == HUNTER_ACTION_RELEASE)
	{
		if (!ShouldApplySubtype(client, true))
		{
			return StopHunter(client);
		}

		if (GetGameTime() - g_fActionStartedAt[client] > g_cvReleaseDelay.FloatValue)
		{
			g_iHunterAction[client] = HUNTER_ACTION_MOVE;
			g_fActionStartedAt[client] = GetGameTime();
			SetEntityMoveType(client, MOVETYPE_WALK);
			buttons = 0;
			return Plugin_Changed;
		}

		return Plugin_Continue;
	}

	if (g_iHunterAction[client] == HUNTER_ACTION_MOVE)
	{
		if (!ShouldApplySubtype(client, true))
		{
			return StopHunter(client);
		}

		g_iHunterAction[client] = HUNTER_ACTION_ATTACK;
		g_fActionStartedAt[client] = GetGameTime();
		g_iHunterTick[client] = 0;
		buttons |= IN_ATTACK;
		buttons |= IN_DUCK;
		TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, g_vecAttackVelocity[client]);
		return Plugin_Changed;
	}

	if (g_iHunterAction[client] == HUNTER_ACTION_ATTACK)
	{
		if (!ShouldApplySubtype(client, true))
		{
			return StopHunter(client);
		}

		if (GetGameTime() - g_fActionStartedAt[client] > 3.0)
		{
			return StopHunter(client);
		}

		g_iHunterTick[client]++;
		buttons = 0;
		if ((g_iHunterTick[client] % 2) == 0)
		{
			buttons |= IN_ATTACK;
		}
		buttons |= IN_DUCK;
		return Plugin_Changed;
	}

	if (g_iPinnedVictim[client] == 0)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplySubtype(client, true))
	{
		return StopHunter(client);
	}

	float now = GetGameTime();
	if (now - g_fLastCheckAt[client] < g_cvCheckInterval.FloatValue)
	{
		return Plugin_Continue;
	}
	g_fLastCheckAt[client] = now;

	int victim = g_iPinnedVictim[client];
	if (!IsValidAliveSurvivor(victim))
	{
		return StopHunter(client);
	}

	if (!IsSurvivorIncapacitated(victim))
	{
		return Plugin_Continue;
	}

	int target = FindRetargetSurvivor(client, victim, g_cvRetargetRange.FloatValue);
	if (!IsValidStandingSurvivor(target))
	{
		return StopHunter(client);
	}

	BuildAttackVelocity(client, target, g_vecAttackVelocity[client]);
	g_iPinnedVictim[client] = 0;
	g_iPinnedHunter[victim] = 0;
	g_iHunterAction[client] = HUNTER_ACTION_RELEASE;
	g_iHunterTick[client] = 0;
	g_fActionStartedAt[client] = now;
	SetEntityMoveType(client, MOVETYPE_NOCLIP);

	return Plugin_Continue;
}

Action StopHunter(int client)
{
	if (client > 0 && client <= MaxClients)
	{
		if (g_iPinnedVictim[client] > 0 && g_iPinnedVictim[client] <= MaxClients)
		{
			g_iPinnedHunter[g_iPinnedVictim[client]] = 0;
		}

		g_iPinnedVictim[client] = 0;
		g_iHunterAction[client] = HUNTER_ACTION_NONE;
		g_iHunterTick[client] = 0;
		g_fActionStartedAt[client] = 0.0;
		g_fLastCheckAt[client] = 0.0;

		if (IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED)
		{
			SetEntityMoveType(client, MOVETYPE_WALK);
		}
	}

	return Plugin_Continue;
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

	if (g_iPinnedVictim[client] > 0 && g_iPinnedVictim[client] <= MaxClients)
	{
		g_iPinnedHunter[g_iPinnedVictim[client]] = 0;
	}

	if (g_iPinnedHunter[client] > 0 && g_iPinnedHunter[client] <= MaxClients)
	{
		g_iPinnedVictim[g_iPinnedHunter[client]] = 0;
	}

	g_iPinnedVictim[client] = 0;
	g_iPinnedHunter[client] = 0;
	g_iHunterAction[client] = HUNTER_ACTION_NONE;
	g_iHunterTick[client] = 0;
	g_fActionStartedAt[client] = 0.0;
	g_fLastCheckAt[client] = 0.0;
	g_vecAttackVelocity[client][0] = 0.0;
	g_vecAttackVelocity[client][1] = 0.0;
	g_vecAttackVelocity[client][2] = 0.0;

	if (IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}
}

void BuildAttackVelocity(int hunter, int target, float velocity[3])
{
	float hunterPos[3];
	float targetPos[3];
	GetClientEyePosition(hunter, hunterPos);
	GetClientEyePosition(target, targetPos);

	MakeVectorFromPoints(hunterPos, targetPos, velocity);
	velocity[2] = 0.0;
	if (GetVectorLength(velocity) < 0.001)
	{
		velocity[0] = GetRandomFloat(-1.0, 1.0);
		velocity[1] = GetRandomFloat(-1.0, 1.0);
	}

	NormalizeVector(velocity, velocity);
	velocity[2] = 0.5;
	NormalizeVector(velocity, velocity);
	ScaleVector(velocity, g_cvLeapSpeed.FloatValue);
}

int FindRetargetSurvivor(int hunter, int ignoredVictim, float maxRange)
{
	float hunterPos[3];
	GetClientEyePosition(hunter, hunterPos);

	int bestTarget = 0;
	float bestDistance = maxRange;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (client == ignoredVictim || !IsValidStandingSurvivor(client))
		{
			continue;
		}

		float pos[3];
		GetClientEyePosition(client, pos);
		float distance = GetVectorDistance(pos, hunterPos);
		if (distance > bestDistance)
		{
			continue;
		}

		bestDistance = distance;
		bestTarget = client;
	}

	return bestTarget;
}

bool ShouldApplySubtype(int client, bool requireAlive)
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

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_HUNTER_TARGET_SWITCH;
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client);
}

bool IsValidStandingSurvivor(int client)
{
	return IsValidAliveSurvivor(client) && !IsSurvivorIncapacitated(client);
}

bool IsSurvivorIncapacitated(int client)
{
	return view_as<bool>(GetEntProp(client, Prop_Send, "m_isIncapacitated", 1));
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
