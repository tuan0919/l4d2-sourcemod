#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define PLUGIN_VERSION "2.0.2"

#define TEAM_INFECTED 3

#define ELITE_TYPE_DATA_FILE "data/elite_si_type_descriptions.cfg"
#define ELITE_CLASS_COUNT 7
#define ELITE_SUBTYPE_COUNT 40
#define ELITE_TYPE_NAME_LEN 48
#define ELITE_TYPE_DESC_LEN 192

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_ABNORMAL_BEHAVIOR,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING,
	ELITE_SUBTYPE_CHARGER_ACTION,
	ELITE_SUBTYPE_SMOKER_ASPHYXIATION,
	ELITE_SUBTYPE_SMOKER_COLLAPSED_LUNG,
	ELITE_SUBTYPE_SMOKER_METHANE_BLAST,
	ELITE_SUBTYPE_SMOKER_METHANE_LEAK,
	ELITE_SUBTYPE_SMOKER_METHANE_STRIKE,
	ELITE_SUBTYPE_SMOKER_MOON_WALK,
	ELITE_SUBTYPE_SMOKER_RESTRAINED_HOSTAGE,
	ELITE_SUBTYPE_SMOKER_SMOKE_SCREEN,
	ELITE_SUBTYPE_SMOKER_TONGUE_STRIP,
	ELITE_SUBTYPE_SMOKER_TONGUE_WHIP,
	ELITE_SUBTYPE_SMOKER_VOID_POCKET,
	ELITE_SUBTYPE_BOOMER_BILE_BELLY,
	ELITE_SUBTYPE_BOOMER_BILE_BLAST,
	ELITE_SUBTYPE_BOOMER_BILE_FEET,
	ELITE_SUBTYPE_BOOMER_BILE_MASK,
	ELITE_SUBTYPE_BOOMER_BILE_PIMPLE,
	ELITE_SUBTYPE_BOOMER_BILE_SHOWER,
	ELITE_SUBTYPE_BOOMER_BILE_SWIPE,
	ELITE_SUBTYPE_BOOMER_BILE_THROW,
	ELITE_SUBTYPE_BOOMER_EXPLOSIVE_DIARRHEA,
	ELITE_SUBTYPE_BOOMER_FLATULENCE,
	ELITE_SUBTYPE_HUNTER_TARGET_SWITCH,
	ELITE_SUBTYPE_BOOMER_FLASHBANG,
	ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP,
	ELITE_SUBTYPE_SMOKER_TOXIC_GAS,
	ELITE_SUBTYPE_SMOKER_IGNITOR,
	ELITE_SUBTYPE_SPITTER_ACID_POOL,
	ELITE_SUBTYPE_SPITTER_SNEAKY,
	ELITE_SUBTYPE_BOOMER_LEAKER,
	ELITE_SUBTYPE_HUNTER_HEROIC,
	ELITE_SUBTYPE_CHARGER_UNSTOPPABLE,
	ELITE_SUBTYPE_JOCKEY_JUMPER,
	ELITE_SUBTYPE_JOCKEY_HEROIC,
	ELITE_SUBTYPE_TANK_IGNITOR,
	ELITE_SUBTYPE_TANK_EXPLOSIVE
}

enum
{
	ZC_SMOKER = 1,
	ZC_BOOMER,
	ZC_HUNTER,
	ZC_SPITTER,
	ZC_JOCKEY,
	ZC_CHARGER,
	ZC_TANK = 8
}

enum
{
	ELITE_CLASS_SMOKER = 0,
	ELITE_CLASS_BOOMER,
	ELITE_CLASS_HUNTER,
	ELITE_CLASS_SPITTER,
	ELITE_CLASS_JOCKEY,
	ELITE_CLASS_CHARGER,
	ELITE_CLASS_TANK
}

ConVar g_cvEnable;
ConVar g_cvEliteChance;
ConVar g_cvEliteSpawnCooldown;
ConVar g_cvEliteHpMultiplier;
ConVar g_cvEliteTankHpMultiplier;
ConVar g_cvSpawnAnnounce;
ConVar g_cvSmokerForceSubtype;
ConVar g_cvBoomerForceSubtype;
ConVar g_cvSubtypeChance[ELITE_CLASS_COUNT][ELITE_SUBTYPE_COUNT];

bool g_bIsElite[MAXPLAYERS + 1];
bool g_bIsFireImmune[MAXPLAYERS + 1];
int g_iEliteSubtype[MAXPLAYERS + 1];
float g_fNextEliteSpawnTime;

GlobalForward g_fwEliteAssigned;
GlobalForward g_fwEliteCleared;

