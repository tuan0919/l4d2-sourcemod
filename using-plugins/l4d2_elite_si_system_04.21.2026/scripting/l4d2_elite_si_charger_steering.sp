#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZC_CHARGER 6

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_ABNORMAL_BEHAVIOR,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvEliteOnly;
ConVar g_cvSubtype;
ConVar g_cvSteerStrength;
ConVar g_cvTargetRange;
ConVar g_cvIgnoreIncap;
ConVar g_cvMinSpeed;

bool g_bHasEliteApi;
bool g_bCharging[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Charger Steering",
	author = "OpenCode",
	description = "Charger steering branch for elite charger-steering subtype.",
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
	g_cvEnable = CreateConVar("l4d2_elite_charger_steering_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEliteOnly = CreateConVar("l4d2_elite_charger_steering_elite_only", "1", "0=Apply to all bot chargers, 1=Only elite subtype chargers.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSubtype = CreateConVar("l4d2_elite_charger_steering_subtype", "3", "Subtype id required when elite_only=1.", FCVAR_NOTIFY, true, 0.0, true, 32.0);
	g_cvSteerStrength = CreateConVar("l4d2_elite_charger_steering_strength", "0.22", "Steering blend per frame (0.0-1.0).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTargetRange = CreateConVar("l4d2_elite_charger_steering_target_range", "1200.0", "Maximum range to search survivor target.", FCVAR_NOTIFY, true, 10.0, true, 5000.0);
	g_cvIgnoreIncap = CreateConVar("l4d2_elite_charger_steering_ignore_incapped", "1", "0=Can target incapped survivors, 1=Ignore incapped survivors.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMinSpeed = CreateConVar("l4d2_elite_charger_steering_min_speed", "250.0", "Minimum horizontal speed while steering.", FCVAR_NOTIFY, true, 1.0, true, 2000.0);

	CreateConVar("l4d2_elite_charger_steering_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_charger_steering");

	HookEvent("charger_charge_start", Event_ChargeStart, EventHookMode_Post);
	HookEvent("charger_charge_end", Event_ChargeEnd, EventHookMode_Post);
	HookEvent("player_spawn", Event_ResetClientState, EventHookMode_Post);
	HookEvent("player_death", Event_ResetClientState, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bCharging[i] = false;
	}

	RefreshEliteState();
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

public void OnClientPutInServer(int client)
{
	g_bCharging[client] = false;
}

public void OnClientDisconnect(int client)
{
	g_bCharging[client] = false;
}

public void Event_ResetClientState(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		g_bCharging[client] = false;
	}
}

public void Event_ChargeStart(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		g_bCharging[client] = true;
	}
}

public void Event_ChargeEnd(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		g_bCharging[client] = false;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplySteering(client))
	{
		return Plugin_Continue;
	}

	int target = FindBestTarget(client, g_cvTargetRange.FloatValue, g_cvIgnoreIncap.BoolValue);
	if (target <= 0)
	{
		return Plugin_Continue;
	}

	SteerTowardTarget(client, target);
	return Plugin_Continue;
}

bool ShouldApplySteering(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	if (!g_bCharging[client] || !IsFakeClient(client) || GetClientTeam(client) != TEAM_INFECTED)
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_CHARGER)
	{
		return false;
	}

	if (GetEntPropEnt(client, Prop_Send, "m_carryVictim") != -1)
	{
		return false;
	}

	if (!g_cvEliteOnly.BoolValue)
	{
		return true;
	}

	if (!g_bHasEliteApi)
	{
		return false;
	}

	if (!EliteSI_IsElite(client))
	{
		return false;
	}

	int requiredSubtype = g_cvSubtype.IntValue;
	if (requiredSubtype <= ELITE_SUBTYPE_NONE)
	{
		requiredSubtype = ELITE_SUBTYPE_CHARGER_STEERING;
	}

	return EliteSI_GetSubtype(client) == requiredSubtype;
}

int FindBestTarget(int charger, float maxRange, bool ignoreIncap)
{
	float chargerPos[3];
	GetClientAbsOrigin(charger, chargerPos);

	float bestDist = maxRange;
	int bestTarget = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SURVIVOR)
		{
			continue;
		}

		if (ignoreIncap && IsPlayerIncapped(i))
		{
			continue;
		}

		float survivorPos[3];
		GetClientAbsOrigin(i, survivorPos);

		float dist = GetVectorDistance(chargerPos, survivorPos);
		if (dist < bestDist)
		{
			bestDist = dist;
			bestTarget = i;
		}
	}

	return bestTarget;
}

void SteerTowardTarget(int charger, int target)
{
	float chargerPos[3], targetPos[3], currentVel[3], desiredDir[3], currentDir[3], outDir[3], outVel[3];
	GetClientAbsOrigin(charger, chargerPos);
	GetClientAbsOrigin(target, targetPos);
	GetEntPropVector(charger, Prop_Data, "m_vecVelocity", currentVel);

	float verticalVel = currentVel[2];

	MakeVectorFromPoints(chargerPos, targetPos, desiredDir);
	desiredDir[2] = 0.0;
	if (GetVectorLength(desiredDir) <= 0.1)
	{
		return;
	}
	NormalizeVector(desiredDir, desiredDir);

	currentDir[0] = currentVel[0];
	currentDir[1] = currentVel[1];
	currentDir[2] = 0.0;
	float speed = GetVectorLength(currentDir);

	if (speed <= 0.1)
	{
		float eyeAngles[3];
		GetClientEyeAngles(charger, eyeAngles);
		GetAngleVectors(eyeAngles, currentDir, NULL_VECTOR, NULL_VECTOR);
		currentDir[2] = 0.0;
		NormalizeVector(currentDir, currentDir);
	}
	else
	{
		NormalizeVector(currentDir, currentDir);
	}

	float steerStrength = g_cvSteerStrength.FloatValue;
	if (steerStrength < 0.0)
	{
		steerStrength = 0.0;
	}
	else if (steerStrength > 1.0)
	{
		steerStrength = 1.0;
	}

	outDir[0] = currentDir[0] * (1.0 - steerStrength) + desiredDir[0] * steerStrength;
	outDir[1] = currentDir[1] * (1.0 - steerStrength) + desiredDir[1] * steerStrength;
	outDir[2] = 0.0;

	if (GetVectorLength(outDir) <= 0.1)
	{
		return;
	}

	NormalizeVector(outDir, outDir);

	float minSpeed = g_cvMinSpeed.FloatValue;
	if (speed < minSpeed)
	{
		speed = minSpeed;
	}

	outVel[0] = outDir[0] * speed;
	outVel[1] = outDir[1] * speed;
	outVel[2] = verticalVel;

	TeleportEntity(charger, NULL_VECTOR, NULL_VECTOR, outVel);
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}

bool IsPlayerIncapped(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}
