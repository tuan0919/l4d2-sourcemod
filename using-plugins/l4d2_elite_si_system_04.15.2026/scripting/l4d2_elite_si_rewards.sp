#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.2.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define HINT_COLOR_NORMAL_DEFAULT "255 255 255"
#define HINT_COLOR_ELITE_DEFAULT "255 255 0"

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
	ZC_CHARGER,
	ZC_WITCH,
	ZC_TANK
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvEnableSiRewards;
ConVar g_cvEnableNormalSiRewards;
ConVar g_cvEnableTankRewards;
ConVar g_cvEnableWitchRewards;
ConVar g_cvMaxTempHealth;

ConVar g_cvRewardSmoker;
ConVar g_cvRewardBoomer;
ConVar g_cvRewardHunter;
ConVar g_cvRewardSpitter;
ConVar g_cvRewardJockey;
ConVar g_cvRewardCharger;
ConVar g_cvRewardNormalSiAmount;

ConVar g_cvScaleDifficulty;
ConVar g_cvDiffEasy;
ConVar g_cvDiffNormal;
ConVar g_cvDiffHard;
ConVar g_cvDiffExpert;
ConVar g_cvHeadshotBonus;
ConVar g_cvHeadshotMultiplier;

ConVar g_cvTankRewardMode;
ConVar g_cvTankRewardAmount;
ConVar g_cvWitchRewardMode;
ConVar g_cvWitchRewardAmount;

ConVar g_cvShowHint;
ConVar g_cvHintColorNormalSi;
ConVar g_cvHintColorEliteSi;
ConVar g_cvZDifficulty;

float g_fPillsDecayRate;

char g_sHintColorNormalSi[16];
char g_sHintColorEliteSi[16];

GlobalForward g_fwRewardGranted;

char g_siIcons[9][32] =
{
	"Unknown",
	"Stat_vs_Most_Smoker_Pulls",
	"Stat_vs_Most_Vomit_Hit",
	"Stat_vs_Most_Hunter_Pounces",
	"Stat_vs_Most_Spit_Dmg",
	"Stat_vs_Most_Jockey_Rides",
	"Stat_vs_Most_Damage_As_Charger",
	"Unknown",
	"Stat_vs_Most_Damage_As_Tank"
};

