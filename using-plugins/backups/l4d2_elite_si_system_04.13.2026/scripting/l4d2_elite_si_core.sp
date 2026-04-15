#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_INFECTED 3

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_HARDSI,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING,
	ELITE_SUBTYPE_CHARGER_ACTION
}

enum
{
	ZC_SMOKER = 1,
	ZC_BOOMER,
	ZC_HUNTER,
	ZC_SPITTER,
	ZC_JOCKEY,
	ZC_CHARGER
}

ConVar g_cvEnable;
ConVar g_cvEliteChance;
ConVar g_cvEliteHpMultiplier;
ConVar g_cvEliteFireChance;
ConVar g_cvSmokerAbilityChance;
ConVar g_cvSpitterAbilityChance;
ConVar g_cvChargerSteeringChance;
ConVar g_cvChargerActionChance;

bool g_bIsElite[MAXPLAYERS + 1];
bool g_bIsFireImmune[MAXPLAYERS + 1];
int g_iEliteSubtype[MAXPLAYERS + 1];

GlobalForward g_fwEliteAssigned;
GlobalForward g_fwEliteCleared;

static const int ELITE_HARDSI_COLORS[6][3] =
{
	{180, 0, 255},
	{0, 255, 80},
	{0, 220, 255},
	{255, 140, 0},
	{255, 255, 0},
	{255, 30, 30}
};

