#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.1.0"

bool g_bIsElite[MAXPLAYERS + 1];
bool g_bEliteFireImmune[MAXPLAYERS + 1];

ConVar hHRSmoker;
ConVar hHRBoomer;
ConVar hHRHunter;
ConVar hHRSpitter;
ConVar hHRJockey;
ConVar hHRCharger;
ConVar hHRMax;
ConVar hHRTank;
ConVar hHRWitch;
ConVar hHRSI;

ConVar g_cvEliteChance;
ConVar g_cvEliteHpMult;
ConVar g_cvEliteFireChance;
ConVar g_cvScaleDifficulty;
ConVar g_cvDiffEasy;
ConVar g_cvDiffNormal;
ConVar g_cvDiffHard;
ConVar g_cvDiffExpert;
ConVar g_cvHeadshotBonusEnable;
ConVar g_cvHeadshotBonusMult;
ConVar g_cvTankRewardMode;
ConVar g_cvTankRewardAmount;
ConVar g_cvWitchRewardMode;
ConVar g_cvWitchRewardAmount;
ConVar g_cvZDifficulty;

int iRewardSmoker;
int iRewardBoomer;
int iRewardHunter;
int iRewardSpitter;
int iRewardJockey;
int iRewardCharger;
int iMax;
bool bTank;
bool bWitch;
bool bSI;
bool g_bScaleDifficulty;
float g_fDiffEasy;
float g_fDiffNormal;
float g_fDiffHard;
float g_fDiffExpert;
bool g_bHeadshotBonus;
float g_fHeadshotBonusMult;
int g_iTankRewardMode;
int g_iTankRewardAmount;
int g_iWitchRewardMode;
int g_iWitchRewardAmount;

float g_fDecayDecay;

static const int ELITE_COLORS[6][3] =
{
    { 180,   0, 255 },   // Smoker
    {   0, 255,  80 },   // Boomer
    {   0, 220, 255 },   // Hunter
    { 255, 140,   0 },   // Spitter
    { 255, 255,   0 },   // Jockey
    { 255,  30,  30 }    // Charger
};

