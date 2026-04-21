#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <actions>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_NONE 0
#define ELITE_SUBTYPE_ABNORMAL_BEHAVIOR 1

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvFastPounceDistance;
ConVar g_cvPounceVerticalLimit;
ConVar g_cvAimOffsetSensitivity;
ConVar g_cvStraightPounceDistance;
ConVar g_cvLeapAwayBlockEnable;

ConVar g_cvHunterLeapAwayGiveUpRange;

bool g_bHasEliteApi;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Abnormal Hunter",
	author = "OpenCode",
	description = "Abnormal Behavior module for elite Hunter.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_hardsi_hunter_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFastPounceDistance = CreateConVar("l4d2_elite_si_hardsi_hunter_fast_pounce_distance", "1000", "Distance where hunter starts fast pounce behavior.", FCVAR_NOTIFY, true, 0.0, true, 5000.0);
	g_cvPounceVerticalLimit = CreateConVar("l4d2_elite_si_hardsi_hunter_pounce_vertical_limit", "7.0", "Vertical angle limit for hunter pounce.", FCVAR_NOTIFY, true, 0.0, true, 60.0);
	g_cvAimOffsetSensitivity = CreateConVar("l4d2_elite_si_hardsi_hunter_aim_offset_sensitivity", "30.0", "Aim offset threshold to angle hunter pounce.", FCVAR_NOTIFY, true, 0.0, true, 179.0);
	g_cvStraightPounceDistance = CreateConVar("l4d2_elite_si_hardsi_hunter_straight_pounce_distance", "200", "Within this distance, hunter keeps straight pounce.", FCVAR_NOTIFY, true, 0.0, true, 2000.0);
	g_cvLeapAwayBlockEnable = CreateConVar("l4d2_elite_si_hardsi_hunter_leap_away_block_enable", "1", "0=Do not override hunter leap-away assault, 1=Block leap-away assault behavior.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	CreateConVar("l4d2_elite_si_hardsi_hunter_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hardsi_hunter");

	g_cvHunterLeapAwayGiveUpRange = FindConVar("hunter_leap_away_give_up_range");

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
	if (!StrEqual(ability, "ability_lunge"))
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplyAbnormalBehavior(client, true, ZC_HUNTER))
	{
		return;
	}

	HandleHunterPounceUse(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplyAbnormalBehavior(client, true, ZC_HUNTER))
	{
		return Plugin_Continue;
	}

	if (GetEntProp(client, Prop_Send, "m_isGhost") == 1)
	{
		return Plugin_Continue;
	}

	if (L4D_IsPlayerStaggering(client))
	{
		return Plugin_Continue;
	}

	return HandleHunterRunCmd(client, buttons);
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	if (!g_cvEnable.BoolValue || !g_cvLeapAwayBlockEnable.BoolValue)
	{
		return;
	}

	if (strncmp(name, "Hunter", 6) != 0 || strcmp(name[6], "Attack") != 0)
	{
		return;
	}

	if (!ShouldApplyAbnormalBehavior(actor, false, ZC_HUNTER))
	{
		return;
	}

	action.OnCommandAssault = HunterAttack_OnCommandAssault;
}

Action HunterAttack_OnCommandAssault(any action, int actor, ActionDesiredResult result)
{
	if (g_cvHunterLeapAwayGiveUpRange != null && g_cvHunterLeapAwayGiveUpRange.IntValue <= 0)
	{
		return Plugin_Continue;
	}

	return Plugin_Handled;
}

Action HandleHunterRunCmd(int client, int &buttons)
{
	if ((GetEntityFlags(client) & FL_ONGROUND) == 0)
	{
		return Plugin_Continue;
	}

	if (GetEntProp(client, Prop_Send, "m_bDucked") == 0)
	{
		return Plugin_Continue;
	}

	float pos[3];
	GetClientAbsOrigin(client, pos);
	int nearestDist = GetSurvivorProximity(pos, -1);
	if (nearestDist == -1 || nearestDist > g_cvFastPounceDistance.IntValue)
	{
		return Plugin_Continue;
	}

	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (ability == -1 || !IsValidEntity(ability))
	{
		return Plugin_Continue;
	}

	if (GetEntPropFloat(ability, Prop_Send, "m_nextActivationTimer", 1) > GetGameTime())
	{
		buttons |= IN_ATTACK2;
		return Plugin_Changed;
	}

	buttons |= IN_ATTACK;
	return Plugin_Changed;
}

void HandleHunterPounceUse(int client)
{
	if (!IsClientInGame(client) || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_HUNTER)
	{
		return;
	}

	int lungeEntity = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (lungeEntity == -1 || !IsValidEntity(lungeEntity))
	{
		return;
	}

	float lunge[3];
	GetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", lunge);

	float pos[3];
	GetClientAbsOrigin(client, pos);

	int target = GetClientAimTarget(client, false);
	if (!IsValidAliveSurvivor(target))
	{
		target = FindClosestSurvivor(pos, 2500.0, false);
	}

	if (!IsValidAliveSurvivor(target))
	{
		LimitHunterLungeVertical(lunge, g_cvPounceVerticalLimit.FloatValue);
		SetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", lunge);
		return;
	}

	int dist = GetSurvivorProximity(pos, target);
	if (dist > g_cvStraightPounceDistance.IntValue && IsTargetWatchingAttacker(target, client, g_cvAimOffsetSensitivity.FloatValue))
	{
		float yaw = GetRandomFloat(-35.0, 35.0);
		RotateVectorYaw(lunge, yaw);
	}

	LimitHunterLungeVertical(lunge, g_cvPounceVerticalLimit.FloatValue);
	SetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", lunge);
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

int GetSurvivorProximity(const float origin[3], int target)
{
	if (target > 0 && IsValidAliveSurvivor(target))
	{
		float targetPos[3];
		GetClientAbsOrigin(target, targetPos);
		return RoundToNearest(GetVectorDistance(origin, targetPos));
	}

	int closest = FindClosestSurvivor(origin, 99999.0, false);
	if (!IsValidAliveSurvivor(closest))
	{
		return -1;
	}

	float closestPos[3];
	GetClientAbsOrigin(closest, closestPos);
	return RoundToNearest(GetVectorDistance(origin, closestPos));
}

bool IsPlayerIncapped(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
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

void LimitHunterLungeVertical(float lunge[3], float maxAngle)
{
	float horizontal = SquareRoot(Pow(lunge[0], 2.0) + Pow(lunge[1], 2.0));
	if (horizontal <= 0.1)
	{
		return;
	}

	float maxZ = horizontal * Sine(DegToRad(maxAngle));
	if (lunge[2] > maxZ)
	{
		lunge[2] = maxZ;
	}
	else if (lunge[2] < -maxZ)
	{
		lunge[2] = -maxZ;
	}
}

void RotateVectorYaw(float vec[3], float yawDeg)
{
	float yaw = DegToRad(yawDeg);
	float c = Cosine(yaw);
	float s = Sine(yaw);

	float x = vec[0] * c - vec[1] * s;
	float y = vec[0] * s + vec[1] * c;

	vec[0] = x;
	vec[1] = y;
}
