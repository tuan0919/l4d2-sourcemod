#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define PLUGIN_VERSION "1.4.0"

#define TEAM_INFECTED 3

#define ELITE_TYPE_DATA_FILE "data/elite_si_type_descriptions.cfg"
#define ELITE_CLASS_COUNT 7
#define ELITE_SUBTYPE_COUNT 28
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
	ELITE_SUBTYPE_BOOMER_FLASHBANG
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

static const int ELITE_SMOKER_NOXIOUS_COLORS[11][3] =
{
	{255, 20, 20},
	{255, 70, 40},
	{255, 120, 20},
	{220, 255, 40},
	{255, 95, 0},
	{120, 180, 255},
	{255, 55, 95},
	{150, 150, 150},
	{255, 180, 0},
	{230, 110, 255},
	{100, 255, 255}
};

static const int ELITE_BOOMER_NAUSEATING_COLORS[10][3] =
{
	{120, 255, 70},
	{255, 170, 50},
	{90, 220, 255},
	{255, 255, 120},
	{255, 95, 150},
	{255, 130, 60},
	{255, 80, 80},
	{200, 255, 120},
	{255, 210, 90},
	{165, 225, 110}
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
	g_cvSpawnAnnounce = CreateConVar("l4d2_elite_si_core_spawn_announce", "1", "0=Off, 1=Announce elite SI spawn to chat with {red} color.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmokerForceSubtype = CreateConVar("l4d2_elite_si_core_smoker_force_subtype", "0", "0=random smoker subtype, 2 or 5-15=force exact smoker subtype for test.", FCVAR_NOTIFY, true, 0.0, true, 15.0);
	g_cvBoomerForceSubtype = CreateConVar("l4d2_elite_si_core_boomer_force_subtype", "0", "0=random boomer subtype, 1, 16-25 or 27=force exact boomer subtype for test.", FCVAR_NOTIFY, true, 0.0, true, 27.0);

	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_ABILITY_MOVEMENT, "l4d2_elite_si_core_smoker_movement_subtype_chance", "1", "Relative weight for Smoker elite to roll Strange Movement.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_ASPHYXIATION, "l4d2_elite_si_core_smoker_asphyxiation_subtype_chance", "1", "Relative weight for Smoker elite to roll Asphyxiation.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_COLLAPSED_LUNG, "l4d2_elite_si_core_smoker_collapsed_lung_subtype_chance", "1", "Relative weight for Smoker elite to roll Collapsed Lung.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_METHANE_BLAST, "l4d2_elite_si_core_smoker_methane_blast_subtype_chance", "1", "Relative weight for Smoker elite to roll Methane Blast.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_METHANE_LEAK, "l4d2_elite_si_core_smoker_methane_leak_subtype_chance", "1", "Relative weight for Smoker elite to roll Methane Leak.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_METHANE_STRIKE, "l4d2_elite_si_core_smoker_methane_strike_subtype_chance", "1", "Relative weight for Smoker elite to roll Methane Strike.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_MOON_WALK, "l4d2_elite_si_core_smoker_moon_walk_subtype_chance", "1", "Relative weight for Smoker elite to roll Moon Walk.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_RESTRAINED_HOSTAGE, "l4d2_elite_si_core_smoker_restrained_hostage_subtype_chance", "1", "Relative weight for Smoker elite to roll Restrained Hostage.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_SMOKE_SCREEN, "l4d2_elite_si_core_smoker_smoke_screen_subtype_chance", "1", "Relative weight for Smoker elite to roll Smoke Screen.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_TONGUE_STRIP, "l4d2_elite_si_core_smoker_tongue_strip_subtype_chance", "1", "Relative weight for Smoker elite to roll Tongue Strip.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_TONGUE_WHIP, "l4d2_elite_si_core_smoker_tongue_whip_subtype_chance", "1", "Relative weight for Smoker elite to roll Tongue Whip.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SMOKER, ELITE_SUBTYPE_SMOKER_VOID_POCKET, "l4d2_elite_si_core_smoker_void_pocket_subtype_chance", "1", "Relative weight for Smoker elite to roll Void Pocket.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_boomer_abnormal_subtype_chance", "1", "Relative weight for Boomer elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_BELLY, "l4d2_elite_si_core_boomer_bile_belly_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Belly.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_BLAST, "l4d2_elite_si_core_boomer_bile_blast_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Blast.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_FEET, "l4d2_elite_si_core_boomer_bile_feet_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Feet.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_MASK, "l4d2_elite_si_core_boomer_bile_mask_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Mask.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_PIMPLE, "l4d2_elite_si_core_boomer_bile_pimple_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Pimple.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_SHOWER, "l4d2_elite_si_core_boomer_bile_shower_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Shower.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_SWIPE, "l4d2_elite_si_core_boomer_bile_swipe_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Swipe.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_BILE_THROW, "l4d2_elite_si_core_boomer_bile_throw_subtype_chance", "1", "Relative weight for Boomer elite to roll Bile Throw.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_EXPLOSIVE_DIARRHEA, "l4d2_elite_si_core_boomer_explosive_diarrhea_subtype_chance", "1", "Relative weight for Boomer elite to roll Explosive Diarrhea.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_FLATULENCE, "l4d2_elite_si_core_boomer_flatulence_subtype_chance", "1", "Relative weight for Boomer elite to roll Flatulence.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_BOOMER, ELITE_SUBTYPE_BOOMER_FLASHBANG, "l4d2_elite_si_core_boomer_flashbang_subtype_chance", "1", "Relative weight for Boomer elite to roll Flashbang.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_HUNTER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_hunter_abnormal_subtype_chance", "1", "Relative weight for Hunter elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_HUNTER, ELITE_SUBTYPE_HUNTER_TARGET_SWITCH, "l4d2_elite_si_core_hunter_target_switch_subtype_chance", "1", "Relative weight for Hunter elite to roll Target Switch.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_SPITTER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_spitter_abnormal_subtype_chance", "1", "Relative weight for Spitter elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_SPITTER, ELITE_SUBTYPE_ABILITY_MOVEMENT, "l4d2_elite_si_core_spitter_ability_subtype_chance", "1", "Relative weight for Spitter elite to roll Strange Movement.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_JOCKEY, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_jockey_abnormal_subtype_chance", "1", "Relative weight for Jockey elite to roll Abnormal behavior.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_charger_abnormal_subtype_chance", "1", "Relative weight for Charger elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_CHARGER_STEERING, "l4d2_elite_si_core_charger_steering_subtype_chance", "1", "Relative weight for Charger elite to roll ChargerSteering.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_CHARGER, ELITE_SUBTYPE_CHARGER_ACTION, "l4d2_elite_si_core_charger_action_subtype_chance", "1", "Relative weight for Charger elite to roll ChargerAction.");

	RegisterSubtypeChanceConVar(ELITE_CLASS_TANK, ELITE_SUBTYPE_ABNORMAL_BEHAVIOR, "l4d2_elite_si_core_tank_abnormal_subtype_chance", "1", "Relative weight for Tank elite to roll Abnormal behavior.");
	RegisterSubtypeChanceConVar(ELITE_CLASS_TANK, ELITE_SUBTYPE_ABILITY_MOVEMENT, "l4d2_elite_si_core_tank_movement_subtype_chance", "1", "Relative weight for Tank elite to roll Strange Movement.");

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
	g_bIsFireImmune[client] = false;

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

	int colorIndex = GetSiClassIndex(zClass);
	if (colorIndex < 0)
	{
		return;
	}
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);

	if (zClass == ZC_SMOKER && IsSmokerNoxiousSubtype(subtype))
	{
		int noxiousIndex = subtype - ELITE_SUBTYPE_SMOKER_ASPHYXIATION;
		SetEntityRenderColor(client, ELITE_SMOKER_NOXIOUS_COLORS[noxiousIndex][0], ELITE_SMOKER_NOXIOUS_COLORS[noxiousIndex][1], ELITE_SMOKER_NOXIOUS_COLORS[noxiousIndex][2], 255);
		return;
	}

	if (zClass == ZC_BOOMER && IsBoomerNauseatingSubtype(subtype))
	{
		int boomerIndex = subtype - ELITE_SUBTYPE_BOOMER_BILE_BELLY;
		SetEntityRenderColor(client, ELITE_BOOMER_NAUSEATING_COLORS[boomerIndex][0], ELITE_BOOMER_NAUSEATING_COLORS[boomerIndex][1], ELITE_BOOMER_NAUSEATING_COLORS[boomerIndex][2], 255);
		return;
	}

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
			if (forcedSubtype == ELITE_SUBTYPE_ABILITY_MOVEMENT || (forcedSubtype >= ELITE_SUBTYPE_SMOKER_ASPHYXIATION && forcedSubtype <= ELITE_SUBTYPE_SMOKER_VOID_POCKET))
			{
				return forcedSubtype;
			}
		}

		case ZC_BOOMER:
		{
			int forcedSubtype = g_cvBoomerForceSubtype.IntValue;
			if (forcedSubtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || forcedSubtype == ELITE_SUBTYPE_BOOMER_FLASHBANG || (forcedSubtype >= ELITE_SUBTYPE_BOOMER_BILE_BELLY && forcedSubtype <= ELITE_SUBTYPE_BOOMER_FLATULENCE))
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

bool IsSmokerNoxiousSubtype(int subtype)
{
	return subtype >= ELITE_SUBTYPE_SMOKER_ASPHYXIATION && subtype <= ELITE_SUBTYPE_SMOKER_VOID_POCKET;
}

bool IsBoomerNauseatingSubtype(int subtype)
{
	return subtype >= ELITE_SUBTYPE_BOOMER_BILE_BELLY && subtype <= ELITE_SUBTYPE_BOOMER_FLATULENCE;
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
		case ELITE_SUBTYPE_SMOKER_ASPHYXIATION: strcopy(buffer, maxlen, "Asphyxiation");
		case ELITE_SUBTYPE_SMOKER_COLLAPSED_LUNG: strcopy(buffer, maxlen, "Collapsed Lung");
		case ELITE_SUBTYPE_SMOKER_METHANE_BLAST: strcopy(buffer, maxlen, "Methane Blast");
		case ELITE_SUBTYPE_SMOKER_METHANE_LEAK: strcopy(buffer, maxlen, "Methane Leak");
		case ELITE_SUBTYPE_SMOKER_METHANE_STRIKE: strcopy(buffer, maxlen, "Methane Strike");
		case ELITE_SUBTYPE_SMOKER_MOON_WALK: strcopy(buffer, maxlen, "Moon Walk");
		case ELITE_SUBTYPE_SMOKER_RESTRAINED_HOSTAGE: strcopy(buffer, maxlen, "Restrained Hostage");
		case ELITE_SUBTYPE_SMOKER_SMOKE_SCREEN: strcopy(buffer, maxlen, "Smoke Screen");
		case ELITE_SUBTYPE_SMOKER_TONGUE_STRIP: strcopy(buffer, maxlen, "Tongue Strip");
		case ELITE_SUBTYPE_SMOKER_TONGUE_WHIP: strcopy(buffer, maxlen, "Tongue Whip");
		case ELITE_SUBTYPE_SMOKER_VOID_POCKET: strcopy(buffer, maxlen, "Void Pocket");
		case ELITE_SUBTYPE_BOOMER_BILE_BELLY: strcopy(buffer, maxlen, "Bile Belly");
		case ELITE_SUBTYPE_BOOMER_BILE_BLAST: strcopy(buffer, maxlen, "Bile Blast");
		case ELITE_SUBTYPE_BOOMER_BILE_FEET: strcopy(buffer, maxlen, "Bile Feet");
		case ELITE_SUBTYPE_BOOMER_BILE_MASK: strcopy(buffer, maxlen, "Bile Mask");
		case ELITE_SUBTYPE_BOOMER_BILE_PIMPLE: strcopy(buffer, maxlen, "Bile Pimple");
		case ELITE_SUBTYPE_BOOMER_BILE_SHOWER: strcopy(buffer, maxlen, "Bile Shower");
		case ELITE_SUBTYPE_BOOMER_BILE_SWIPE: strcopy(buffer, maxlen, "Bile Swipe");
		case ELITE_SUBTYPE_BOOMER_BILE_THROW: strcopy(buffer, maxlen, "Bile Throw");
		case ELITE_SUBTYPE_BOOMER_EXPLOSIVE_DIARRHEA: strcopy(buffer, maxlen, "Explosive Diarrhea");
		case ELITE_SUBTYPE_BOOMER_FLATULENCE: strcopy(buffer, maxlen, "Flatulence");
		case ELITE_SUBTYPE_HUNTER_TARGET_SWITCH: strcopy(buffer, maxlen, "Target Switch");
		case ELITE_SUBTYPE_BOOMER_FLASHBANG: strcopy(buffer, maxlen, "Flashbang");
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
		case ELITE_SUBTYPE_SMOKER_ASPHYXIATION: strcopy(buffer, maxlen, "causes nearby Survivors to struggle to breathe");
		case ELITE_SUBTYPE_SMOKER_COLLAPSED_LUNG: strcopy(buffer, maxlen, "tongue trauma inflicts lingering internal damage");
		case ELITE_SUBTYPE_SMOKER_METHANE_BLAST: strcopy(buffer, maxlen, "explodes on death and blasts nearby Survivors");
		case ELITE_SUBTYPE_SMOKER_METHANE_LEAK: strcopy(buffer, maxlen, "periodically releases a damaging methane cloud");
		case ELITE_SUBTYPE_SMOKER_METHANE_STRIKE: strcopy(buffer, maxlen, "shoving it can trigger an instant stagger gas strike");
		case ELITE_SUBTYPE_SMOKER_MOON_WALK: strcopy(buffer, maxlen, "can backpedal while maintaining tongue pressure");
		case ELITE_SUBTYPE_SMOKER_RESTRAINED_HOSTAGE: strcopy(buffer, maxlen, "uses its victim as a shield and redirects pain");
		case ELITE_SUBTYPE_SMOKER_SMOKE_SCREEN: strcopy(buffer, maxlen, "smoke veil can make incoming attacks miss");
		case ELITE_SUBTYPE_SMOKER_TONGUE_STRIP: strcopy(buffer, maxlen, "tongue grab can strip away the victim's item");
		case ELITE_SUBTYPE_SMOKER_TONGUE_WHIP: strcopy(buffer, maxlen, "tongue snap lashes and flings nearby Survivors");
		case ELITE_SUBTYPE_SMOKER_VOID_POCKET: strcopy(buffer, maxlen, "pulls nearby Survivors violently toward itself");
		case ELITE_SUBTYPE_BOOMER_BILE_BELLY: strcopy(buffer, maxlen, "takes reduced incoming damage due to bloated bile armor");
		case ELITE_SUBTYPE_BOOMER_BILE_BLAST: strcopy(buffer, maxlen, "dies with a methane shockwave that damages and flings survivors");
		case ELITE_SUBTYPE_BOOMER_BILE_FEET: strcopy(buffer, maxlen, "moves faster with slick bile-coated mobility");
		case ELITE_SUBTYPE_BOOMER_BILE_MASK: strcopy(buffer, maxlen, "vomit can heavily mask survivor HUD vision");
		case ELITE_SUBTYPE_BOOMER_BILE_PIMPLE: strcopy(buffer, maxlen, "periodic bile pimple bursts damage nearby survivors");
		case ELITE_SUBTYPE_BOOMER_BILE_SHOWER: strcopy(buffer, maxlen, "successful vomit calls an extra common infected mob");
		case ELITE_SUBTYPE_BOOMER_BILE_SWIPE: strcopy(buffer, maxlen, "claw hits can inflict lingering bile wound damage");
		case ELITE_SUBTYPE_BOOMER_BILE_THROW: strcopy(buffer, maxlen, "can lob bile globs at visible survivors");
		case ELITE_SUBTYPE_BOOMER_EXPLOSIVE_DIARRHEA: strcopy(buffer, maxlen, "vomiting also sprays bile to survivors behind it");
		case ELITE_SUBTYPE_BOOMER_FLATULENCE: strcopy(buffer, maxlen, "periodically releases damaging bile gas clouds");
		case ELITE_SUBTYPE_HUNTER_TARGET_SWITCH: strcopy(buffer, maxlen, "abandons incapacitated prey and pounces a new target");
		case ELITE_SUBTYPE_BOOMER_FLASHBANG: strcopy(buffer, maxlen, "detonates with a blinding flash when killed");
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
			return subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT || IsSmokerNoxiousSubtype(subtype);
		}

		case ELITE_CLASS_BOOMER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_BOOMER_FLASHBANG || IsBoomerNauseatingSubtype(subtype);
		}

		case ELITE_CLASS_HUNTER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_HUNTER_TARGET_SWITCH;
		}

		case ELITE_CLASS_JOCKEY:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR;
		}

		case ELITE_CLASS_SPITTER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT;
		}

		case ELITE_CLASS_CHARGER:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_CHARGER_STEERING || subtype == ELITE_SUBTYPE_CHARGER_ACTION;
		}

		case ELITE_CLASS_TANK:
		{
			return subtype == ELITE_SUBTYPE_ABNORMAL_BEHAVIOR || subtype == ELITE_SUBTYPE_ABILITY_MOVEMENT;
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
