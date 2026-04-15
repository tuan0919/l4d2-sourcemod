#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_CHARGER 6

#define ELITE_SUBTYPE_NONE 0
#define ELITE_SUBTYPE_ABNORMAL_BEHAVIOR 1

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvBhop;
ConVar g_cvChargeDistance;
ConVar g_cvHealthThreshold;
ConVar g_cvAimOffsetSensitivity;

bool g_bHasEliteApi;
bool g_bCharging[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Abnormal Charger",
	author = "OpenCode",
	description = "Abnormal Behavior module for elite Charger.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_hardsi_charger_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBhop = CreateConVar("l4d2_elite_si_hardsi_charger_bhop", "1", "Enable charger bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvChargeDistance = CreateConVar("l4d2_elite_si_hardsi_charger_charge_distance", "300", "Charger prepares charge within this distance.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);
	g_cvHealthThreshold = CreateConVar("l4d2_elite_si_hardsi_charger_health_threshold", "300", "Charger can force charge below this health.", FCVAR_NOTIFY, true, 0.0, true, 5000.0);
	g_cvAimOffsetSensitivity = CreateConVar("l4d2_elite_si_hardsi_charger_aim_offset_sensitivity", "22.5", "If target is watching charger below this offset, try retargeting.", FCVAR_NOTIFY, true, 0.0, true, 179.0);

	CreateConVar("l4d2_elite_si_hardsi_charger_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hardsi_charger");

	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);
	HookEvent("charger_charge_start", Event_ChargeStart, EventHookMode_Post);
	HookEvent("charger_charge_end", Event_ChargeEnd, EventHookMode_Post);
	HookEvent("player_spawn", Event_ResetChargeState, EventHookMode_Post);
	HookEvent("player_death", Event_ResetChargeState, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_bCharging[i] = false;
	}

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

public void Event_ResetChargeState(Event event, const char[] name, bool dontBroadcast)
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

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	char ability[32];
	event.GetString("ability", ability, sizeof(ability));
	if (!StrEqual(ability, "ability_charge"))
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplyAbnormalBehavior(client, true, ZC_CHARGER))
	{
		return;
	}

	HandleChargerChargeUse(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplyAbnormalBehavior(client, true, ZC_CHARGER))
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

	return HandleChargerRunCmd(client, buttons);
}

Action HandleChargerRunCmd(int client, int &buttons)
{
	if (L4D_GetVictimCarry(client) > 0 || L4D_GetVictimCharger(client) > 0 || L4D2_GetQueuedPummelVictim(client) > 0)
	{
		return Plugin_Continue;
	}

	if (!g_bCharging[client])
	{
		float pos[3];
		GetClientAbsOrigin(client, pos);

		int target = FindClosestSurvivor(pos, float(g_cvChargeDistance.IntValue), true);
		int hp = GetEntProp(client, Prop_Send, "m_iHealth");

		if (IsValidAliveSurvivor(target) && !IsPlayerIncapped(target) && GetEntPropEnt(target, Prop_Send, "m_carryAttacker") == -1)
		{
			if (hp <= g_cvHealthThreshold.IntValue || IsWithinDistance(client, target, float(g_cvChargeDistance.IntValue)))
			{
				buttons |= IN_ATTACK;
				buttons |= IN_ATTACK2;
				return Plugin_Changed;
			}
		}
	}

	if (g_cvBhop.BoolValue && !g_bCharging[client])
	{
		return TryBhop(client, buttons, 100.0);
	}

	return Plugin_Continue;
}

void HandleChargerChargeUse(int client)
{
	if (!IsClientInGame(client) || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_CHARGER)
	{
		return;
	}

	float chargerPos[3];
	GetClientAbsOrigin(client, chargerPos);

	int current = GetClientAimTarget(client, false);
	if (!IsValidAliveSurvivor(current) || IsTargetWatchingAttacker(current, client, g_cvAimOffsetSensitivity.FloatValue))
	{
		int other = FindClosestSurvivor(chargerPos, float(g_cvChargeDistance.IntValue), false, current);
		if (IsValidAliveSurvivor(other))
		{
			current = other;
		}
	}

	if (!IsValidAliveSurvivor(current))
	{
		return;
	}

	float targetPos[3];
	GetClientAbsOrigin(current, targetPos);

	float dir[3];
	MakeVectorFromPoints(chargerPos, targetPos, dir);
	NormalizeVector(dir, dir);

	float ang[3];
	GetVectorAngles(dir, ang);
	TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);
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

bool IsWithinDistance(int attacker, int target, float maxDistance)
{
	if (!IsValidAliveSurvivor(target) || !IsClientInGame(attacker))
	{
		return false;
	}

	float a[3], b[3];
	GetClientAbsOrigin(attacker, a);
	GetClientAbsOrigin(target, b);

	return GetVectorDistance(a, b) <= maxDistance;
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
