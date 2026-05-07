#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_TANK 8

#define ELITE_SUBTYPE_NONE 0
#define ELITE_SUBTYPE_ABNORMAL_BEHAVIOR 1

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvBhop;
ConVar g_cvAllowRock;
ConVar g_cvSmartRock;
ConVar g_cvSmartRockRange;
ConVar g_cvSmartRockAimSensitivity;

bool g_bHasEliteApi;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Abnormal Tank",
	author = "OpenCode",
	description = "Abnormal Behavior module for elite Tank.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_hardsi_tank_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBhop = CreateConVar("l4d2_elite_si_hardsi_tank_bhop", "1", "Enable tank bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAllowRock = CreateConVar("l4d2_elite_si_hardsi_tank_allow_rock", "1", "0=Disable tank rocks, 1=Allow.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmartRock = CreateConVar("l4d2_elite_si_hardsi_tank_smart_rock_enable", "1", "Enable smart rock direction adjustment.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmartRockRange = CreateConVar("l4d2_elite_si_hardsi_tank_smart_rock_range", "1200.0", "Smart rock assist range.", FCVAR_NOTIFY, true, 1.0, true, 5000.0);
	g_cvSmartRockAimSensitivity = CreateConVar("l4d2_elite_si_hardsi_tank_smart_rock_aim_offset", "22.5", "Aim offset threshold for smart rock retarget.", FCVAR_NOTIFY, true, -1.0, true, 180.0);

	CreateConVar("l4d2_elite_si_hardsi_tank_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hardsi_tank");

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

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplyAbnormalBehavior(client, true, ZC_TANK))
	{
		return Plugin_Continue;
	}

	if (GetEntProp(client, Prop_Send, "m_isGhost") == 1)
	{
		return Plugin_Continue;
	}

	return HandleTankRunCmd(client, buttons);
}

public Action L4D_TankRock_OnRelease(int tank, int rock, float vecPos[3], float vecAng[3], float vecVel[3], float vecRot[3])
{
	if (!g_cvEnable.BoolValue || !g_cvSmartRock.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplyAbnormalBehavior(tank, true, ZC_TANK))
	{
		return Plugin_Continue;
	}

	float tankPos[3];
	GetClientAbsOrigin(tank, tankPos);

	int target = FindClosestSurvivor(tankPos, g_cvSmartRockRange.FloatValue, true);
	if (!IsValidAliveSurvivor(target))
	{
		return Plugin_Continue;
	}

	if (g_cvSmartRockAimSensitivity.FloatValue >= 0.0 && IsTargetWatchingAttacker(target, tank, g_cvSmartRockAimSensitivity.FloatValue))
	{
		return Plugin_Continue;
	}

	float targetEye[3];
	GetClientEyePosition(target, targetEye);

	float dir[3];
	MakeVectorFromPoints(vecPos, targetEye, dir);
	NormalizeVector(dir, dir);

	float speed = GetVectorLength(vecVel);
	if (speed < 1.0)
	{
		speed = 800.0;
	}

	ScaleVector(dir, speed);
	vecVel[0] = dir[0];
	vecVel[1] = dir[1];
	vecVel[2] = dir[2];

	return Plugin_Changed;
}

Action HandleTankRunCmd(int client, int &buttons)
{
	if (!g_cvAllowRock.BoolValue)
	{
		buttons &= ~IN_ATTACK2;
	}

	if (g_cvBhop.BoolValue)
	{
		return TryBhop(client, buttons, 110.0);
	}

	return Plugin_Continue;
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

bool IsTargetWatchingAttacker(int target, int attacker, float offsetThreshold)
{
	if (!IsValidAliveSurvivor(target) || !IsClientInGame(attacker) || !IsPlayerAlive(attacker))
	{
		return false;
	}

	float aimOffset = GetPlayerAimOffset(target, attacker);
	return aimOffset <= offsetThreshold;
}

float GetPlayerAimOffset(int attacker, int target)
{
	float attackerPos[3], targetPos[3], aimVector[3], directVector[3];

	GetClientEyeAngles(attacker, aimVector);
	aimVector[0] = 0.0;
	aimVector[2] = 0.0;
	GetAngleVectors(aimVector, aimVector, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(aimVector, aimVector);

	GetClientAbsOrigin(attacker, attackerPos);
	GetClientAbsOrigin(target, targetPos);
	attackerPos[2] = 0.0;
	targetPos[2] = 0.0;

	MakeVectorFromPoints(attackerPos, targetPos, directVector);
	NormalizeVector(directVector, directVector);

	return RadToDeg(ArcCosine(GetVectorDotProduct(aimVector, directVector)));
}
