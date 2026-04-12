#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "2.0.0"

#define CVAR_FLAGS FCVAR_NOTIFY
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZC_CHARGER 6

#define ELITE_SUBTYPE_NONE 0
#define ELITE_SUBTYPE_CHARGER_STEERING 3

native bool L4D2_IsEliteSI(int client);
native int L4D2_GetEliteSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvEliteOnly;
ConVar g_cvEliteSubtype;
ConVar g_cvSteerStrength;
ConVar g_cvTargetRange;
ConVar g_cvIgnoreIncap;
ConVar g_cvMinSpeed;

bool g_bHasEliteApi;
bool g_bCharging[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite Charger Steering",
	author = "SilverShot, rewrite by OpenCode",
	description = "Bot steering for Elite Charger subtype only.",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	MarkNativeAsOptional("L4D2_IsEliteSI");
	MarkNativeAsOptional("L4D2_GetEliteSubtype");
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	g_bHasEliteApi = LibraryExists("l4d2_elite_SI_reward");
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "l4d2_elite_SI_reward"))
	{
		g_bHasEliteApi = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "l4d2_elite_SI_reward"))
	{
		g_bHasEliteApi = false;
	}
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_charger_steering_allow", "1", "0=Off, 1=On.", CVAR_FLAGS);
	g_cvEliteOnly = CreateConVar("l4d2_charger_steering_elite_only", "1", "0=Apply to all charger bots. 1=Only elite subtype chargers.", CVAR_FLAGS);
	g_cvEliteSubtype = CreateConVar("l4d2_charger_steering_elite_subtype", "3", "Elite subtype id used by this plugin.", CVAR_FLAGS);
	g_cvSteerStrength = CreateConVar("l4d2_charger_steering_bot_strength", "0.22", "Steering strength per frame. 0.0-1.0.", CVAR_FLAGS);
	g_cvTargetRange = CreateConVar("l4d2_charger_steering_target_range", "1200.0", "Max target search range.", CVAR_FLAGS);
	g_cvIgnoreIncap = CreateConVar("l4d2_charger_steering_ignore_incapped", "1", "0=Can target incapped survivors, 1=Ignore incapped survivors.", CVAR_FLAGS);
	g_cvMinSpeed = CreateConVar("l4d2_charger_steering_min_speed", "250.0", "Minimum horizontal speed while steering.", CVAR_FLAGS);

	CreateConVar("l4d2_charger_steering_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_charger_steering");

	HookEvent("player_spawn", Event_ResetClientState, EventHookMode_Post);
	HookEvent("player_death", Event_ResetClientState, EventHookMode_Post);
	HookEvent("charger_charge_start", Event_ChargeStart, EventHookMode_Post);
	HookEvent("charger_charge_end", Event_ChargeEnd, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			g_bCharging[i] = false;
		}
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

void Event_ResetClientState(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		g_bCharging[client] = false;
	}
}

void Event_ChargeStart(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		g_bCharging[client] = true;
	}
}

void Event_ChargeEnd(Event event, const char[] name, bool dontBroadcast)
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

	if (!L4D2_IsEliteSI(client))
	{
		return false;
	}

	int requiredSubtype = g_cvEliteSubtype.IntValue;
	if (requiredSubtype <= ELITE_SUBTYPE_NONE)
	{
		requiredSubtype = ELITE_SUBTYPE_CHARGER_STEERING;
	}

	return L4D2_GetEliteSubtype(client) == requiredSubtype;
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

	outDir[0] = (currentDir[0] * (1.0 - steerStrength)) + (desiredDir[0] * steerStrength);
	outDir[1] = (currentDir[1] * (1.0 - steerStrength)) + (desiredDir[1] * steerStrength);
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

bool IsPlayerIncapped(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}