static const int ELITE_ABNORMAL_BEHAVIOR_COLORS[ELITE_CLASS_COUNT][3] =
{
	{180, 0, 255},
	{0, 255, 80},
	{0, 220, 255},
	{255, 140, 0},
	{255, 255, 0},
	{255, 30, 30},
	{255, 110, 40}
};

static const int ELITE_ABILITY_COLORS[ELITE_CLASS_COUNT][3] =
{
	{255, 80, 255},
	{0, 255, 80},
	{0, 220, 255},
	{255, 215, 0},
	{255, 255, 0},
	{255, 30, 30},
	{255, 170, 60}
};

static const char g_sEliteClassKeys[ELITE_CLASS_COUNT][] =
{
	"smoker",
	"boomer",
	"hunter",
	"spitter",
	"jockey",
	"charger",
	"tank"
};

char g_sEliteTypeNames[ELITE_CLASS_COUNT][ELITE_SUBTYPE_COUNT][ELITE_TYPE_NAME_LEN];
char g_sEliteTypeDescs[ELITE_CLASS_COUNT][ELITE_SUBTYPE_COUNT][ELITE_TYPE_DESC_LEN];

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
	CreateNative("EliteSI_GetTypeName", Native_EliteSI_GetTypeName);
	CreateNative("EliteSI_GetTypeDescription", Native_EliteSI_GetTypeDescription);

	CreateNative("L4D2_IsEliteSI", Native_EliteSI_IsElite);
	CreateNative("L4D2_GetEliteSubtype", Native_EliteSI_GetSubtype);
	CreateNative("L4D2_GetEliteTypeName", Native_EliteSI_GetTypeName);
	CreateNative("L4D2_GetEliteTypeDescription", Native_EliteSI_GetTypeDescription);

	RegPluginLibrary("elite_si_core");
	RegPluginLibrary("l4d2_elite_SI_reward");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_core_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEliteChance = CreateConVar("l4d2_elite_si_core_spawn_chance", "50", "Chance (0-100) that a spawned SI becomes Elite.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvEliteSpawnCooldown = CreateConVar("l4d2_elite_si_core_spawn_cooldown", "20.0", "Cooldown in seconds between successful elite SI spawns (0=Off).", FCVAR_NOTIFY, true, 0.0, true, 300.0);
	g_cvEliteHpMultiplier = CreateConVar("l4d2_elite_si_core_hp_multiplier", "2.5", "Elite HP multiplier.", FCVAR_NOTIFY, true, 0.1, true, 20.0);
	g_cvEliteTankHpMultiplier = CreateConVar("l4d2_elite_si_core_tank_hp_multiplier", "1.2", "Elite Tank HP multiplier.", FCVAR_NOTIFY, true, 0.1, true, 20.0);
	g_cvSpawnAnnounce = CreateConVar("l4d2_elite_si_core_spawn_announce", "1", "0=Off, 1=Announce elite SI spawn to chat with {red} color.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmokerForceSubtype = CreateConVar("l4d2_elite_si_core_smoker_force_subtype", "0", "0=random smoker subtype, 1=force Abnormal behavior, 2=force Strange Movement, 28=force Pull Weapon Drop, 29=force Toxic Gas, 30=force Ignitor for test.", FCVAR_NOTIFY, true, 0.0, true, 30.0);
	g_cvBoomerForceSubtype = CreateConVar("l4d2_elite_si_core_boomer_force_subtype", "0", "0=random boomer subtype, 1 or 27=force exact boomer subtype for test.", FCVAR_NOTIFY, true, 0.0, true, 27.0);

	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_smoker_abnormal_subtype_chance", "1", "Relative weight for Smoker elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_ABILITY_MOVEMENT, "l4d2_elite_si_core_smoker_movement_subtype_chance", "1", "Relative weight for Smoker elite to roll Strange Movement.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP, "l4d2_elite_si_core_smoker_pull_weapon_drop_subtype_chance", "1", "Relative weight for Smoker elite to roll Pull Weapon Drop.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_TOXIC_GAS, "l4d2_elite_si_core_smoker_toxic_gas_subtype_chance", "1", "Relative weight for Smoker elite to roll Toxic Gas.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_IGNITOR, "l4d2_elite_si_core_smoker_ignitor_subtype_chance", "1", "Relative weight for Smoker elite to roll Ignitor.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_boomer_abnormal_subtype_chance", "1", "Relative weight for Boomer elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_FLASHBANG, "l4d2_elite_si_core_boomer_flashbang_subtype_chance", "1", "Relative weight for Boomer elite to roll Flashbang.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_LEAKER, "l4d2_elite_si_core_boomer_leaker_subtype_chance", "1", "Relative weight for Boomer elite to roll Leaker.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_HUNTER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_hunter_abnormal_subtype_chance", "1", "Relative weight for Hunter elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_HUNTER, ELITE_SUBTYPE_HUNTER_TARGET_SWITCH, "l4d2_elite_si_core_hunter_target_switch_subtype_chance", "1", "Relative weight for Hunter elite to roll Target Switch.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_HUNTER, ELITE_SUBTYPE_HUNTER_HEROIC, "l4d2_elite_si_core_hunter_heroic_subtype_chance", "1", "Relative weight for Hunter elite to roll Heroic.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_SPITTER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_spitter_abnormal_subtype_chance", "1", "Relative weight for Spitter elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SPITTER, ELITE_SUBTYPE_ABILITY_MOVEMENT, "l4d2_elite_si_core_spitter_ability_subtype_chance", "1", "Relative weight for Spitter elite to roll Strange Movement.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SPITTER, ELITE_SUBTYPE_SPITTER_ACID_POOL, "l4d2_elite_si_core_spitter_acid_pool_subtype_chance", "1", "Relative weight for Spitter elite to roll Acid Pool.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SPITTER, ELITE_SUBTYPE_SPITTER_SNEAKY, "l4d2_elite_si_core_spitter_sneaky_subtype_chance", "1", "Relative weight for Spitter elite to roll Sneaky.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_JOCKEY, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_jockey_abnormal_subtype_chance", "1", "Relative weight for Jockey elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_JOCKEY, ELITE_SUBTYPE_JOCKEY_JUMPER, "l4d2_elite_si_core_jockey_jumper_subtype_chance", "1", "Relative weight for Jockey elite to roll Jumper.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_JOCKEY, ELITE_SUBTYPE_JOCKEY_HEROIC, "l4d2_elite_si_core_jockey_heroic_subtype_chance", "1", "Relative weight for Jockey elite to roll Heroic.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_charger_abnormal_subtype_chance", "1", "Relative weight for Charger elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_CHARGER_STEERING, "l4d2_elite_si_core_charger_steering_subtype_chance", "1", "Relative weight for Charger elite to roll ChargerSteering.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_CHARGER_ACTION, "l4d2_elite_si_core_charger_action_subtype_chance", "1", "Relative weight for Charger elite to roll ChargerAction.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_CHARGER_UNSTOPPABLE, "l4d2_elite_si_core_charger_unstoppable_subtype_chance", "1", "Relative weight for Charger elite to roll Unstoppable.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_TANK, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_tank_abnormal_subtype_chance", "1", "Relative weight for Tank elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_TANK, ELITE_SUBTYPE_ABILITY_MOVEMENT, "l4d2_elite_si_core_tank_movement_subtype_chance", "1", "Relative weight for Tank elite to roll Strange Movement.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_TANK, ELITE_SUBTYPE_TANK_IGNITOR, "l4d2_elite_si_core_tank_ignitor_subtype_chance", "1", "Relative weight for Tank elite to roll Ignitor.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_TANK, ELITE_SUBTYPE_TANK_EXPLOSIVE, "l4d2_elite_si_core_tank_explosive_subtype_chance", "1", "Relative weight for Tank elite to roll Explosive.");

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

	LoadEliteTypeDescriptionsFromData();
	g_fNextEliteSpawnTime = 0.0;
}

