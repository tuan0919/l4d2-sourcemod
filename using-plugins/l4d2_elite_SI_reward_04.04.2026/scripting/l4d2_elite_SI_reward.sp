#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

bool g_bIsElite[MAXPLAYERS + 1];

ConVar hHRFirst;
ConVar hHRSecond;
ConVar hHRThird;
ConVar hHRMax;
ConVar hHRTank;
ConVar hHRWitch;
ConVar hHRSI;

ConVar g_cvEliteChance;
ConVar g_cvEliteHpMult;
ConVar g_cvEliteSpeed;
ConVar g_cvEliteFireChance;

int iFirst;
int iSecond;
int iThird;
int iMax;
bool bTank;
bool bWitch;
bool bSI;

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
	description = "Elite Infected & HP Rewards (Temp HP)",
	version = PLUGIN_VERSION,
	url = ""
};

public void OnPluginStart()
{
	CreateConVar("l4d2_si_infectec_reward_ver", PLUGIN_VERSION, "Version", FCVAR_SPONLY|FCVAR_DONTRECORD);
	hHRFirst = CreateConVar("l4d_hp_rewards_first", "2", "Rewarded HP For Killing Boomers And Spitters");
	hHRSecond = CreateConVar("l4d_hp_rewards_second", "3", "Rewarded HP For Killing Smokers And Jockeys");
	hHRThird = CreateConVar("l4d_hp_rewards_third", "5", "Rewarded HP For Killing Hunters And Chargers");
	hHRMax = CreateConVar("l4d_hp_rewards_max", "200", "Max HP Limit");
	hHRTank = CreateConVar("l4d_hp_rewards_tank", "1", "Enable/Disable Tank Rewards");
	hHRWitch = CreateConVar("l4d_hp_rewards_witch", "1", "Enable/Disable Witch Rewards");
	hHRSI = CreateConVar("l4d_hp_rewards_si", "1", "Enable/Disable Special Infected Rewards");

	g_cvEliteChance = CreateConVar("l4d_hp_rewards_elite_chance", "30", "Chance for SI to become Elite (0-100)");
	g_cvEliteHpMult = CreateConVar("l4d_hp_rewards_elite_hp_mult", "2.5", "Elite HP multiplier");
	g_cvEliteSpeed = CreateConVar("l4d_hp_rewards_elite_speed", "1.15", "Elite SI movement speed multiplier");
    g_cvEliteFireChance = CreateConVar("l4d_hp_rewards_elite_fire", "20", "Chance for Elite to catch fire (0-100)");

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	HookEvent("witch_killed", OnWitchKilled);
	HookEvent("round_start", OnRoundStart);
	
	iFirst = GetConVarInt(hHRFirst);
	iSecond = GetConVarInt(hHRSecond);
	iThird = GetConVarInt(hHRThird);
	iMax = GetConVarInt(hHRMax);
	bTank = GetConVarBool(hHRTank);
	bSI = GetConVarBool(hHRSI);
	bWitch = GetConVarBool(hHRWitch);

	HookConVarChange(hHRFirst, HRConfigsChanged);
	HookConVarChange(hHRSecond, HRConfigsChanged);
	HookConVarChange(hHRThird, HRConfigsChanged);
	HookConVarChange(hHRMax, HRConfigsChanged);
	HookConVarChange(hHRTank, HRConfigsChanged);
	HookConVarChange(hHRWitch, HRConfigsChanged);
	HookConVarChange(hHRSI, HRConfigsChanged);

	AutoExecConfig(true, "l4d_hp_rewards");

	ConVar decayCvar = FindConVar("pain_pills_decay_rate");
	g_fDecayDecay = (decayCvar != null) ? decayCvar.FloatValue : 0.27;
    HookConVarChange(decayCvar, OnDecayChanged);

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
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
    g_bIsElite[client] = false;
    SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void HRConfigsChanged(ConVar convar, const char[] oValue, const char[] nValue)
{
	iFirst = GetConVarInt(hHRFirst);
	iSecond = GetConVarInt(hHRSecond);
	iThird = GetConVarInt(hHRThird);
	iMax = GetConVarInt(hHRMax);
	bTank = GetConVarBool(hHRTank);
	bSI = GetConVarBool(hHRSI);
    bWitch = GetConVarBool(hHRWitch);
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
            if (damagetype & DMG_BURN) {
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

	// HP mult
	int eliteHp = RoundToFloor(float(GetEntProp(client, Prop_Data, "m_iMaxHealth")) * g_cvEliteHpMult.FloatValue);
    SetEntProp(client, Prop_Data, "m_iMaxHealth", eliteHp);
	SetEntityHealth(client, eliteHp);

	// Color tint
	int colorIdx = zClass - 1;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, ELITE_COLORS[colorIdx][0], ELITE_COLORS[colorIdx][1], ELITE_COLORS[colorIdx][2], 255);

	// Speed boost
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvEliteSpeed.FloatValue);

    // Fire chance
    if (GetRandomInt(1, 100) <= g_cvEliteFireChance.IntValue) {
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

    // TANK DEATH -> reward ALL
	if (bTank && zClass == 8) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsPlayerIncapped(i)) {
				int added = GiveBonus(i, 20);
				char text[128];
				Format(text, sizeof(text), "Tank slain, bonus %i Temp HP!", added);
				DisplayInstructorHint(i, text, "Stat_vs_Most_Damage_As_Tank");
			}
		}
		return;
	}

    // SI DEATH -> reward killer ONLY IF ELITE
	if (bSI) {
		if (g_bIsElite[victim]) {
            if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && GetClientTeam(attacker) == 2 && IsPlayerAlive(attacker)) {
                int aHealth = 0;
                if (zClass == 2 || zClass == 4) aHealth = iFirst;
                else if (zClass == 1 || zClass == 5) aHealth = iSecond;
                else if (zClass == 3 || zClass == 6) aHealth = iThird;

                if (headshot) aHealth *= 2;

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
    if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && GetClientTeam(attacker) == 2 && IsPlayerAlive(attacker)) {
        bool headshot = event.GetBool("headshot");
        int added = GiveBonus(attacker, headshot ? 30 : 15); // Adjust Witch reward accordingly
        char text[128];
        Format(text, sizeof(text), "Witch slain, bonus %i Temp HP!", added);
        DisplayInstructorHint(attacker, text, "icon_skull");
    }
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

	if (!IsClientInGame(client)) {
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
	SetEntityRenderMode(client, RENDER_NORMAL);
	SetEntityRenderColor(client, 255, 255, 255, 255);
}