char g_ZombiesIcons[9][32] = {
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

char g_ZombiesNames[9][32] = {
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

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("L4D2_IsEliteSI", Native_L4D2_IsEliteSI);
	RegPluginLibrary("l4d2_elite_SI_reward");
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "[L4D2] SI Infected Rewards",
	author = "Combined by Assistant",
	description = "Elite SI rewards with per-class tuning",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	CreateConVar("l4d2_si_infectec_reward_ver", PLUGIN_VERSION, "Version", FCVAR_SPONLY|FCVAR_DONTRECORD);
	hHRSmoker = CreateConVar("l4d_hp_rewards_smoker", "3", "Rewarded HP for killing Elite Smoker");
	hHRBoomer = CreateConVar("l4d_hp_rewards_boomer", "2", "Rewarded HP for killing Elite Boomer");
	hHRHunter = CreateConVar("l4d_hp_rewards_hunter", "5", "Rewarded HP for killing Elite Hunter");
	hHRSpitter = CreateConVar("l4d_hp_rewards_spitter", "2", "Rewarded HP for killing Elite Spitter");
	hHRJockey = CreateConVar("l4d_hp_rewards_jockey", "3", "Rewarded HP for killing Elite Jockey");
	hHRCharger = CreateConVar("l4d_hp_rewards_charger", "5", "Rewarded HP for killing Elite Charger");
	hHRMax = CreateConVar("l4d_hp_rewards_max", "200", "Max HP Limit");
	hHRTank = CreateConVar("l4d_hp_rewards_tank", "1", "Enable/Disable Tank Rewards");
	hHRWitch = CreateConVar("l4d_hp_rewards_witch", "1", "Enable/Disable Witch Rewards");
	hHRSI = CreateConVar("l4d_hp_rewards_si", "1", "Enable/Disable Special Infected Rewards");

	g_cvEliteChance = CreateConVar("l4d_hp_rewards_elite_chance", "30", "Chance for SI to become Elite (0-100)");
	g_cvEliteHpMult = CreateConVar("l4d_hp_rewards_elite_hp_mult", "2.5", "Elite HP multiplier");
	g_cvEliteFireChance = CreateConVar("l4d_hp_rewards_elite_fire", "20", "Chance for Elite to catch fire (0-100)");
	g_cvScaleDifficulty = CreateConVar("l4d_hp_rewards_scale_difficulty", "1", "Scale rewards by current game difficulty");
	g_cvDiffEasy = CreateConVar("l4d_hp_rewards_diff_easy", "0.8", "Reward multiplier for easy");
	g_cvDiffNormal = CreateConVar("l4d_hp_rewards_diff_normal", "1.0", "Reward multiplier for normal");
	g_cvDiffHard = CreateConVar("l4d_hp_rewards_diff_hard", "1.2", "Reward multiplier for hard/advanced");
	g_cvDiffExpert = CreateConVar("l4d_hp_rewards_diff_expert", "1.5", "Reward multiplier for impossible/expert");
	g_cvHeadshotBonusEnable = CreateConVar("l4d_hp_rewards_headshot_bonus", "1", "Enable reward bonus for headshot kills");
	g_cvHeadshotBonusMult = CreateConVar("l4d_hp_rewards_headshot_mult", "2.0", "Headshot reward multiplier");
	g_cvTankRewardMode = CreateConVar("l4d_hp_rewards_tank_mode", "1", "Tank reward mode: 0=attacker only, 1=whole team");
	g_cvTankRewardAmount = CreateConVar("l4d_hp_rewards_tank_amount", "20", "Base Tank reward amount");
	g_cvWitchRewardMode = CreateConVar("l4d_hp_rewards_witch_mode", "0", "Witch reward mode: 0=attacker only, 1=whole team");
	g_cvWitchRewardAmount = CreateConVar("l4d_hp_rewards_witch_amount", "15", "Base Witch reward amount");

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	HookEvent("witch_killed", OnWitchKilled);
	HookEvent("round_start", OnRoundStart);
	
	iRewardSmoker = GetConVarInt(hHRSmoker);
	iRewardBoomer = GetConVarInt(hHRBoomer);
	iRewardHunter = GetConVarInt(hHRHunter);
	iRewardSpitter = GetConVarInt(hHRSpitter);
	iRewardJockey = GetConVarInt(hHRJockey);
	iRewardCharger = GetConVarInt(hHRCharger);
	iMax = GetConVarInt(hHRMax);
	bTank = GetConVarBool(hHRTank);
	bSI = GetConVarBool(hHRSI);
	bWitch = GetConVarBool(hHRWitch);
	g_bScaleDifficulty = GetConVarBool(g_cvScaleDifficulty);
	g_fDiffEasy = g_cvDiffEasy.FloatValue;
	g_fDiffNormal = g_cvDiffNormal.FloatValue;
	g_fDiffHard = g_cvDiffHard.FloatValue;
	g_fDiffExpert = g_cvDiffExpert.FloatValue;
	g_bHeadshotBonus = GetConVarBool(g_cvHeadshotBonusEnable);
	g_fHeadshotBonusMult = g_cvHeadshotBonusMult.FloatValue;
	g_iTankRewardMode = GetConVarInt(g_cvTankRewardMode);
	g_iTankRewardAmount = GetConVarInt(g_cvTankRewardAmount);
	g_iWitchRewardMode = GetConVarInt(g_cvWitchRewardMode);
	g_iWitchRewardAmount = GetConVarInt(g_cvWitchRewardAmount);
	g_cvZDifficulty = FindConVar("z_difficulty");

	HookConVarChange(hHRSmoker, HRConfigsChanged);
	HookConVarChange(hHRBoomer, HRConfigsChanged);
	HookConVarChange(hHRHunter, HRConfigsChanged);
	HookConVarChange(hHRSpitter, HRConfigsChanged);
	HookConVarChange(hHRJockey, HRConfigsChanged);
	HookConVarChange(hHRCharger, HRConfigsChanged);
	HookConVarChange(hHRMax, HRConfigsChanged);
	HookConVarChange(hHRTank, HRConfigsChanged);
	HookConVarChange(hHRWitch, HRConfigsChanged);
	HookConVarChange(hHRSI, HRConfigsChanged);
	HookConVarChange(g_cvScaleDifficulty, HRConfigsChanged);
	HookConVarChange(g_cvDiffEasy, HRConfigsChanged);
	HookConVarChange(g_cvDiffNormal, HRConfigsChanged);
	HookConVarChange(g_cvDiffHard, HRConfigsChanged);
	HookConVarChange(g_cvDiffExpert, HRConfigsChanged);
	HookConVarChange(g_cvHeadshotBonusEnable, HRConfigsChanged);
	HookConVarChange(g_cvHeadshotBonusMult, HRConfigsChanged);
	HookConVarChange(g_cvTankRewardMode, HRConfigsChanged);
	HookConVarChange(g_cvTankRewardAmount, HRConfigsChanged);
	HookConVarChange(g_cvWitchRewardMode, HRConfigsChanged);
	HookConVarChange(g_cvWitchRewardAmount, HRConfigsChanged);

	AutoExecConfig(true, "l4d_hp_rewards");

	ConVar decayCvar = FindConVar("pain_pills_decay_rate");
	g_fDecayDecay = (decayCvar != null) ? decayCvar.FloatValue : 0.27;
	if (decayCvar != null) {
		HookConVarChange(decayCvar, OnDecayChanged);
	}

    for (int i = 1; i <= MaxClients; i++) {
        if (IsClientInGame(i)) {
            OnClientPutInServer(i);
        }
    }
}

public void OnDecayChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    g_fDecayDecay = convar.FloatValue;
}

