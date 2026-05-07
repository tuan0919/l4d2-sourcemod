#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_BOOMER 2

#define ELITE_SUBTYPE_NONE 0
#define ELITE_SUBTYPE_ABNORMAL_BEHAVIOR 1

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvBhop;

ConVar g_cvVomitRange;

bool g_bHasEliteApi;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Abnormal Boomer",
	author = "OpenCode",
	description = "Abnormal Behavior module for elite Boomer.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_hardsi_boomer_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBhop = CreateConVar("l4d2_elite_si_hardsi_boomer_bhop", "1", "Enable boomer bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	CreateConVar("l4d2_elite_si_hardsi_boomer_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hardsi_boomer");

	g_cvVomitRange = FindConVar("z_vomit_range");

	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);

	RefreshEliteApiState();
}

public void OnAllPluginsLoaded()
{
	RefreshEliteApiState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteApiState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteApiState();
	}
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	char ability[32];
	event.GetString("ability", ability, sizeof(ability));
	if (!StrEqual(ability, "ability_vomit"))
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplyAbnormalBehavior(client, true, ZC_BOOMER))
	{
		return;
	}

	HandleBoomerVomitUse(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue || !g_cvBhop.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplyAbnormalBehavior(client, true, ZC_BOOMER))
	{
		return Plugin_Continue;
	}

	if (GetEntProp(client, Prop_Send, "m_isGhost") == 1)
	{
		return Plugin_Continue;
	}

	return TryBhop(client, buttons, 90.0);
}

void HandleBoomerVomitUse(int client)
{
	if (!IsClientInGame(client) || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_BOOMER)
	{
		return;
	}

	float boomerPos[3];
	GetClientAbsOrigin(client, boomerPos);

	float vomitRange = (g_cvVomitRange != null) ? g_cvVomitRange.FloatValue : 650.0;
	int target = FindClosestSurvivor(boomerPos, vomitRange + 180.0, true);
	if (!IsValidAliveSurvivor(target))
	{
		return;
	}

	float targetEye[3], velocity[3], outAngles[3];
	GetClientEyePosition(target, targetEye);
	MakeVectorFromPoints(boomerPos, targetEye, velocity);

	float speed = GetVectorLength(velocity);
	if (speed < vomitRange)
	{
		speed = 0.5 * vomitRange;
	}

	NormalizeVector(velocity, velocity);
	ScaleVector(velocity, speed);
	GetVectorAngles(velocity, outAngles);

	int flags = GetEntityFlags(client);
	SetEntityFlags(client, (flags & ~FL_FROZEN) & ~FL_ONGROUND);
	TeleportEntity(client, NULL_VECTOR, outAngles, velocity);
	SetEntityFlags(client, flags);
}

Action TryBhop(int client, int &buttons, float boost)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	if ((GetEntityFlags(client) & FL_ONGROUND) == 0)
	{
		return Plugin_Continue;
	}

	if (GetEntityMoveType(client) == MOVETYPE_LADDER || GetEntProp(client, Prop_Data, "m_nWaterLevel") > 1)
	{
		return Plugin_Continue;
	}

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
	velocity[2] = 0.0;
	if (GetVectorLength(velocity) <= 0.9 * GetEntPropFloat(client, Prop_Send, "m_flMaxspeed"))
	{
		return Plugin_Continue;
	}

	float eyeAngles[3];
	float forwardVec[3];
	GetClientEyeAngles(client, eyeAngles);
	GetAngleVectors(eyeAngles, forwardVec, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(forwardVec, forwardVec);
	ScaleVector(forwardVec, boost);

	float newVel[3];
	GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", newVel);
	AddVectors(newVel, forwardVec, newVel);

	buttons |= IN_DUCK;
	buttons |= IN_JUMP;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, newVel);
	return Plugin_Changed;
}

bool ShouldApplyAbnormalBehavior(int client, bool requireAlive, int requiredClass = 0)
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

	if (requiredClass > 0 && GetEntProp(client, Prop_Send, "m_zombieClass") != requiredClass)
	{
		return false;
	}

	if (!g_bHasEliteApi)
	{
		return false;
	}

	if (!EliteSI_IsElite(client))
	{
		return false;
	}

	int subtype = EliteSI_GetSubtype(client);
	return subtype > ELITE_SUBTYPE_NONE && subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR;
}

void RefreshEliteApiState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}

bool IsValidAliveSurvivor(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SURVIVOR);
}

bool IsPlayerIncapped(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}

int FindClosestSurvivor(const float origin[3], float maxDistance, bool ignoreIncap, int exclude = -1)
{
	int bestTarget = 0;
	float bestDistance = maxDistance;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == exclude || !IsValidAliveSurvivor(i))
		{
			continue;
		}

		if (ignoreIncap && IsPlayerIncapped(i))
		{
			continue;
		}

		float targetPos[3];
		GetClientAbsOrigin(i, targetPos);

		float distance = GetVectorDistance(origin, targetPos);
		if (distance < bestDistance)
		{
			bestDistance = distance;
			bestTarget = i;
		}
	}

	return bestTarget;
}
