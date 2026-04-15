#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <left4dhooks>
#include <actions>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_HARDSI,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING
}

enum
{
	ZC_SMOKER = 1,
	ZC_BOOMER,
	ZC_HUNTER,
	ZC_SPITTER,
	ZC_JOCKEY,
	ZC_CHARGER,
	ZC_WITCH,
	ZC_TANK
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvSmokerEnable;
ConVar g_cvBoomerEnable;
ConVar g_cvHunterEnable;
ConVar g_cvSpitterEnable;
ConVar g_cvJockeyEnable;
ConVar g_cvChargerEnable;
ConVar g_cvTankEnable;

ConVar g_cvAssaultInterval;
ConVar g_cvAggressiveCfg;

ConVar g_cvBoomerBhop;
ConVar g_cvSpitterBhop;
ConVar g_cvChargerBhop;
ConVar g_cvTankBhop;

ConVar g_cvHunterFastPounceDistance;
ConVar g_cvHunterPounceVerticalLimit;
ConVar g_cvHunterAimOffsetSensitivity;
ConVar g_cvHunterStraightPounceDistance;

ConVar g_cvJockeyHopDistance;

ConVar g_cvChargerChargeDistance;
ConVar g_cvChargerHealthThreshold;
ConVar g_cvChargerAimOffsetSensitivity;

ConVar g_cvTankAllowRock;
ConVar g_cvTankSmartRock;
ConVar g_cvTankSmartRockRange;
ConVar g_cvTankSmartRockAimSensitivity;

ConVar g_cvVomitRange;

bool g_bHasEliteApi;
bool g_bCharging[MAXPLAYERS + 1];

int g_iCurrentTarget[MAXPLAYERS + 1];

Handle g_hAssaultTimer;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI HardSI",
	author = "OpenCode",
	description = "HardSI behavior branch for elite subtype only.",
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
	g_cvEnable = CreateConVar("l4d2_elite_hardsi_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmokerEnable = CreateConVar("l4d2_elite_hardsi_smoker_enable", "1", "Enable HardSI smoker logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBoomerEnable = CreateConVar("l4d2_elite_hardsi_boomer_enable", "1", "Enable HardSI boomer logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvHunterEnable = CreateConVar("l4d2_elite_hardsi_hunter_enable", "1", "Enable HardSI hunter logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSpitterEnable = CreateConVar("l4d2_elite_hardsi_spitter_enable", "1", "Enable HardSI spitter logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvJockeyEnable = CreateConVar("l4d2_elite_hardsi_jockey_enable", "1", "Enable HardSI jockey logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvChargerEnable = CreateConVar("l4d2_elite_hardsi_charger_enable", "1", "Enable HardSI charger logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTankEnable = CreateConVar("l4d2_elite_hardsi_tank_enable", "1", "Enable HardSI tank logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvAssaultInterval = CreateConVar("l4d2_elite_hardsi_assault_interval", "2.0", "Interval (sec) for nb_assault reminder. 0=off.", FCVAR_NOTIFY, true, 0.0, true, 30.0);
	g_cvAggressiveCfg = CreateConVar("l4d2_elite_hardsi_aggressive_cfg", "aggressive_ai.cfg", "Cfg file in cfg/l4d2_elite_hardsi/ executed on map config load.", FCVAR_NOTIFY);

	g_cvBoomerBhop = CreateConVar("l4d2_elite_hardsi_boomer_bhop", "1", "Enable boomer bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSpitterBhop = CreateConVar("l4d2_elite_hardsi_spitter_bhop", "1", "Enable spitter bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvChargerBhop = CreateConVar("l4d2_elite_hardsi_charger_bhop", "1", "Enable charger bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTankBhop = CreateConVar("l4d2_elite_hardsi_tank_bhop", "1", "Enable tank bhop facsimile.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvHunterFastPounceDistance = CreateConVar("l4d2_elite_hardsi_hunter_fast_pounce_distance", "1000", "Distance where hunter starts fast pounce behavior.", FCVAR_NOTIFY, true, 0.0, true, 5000.0);
	g_cvHunterPounceVerticalLimit = CreateConVar("l4d2_elite_hardsi_hunter_pounce_vertical_limit", "7.0", "Vertical angle limit for hunter pounce.", FCVAR_NOTIFY, true, 0.0, true, 60.0);
	g_cvHunterAimOffsetSensitivity = CreateConVar("l4d2_elite_hardsi_hunter_aim_offset_sensitivity", "30.0", "Aim offset threshold to angle hunter pounce.", FCVAR_NOTIFY, true, 0.0, true, 179.0);
	g_cvHunterStraightPounceDistance = CreateConVar("l4d2_elite_hardsi_hunter_straight_pounce_distance", "200", "Within this distance, hunter keeps straight pounce.", FCVAR_NOTIFY, true, 0.0, true, 2000.0);

	g_cvJockeyHopDistance = CreateConVar("l4d2_elite_hardsi_jockey_hop_distance", "500", "Distance where jockey starts leap/hop pressure.", FCVAR_NOTIFY, true, 0.0, true, 2500.0);

	g_cvChargerChargeDistance = CreateConVar("l4d2_elite_hardsi_charger_charge_distance", "300", "Charger prepares charge within this distance.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);
	g_cvChargerHealthThreshold = CreateConVar("l4d2_elite_hardsi_charger_health_threshold", "300", "Charger can force charge below this health.", FCVAR_NOTIFY, true, 0.0, true, 5000.0);
	g_cvChargerAimOffsetSensitivity = CreateConVar("l4d2_elite_hardsi_charger_aim_offset_sensitivity", "22.5", "If target is watching charger below this offset, try retargeting.", FCVAR_NOTIFY, true, 0.0, true, 179.0);

	g_cvTankAllowRock = CreateConVar("l4d2_elite_hardsi_tank_allow_rock", "1", "0=Disable tank rocks, 1=Allow.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTankSmartRock = CreateConVar("l4d2_elite_hardsi_tank_smart_rock_enable", "1", "Enable smart rock direction adjustment.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTankSmartRockRange = CreateConVar("l4d2_elite_hardsi_tank_smart_rock_range", "1200.0", "Smart rock assist range.", FCVAR_NOTIFY, true, 1.0, true, 5000.0);
	g_cvTankSmartRockAimSensitivity = CreateConVar("l4d2_elite_hardsi_tank_smart_rock_aim_offset", "22.5", "Aim offset threshold for smart rock retarget.", FCVAR_NOTIFY, true, -1.0, true, 180.0);

	CreateConVar("l4d2_elite_hardsi_version", PLUGIN_VERSION, "HardSI version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_hardsi");

	g_cvVomitRange = FindConVar("z_vomit_range");

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);
	HookEvent("charger_charge_start", Event_ChargeStart, EventHookMode_Post);
	HookEvent("charger_charge_end", Event_ChargeEnd, EventHookMode_Post);
	HookEvent("player_spawn", Event_ResetChargeState, EventHookMode_Post);
	HookEvent("player_death", Event_ResetChargeState, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			g_bCharging[i] = false;
			g_iCurrentTarget[i] = 0;
		}
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

public void OnMapEnd()
{
	ResetAssaultTimer(true);
}

public void OnConfigsExecuted()
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	char cfgName[64];
	g_cvAggressiveCfg.GetString(cfgName, sizeof(cfgName));
	if (cfgName[0] != '\0')
	{
		ServerCommand("exec l4d2_elite_hardsi/%s", cfgName);
	}

	RestartAssaultTimer();
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bCharging[i] = false;
		g_iCurrentTarget[i] = 0;
	}

	RestartAssaultTimer();
	return Plugin_Continue;
}

public void Event_ResetChargeState(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client > 0 && client <= MaxClients)
	{
		g_bCharging[client] = false;
		g_iCurrentTarget[client] = 0;
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

public Action Timer_Assault(Handle timer)
{
	if (timer != g_hAssaultTimer)
	{
		return Plugin_Stop;
	}

	if (!g_cvEnable.BoolValue || g_cvAssaultInterval.FloatValue <= 0.0)
	{
		ResetAssaultTimer(true);
		return Plugin_Stop;
	}

	RunCheatCommand("nb_assault");
	return Plugin_Continue;
}

void RestartAssaultTimer()
{
	ResetAssaultTimer(true);

	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	float interval = g_cvAssaultInterval.FloatValue;
	if (interval <= 0.0)
	{
		return;
	}

	g_hAssaultTimer = CreateTimer(interval, Timer_Assault, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void ResetAssaultTimer(bool close)
{
	if (g_hAssaultTimer == null)
	{
		return;
	}

	if (close)
	{
		KillTimer(g_hAssaultTimer);
	}

	g_hAssaultTimer = null;
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplyHardSi(client, true))
	{
		return;
	}

	char ability[32];
	event.GetString("ability", ability, sizeof(ability));

	if (StrEqual(ability, "ability_lunge"))
	{
		if (g_cvHunterEnable.BoolValue)
		{
			HandleHunterPounceUse(client);
		}
		return;
	}

	if (StrEqual(ability, "ability_vomit"))
	{
		if (g_cvBoomerEnable.BoolValue)
		{
			HandleBoomerVomitUse(client);
		}
		return;
	}

	if (StrEqual(ability, "ability_charge"))
	{
		if (g_cvChargerEnable.BoolValue)
		{
			HandleChargerChargeUse(client);
		}
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue || !ShouldApplyHardSi(client, true))
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

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	switch (zClass)
	{
		case ZC_BOOMER:
		{
			if (g_cvBoomerEnable.BoolValue && g_cvBoomerBhop.BoolValue)
			{
				return TryBhop(client, buttons, 90.0);
			}
		}
		case ZC_HUNTER:
		{
			if (g_cvHunterEnable.BoolValue)
			{
				return HandleHunterRunCmd(client, buttons);
			}
		}
		case ZC_SPITTER:
		{
			if (g_cvSpitterEnable.BoolValue && g_cvSpitterBhop.BoolValue)
			{
				return TryBhop(client, buttons, 85.0);
			}
		}
		case ZC_CHARGER:
		{
			if (g_cvChargerEnable.BoolValue)
			{
				Action result = HandleChargerRunCmd(client, buttons);
				if (result != Plugin_Continue)
				{
					return result;
				}
			}
		}
		case ZC_JOCKEY:
		{
			if (g_cvJockeyEnable.BoolValue)
			{
				return HandleJockeyRunCmd(client, buttons);
			}
		}
		case ZC_TANK:
		{
			if (g_cvTankEnable.BoolValue)
			{
				return HandleTankRunCmd(client, buttons);
			}
		}
	}

	return Plugin_Continue;
}

public Action L4D2_OnChooseVictim(int specialInfected, int &curTarget)
{
	if (specialInfected > 0 && specialInfected <= MaxClients)
	{
		g_iCurrentTarget[specialInfected] = curTarget;
	}

	return Plugin_Continue;
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	if (!g_cvEnable.BoolValue || !g_cvSmokerEnable.BoolValue)
	{
		return;
	}

	if (!ShouldApplyHardSiByActor(actor))
	{
		return;
	}

	if (strncmp(name, "Smoker", 6) == 0 && strcmp(name[6], "Attack") == 0)
	{
		action.OnCommandAssault = SmokerAttack_OnCommandAssault;
	}
}

Action SmokerAttack_OnCommandAssault(any action, int actor, ActionDesiredResult result)
{
	return Plugin_Handled;
}

public Action L4D_TankRock_OnRelease(int tank, int rock, float vecPos[3], float vecAng[3], float vecVel[3], float vecRot[3])
{
	if (!g_cvEnable.BoolValue || !g_cvTankEnable.BoolValue || !g_cvTankSmartRock.BoolValue)
	{
		return Plugin_Continue;
	}

	if (!ShouldApplyHardSi(tank, true))
	{
		return Plugin_Continue;
	}

	if (!IsClientInGame(tank) || GetEntProp(tank, Prop_Send, "m_zombieClass") != ZC_TANK)
	{
		return Plugin_Continue;
	}

	float tankPos[3];
	GetClientAbsOrigin(tank, tankPos);

	int target = FindClosestSurvivor(tankPos, g_cvTankSmartRockRange.FloatValue, true);
	if (!IsValidAliveSurvivor(target))
	{
		return Plugin_Continue;
	}

	if (g_cvTankSmartRockAimSensitivity.FloatValue >= 0.0 && IsTargetWatchingAttacker(target, tank, g_cvTankSmartRockAimSensitivity.FloatValue))
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
	if (nearestDist == -1 || nearestDist > g_cvHunterFastPounceDistance.IntValue)
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

		int target = FindClosestSurvivor(pos, float(g_cvChargerChargeDistance.IntValue), true);
		int hp = GetEntProp(client, Prop_Send, "m_iHealth");

		if (IsValidAliveSurvivor(target) && !IsPlayerIncapped(target) && GetEntPropEnt(target, Prop_Send, "m_carryAttacker") == -1)
		{
			if (hp <= g_cvChargerHealthThreshold.IntValue || IsWithinDistance(client, target, float(g_cvChargerChargeDistance.IntValue)))
			{
				buttons |= IN_ATTACK;
				buttons |= IN_ATTACK2;
				return Plugin_Changed;
			}
		}
	}

	if (g_cvChargerBhop.BoolValue && !g_bCharging[client])
	{
		return TryBhop(client, buttons, 100.0);
	}

	return Plugin_Continue;
}

Action HandleJockeyRunCmd(int client, int &buttons)
{
	float pos[3];
	GetClientAbsOrigin(client, pos);

	int nearestDist = GetSurvivorProximity(pos, -1);
	if (nearestDist == -1 || nearestDist > g_cvJockeyHopDistance.IntValue)
	{
		return Plugin_Continue;
	}

	buttons |= IN_JUMP;
	buttons |= IN_ATTACK;
	if (GetRandomInt(0, 1) == 1)
	{
		buttons |= IN_ATTACK2;
	}

	return Plugin_Changed;
}

Action HandleTankRunCmd(int client, int &buttons)
{
	if (!g_cvTankAllowRock.BoolValue)
	{
		buttons &= ~IN_ATTACK2;
	}

	if (g_cvTankBhop.BoolValue)
	{
		return TryBhop(client, buttons, 110.0);
	}

	return Plugin_Continue;
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

	float targetEye[3], velocity[3], angles[3];
	GetClientEyePosition(target, targetEye);
	MakeVectorFromPoints(boomerPos, targetEye, velocity);

	float speed = GetVectorLength(velocity);
	if (speed < vomitRange)
	{
		speed = 0.5 * vomitRange;
	}

	NormalizeVector(velocity, velocity);
	ScaleVector(velocity, speed);
	GetVectorAngles(velocity, angles);

	int flags = GetEntityFlags(client);
	SetEntityFlags(client, (flags & ~FL_FROZEN) & ~FL_ONGROUND);
	TeleportEntity(client, NULL_VECTOR, angles, velocity);
	SetEntityFlags(client, flags);
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
		LimitHunterLungeVertical(lunge, g_cvHunterPounceVerticalLimit.FloatValue);
		SetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", lunge);
		return;
	}

	int dist = GetSurvivorProximity(pos, target);
	if (dist > g_cvHunterStraightPounceDistance.IntValue && IsTargetWatchingAttacker(target, client, g_cvHunterAimOffsetSensitivity.FloatValue))
	{
		float yaw = GetRandomFloat(-35.0, 35.0);
		RotateVectorYaw(lunge, yaw);
	}

	LimitHunterLungeVertical(lunge, g_cvHunterPounceVerticalLimit.FloatValue);
	SetEntPropVector(lungeEntity, Prop_Send, "m_queuedLunge", lunge);
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
	if (!IsValidAliveSurvivor(current) || IsTargetWatchingAttacker(current, client, g_cvChargerAimOffsetSensitivity.FloatValue))
	{
		int other = FindClosestSurvivor(chargerPos, float(g_cvChargerChargeDistance.IntValue), false, current);
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

bool ShouldApplyHardSi(int client, bool requireAlive)
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

	if (!g_bHasEliteApi)
	{
		return false;
	}

	if (!EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_HARDSI;
}

bool ShouldApplyHardSiByActor(int actor)
{
	if (actor > 0 && actor <= MaxClients && IsClientInGame(actor))
	{
		return ShouldApplyHardSi(actor, false);
	}

	return false;
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

void RunCheatCommand(const char[] command)
{
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	ServerCommand("%s", command);
	ServerExecute();
	SetCommandFlags(command, flags);
}