public void OnClientPutInServer(int client) {
    g_bIsElite[client] = false;
    g_bEliteFireImmune[client] = false;
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
    g_bIsElite[client] = false;
    g_bEliteFireImmune[client] = false;
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void HRConfigsChanged(ConVar convar, const char[] oValue, const char[] nValue)
{
	iRewardSmoker = GetConVarInt(hHRSmoker);
	iRewardBoomer = GetConVarInt(hHRBoomer);
	iRewardHunter = GetConVarInt(hHRHunter);
	iRewardSpitter = GetConVarInt(hHRSpitter);
	iRewardJockey = GetConVarInt(hHRJockey);
	iRewardCharger = GetConVarInt(hHRCharger);
	iMax = GetConVarInt(hHRMax);
	bTank = GetConVarBool(hHRTank);
	bSI = GetConVarBool(hHRSI);
	bWitch = GetConVarBool(hHRWitch);
	g_bScaleDifficulty = GetConVarBool(g_cvScaleDifficulty);
	g_fDiffEasy = g_cvDiffEasy.FloatValue;
	g_fDiffNormal = g_cvDiffNormal.FloatValue;
	g_fDiffHard = g_cvDiffHard.FloatValue;
	g_fDiffExpert = g_cvDiffExpert.FloatValue;
	g_bHeadshotBonus = GetConVarBool(g_cvHeadshotBonusEnable);
	g_fHeadshotBonusMult = g_cvHeadshotBonusMult.FloatValue;
	g_iTankRewardMode = GetConVarInt(g_cvTankRewardMode);
	g_iTankRewardAmount = GetConVarInt(g_cvTankRewardAmount);
	g_iWitchRewardMode = GetConVarInt(g_cvWitchRewardMode);
	g_iWitchRewardAmount = GetConVarInt(g_cvWitchRewardAmount);
}

public Action OnRoundStart(Event event, const char[] name, bool dontBroadcast) {
    for (int i = 1; i <= MaxClients; i++) {
        ResetClientEliteState(i);
    }
    return Plugin_Continue;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    // If victim is elite SI and damage is FIRE, block it
	if (victim > 0 && victim <= MaxClients && GetClientTeam(victim) == 3) {
		if (g_bIsElite[victim]) {
			if (g_bEliteFireImmune[victim] && (damagetype & DMG_BURN)) {
				return Plugin_Handled;
			}
		}
	}
    return Plugin_Continue;
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) != 3)
		return Plugin_Continue;

	CreateTimer(0.15, Timer_ProcessSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Continue;
}

public Action Timer_ProcessSpawn(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 3) {
        return Plugin_Stop;
    }

	ResetClientEliteState(client);

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	if (zClass < 1 || zClass > 6) // Excludes Tank (8) and randoms
		return Plugin_Stop;

	if (GetRandomInt(1, 100) > g_cvEliteChance.IntValue)
		return Plugin_Stop;

	g_bIsElite[client] = true;
	g_bEliteFireImmune[client] = false;

	// HP mult
	int eliteHp = RoundToFloor(float(GetEntProp(client, Prop_Data, "m_iMaxHealth")) * g_cvEliteHpMult.FloatValue);
    SetEntProp(client, Prop_Data, "m_iMaxHealth", eliteHp);
	SetEntityHealth(client, eliteHp);

	// Color tint
	int colorIdx = zClass - 1;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, ELITE_COLORS[colorIdx][0], ELITE_COLORS[colorIdx][1], ELITE_COLORS[colorIdx][2], 255);

    // Fire chance
    if (GetRandomInt(1, 100) <= g_cvEliteFireChance.IntValue) {
        g_bEliteFireImmune[client] = true;
        IgniteEntity(client, 9999.0);
    }

	return Plugin_Stop;
}

