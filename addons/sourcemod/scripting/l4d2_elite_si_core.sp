#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>

#define PLUGIN_VERSION "1.1.0"

#define TEAM_INFECTED 3

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_HARDSI,
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
	ELITE_SUBTYPE_SMOKER_VOID_POCKET
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
ConVar g_cvEliteSpawnCooldown;
ConVar g_cvEliteHpMultiplier;
ConVar g_cvEliteFireChance;
ConVar g_cvSpitterAbilityChance;
ConVar g_cvChargerSteeringChance;
ConVar g_cvChargerActionChance;
ConVar g_cvSpawnAnnounce;
ConVar g_cvAutoLoadSmokerNoxious;
ConVar g_cvSmokerForceSubtype;

bool g_bIsElite[MAXPLAYERS + 1];
bool g_bIsFireImmune[MAXPLAYERS + 1];
int g_iEliteSubtype[MAXPLAYERS + 1];
float g_fNextEliteSpawnTime;
bool g_bHasSmokerNoxiousModule;
bool g_bAutoLoadQueued;
int g_iAutoLoadAttempt;

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
	g_cvEliteSpawnCooldown = CreateConVar("l4d2_elite_si_core_spawn_cooldown", "20.0", "Cooldown in seconds between successful elite SI spawns (0=Off).", FCVAR_NOTIFY, true, 0.0, true, 300.0);
	g_cvEliteHpMultiplier = CreateConVar("l4d2_elite_si_core_hp_multiplier", "2.5", "Elite HP multiplier.", FCVAR_NOTIFY, true, 0.1, true, 20.0);
	g_cvEliteFireChance = CreateConVar("l4d2_elite_si_core_fire_ignite_chance", "20", "Chance (0-100) for elite SI to ignite itself and gain fire immunity.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvSpitterAbilityChance = CreateConVar("l4d2_elite_si_core_spitter_ability_subtype_chance", "50", "Spitter elite chance to roll Strange Movement subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvChargerSteeringChance = CreateConVar("l4d2_elite_si_core_charger_steering_subtype_chance", "100", "Charger elite chance to roll ChargerSteering subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvChargerActionChance = CreateConVar("l4d2_elite_si_core_charger_action_subtype_chance", "0", "Charger elite chance to roll ChargerAction subtype (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvSpawnAnnounce = CreateConVar("l4d2_elite_si_core_spawn_announce", "1", "0=Off, 1=Announce elite SI spawn to chat with {red} color.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAutoLoadSmokerNoxious = CreateConVar("l4d2_elite_si_core_auto_load_smoker_noxious", "1", "0=Off, 1=Auto-load l4d2_elite_si_smoker_noxious.smx if missing.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmokerForceSubtype = CreateConVar("l4d2_elite_si_core_smoker_force_subtype", "0", "0=random smoker noxious subtype, 5-15=force exact smoker subtype for test.", FCVAR_NOTIFY, true, 0.0, true, 15.0);

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

	RefreshSmokerNoxiousModuleState();
	TryAutoLoadSmokerNoxious();
	g_fNextEliteSpawnTime = 0.0;
}

public void OnAllPluginsLoaded()
{
	RefreshSmokerNoxiousModuleState();
	TryAutoLoadSmokerNoxious();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_smoker_noxious"))
	{
		RefreshSmokerNoxiousModuleState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_smoker_noxious"))
	{
		RefreshSmokerNoxiousModuleState();
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

	if (GetRandomInt(1, 100) <= g_cvEliteFireChance.IntValue)
	{
		g_bIsFireImmune[client] = true;
		IgniteEntity(client, 9999.0);
	}

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

	int colorIndex = zClass - 1;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);

	if (zClass == ZC_SMOKER && IsSmokerNoxiousSubtype(subtype))
	{
		int noxiousIndex = subtype - ELITE_SUBTYPE_SMOKER_ASPHYXIATION;
		SetEntityRenderColor(client, ELITE_SMOKER_NOXIOUS_COLORS[noxiousIndex][0], ELITE_SMOKER_NOXIOUS_COLORS[noxiousIndex][1], ELITE_SMOKER_NOXIOUS_COLORS[noxiousIndex][2], 255);
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

	SetEntityRenderColor(client, ELITE_HARDSI_COLORS[colorIndex][0], ELITE_HARDSI_COLORS[colorIndex][1], ELITE_HARDSI_COLORS[colorIndex][2], 255);
}

int RollSubtypeByClass(int zClass)
{
	switch (zClass)
	{
		case ZC_SMOKER:
		{
			return RollSmokerNoxiousSubtype();
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

int RollSmokerNoxiousSubtype()
{
	int forcedSubtype = g_cvSmokerForceSubtype.IntValue;
	if (forcedSubtype >= ELITE_SUBTYPE_SMOKER_ASPHYXIATION && forcedSubtype <= ELITE_SUBTYPE_SMOKER_VOID_POCKET)
	{
		return forcedSubtype;
	}

	return ELITE_SUBTYPE_SMOKER_ASPHYXIATION + GetRandomInt(0, 10);
}

bool IsSmokerNoxiousSubtype(int subtype)
{
	return subtype >= ELITE_SUBTYPE_SMOKER_ASPHYXIATION && subtype <= ELITE_SUBTYPE_SMOKER_VOID_POCKET;
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
	GetSubtypeLabel(subtype, typeLabel, sizeof(typeLabel));
	GetSubtypeDescription(subtype, typeDesc, sizeof(typeDesc));

	CPrintToChatAll("{red}Elite %s has spawned - %s (%s).", classLabel, typeLabel, typeDesc);
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
		default: strcopy(buffer, maxlen, "SI");
	}
}

void GetSubtypeLabel(int subtype, char[] buffer, int maxlen)
{
	switch (subtype)
	{
		case ELITE_SUBTYPE_HARDSI: strcopy(buffer, maxlen, "Abnormal behavior");
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
		default: strcopy(buffer, maxlen, "Unknown");
	}
}

void GetSubtypeDescription(int subtype, char[] buffer, int maxlen)
{
	switch (subtype)
	{
		case ELITE_SUBTYPE_HARDSI: strcopy(buffer, maxlen, "aggressive AI pressure with advanced attack patterns");
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
		default: strcopy(buffer, maxlen, "unknown elite trait");
	}
}

bool IsTrackableSiClass(int zClass)
{
	return zClass >= ZC_SMOKER && zClass <= ZC_CHARGER;
}

bool IsValidInfected(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == TEAM_INFECTED);
}

void RefreshSmokerNoxiousModuleState()
{
	g_bHasSmokerNoxiousModule = LibraryExists("elite_si_smoker_noxious");
}

void TryAutoLoadSmokerNoxious()
{
	if (!g_cvAutoLoadSmokerNoxious.BoolValue || g_bHasSmokerNoxiousModule || g_bAutoLoadQueued)
	{
		return;
	}

	g_iAutoLoadAttempt++;
	g_bAutoLoadQueued = true;
	ServerCommand("sm plugins load qol/l4d2_elite_si_smoker_noxious.smx");
	CreateTimer(1.0, Timer_VerifyAutoLoad, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_VerifyAutoLoad(Handle timer)
{
	g_bAutoLoadQueued = false;
	RefreshSmokerNoxiousModuleState();

	if (!g_bHasSmokerNoxiousModule)
	{
		if (g_iAutoLoadAttempt <= 2)
		{
			PrintToServer("[EliteSI Core] Smoker Noxious module missing, trying auto-load attempt %d.", g_iAutoLoadAttempt + 1);
			TryAutoLoadSmokerNoxious();
		}

		LogError("[EliteSI Core] Unable to auto-load qol/l4d2_elite_si_smoker_noxious.smx (attempt %d). Verify plugin exists in addons/sourcemod/plugins/qol/ and left4dhooks is loaded.", g_iAutoLoadAttempt);
		PrintToServer("[EliteSI Core] Auto-load failed. Check errors log for details.");
	}
	else
	{
		PrintToServer("[EliteSI Core] Smoker Noxious module loaded successfully.");
	}

	return Plugin_Stop;
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