char g_siNames[9][32] =
{
	"Unknown",
	"Smoker",
	"Boomer",
	"Hunter",
	"Spitter",
	"Jockey",
	"Charger",
	"Unknown",
	"Tank"
};

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Rewards",
	author = "OpenCode",
	description = "Temp HP rewards for elite SI/Tank/Witch with subtype-aware flow.",
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

	g_fwRewardGranted = new GlobalForward("EliteSIReward_OnGranted", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	RegPluginLibrary("elite_si_rewards");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_reward_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEnableSiRewards = CreateConVar("l4d2_elite_reward_si_enable", "1", "0=Off SI rewards, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEnableNormalSiRewards = CreateConVar("l4d2_elite_reward_normal_si_enable", "0", "0=Only elite SI reward, 1=Normal SI can also reward.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEnableTankRewards = CreateConVar("l4d2_elite_reward_tank_enable", "1", "0=Off tank reward, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEnableWitchRewards = CreateConVar("l4d2_elite_reward_witch_enable", "1", "0=Off witch reward, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMaxTempHealth = CreateConVar("l4d2_elite_reward_temp_hp_limit", "200", "Temp HP cap when granting reward.", FCVAR_NOTIFY, true, 1.0, true, 500.0);

	g_cvRewardSmoker = CreateConVar("l4d2_elite_reward_smoker", "3", "Reward when killing elite smoker.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvRewardBoomer = CreateConVar("l4d2_elite_reward_boomer", "2", "Reward when killing elite boomer.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvRewardHunter = CreateConVar("l4d2_elite_reward_hunter", "5", "Reward when killing elite hunter.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvRewardSpitter = CreateConVar("l4d2_elite_reward_spitter", "2", "Reward when killing elite spitter.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvRewardJockey = CreateConVar("l4d2_elite_reward_jockey", "3", "Reward when killing elite jockey.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvRewardCharger = CreateConVar("l4d2_elite_reward_charger", "5", "Reward when killing elite charger.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvRewardNormalSiAmount = CreateConVar("l4d2_elite_reward_normal_si_amount", "1", "Reward when killing normal (non-elite) SI.", FCVAR_NOTIFY, true, 0.0, true, 100.0);

	g_cvScaleDifficulty = CreateConVar("l4d2_elite_reward_scale_by_difficulty", "1", "0=Disable, 1=Scale reward by z_difficulty.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDiffEasy = CreateConVar("l4d2_elite_reward_diff_easy", "0.8", "Difficulty multiplier on easy.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvDiffNormal = CreateConVar("l4d2_elite_reward_diff_normal", "1.0", "Difficulty multiplier on normal.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvDiffHard = CreateConVar("l4d2_elite_reward_diff_hard", "1.2", "Difficulty multiplier on hard/advanced.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvDiffExpert = CreateConVar("l4d2_elite_reward_diff_expert", "1.5", "Difficulty multiplier on impossible/expert.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvHeadshotBonus = CreateConVar("l4d2_elite_reward_headshot_bonus_enable", "1", "0=Disable headshot bonus, 1=Enable.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvHeadshotMultiplier = CreateConVar("l4d2_elite_reward_headshot_bonus_multiplier", "2.0", "Headshot multiplier.", FCVAR_NOTIFY, true, 1.0, true, 10.0);

	g_cvTankRewardMode = CreateConVar("l4d2_elite_reward_tank_mode", "1", "Tank mode: 0=attacker only, 1=whole team.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTankRewardAmount = CreateConVar("l4d2_elite_reward_tank_amount", "20", "Base reward for tank death.", FCVAR_NOTIFY, true, 0.0, true, 300.0);
	g_cvWitchRewardMode = CreateConVar("l4d2_elite_reward_witch_mode", "0", "Witch mode: 0=attacker only, 1=whole team.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvWitchRewardAmount = CreateConVar("l4d2_elite_reward_witch_amount", "15", "Base reward for witch death.", FCVAR_NOTIFY, true, 0.0, true, 300.0);

	g_cvShowHint = CreateConVar("l4d2_elite_reward_show_hint", "1", "0=No hint, 1=Show instructor hint on reward.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvHintColorNormalSi = CreateConVar("l4d2_elite_reward_hint_color_normal_si", HINT_COLOR_NORMAL_DEFAULT, "Instructor hint text color for normal SI reward in format 'R G B'.", FCVAR_NOTIFY);
	g_cvHintColorEliteSi = CreateConVar("l4d2_elite_reward_hint_color_elite_si", HINT_COLOR_ELITE_DEFAULT, "Instructor hint text color for elite SI reward in format 'R G B'.", FCVAR_NOTIFY);

	CreateConVar("l4d2_elite_reward_version", PLUGIN_VERSION, "Elite reward plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_rewards");

	g_cvZDifficulty = FindConVar("z_difficulty");

	ConVar decay = FindConVar("pain_pills_decay_rate");
	g_fPillsDecayRate = (decay != null) ? decay.FloatValue : 0.27;
	if (decay != null)
	{
		decay.AddChangeHook(OnDecayChanged);
	}

	RefreshHintColorCache();
	g_cvHintColorNormalSi.AddChangeHook(OnHintColorChanged);
	g_cvHintColorEliteSi.AddChangeHook(OnHintColorChanged);

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);
}

public void OnDecayChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_fPillsDecayRate = convar.FloatValue;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetClientTeam(victim) != TEAM_INFECTED)
	{
		return;
	}

	int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	bool headshot = event.GetBool("headshot");

	if (zClass == ZC_TANK)
	{
		HandleTankReward(attacker, headshot);
		return;
	}

	if (!g_cvEnableSiRewards.BoolValue)
	{
		return;
	}

	if (!IsTrackableSiClass(zClass))
	{
		return;
	}

	bool isEliteKill = IsEliteKill(victim);
	if (!isEliteKill && !g_cvEnableNormalSiRewards.BoolValue)
	{
		return;
	}

	if (!IsValidAliveSurvivor(attacker))
	{
		return;
	}

	int baseReward = isEliteKill ? GetSiClassReward(zClass) : g_cvRewardNormalSiAmount.IntValue;
	int reward = ApplyRewardModifiers(baseReward, headshot);
	if (reward <= 0)
	{
		return;
	}

	int added = GiveTempHealth(attacker, reward);
	if (g_cvShowHint.BoolValue)
	{
		char text[160];
		if (isEliteKill)
		{
			int subtype = GetSafeEliteSubtype(victim);
			char subtypeText[24];
			GetSubtypeLabel(subtype, subtypeText, sizeof(subtypeText));
			Format(text, sizeof(text), "%s Elite %s [%s] +%d Temp HP", headshot ? "Headshot" : "Killed", g_siNames[zClass], subtypeText, added);
			DisplayInstructorHint(attacker, text, g_siIcons[zClass], g_sHintColorEliteSi);
		}
		else
		{
			Format(text, sizeof(text), "%s Normal %s +%d Temp HP", headshot ? "Headshot" : "Killed", g_siNames[zClass], added);
			DisplayInstructorHint(attacker, text, g_siIcons[zClass], g_sHintColorNormalSi);
		}
	}

	NotifyRewardGranted(attacker, added, zClass, 0);
}

public void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue || !g_cvEnableWitchRewards.BoolValue)
	{
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidAliveSurvivor(attacker))
	{
		return;
	}

	int reward = ApplyRewardModifiers(g_cvWitchRewardAmount.IntValue, event.GetBool("headshot"));
	if (reward <= 0)
	{
		return;
	}

	if (g_cvWitchRewardMode.IntValue == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsValidAliveSurvivor(i) || IsPlayerIncapped(i))
			{
				continue;
			}

			int added = GiveTempHealth(i, reward);
			if (g_cvShowHint.BoolValue)
			{
				char text[128];
				Format(text, sizeof(text), "Witch slain, team +%d Temp HP", added);
				DisplayInstructorHint(i, text, "icon_skull", HINT_COLOR_NORMAL_DEFAULT);
			}

			NotifyRewardGranted(i, added, ZC_WITCH, 1);
		}
	}
	else
	{
		int added = GiveTempHealth(attacker, reward);
		if (g_cvShowHint.BoolValue)
		{
			char text[128];
			Format(text, sizeof(text), "Witch slain, +%d Temp HP", added);
			DisplayInstructorHint(attacker, text, "icon_skull", HINT_COLOR_NORMAL_DEFAULT);
		}

		NotifyRewardGranted(attacker, added, ZC_WITCH, 0);
	}
}

void HandleTankReward(int attacker, bool headshot)
{
	if (!g_cvEnableTankRewards.BoolValue)
	{
		return;
	}

	int reward = ApplyRewardModifiers(g_cvTankRewardAmount.IntValue, headshot);
	if (reward <= 0)
	{
		return;
	}

	if (g_cvTankRewardMode.IntValue == 1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsValidAliveSurvivor(i) || IsPlayerIncapped(i))
			{
				continue;
			}

			int added = GiveTempHealth(i, reward);
			if (g_cvShowHint.BoolValue)
			{
				char text[128];
				Format(text, sizeof(text), "Tank slain, team +%d Temp HP", added);
				DisplayInstructorHint(i, text, g_siIcons[ZC_TANK], HINT_COLOR_NORMAL_DEFAULT);
			}

			NotifyRewardGranted(i, added, ZC_TANK, 1);
		}
	}
	else if (IsValidAliveSurvivor(attacker))
	{
		int added = GiveTempHealth(attacker, reward);
		if (g_cvShowHint.BoolValue)
		{
			char text[128];
			Format(text, sizeof(text), "Tank slain, +%d Temp HP", added);
			DisplayInstructorHint(attacker, text, g_siIcons[ZC_TANK], HINT_COLOR_NORMAL_DEFAULT);
		}

		NotifyRewardGranted(attacker, added, ZC_TANK, 0);
	}
}

bool IsEliteKill(int victim)
{
	if (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") != FeatureStatus_Available)
	{
		return false;
	}

	return EliteSI_IsElite(victim);
}

int GetSafeEliteSubtype(int client)
{
	if (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") != FeatureStatus_Available)
	{
		return ELITE_SUBTYPE_NONE;
	}

	return EliteSI_GetSubtype(client);
}

int GetSiClassReward(int zClass)
{
	switch (zClass)
	{
		case ZC_SMOKER: return g_cvRewardSmoker.IntValue;
		case ZC_BOOMER: return g_cvRewardBoomer.IntValue;
		case ZC_HUNTER: return g_cvRewardHunter.IntValue;
		case ZC_SPITTER: return g_cvRewardSpitter.IntValue;
		case ZC_JOCKEY: return g_cvRewardJockey.IntValue;
		case ZC_CHARGER: return g_cvRewardCharger.IntValue;
	}

	return 0;
}

bool IsTrackableSiClass(int zClass)
{
	return zClass >= ZC_SMOKER && zClass <= ZC_CHARGER;
}

int ApplyRewardModifiers(int baseReward, bool headshot)
{
	if (baseReward <= 0)
	{
		return 0;
	}

	float output = float(baseReward) * GetDifficultyMultiplier();
	if (g_cvHeadshotBonus.BoolValue && headshot)
	{
		output *= g_cvHeadshotMultiplier.FloatValue;
	}

	int finalReward = RoundToFloor(output);
	return finalReward < 0 ? 0 : finalReward;
}

float GetDifficultyMultiplier()
{
	if (!g_cvScaleDifficulty.BoolValue || g_cvZDifficulty == null)
	{
		return 1.0;
	}

	char difficulty[16];
	g_cvZDifficulty.GetString(difficulty, sizeof(difficulty));

	if (StrEqual(difficulty, "easy", false))
	{
		return g_cvDiffEasy.FloatValue;
	}

	if (StrEqual(difficulty, "normal", false))
	{
		return g_cvDiffNormal.FloatValue;
	}

	if (StrEqual(difficulty, "hard", false))
	{
		return g_cvDiffHard.FloatValue;
	}

	if (StrEqual(difficulty, "impossible", false) || StrEqual(difficulty, "expert", false))
	{
		return g_cvDiffExpert.FloatValue;
	}

	return 1.0;
}

int GiveTempHealth(int client, int amount)
{
	int realHp = GetClientHealth(client);
	float tempHp = GetTempHealth(client);

	if (IsPlayerIncapped(client))
	{
		amount *= 10;
		SetTempHealth(client, tempHp + float(amount));
		return amount;
	}

	int maxCap = g_cvMaxTempHealth.IntValue;
	if (realHp + tempHp + float(amount) >= float(maxCap))
	{
		int extra = maxCap - realHp - RoundToFloor(tempHp);
		if (extra < 0)
		{
			extra = 0;
		}

		SetTempHealth(client, tempHp + float(extra));
		return extra;
	}

	SetTempHealth(client, tempHp + float(amount));
	return amount;
}

float GetTempHealth(int client)
{
	float value = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	value -= (GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * g_fPillsDecayRate;
	return value < 0.0 ? 0.0 : value;
}

void SetTempHealth(int client, float value)
{
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", value < 0.0 ? 0.0 : value);
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}

bool IsPlayerIncapped(int client)
{
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}

bool IsValidAliveSurvivor(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SURVIVOR);
}

void GetSubtypeLabel(int subtype, char[] buffer, int maxlen)
{
	switch (subtype)
	{
		case ELITE_SUBTYPE_HARDSI: strcopy(buffer, maxlen, "Abnormal behavior");
		case ELITE_SUBTYPE_ABILITY_MOVEMENT: strcopy(buffer, maxlen, "Strange Movement");
		case ELITE_SUBTYPE_CHARGER_STEERING: strcopy(buffer, maxlen, "ChargerSteer");
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

void NotifyRewardGranted(int receiver, int amount, int sourceClass, int mode)
{
	if (g_fwRewardGranted == null)
	{
		return;
	}

	Call_StartForward(g_fwRewardGranted);
	Call_PushCell(receiver);
	Call_PushCell(amount);
	Call_PushCell(sourceClass);
	Call_PushCell(mode);
	Call_Finish();
}

public void OnHintColorChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RefreshHintColorCache();
}

void RefreshHintColorCache()
{
	g_cvHintColorNormalSi.GetString(g_sHintColorNormalSi, sizeof(g_sHintColorNormalSi));
	g_cvHintColorEliteSi.GetString(g_sHintColorEliteSi, sizeof(g_sHintColorEliteSi));

	if (g_sHintColorNormalSi[0] == '\0')
	{
		strcopy(g_sHintColorNormalSi, sizeof(g_sHintColorNormalSi), HINT_COLOR_NORMAL_DEFAULT);
	}

	if (g_sHintColorEliteSi[0] == '\0')
	{
		strcopy(g_sHintColorEliteSi, sizeof(g_sHintColorEliteSi), HINT_COLOR_ELITE_DEFAULT);
	}
}

void DisplayInstructorHint(int target, const char[] text, const char[] icon, const char[] color)
{
	int entity = CreateEntityByName("env_instructor_hint");
	if (entity <= 0)
	{
		return;
	}

	char key[32];
	FormatEx(key, sizeof(key), "hintEliteReward%d", target);
	DispatchKeyValue(target, "targetname", key);
	DispatchKeyValue(entity, "hint_target", key);
	DispatchKeyValue(entity, "hint_static", "false");
	DispatchKeyValue(entity, "hint_timeout", "5.0");
	DispatchKeyValue(entity, "hint_icon_offset", "0.1");
	DispatchKeyValue(entity, "hint_range", "0.1");
	DispatchKeyValue(entity, "hint_nooffscreen", "true");
	DispatchKeyValue(entity, "hint_icon_onscreen", icon);
	DispatchKeyValue(entity, "hint_icon_offscreen", icon);
	DispatchKeyValue(entity, "hint_forcecaption", "true");
	DispatchKeyValue(entity, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(entity, "hint_instance_type", "0");
	DispatchKeyValue(entity, "hint_color", color);

	char hintText[192];
	strcopy(hintText, sizeof(hintText), text);
	ReplaceString(hintText, sizeof(hintText), "\n", " ");
	DispatchKeyValue(entity, "hint_caption", hintText);

	DispatchSpawn(entity);
	AcceptEntityInput(entity, "ShowHint", target);

	CreateTimer(5.0, Timer_KillEntity, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillEntity(Handle timer, int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		char classname[32];
		GetEdictClassname(entity, classname, sizeof(classname));
		if (!StrEqual(classname, "player"))
		{
			AcceptEntityInput(entity, "Kill");
		}
	}

	return Plugin_Stop;
}