public void OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetClientTeam(victim) != 3)
		return;

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	bool headshot = event.GetBool("headshot");
	int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");

	// TANK DEATH
	if (bTank && zClass == 8) {
		int reward = ApplyRewardModifiers(g_iTankRewardAmount, headshot);

		if (g_iTankRewardMode == 1) {
			for (int i = 1; i <= MaxClients; i++) {
				if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsPlayerIncapped(i)) {
					int added = GiveBonus(i, reward);
					char text[128];
					Format(text, sizeof(text), "Tank slain, team bonus %i Temp HP!", added);
					DisplayInstructorHint(i, text, "Stat_vs_Most_Damage_As_Tank");
				}
			}
		} else if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && GetClientTeam(attacker) == 2 && IsPlayerAlive(attacker)) {
			int added = GiveBonus(attacker, reward);
			char text[128];
			Format(text, sizeof(text), "Tank slain, bonus %i Temp HP!", added);
			DisplayInstructorHint(attacker, text, "Stat_vs_Most_Damage_As_Tank");
		}

		return;
	}

	// SI DEATH -> reward killer ONLY IF ELITE
	if (bSI) {
		if (g_bIsElite[victim]) {
            if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && GetClientTeam(attacker) == 2 && IsPlayerAlive(attacker)) {
				int aHealth = ApplyRewardModifiers(GetSIRewardByClass(zClass), headshot);

				int added = GiveBonus(attacker, aHealth);
                
                char text[128];
                Format(text, sizeof(text), "%s Elite %s bonus %i Temp HP %s", headshot ? "Headshot" : "Killed", g_ZombiesNames[zClass], added, IsPlayerIncapped(attacker) ? "(Incapped)" : "");
                DisplayInstructorHint(attacker, text, g_ZombiesIcons[zClass]);
            }
        }
	}
}

public void OnWitchKilled(Event event, const char[] name, bool dontBroadcast) {
    if (!bWitch) return;

    int attacker = GetClientOfUserId(event.GetInt("userid")); // For witch_killed, userid is the killer
    if (attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker) || GetClientTeam(attacker) != 2 || !IsPlayerAlive(attacker)) {
        return;
    }

    bool headshot = event.GetBool("headshot");
    int reward = ApplyRewardModifiers(g_iWitchRewardAmount, headshot);

    if (g_iWitchRewardMode == 1) {
        for (int i = 1; i <= MaxClients; i++) {
            if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsPlayerIncapped(i)) {
                int added = GiveBonus(i, reward);
                char text[128];
                Format(text, sizeof(text), "Witch slain, team bonus %i Temp HP!", added);
                DisplayInstructorHint(i, text, "icon_skull");
            }
        }
    } else {
        int added = GiveBonus(attacker, reward);
        char text[128];
        Format(text, sizeof(text), "Witch slain, bonus %i Temp HP!", added);
        DisplayInstructorHint(attacker, text, "icon_skull");
    }
}

int GetSIRewardByClass(int zClass) {
	switch (zClass) {
		case 1: return iRewardSmoker;
		case 2: return iRewardBoomer;
		case 3: return iRewardHunter;
		case 4: return iRewardSpitter;
		case 5: return iRewardJockey;
		case 6: return iRewardCharger;
	}

	return 0;
}

int ApplyRewardModifiers(int baseReward, bool headshot) {
	if (baseReward <= 0) {
		return 0;
	}

	float result = float(baseReward) * GetDifficultyMultiplier();

	if (g_bHeadshotBonus && headshot) {
		result *= g_fHeadshotBonusMult;
	}

	int finalReward = RoundToFloor(result);
	return finalReward < 0 ? 0 : finalReward;
}