public void OnMapStart()
{
	LoadEliteTypeDescriptionsFromData();
}

public void OnAllPluginsLoaded()
{
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
	g_fNextEliteSpawnTime = 0.0;

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

	float now = GetGameTime();
	float eliteCooldown = g_cvEliteSpawnCooldown.FloatValue;
	if (eliteCooldown > 0.0 && now < g_fNextEliteSpawnTime)
	{
		return Plugin_Stop;
	}

	if (GetRandomInt(1, 100) > g_cvEliteChance.IntValue)
	{
		return Plugin_Stop;
	}

	g_bIsElite[client] = true;
	g_iEliteSubtype[client] = RollSubtypeByClass(zClass);
	g_bIsFireImmune[client] = (g_iEliteSubtype[client] == ELITE_SUBTYPE_SMOKER_IGNITOR || g_iEliteSubtype[client] == ELITE_SUBTYPE_BOOMER_LEAKER || g_iEliteSubtype[client] == ELITE_SUBTYPE_TANK_IGNITOR);

	ApplyEliteHealth(client);
	ApplyEliteColor(client, zClass, g_iEliteSubtype[client]);

	NotifyEliteAssigned(client, zClass, g_iEliteSubtype[client]);
	AnnounceEliteSpawn(client, zClass, g_iEliteSubtype[client]);

	if (eliteCooldown > 0.0)
	{
		g_fNextEliteSpawnTime = now + eliteCooldown;
	}

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

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	float hpMultiplier = (zClass == ZC_TANK) ? g_cvEliteTankHpMultiplier.FloatValue : g_cvEliteHpMultiplier.FloatValue;
	int eliteHp = RoundToFloor(float(baseMaxHp) * hpMultiplier);
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

	int colorIndex = GetSiClassIndex(zClass);
	if (colorIndex < 0)
	{
		return;
	}
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);

	if (subtype == ELITE_SUBTYPE_HUNTER_TARGET_SWITCH)
	{
		SetEntityRenderColor(client, 80, 235, 255, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_BOOMER_FLASHBANG)
	{
		SetEntityRenderColor(client, 180, 255, 235, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP)
	{
		SetEntityRenderColor(client, 150, 110, 255, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_SMOKER_TOXIC_GAS)
	{
		SetEntityRenderColor(client, 55, 75, 55, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_SMOKER_IGNITOR)
	{
		SetEntityRenderColor(client, 255, 120, 40, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_SPITTER_ACID_POOL)
	{
		SetEntityRenderColor(client, 120, 255, 80, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_SPITTER_SNEAKY)
	{
		SetEntityRenderColor(client, 120, 255, 180, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_BOOMER_LEAKER)
	{
		SetEntityRenderColor(client, 255, 170, 90, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_HUNTER_HEROIC)
	{
		SetEntityRenderColor(client, 255, 60, 0, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_TANK_IGNITOR)
	{
		SetEntityRenderColor(client, 255, 80, 0, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_TANK_EXPLOSIVE)
	{
		SetEntityRenderColor(client, 255, 30, 0, 255);
		return;
	}

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

	if (subtype == ELITE_SUBTYPE_CHARGER_UNSTOPPABLE)
	{
		SetEntityRenderColor(client, 120, 80, 80, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_JOCKEY_JUMPER)
	{
		SetEntityRenderColor(client, 255, 190, 40, 255);
		return;
	}

	if (subtype == ELITE_SUBTYPE_JOCKEY_HEROIC)
	{
		SetEntityRenderColor(client, 255, 80, 20, 255);
		return;
	}

	SetEntityRenderColor(client, ELITE_ABNORMAL_BEHAVIOR_COLORS[colorIndex][0], ELITE_ABNORMAL_BEHAVIOR_COLORS[colorIndex][1], ELITE_ABNORMAL_BEHAVIOR_COLORS[colorIndex][2], 255);
}

int RollSubtypeByClass(int zClass)
{
	int forcedSubtype = GetForcedSubtypeForClass(zClass);
	if (forcedSubtype != ELITE_SUBTYPE_NONE)
	{
		return forcedSubtype;
	}

	return RollWeightedSubtypeByClass(zClass);
}

int GetForcedSubtypeForClass(int zClass)
{
	switch (zClass)
	{
		case ZC_SMOKER:
		{
			int forcedSubtype = g_cvSmokerForceSubtype.IntValue;
			if (forcedSubtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || forcedSubtype == ELITE_SUBTYPE_ABILITY_MOVEMENT || forcedSubtype == ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP || forcedSubtype == ELITE_SUBTYPE_SMOKER_TOXIC_GAS || forcedSubtype == ELITE_SUBTYPE_SMOKER_IGNITOR)
			{
				return forcedSubtype;
			}
		}

		case ZC_BOOMER:
		{
			int forcedSubtype = g_cvBoomerForceSubtype.IntValue;
			if (forcedSubtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || forcedSubtype == ELITE_SUBTYPE_BOOMER_FLASHBANG)
			{
				return forcedSubtype;
			}
		}
	}

	return ELITE_SUBTYPE_NONE;
}

int RollWeightedSubtypeByClass(int zClass)
{
	int classIdx = GetSiClassIndex(zClass);
	if (classIdx < 0)
	{
		return ELITE_SUBTYPE_ABNORMAL_BEHAVIOR;
	}

	int subtypes[ELITE_SUBTYPE_COUNT];
	int weights[ELITE_SUBTYPE_COUNT];
	int count = 0;
	int totalWeight = 0;

	for (int subtype = ELITE_SUBTYPE_ABNORMAL_BEHAVIOR; subtype < ELITE_SUBTYPE_COUNT; subtype++)
	{
		if (!IsSubtypeSupportedByClassIndex(classIdx, subtype))
		{
			continue;
		}

		int weight = GetSubtypeChanceWeight(classIdx, subtype);
		if (weight <= 0)
		{
			continue;
		}

		subtypes[count] = subtype;
		weights[count] = weight;
		totalWeight += weight;
		count++;
	}

	if (count <= 0 || totalWeight <= 0)
	{
		return GetDefaultSubtypeForClass(zClass);
	}

	int roll = GetRandomInt(1, totalWeight);
	int running = 0;
	for (int i = 0; i < count; i++)
	{
		running += weights[i];
		if (roll <= running)
		{
			return subtypes[i];
		}
	}

	return subtypes[count - 1];
}

int GetSubtypeChanceWeight(int classIdx, int subtype)
{
	ConVar convar = g_cvSubtypeChance[classIdx][subtype];
	if (convar == null)
	{
		return 0;
	}

	return convar.IntValue;
}

int GetDefaultSubtypeForClass(int zClass)
{
	if (zClass == ZC_SMOKER)
	{
		return ELITE_SUBTYPE_ABILITY_MOVEMENT;
	}

	return ELITE_SUBTYPE_ABNORMAL_BEHAVIOR;
}

void RegisterSubtypeChanceConVar(int classIdx, int subtype, const char[] name, const char[] defaultValue, const char[] description)
{
	g_cvSubtypeChance[classIdx][subtype] = CreateConVar(name, defaultValue, description, FCVAR_NOTIFY, true, 0.0, true, 100.0);
}

void AnnounceEliteSpawn(int client, int zClass, int subtype)
{
	if (!g_cvSpawnAnnounce.BoolValue)
	{
		return;
	}

	if (!IsValidInfected(client) || !IsPlayerAlive(client) || !g_bIsElite[client])
	{
		return;
	}

	char classLabel[24];
	char typeLabel[48];
	char typeDesc[192];
	GetSiClassLabel(zClass, classLabel, sizeof(classLabel));
	GetEliteTypeNameByClassSubtype(zClass, subtype, typeLabel, sizeof(typeLabel));
	GetEliteTypeDescriptionByClassSubtype(zClass, subtype, typeDesc, sizeof(typeDesc));

	CPrintToChatAll("{red}Elite %s has spawned - %s (%s).", classLabel, typeLabel, typeDesc);
}

void GetEliteTypeNameByClassSubtype(int zClass, int subtype, char[] buffer, int maxlen)
{
	if (TryGetConfiguredEliteTypeName(zClass, subtype, buffer, maxlen))
	{
		return;
	}

	GetSubtypeLabelDefault(subtype, buffer, maxlen);
}

void GetEliteTypeDescriptionByClassSubtype(int zClass, int subtype, char[] buffer, int maxlen)
{
	if (TryGetConfiguredEliteTypeDescription(zClass, subtype, buffer, maxlen))
	{
		return;
	}

	GetSubtypeDescriptionDefault(subtype, buffer, maxlen);
}

bool TryGetConfiguredEliteTypeName(int zClass, int subtype, char[] buffer, int maxlen)
{
	int classIndex = GetSiClassIndex(zClass);
	if (classIndex == -1 || !IsValidSubtypeForConfig(subtype))
	{
		return false;
	}

	if (g_sEliteTypeNames[classIndex][subtype][0] == '\0')
	{
		return false;
	}

	strcopy(buffer, maxlen, g_sEliteTypeNames[classIndex][subtype]);
	return true;
}

bool TryGetConfiguredEliteTypeDescription(int zClass, int subtype, char[] buffer, int maxlen)
{
	int classIndex = GetSiClassIndex(zClass);
	if (classIndex == -1 || !IsValidSubtypeForConfig(subtype))
	{
		return false;
	}

	if (g_sEliteTypeDescs[classIndex][subtype][0] == '\0')
	{
		return false;
	}

	strcopy(buffer, maxlen, g_sEliteTypeDescs[classIndex][subtype]);
	return true;
}

void GetSiClassLabel(int zClass, char[] buffer, int maxlen)
{
		switch (zClass)
		{
			case ZC_SMOKER: strcopy(buffer, maxlen, "Smoker");
			case ZC_BOOMER: strcopy(buffer, maxlen, "Boomer");
			case ZC_HUNTER: strcopy(buffer, maxlen, "Hunter");
			case ZC_SPITTER: strcopy(buffer, maxlen, "Spitter");
			case ZC_JOCKEY: strcopy(buffer, maxlen, "Jockey");
			case ZC_CHARGER: strcopy(buffer, maxlen, "Charger");
			case ZC_TANK: strcopy(buffer, maxlen, "Tank");
			default: strcopy(buffer, maxlen, "SI");
		}
}

void GetSubtypeLabelDefault(int subtype, char[] buffer, int maxlen)
{
		switch (subtype)
	{
		case ELITE_SUBTYPE_ABNORMAL_BEHAVIOR: strcopy(buffer, maxlen, "Abnormal behavior");
		case ELITE_SUBTYPE_ABILITY_MOVEMENT: strcopy(buffer, maxlen, "Strange Movement");
		case ELITE_SUBTYPE_CHARGER_STEERING: strcopy(buffer, maxlen, "ChargerSteering");
		case ELITE_SUBTYPE_CHARGER_ACTION: strcopy(buffer, maxlen, "ChargerAction");
		case ELITE_SUBTYPE_HUNTER_TARGET_SWITCH: strcopy(buffer, maxlen, "Target Switch");
		case ELITE_SUBTYPE_BOOMER_FLASHBANG: strcopy(buffer, maxlen, "Flashbang");
		case ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP: strcopy(buffer, maxlen, "Pull Weapon Drop");
		case ELITE_SUBTYPE_SMOKER_TOXIC_GAS: strcopy(buffer, maxlen, "Toxic Gas");
		case ELITE_SUBTYPE_SMOKER_IGNITOR: strcopy(buffer, maxlen, "Ignitor Smoker");
		case ELITE_SUBTYPE_SPITTER_ACID_POOL: strcopy(buffer, maxlen, "Acid Pool");
		case ELITE_SUBTYPE_SPITTER_SNEAKY: strcopy(buffer, maxlen, "Sneaky");
		case ELITE_SUBTYPE_BOOMER_LEAKER: strcopy(buffer, maxlen, "Leaker");
		case ELITE_SUBTYPE_HUNTER_HEROIC: strcopy(buffer, maxlen, "Heroic");
		case ELITE_SUBTYPE_CHARGER_UNSTOPPABLE: strcopy(buffer, maxlen, "Unstoppable");
		case ELITE_SUBTYPE_JOCKEY_JUMPER: strcopy(buffer, maxlen, "Jumper");
		case ELITE_SUBTYPE_JOCKEY_HEROIC: strcopy(buffer, maxlen, "Heroic");
		case ELITE_SUBTYPE_TANK_IGNITOR: strcopy(buffer, maxlen, "Ignitor");
		case ELITE_SUBTYPE_TANK_EXPLOSIVE: strcopy(buffer, maxlen, "Explosive");
		default: strcopy(buffer, maxlen, "Unknown");
	}
}

void GetSubtypeDescriptionDefault(int subtype, char[] buffer, int maxlen)
{
		switch (subtype)
	{
		case ELITE_SUBTYPE_ABNORMAL_BEHAVIOR: strcopy(buffer, maxlen, "aggressive AI pressure with advanced attack patterns");
		case ELITE_SUBTYPE_ABILITY_MOVEMENT: strcopy(buffer, maxlen, "maintains momentum while casting special abilities");
		case ELITE_SUBTYPE_CHARGER_STEERING: strcopy(buffer, maxlen, "can steer aggressively during a charge");
		case ELITE_SUBTYPE_CHARGER_ACTION: strcopy(buffer, maxlen, "uses dedicated charger action routines");
		case ELITE_SUBTYPE_HUNTER_TARGET_SWITCH: strcopy(buffer, maxlen, "abandons incapacitated prey and pounces a new target");
		case ELITE_SUBTYPE_BOOMER_FLASHBANG: strcopy(buffer, maxlen, "detonates with a blinding flash when killed");
		case ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP: strcopy(buffer, maxlen, "forces the grabbed survivor to drop the weapon currently in hand");
		case ELITE_SUBTYPE_SMOKER_TOXIC_GAS: strcopy(buffer, maxlen, "abandons tongue pulls, rushes in for melee, and releases damaging toxic smoke when shoved or killed");
		case ELITE_SUBTYPE_SMOKER_IGNITOR: strcopy(buffer, maxlen, "spawns engulfed in flames, ignites survivors after tongue grabs and melee hits, and leaves a burning fire patch on death");
		case ELITE_SUBTYPE_SPITTER_ACID_POOL: strcopy(buffer, maxlen, "never spits normally, rushes survivors with faster movement, and drops acid pools underfoot and on jumps");
		case ELITE_SUBTYPE_SPITTER_SNEAKY: strcopy(buffer, maxlen, "keeps distance, cloaks in cycles with bullet immunity, and fires a two-shot acid burst before vanishing again");
		case ELITE_SUBTYPE_BOOMER_LEAKER: strcopy(buffer, maxlen, "ignites on spawn, rushes in to self-detonate after crouching nearby, and replaces bile explosions with lingering fire patches");
		case ELITE_SUBTYPE_HUNTER_HEROIC: strcopy(buffer, maxlen, "holds a loaded pipe bomb, dropping it upon pinning a survivor or upon death to cause a massive explosion");
		case ELITE_SUBTYPE_CHARGER_UNSTOPPABLE: strcopy(buffer, maxlen, "temporarily invisible and invincible during charges, knocks targets into the air on melee, and stops carrying midway");
		case ELITE_SUBTYPE_JOCKEY_JUMPER: strcopy(buffer, maxlen, "keeps bouncing upward while riding a survivor to create extra fall damage");
		case ELITE_SUBTYPE_JOCKEY_HEROIC: strcopy(buffer, maxlen, "carries a pipe bomb in hand, activating it when riding a survivor and dropping it if interrupted or killed");
		case ELITE_SUBTYPE_TANK_IGNITOR: strcopy(buffer, maxlen, "always on fire and immune to burn damage, throws burning rocks that create fire patches on impact");
		case ELITE_SUBTYPE_TANK_EXPLOSIVE: strcopy(buffer, maxlen, "throws rocks that explode on impact, dealing massive AOE blast damage and shaking the screen; direct hits detonate under the survivor's feet");
		default: strcopy(buffer, maxlen, "unknown elite trait");
	}
}

int GetSiClassIndex(int zClass)
{
	switch (zClass)
	{
		case ZC_SMOKER: return ELITE_CLASS_SMOKER;
		case ZC_BOOMER: return ELITE_CLASS_BOOMER;
		case ZC_HUNTER: return ELITE_CLASS_HUNTER;
		case ZC_SPITTER: return ELITE_CLASS_SPITTER;
		case ZC_JOCKEY: return ELITE_CLASS_JOCKEY;
		case ZC_CHARGER: return ELITE_CLASS_CHARGER;
		case ZC_TANK: return ELITE_CLASS_TANK;
	}

	return -1;
}

bool IsValidSubtypeForConfig(int subtype)
{
	return subtype >= ELITE_SUBTYPE_ABNORMAL_BEHAVIOR && subtype < ELITE_SUBTYPE_COUNT;
}

bool IsSubtypeSupportedByClassIndex(int classIdx, int subtype)
{
	if (classIdx < 0 || classIdx >= ELITE_CLASS_COUNT || !IsValidSubtypeForConfig(subtype))
	{
		return false;
	}

	switch (classIdx)
	{
		case ELITE_CLASS_SMOKER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT || subtype == ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP || subtype == ELITE_SUBTYPE_SMOKER_TOXIC_GAS || subtype == ELITE_SUBTYPE_SMOKER_IGNITOR;
		}

		case ELITE_CLASS_BOOMER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_BOOMER_FLASHBANG || subtype == ELITE_SUBTYPE_BOOMER_LEAKER;
		}

		case ELITE_CLASS_HUNTER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_HUNTER_TARGET_SWITCH || subtype == ELITE_SUBTYPE_HUNTER_HEROIC;
		}

		case ELITE_CLASS_JOCKEY:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_JOCKEY_JUMPER || subtype == ELITE_SUBTYPE_JOCKEY_HEROIC;
		}

		case ELITE_CLASS_SPITTER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT || subtype == ELITE_SUBTYPE_SPITTER_ACID_POOL || subtype == ELITE_SUBTYPE_SPITTER_SNEAKY;
		}

		case ELITE_CLASS_CHARGER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_CHARGER_STEERING || subtype == ELITE_SUBTYPE_CHARGER_ACTION || subtype == ELITE_SUBTYPE_CHARGER_UNSTOPPABLE;
		}

		case ELITE_CLASS_TANK:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT || subtype == ELITE_SUBTYPE_TANK_IGNITOR || subtype == ELITE_SUBTYPE_TANK_EXPLOSIVE;
		}
	}

	return false;
}

void ResetEliteTypeDescriptionCache()
{
	for (int c = 0; c < ELITE_CLASS_COUNT; c++)
	{
		for (int s = 0; s < ELITE_SUBTYPE_COUNT; s++)
		{
			g_sEliteTypeNames[c][s][0] = '\0';
			g_sEliteTypeDescs[c][s][0] = '\0';
		}
	}
}

void LoadEliteTypeDescriptionsFromData()
{
	ResetEliteTypeDescriptionCache();

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), ELITE_TYPE_DATA_FILE);

	if (!FileExists(path))
	{
		WriteDefaultEliteTypeDescriptionFile(path);
	}

	KeyValues kv = new KeyValues("elite_type_descriptions");
	if (!kv.ImportFromFile(path))
	{
		LogError("[EliteSI Core] Failed to load %s", path);
		delete kv;
		return;
	}

	for (int classIdx = 0; classIdx < ELITE_CLASS_COUNT; classIdx++)
	{
		if (!kv.JumpToKey(g_sEliteClassKeys[classIdx], false))
		{
			continue;
		}

		for (int subtype = ELITE_SUBTYPE_ABNORMAL_BEHAVIOR; subtype < ELITE_SUBTYPE_COUNT; subtype++)
		{
			if (!IsSubtypeSupportedByClassIndex(classIdx, subtype))
			{
				continue;
			}

			char defaultName[ELITE_TYPE_NAME_LEN];
			char defaultDesc[ELITE_TYPE_DESC_LEN];
			GetSubtypeLabelDefault(subtype, defaultName, sizeof(defaultName));
			GetSubtypeDescriptionDefault(subtype, defaultDesc, sizeof(defaultDesc));

			char keyName[16];
			IntToString(subtype, keyName, sizeof(keyName));
			if (!kv.JumpToKey(keyName, false))
			{
				continue;
			}

			kv.GetString("name", g_sEliteTypeNames[classIdx][subtype], ELITE_TYPE_NAME_LEN, defaultName);
			kv.GetString("description", g_sEliteTypeDescs[classIdx][subtype], ELITE_TYPE_DESC_LEN, defaultDesc);
			kv.GoBack();
		}

		kv.GoBack();
	}

	delete kv;
}

void WriteDefaultEliteTypeDescriptionFile(const char[] path)
{
	KeyValues kv = new KeyValues("elite_type_descriptions");

	for (int classIdx = 0; classIdx < ELITE_CLASS_COUNT; classIdx++)
	{
		if (!kv.JumpToKey(g_sEliteClassKeys[classIdx], true))
		{
			continue;
		}

		for (int subtype = ELITE_SUBTYPE_ABNORMAL_BEHAVIOR; subtype < ELITE_SUBTYPE_COUNT; subtype++)
		{
			if (!IsSubtypeSupportedByClassIndex(classIdx, subtype))
			{
				continue;
			}

			char keyName[16];
			char name[ELITE_TYPE_NAME_LEN];
			char desc[ELITE_TYPE_DESC_LEN];

			IntToString(subtype, keyName, sizeof(keyName));
			GetSubtypeLabelDefault(subtype, name, sizeof(name));
			GetSubtypeDescriptionDefault(subtype, desc, sizeof(desc));

			if (!kv.JumpToKey(keyName, true))
			{
				continue;
			}

			kv.SetString("name", name);
			kv.SetString("description", desc);
			kv.GoBack();
		}

		kv.GoBack();
	}

	if (!kv.ExportToFile(path))
	{
		LogError("[EliteSI Core] Failed to write default elite type data file: %s", path);
	}

	delete kv;
}

bool IsTrackableSiClass(int zClass)
{
	return (zClass >= ZC_SMOKER && zClass <= ZC_CHARGER) || zClass == ZC_TANK;
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

public any Native_EliteSI_GetTypeName(Handle plugin, int numParams)
{
	if (numParams < 3)
	{
		return false;
	}

	int client = GetNativeCell(1);
	int maxlen = GetNativeCell(3);

	if (maxlen > 0)
	{
		SetNativeString(2, "", maxlen, false);
	}

	if (!IsValidInfected(client) || !g_bIsElite[client])
	{
		return false;
	}

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	char typeName[ELITE_TYPE_NAME_LEN];
	GetEliteTypeNameByClassSubtype(zClass, g_iEliteSubtype[client], typeName, sizeof(typeName));

	if (maxlen > 0)
	{
		SetNativeString(2, typeName, maxlen, false);
	}

	return true;
}

public any Native_EliteSI_GetTypeDescription(Handle plugin, int numParams)
{
	if (numParams < 3)
	{
		return false;
	}

	int client = GetNativeCell(1);
	int maxlen = GetNativeCell(3);

	if (maxlen > 0)
	{
		SetNativeString(2, "", maxlen, false);
	}

	if (!IsValidInfected(client) || !g_bIsElite[client])
	{
		return false;
	}

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	char typeDesc[ELITE_TYPE_DESC_LEN];
	GetEliteTypeDescriptionByClassSubtype(zClass, g_iEliteSubtype[client], typeDesc, sizeof(typeDesc));

	if (maxlen > 0)
	{
		SetNativeString(2, typeDesc, maxlen, false);
	}

	return true;
}