static const int ELITE_ABILITY_COLORS[6][3] =
{
	{255, 80, 255},
	{0, 255, 80},
	{0, 220, 255},
	{255, 215, 0},
	{255, 255, 0},
	{255, 30, 30}
};

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Core",
	author = "OpenCode",
	description = "Core elite assignment, subtype and trait API.",
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

	CreateNative("EliteSI_IsElite", Native_EliteSI_IsElite);
	CreateNative("EliteSI_GetSubtype", Native_EliteSI_GetSubtype);
	CreateNative("EliteSI_IsFireImmune", Native_EliteSI_IsFireImmune);

	CreateNative("L4D2_IsEliteSI", Native_EliteSI_IsElite);
	CreateNative("L4D2_GetEliteSubtype", Native_EliteSI_GetSubtype);

	RegPluginLibrary("elite_si_core");
	RegPluginLibrary("l4d2_elite_SI_reward");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_core_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEliteChance = CreateConVar("l4d2_elite_si_core_spawn_chance", "30", "Chance (0-100) that a spawned SI becomes Elite.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvEliteHpMultiplier = CreateConVar("l4d2_elite_si_core_hp_multiplier", "2.5", "Elite HP multiplier.", FCVAR_NOTIFY, true, 0.1, true, 20.0);
	g_cvEliteFireChance = CreateConVar("l4d2_elite_si_core_fire_ignite_chance", "20", "Chance (0-100) for elite SI to ignite itself and gain fire immunity.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvSmokerAbilityChance = CreateConVar("l4d2_elite_si_core_smoker_ability_subtype_chance", "50", "Smoker elite chance to roll AbilityMovement subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvSpitterAbilityChance = CreateConVar("l4d2_elite_si_core_spitter_ability_subtype_chance", "50", "Spitter elite chance to roll AbilityMovement subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvChargerSteeringChance = CreateConVar("l4d2_elite_si_core_charger_steering_subtype_chance", "100", "Charger elite chance to roll ChargerSteering subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvChargerActionChance = CreateConVar("l4d2_elite_si_core_charger_action_subtype_chance", "0", "Charger elite chance to roll ChargerAction subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);

	CreateConVar("l4d2_elite_si_core_version", PLUGIN_VERSION, "Elite SI core version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_core");

	g_fwEliteAssigned = new GlobalForward("EliteSI_OnEliteAssigned", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	g_fwEliteCleared = new GlobalForward("EliteSI_OnEliteCleared", ET_Ignore, Param_Cell);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client)
{
	ResetEliteState(client, false, false);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	ResetEliteState(client, false, false);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			bool isInfected = (GetClientTeam(i) == TEAM_INFECTED);
			ResetEliteState(i, isInfected, true);
		}
	}

	return Plugin_Continue;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidInfected(client))
	{
		return Plugin_Continue;
	}

	CreateTimer(0.12, Timer_ProcessSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_ProcessSpawn(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (!IsValidInfected(client) || !IsPlayerAlive(client))
	{
		return Plugin_Stop;
	}

	ResetEliteState(client, true, true);

	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Stop;
	}

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	if (!IsTrackableSiClass(zClass))
	{
		return Plugin_Stop;
	}

	if (GetRandomInt(1, 100) > g_cvEliteChance.IntValue)
	{
		return Plugin_Stop;
	}

	g_bIsElite[client] = true;
	g_iEliteSubtype[client] = RollSubtypeByClass(zClass);
	g_bIsFireImmune[client] = false;

	ApplyEliteHealth(client);
	ApplyEliteColor(client, zClass, g_iEliteSubtype[client]);

	if (GetRandomInt(1, 100) <= g_cvEliteFireChance.IntValue)
	{
		g_bIsFireImmune[client] = true;
		IgniteEntity(client, 9999.0);
	}

	NotifyEliteAssigned(client, zClass, g_iEliteSubtype[client]);
	return Plugin_Stop;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!IsValidInfected(victim))
	{
		return Plugin_Continue;
	}

	if (!g_bIsElite[victim] || !g_bIsFireImmune[victim])
	{
		return Plugin_Continue;
	}

	if (damageType & DMG_BURN)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void ResetEliteState(int client, bool resetRender, bool notifyForward)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	bool wasElite = g_bIsElite[client];
	g_bIsElite[client] = false;
	g_bIsFireImmune[client] = false;
	g_iEliteSubtype[client] = ELITE_SUBTYPE_NONE;

	if (resetRender && IsClientInGame(client))
	{
		SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
		SetEntityRenderMode(client, RENDER_NORMAL);
		SetEntityRenderColor(client, 255, 255, 255, 255);
	}

	if (notifyForward && wasElite)
	{
		NotifyEliteCleared(client);
	}
}

void ApplyEliteHealth(int client)
{
	int baseMaxHp = GetEntProp(client, Prop_Data, "m_iMaxHealth");
	if (baseMaxHp <= 0)
	{
		return;
	}

	int eliteHp = RoundToFloor(float(baseMaxHp) * g_cvEliteHpMultiplier.FloatValue);
	if (eliteHp <= 0)
	{
		eliteHp = baseMaxHp;
	}

	SetEntProp(client, Prop_Data, "m_iMaxHealth", eliteHp);
	SetEntityHealth(client, eliteHp);
}

void ApplyEliteColor(int client, int zClass, int subtype)
{
	if (!IsTrackableSiClass(zClass))
	{
		return;
	}

	int colorIndex = zClass - 1;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);

	if (subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT)
	{
		SetEntityRenderColor(client, ELITE_ABILITY_COLORS[colorIndex][0], ELITE_ABILITY_COLORS[colorIndex][1], ELITE_ABILITY_COLORS[colorIndex][2], 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_CHARGER_STEERING)
	{
		SetEntityRenderColor(client, 255, 60, 60, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_CHARGER_ACTION)
	{
		SetEntityRenderColor(client, 255, 120, 20, 255);
		return;
	}

	SetEntityRenderColor(client, ELITE_HARDSI_COLORS[colorIndex][0], ELITE_HARDSI_COLORS[colorIndex][1], ELITE_HARDSI_COLORS[colorIndex][2], 255);
}

int RollSubtypeByClass(int zClass)
{
	switch (zClass)
	{
		case ZC_SMOKER:
		{
			return GetRandomInt(1, 100) <= g_cvSmokerAbilityChance.IntValue ? ELITE_SUBTYPE_ABILITY_MOVEMENT : ELITE_SUBTYPE_HARDSI;
		}
		case ZC_SPITTER:
		{
			return GetRandomInt(1, 100) <= g_cvSpitterAbilityChance.IntValue ? ELITE_SUBTYPE_ABILITY_MOVEMENT : ELITE_SUBTYPE_HARDSI;
		}
		case ZC_CHARGER:
		{
			int roll = GetRandomInt(1, 100);
			int actionChance = g_cvChargerActionChance.IntValue;
			int steeringChance = g_cvChargerSteeringChance.IntValue;

			if (roll <= actionChance)
			{
				return ELITE_SUBTYPE_CHARGER_ACTION;
			}

			int steeringUpperBound = actionChance + steeringChance;
			if (steeringUpperBound > 100)
			{
				steeringUpperBound = 100;
			}

			if (roll <= steeringUpperBound)
			{
				return ELITE_SUBTYPE_CHARGER_STEERING;
			}

			return ELITE_SUBTYPE_HARDSI;
		}
	}

	return ELITE_SUBTYPE_HARDSI;
}

bool IsTrackableSiClass(int zClass)
{
	return zClass >= ZC_SMOKER && zClass <= ZC_CHARGER;
}

bool IsValidInfected(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED);
}

void NotifyEliteAssigned(int client, int zClass, int subtype)
{
	if (g_fwEliteAssigned == null)
	{
		return;
	}

	Call_StartForward(g_fwEliteAssigned);
	Call_PushCell(client);
	Call_PushCell(zClass);
	Call_PushCell(subtype);
	Call_Finish();
}

void NotifyEliteCleared(int client)
{
	if (g_fwEliteCleared == null)
	{
		return;
	}

	Call_StartForward(g_fwEliteCleared);
	Call_PushCell(client);
	Call_Finish();
}

public any Native_EliteSI_IsElite(Handle plugin, int numParams)
{
	if (numParams < 1)
	{
		return false;
	}

	int client = GetNativeCell(1);
	if (!IsValidInfected(client))
	{
		return false;
	}

	return g_bIsElite[client];
}

public any Native_EliteSI_GetSubtype(Handle plugin, int numParams)
{
	if (numParams < 1)
	{
		return ELITE_SUBTYPE_NONE;
	}

	int client = GetNativeCell(1);
	if (!IsValidInfected(client))
	{
		return ELITE_SUBTYPE_NONE;
	}

	return g_iEliteSubtype[client];
}

public any Native_EliteSI_IsFireImmune(Handle plugin, int numParams)
{
	if (numParams < 1)
	{
		return false;
	}

	int client = GetNativeCell(1);
	if (!IsValidInfected(client))
	{
		return false;
	}

	return g_bIsFireImmune[client];
}