float GetDifficultyMultiplier() {
	if (!g_bScaleDifficulty || g_cvZDifficulty == null) {
		return 1.0;
	}

	char difficulty[16];
	g_cvZDifficulty.GetString(difficulty, sizeof(difficulty));

	if (StrEqual(difficulty, "easy", false)) {
		return g_fDiffEasy;
	}

	if (StrEqual(difficulty, "normal", false)) {
		return g_fDiffNormal;
	}

	if (StrEqual(difficulty, "hard", false)) {
		return g_fDiffHard;
	}

	if (StrEqual(difficulty, "impossible", false) || StrEqual(difficulty, "expert", false)) {
		return g_fDiffExpert;
	}

	return 1.0;
}

bool IsPlayerIncapped(int client) {
	return GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 1;
}

int GiveBonus(int client, int aHealth) {
	int sHealth = GetClientHealth(client); // real health
	float tHealth = GetTempHealth(client);

	if (IsPlayerIncapped(client)) {
		aHealth *= 10;
		SetTempHealth(client, tHealth + float(aHealth));
		return aHealth;
	}

	if (sHealth + tHealth + aHealth >= iMax) {
		int calcHealth = iMax - sHealth - RoundToFloor(tHealth);
        if (calcHealth < 0) calcHealth = 0;
		SetTempHealth(client, tHealth + float(calcHealth));
		return calcHealth;
	} else {
		SetTempHealth(client, tHealth + float(aHealth));
		return aHealth;
	}
}

float GetTempHealth(int client) {
	float fHealth = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	fHealth -= (GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * g_fDecayDecay;
	return fHealth < 0.0 ? 0.0 : fHealth;
}

void SetTempHealth(int client, float fHealth) {
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fHealth < 0.0 ? 0.0 : fHealth);
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}

stock void DisplayInstructorHint(int target, char text[255], char icon[255])
{
	int entity = CreateEntityByName("env_instructor_hint");
	if (entity <= 0)
		return;
	char sBuffer[32];
	FormatEx(sBuffer, sizeof(sBuffer), "hintRewardHPTo%d", target);
	DispatchKeyValue(target, "targetname", sBuffer);
	DispatchKeyValue(entity, "hint_target", sBuffer);
	DispatchKeyValue(entity, "hint_static", "false");
	DispatchKeyValue(entity, "hint_timeout", "5.0");
	DestroyEntity(entity, 5.0);
	FormatEx(sBuffer, sizeof(sBuffer), "%d", 0.1);
	DispatchKeyValue(entity, "hint_icon_offset", sBuffer);
	DispatchKeyValue(entity, "hint_range", "0.1");
	DispatchKeyValue(entity, "hint_nooffscreen", "true");
	DispatchKeyValue(entity, "hint_icon_onscreen", icon);
	DispatchKeyValue(entity, "hint_icon_offscreen", icon);
	DispatchKeyValue(entity, "hint_forcecaption", "true");
	FormatEx(sBuffer, sizeof(sBuffer), "%d %d %d", 255, 255, 255);
	DispatchKeyValue(entity, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(entity, "hint_instance_type", "0");
	DispatchKeyValue(entity, "hint_color", sBuffer);
	ReplaceString(text, sizeof(text), "\n", " ");
	DispatchKeyValue(entity, "hint_caption", text);
	DispatchSpawn(entity);
	AcceptEntityInput(entity, "ShowHint", target);
}

stock void DestroyEntity(int entity, float time = 0.0)
{
	if (time == 0.0) {
		if (IsValidEntity(entity)) {
			char edictname[32];
			GetEdictClassname(entity, edictname, 32);
			if (!StrEqual(edictname, "player"))
				AcceptEntityInput(entity, "kill");
		}
	} else {
		CreateTimer(time, DestroyEntityOnTimer, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action DestroyEntityOnTimer(Handle timer, any entityRef) {
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE)
		DestroyEntity(entity);
	return Plugin_Stop;
}

public any Native_L4D2_IsEliteSI(Handle plugin, int numParams)
{
	if (numParams < 1) {
		return false;
	}

	int client = GetNativeCell(1);
	return IsEliteSI(client);
}

bool IsEliteSI(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client)) {
		return false;
	}

	return g_bIsElite[client];
}

void ResetClientEliteState(int client)
{
	if (client <= 0 || client > MaxClients) {
		return;
	}

	g_bIsElite[client] = false;
    g_bEliteFireImmune[client] = false;

	if (!IsClientInGame(client)) {
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SetEntityRenderMode(client, RENDER_NORMAL);
	SetEntityRenderColor(client, 255, 255, 255, 255);
}
