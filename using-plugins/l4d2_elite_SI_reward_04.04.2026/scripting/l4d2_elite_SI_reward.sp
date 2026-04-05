#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.1.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_SMOKER  1
#define ZC_BOOMER  2
#define ZC_HUNTER  3
#define ZC_SPITTER 4
#define ZC_JOCKEY  5
#define ZC_CHARGER 6
#define ZC_TANK    8

#define MAX_ACID_POOLS 128

bool g_bIsElite[MAXPLAYERS + 1];
bool g_bBoomerIgniteVariant[MAXPLAYERS + 1];
bool g_bSpitterStealth[MAXPLAYERS + 1];
bool g_bForcedSlow[MAXPLAYERS + 1];

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
ConVar g_cvEliteSpecialEnable;
ConVar g_cvEliteDebug;
ConVar g_cvEliteBlastRadius;
ConVar g_cvEliteBlastDamage;
ConVar g_cvEliteBlastForce;
ConVar g_cvEliteBleedDamage;
ConVar g_cvEliteBleedTicks;
ConVar g_cvEliteAcidDuration;
ConVar g_cvEliteAcidTickDamage;
ConVar g_cvEliteAcidRadius;
ConVar g_cvEliteAcidTrailInterval;
ConVar g_cvEliteSlowMult;
ConVar g_cvEliteSlowDuration;
ConVar g_cvEliteSpitterStealthInterval;
ConVar g_cvEliteSpitterStealthDuration;
ConVar g_cvEliteBoomerIgniteChance;
ConVar g_cvEliteBoomerAutoExplodeTime;
ConVar g_cvEliteChargerMaulDamage;
ConVar g_cvEliteChargerMaulTick;

int iFirst;
int iSecond;
int iThird;
int iMax;
bool bTank;
bool bWitch;
bool bSI;

float g_fDecayDecay;
float g_fSpitterStealthEnd[MAXPLAYERS + 1];
float g_fNextSpitterStealth[MAXPLAYERS + 1];
float g_fNextSpitterTrail[MAXPLAYERS + 1];
float g_fBoomerAutoExplodeTime[MAXPLAYERS + 1];
float g_fSlowEndTime[MAXPLAYERS + 1];
float g_fSlowMultiplier[MAXPLAYERS + 1];
float g_fNextAcidTick[MAXPLAYERS + 1];
float g_fNextChargerMaulTick[MAXPLAYERS + 1];
int g_iChargerMaulTargetUserId[MAXPLAYERS + 1];

float g_fAcidPosX[MAX_ACID_POOLS];
float g_fAcidPosY[MAX_ACID_POOLS];
float g_fAcidPosZ[MAX_ACID_POOLS];
float g_fAcidExpireTime[MAX_ACID_POOLS];
float g_fAcidNextFxTime[MAX_ACID_POOLS];
int g_iAcidOwnerUserId[MAX_ACID_POOLS];

Handle g_hEliteThinkTimer = null;
int g_iBeamSprite = -1;
int g_iHaloSprite = -1;
int g_iExplodeSprite = -1;

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

public Plugin myinfo =
{
	name = "[L4D2] SI Infected Rewards",
	author = "Combined by Assistant",
	description = "Elite Infected & HP Rewards (Temp HP)",
	version = PLUGIN_VERSION,
	url = ""
}

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

	g_cvEliteChance = CreateConVar("l4d_hp_rewards_elite_chance", "100", "Chance for SI to become Elite (0-100)");
	g_cvEliteHpMult = CreateConVar("l4d_hp_rewards_elite_hp_mult", "2.5", "Elite HP multiplier");
	g_cvEliteSpeed = CreateConVar("l4d_hp_rewards_elite_speed", "1.15", "Elite SI movement speed multiplier");
    g_cvEliteFireChance = CreateConVar("l4d_hp_rewards_elite_fire", "20", "Chance for Elite to catch fire (0-100)");
	g_cvEliteSpecialEnable = CreateConVar("l4d_hp_rewards_elite_special_enable", "1", "Enable elite special perks and moves");
	g_cvEliteDebug = CreateConVar("l4d_hp_rewards_elite_debug", "1", "Show debug chat when elite perks trigger");
	g_cvEliteBlastRadius = CreateConVar("l4d_hp_rewards_elite_blast_radius", "240.0", "Blast radius for elite special explosions");
	g_cvEliteBlastDamage = CreateConVar("l4d_hp_rewards_elite_blast_damage", "10.0", "Blast damage for elite special explosions");
	g_cvEliteBlastForce = CreateConVar("l4d_hp_rewards_elite_blast_force", "380.0", "Knockback force for elite special explosions");
	g_cvEliteBleedDamage = CreateConVar("l4d_hp_rewards_elite_bleed_damage", "2.0", "Hunter bleed damage per tick");
	g_cvEliteBleedTicks = CreateConVar("l4d_hp_rewards_elite_bleed_ticks", "5", "Hunter bleed ticks");
	g_cvEliteAcidDuration = CreateConVar("l4d_hp_rewards_elite_acid_duration", "4.0", "Acid pool duration");
	g_cvEliteAcidTickDamage = CreateConVar("l4d_hp_rewards_elite_acid_tick_damage", "2.0", "Acid pool damage per tick");
	g_cvEliteAcidRadius = CreateConVar("l4d_hp_rewards_elite_acid_radius", "90.0", "Acid pool radius");
	g_cvEliteAcidTrailInterval = CreateConVar("l4d_hp_rewards_elite_spitter_trail_interval", "0.55", "Spitter acid trail spawn interval while running");
	g_cvEliteSlowMult = CreateConVar("l4d_hp_rewards_elite_slow_mult", "0.72", "Movement multiplier when slowed by elite acid");
	g_cvEliteSlowDuration = CreateConVar("l4d_hp_rewards_elite_slow_duration", "1.2", "Slow duration from elite acid");
	g_cvEliteSpitterStealthInterval = CreateConVar("l4d_hp_rewards_elite_spitter_stealth_interval", "12.0", "Seconds between elite spitter stealth activations");
	g_cvEliteSpitterStealthDuration = CreateConVar("l4d_hp_rewards_elite_spitter_stealth_duration", "3.0", "Elite spitter stealth duration");
	g_cvEliteBoomerIgniteChance = CreateConVar("l4d_hp_rewards_elite_boomer_ignite_variant_chance", "45", "Chance elite boomer becomes ignite auto-explode variant");
	g_cvEliteBoomerAutoExplodeTime = CreateConVar("l4d_hp_rewards_elite_boomer_auto_explode_time", "6.0", "Seconds before ignite variant boomer auto explodes");
	g_cvEliteChargerMaulDamage = CreateConVar("l4d_hp_rewards_elite_charger_maul_damage", "10.0", "Damage per tick when elite charger mauls incapacitated target");
	g_cvEliteChargerMaulTick = CreateConVar("l4d_hp_rewards_elite_charger_maul_tick", "0.6", "Tick interval for elite charger maul damage");

	HookEvent("player_death", OnPlayerDeath);
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
	HookEvent("witch_killed", OnWitchKilled);
	HookEvent("round_start", OnRoundStart);
	HookEvent("charger_impact", OnChargerImpact, EventHookMode_Post);
	HookEvent("lunge_pounce", OnLungePounce, EventHookMode_Post);
	
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

	if (g_hEliteThinkTimer == null) {
		g_hEliteThinkTimer = CreateTimer(0.2, Timer_EliteThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}

    // Force test defaults so every SI spawn is elite while verifying mechanics.
    g_cvEliteChance.IntValue = 100;
    g_cvEliteSpecialEnable.IntValue = 1;
}

public void OnMapStart() {
    g_iBeamSprite = PrecacheModel("materials/sprites/laserbeam.vmt");
    g_iHaloSprite = PrecacheModel("materials/sprites/glow01.vmt");
    g_iExplodeSprite = PrecacheModel("materials/sprites/zerogxplode.vmt");
    PrecacheSound("ambient/explosions/explode_8.wav", true);
    PrecacheSound("player/charger/hit/charger_smash_02.wav", true);
    PrecacheSound("player/spitter/voice/warn/spitter_spot06.wav", true);
}

public void OnDecayChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    g_fDecayDecay = convar.FloatValue;
}

public void OnClientPutInServer(int client) {
    ResetEliteState(client);
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client) {
    ResetEliteState(client);
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
        ResetEliteState(i);
    }
    ClearAllAcidPools();
    return Plugin_Continue;
}

public void OnMapEnd() {
    ClearAllAcidPools();
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && GetClientTeam(victim) == TEAM_INFECTED && g_bIsElite[victim]) {
        // Fire immunity retained from old elite logic.
        if (damagetype & DMG_BURN) {
            return Plugin_Handled;
        }

        // Spitter stealth state: brief phase immunity.
        if (g_bSpitterStealth[victim]) {
            return Plugin_Handled;
        }
    }

    // Elite attacker extra effects on hit.
    if (g_cvEliteSpecialEnable.BoolValue
        && victim > 0 && victim <= MaxClients
        && attacker > 0 && attacker <= MaxClients
        && IsClientInGame(victim) && IsClientInGame(attacker)
        && GetClientTeam(victim) == TEAM_SURVIVOR
        && GetClientTeam(attacker) == TEAM_INFECTED
        && g_bIsElite[attacker]
        && damage > 0.0) {

        int zClass = GetEntProp(attacker, Prop_Send, "m_zombieClass");
        if (zClass == ZC_HUNTER) {
            StartBleeding(victim, attacker, g_cvEliteBleedTicks.IntValue, g_cvEliteBleedDamage.FloatValue);
        } else if (zClass == ZC_SPITTER) {
            float pos[3];
            GetClientAbsOrigin(victim, pos);
            SpawnAcidPool(pos, attacker, g_cvEliteAcidDuration.FloatValue);
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

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	if (zClass < 1 || zClass > 6) // Excludes Tank (8) and randoms
		return Plugin_Stop;

	if (GetRandomInt(1, 100) > g_cvEliteChance.IntValue)
		return Plugin_Stop;

	g_bIsElite[client] = true;
    g_bBoomerIgniteVariant[client] = false;
    g_bSpitterStealth[client] = false;
    g_fSpitterStealthEnd[client] = 0.0;
    g_fNextSpitterTrail[client] = 0.0;
    g_fNextSpitterStealth[client] = GetGameTime() + g_cvEliteSpitterStealthInterval.FloatValue;
    g_fBoomerAutoExplodeTime[client] = 0.0;

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

    if (g_cvEliteSpecialEnable.BoolValue && zClass == ZC_BOOMER) {
        if (GetRandomInt(1, 100) <= g_cvEliteBoomerIgniteChance.IntValue) {
            g_bBoomerIgniteVariant[client] = true;
            IgniteEntity(client, 9999.0);
            g_fBoomerAutoExplodeTime[client] = GetGameTime() + g_cvEliteBoomerAutoExplodeTime.FloatValue;
        }
    }

    if (g_cvEliteDebug.BoolValue) {
        PrintToChatAll("[Elite] %N spawned as ELITE %s", client, g_ZombiesNames[zClass]);
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
    bool wasElite = g_bIsElite[victim];

    if (g_cvEliteSpecialEnable.BoolValue && wasElite && zClass == ZC_BOOMER) {
        // Elite boomer death burst: fling and ignite nearby survivors.
        DoEliteBlast(victim, attacker, g_cvEliteBlastRadius.FloatValue, g_cvEliteBlastDamage.FloatValue, g_cvEliteBlastForce.FloatValue, true);
    }

    // TANK DEATH -> reward ALL
	if (bTank && zClass == ZC_TANK) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsClientInGame(i) && GetClientTeam(i) == 2 && IsPlayerAlive(i) && !IsPlayerIncapped(i)) {
				int added = GiveBonus(i, 20);
				char text[128];
				Format(text, sizeof(text), "Tank slain, bonus %i Temp HP!", added);
				DisplayInstructorHint(i, text, "Stat_vs_Most_Damage_As_Tank");
			}
		}
        ResetEliteState(victim);
		return;
	}

    // SI DEATH -> reward killer ONLY IF ELITE
	if (bSI) {
		if (wasElite) {
            g_bIsElite[victim] = false; // Avoid duplicate reward call in weird event chains.

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

    ResetEliteState(victim);
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

public void OnChargerImpact(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEliteSpecialEnable.BoolValue) {
        return;
    }

    int charger = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidInfectedElite(charger) || GetEntProp(charger, Prop_Send, "m_zombieClass") != ZC_CHARGER) {
        return;
    }

    int victim = GetClientOfUserId(event.GetInt("victim"));
    DoEliteBlast(charger, charger, g_cvEliteBlastRadius.FloatValue, g_cvEliteBlastDamage.FloatValue, g_cvEliteBlastForce.FloatValue, false);
    if (g_cvEliteDebug.BoolValue) {
        PrintToChatAll("[Elite] Charger impact blast by %N", charger);
    }

    // "Can keep smashing incapped survivor until dead" (simulated via periodic maul damage lock-on).
    if (IsValidSurvivor(victim) && IsPlayerAlive(victim) && IsPlayerIncapped(victim)) {
        g_iChargerMaulTargetUserId[charger] = GetClientUserId(victim);
        g_fNextChargerMaulTick[charger] = GetGameTime() + 0.15;
    }
}

public void OnLungePounce(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEliteSpecialEnable.BoolValue) {
        return;
    }

    int hunter = GetClientOfUserId(event.GetInt("userid"));
    int victim = GetClientOfUserId(event.GetInt("victim"));
    if (!IsValidInfectedElite(hunter) || GetEntProp(hunter, Prop_Send, "m_zombieClass") != ZC_HUNTER) {
        return;
    }

    // Hunter landing shockwave + bleed.
    DoEliteBlast(hunter, hunter, g_cvEliteBlastRadius.FloatValue, g_cvEliteBlastDamage.FloatValue, g_cvEliteBlastForce.FloatValue, false);
    if (g_cvEliteDebug.BoolValue) {
        PrintToChatAll("[Elite] Hunter shockwave by %N", hunter);
    }
    if (IsValidSurvivor(victim) && IsPlayerAlive(victim)) {
        StartBleeding(victim, hunter, g_cvEliteBleedTicks.IntValue, g_cvEliteBleedDamage.FloatValue);
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

bool IsValidSurvivor(int client) {
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVOR;
}

bool IsValidInfectedElite(int client) {
    return client > 0
        && client <= MaxClients
        && IsClientInGame(client)
        && IsPlayerAlive(client)
        && GetClientTeam(client) == TEAM_INFECTED
        && g_bIsElite[client];
}

void ResetEliteState(int client) {
    if (client < 1 || client > MaxClients) {
        return;
    }

    if (IsClientInGame(client)) {
        if (GetClientTeam(client) == TEAM_SURVIVOR && g_bForcedSlow[client]) {
            SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
        }
        if (GetClientTeam(client) == TEAM_INFECTED && g_bSpitterStealth[client]) {
            SetEntityRenderMode(client, RENDER_TRANSCOLOR);
            SetEntityRenderColor(client, 255, 255, 255, 255);
        }
    }

    g_bIsElite[client] = false;
    g_bBoomerIgniteVariant[client] = false;
    g_bSpitterStealth[client] = false;
    g_bForcedSlow[client] = false;
    g_fSpitterStealthEnd[client] = 0.0;
    g_fNextSpitterStealth[client] = 0.0;
    g_fNextSpitterTrail[client] = 0.0;
    g_fBoomerAutoExplodeTime[client] = 0.0;
    g_fSlowEndTime[client] = 0.0;
    g_fSlowMultiplier[client] = 1.0;
    g_fNextAcidTick[client] = 0.0;
    g_fNextChargerMaulTick[client] = 0.0;
    g_iChargerMaulTargetUserId[client] = 0;
}

void ClearAllAcidPools() {
    for (int i = 0; i < MAX_ACID_POOLS; i++) {
        g_fAcidExpireTime[i] = 0.0;
        g_fAcidNextFxTime[i] = 0.0;
        g_iAcidOwnerUserId[i] = 0;
        g_fAcidPosX[i] = 0.0;
        g_fAcidPosY[i] = 0.0;
        g_fAcidPosZ[i] = 0.0;
    }
}

void SpawnAcidPool(float pos[3], int owner, float duration) {
    if (!g_cvEliteSpecialEnable.BoolValue) {
        return;
    }

    int slot = -1;
    for (int i = 0; i < MAX_ACID_POOLS; i++) {
        if (g_fAcidExpireTime[i] <= GetGameTime()) {
            slot = i;
            break;
        }
    }
    if (slot == -1) {
        return;
    }

    g_fAcidPosX[slot] = pos[0];
    g_fAcidPosY[slot] = pos[1];
    g_fAcidPosZ[slot] = pos[2];
    g_fAcidExpireTime[slot] = GetGameTime() + duration;
    g_fAcidNextFxTime[slot] = 0.0;
    g_iAcidOwnerUserId[slot] = (owner > 0 && owner <= MaxClients) ? GetClientUserId(owner) : 0;
    ShowAcidPoolFX(pos);

    if (g_cvEliteDebug.BoolValue && owner > 0 && owner <= MaxClients && IsClientInGame(owner)) {
        PrintToChatAll("[Elite] Spitter acid pool created by %N", owner);
    }
}

void ApplySlow(int client, float slowMult, float duration) {
    if (!IsValidSurvivor(client) || !IsPlayerAlive(client)) {
        return;
    }

    if (slowMult < 0.15) {
        slowMult = 0.15;
    }
    if (slowMult > 1.0) {
        slowMult = 1.0;
    }

    if (!g_bForcedSlow[client] || slowMult < g_fSlowMultiplier[client]) {
        g_fSlowMultiplier[client] = slowMult;
    }
    float newEnd = GetGameTime() + duration;
    if (newEnd > g_fSlowEndTime[client]) {
        g_fSlowEndTime[client] = newEnd;
    }
    g_bForcedSlow[client] = true;
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_fSlowMultiplier[client]);
}

void StartBleeding(int victim, int attacker, int ticks, float damagePerTick) {
    if (!IsValidSurvivor(victim) || !IsPlayerAlive(victim) || ticks <= 0 || damagePerTick <= 0.0) {
        return;
    }

    DataPack pack;
    CreateDataTimer(1.0, Timer_BleedTick, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(victim));
    pack.WriteCell((attacker > 0 && attacker <= MaxClients) ? GetClientUserId(attacker) : 0);
    pack.WriteFloat(damagePerTick);
    pack.WriteCell(ticks);
}

public Action Timer_BleedTick(Handle timer, DataPack pack) {
    pack.Reset();
    int victimUserId = pack.ReadCell();
    int attackerUserId = pack.ReadCell();
    float damagePerTick = pack.ReadFloat();
    int ticks = pack.ReadCell();

    int victim = GetClientOfUserId(victimUserId);
    int attacker = GetClientOfUserId(attackerUserId);
    if (!IsValidSurvivor(victim) || !IsPlayerAlive(victim)) {
        return Plugin_Stop;
    }

    SDKHooks_TakeDamage(victim, attacker > 0 ? attacker : 0, attacker > 0 ? attacker : 0, damagePerTick, DMG_POISON);

    ticks--;
    if (ticks <= 0) {
        return Plugin_Stop;
    }

    pack.Reset();
    pack.WriteCell(victimUserId);
    pack.WriteCell(attackerUserId);
    pack.WriteFloat(damagePerTick);
    pack.WriteCell(ticks);
    return Plugin_Continue;
}

void DoEliteBlast(int sourceClient, int attacker, float radius, float damage, float force, bool igniteVictims) {
    float sourcePos[3];
    if (sourceClient <= 0 || sourceClient > MaxClients || !IsClientInGame(sourceClient)) {
        return;
    }
    GetClientAbsOrigin(sourceClient, sourcePos);
    ShowBlastFX(sourcePos, radius, igniteVictims);

    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidSurvivor(i) || !IsPlayerAlive(i)) {
            continue;
        }

        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        float dist = GetVectorDistance(sourcePos, targetPos);
        if (dist > radius) {
            continue;
        }

        SDKHooks_TakeDamage(i, attacker > 0 ? attacker : 0, attacker > 0 ? attacker : 0, damage, DMG_BLAST);

        float push[3];
        push[0] = targetPos[0] - sourcePos[0];
        push[1] = targetPos[1] - sourcePos[1];
        push[2] = 0.0;
        NormalizeVector(push, push);
        ScaleVector(push, force);
        push[2] = force * 0.35;
        TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, push);

        if (igniteVictims) {
            IgniteEntity(i, 2.5);
        }
    }
}

void EnterSpitterStealth(int client) {
    if (!IsValidInfectedElite(client) || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER) {
        return;
    }

    g_bSpitterStealth[client] = true;
    g_fSpitterStealthEnd[client] = GetGameTime() + g_cvEliteSpitterStealthDuration.FloatValue;
    ShowStealthFX(client, true);
    SetEntityRenderMode(client, RENDER_TRANSCOLOR);
    SetEntityRenderColor(client, 255, 255, 255, 45);
    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvEliteSpeed.FloatValue * 1.35);

    if (g_cvEliteDebug.BoolValue) {
        PrintToChatAll("[Elite] Spitter stealth ON: %N", client);
    }
}

void ExitSpitterStealth(int client) {
    if (client < 1 || client > MaxClients || !IsClientInGame(client)) {
        return;
    }

    g_bSpitterStealth[client] = false;
    g_fSpitterStealthEnd[client] = 0.0;
    ShowStealthFX(client, false);

    int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
    if (zClass >= 1 && zClass <= 6) {
        SetEntityRenderMode(client, RENDER_TRANSCOLOR);
        SetEntityRenderColor(client, ELITE_COLORS[zClass - 1][0], ELITE_COLORS[zClass - 1][1], ELITE_COLORS[zClass - 1][2], 255);
    } else {
        SetEntityRenderMode(client, RENDER_TRANSCOLOR);
        SetEntityRenderColor(client, 255, 255, 255, 255);
    }

    SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvEliteSpeed.FloatValue);

    if (g_cvEliteDebug.BoolValue && IsClientInGame(client)) {
        PrintToChatAll("[Elite] Spitter stealth OFF: %N", client);
    }
}

bool IsClientMovingFast(int client, float minSpeed2D) {
    float vel[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
    float speed2D = SquareRoot((vel[0] * vel[0]) + (vel[1] * vel[1]));
    return speed2D >= minSpeed2D;
}

void ShowBlastFX(float origin[3], float radius, bool fireVariant) {
    if (g_iBeamSprite == -1 || g_iHaloSprite == -1) {
        return;
    }

    int r = fireVariant ? 255 : 80;
    int g = fireVariant ? 120 : 180;
    int b = fireVariant ? 20 : 255;
    int color[4];
    color[0] = r;
    color[1] = g;
    color[2] = b;
    color[3] = 255;
    TE_SetupBeamRingPoint(origin, 10.0, radius, g_iBeamSprite, g_iHaloSprite, 0, 10, 0.45, 10.0, 1.0, color, 0, 0);
    TE_SendToAll();

    if (g_iExplodeSprite != -1) {
        TE_SetupExplosion(origin, g_iExplodeSprite, 0.9, 1, 0, 0, RoundToFloor(radius));
        TE_SendToAll();
    }

    EmitAmbientSound("ambient/explosions/explode_8.wav", origin, SOUND_FROM_WORLD, SNDLEVEL_NORMAL);
}

void ShowAcidPoolFX(float origin[3]) {
    if (g_iBeamSprite == -1 || g_iHaloSprite == -1) {
        return;
    }

    int color[4];
    color[0] = 30;
    color[1] = 255;
    color[2] = 80;
    color[3] = 220;
    TE_SetupBeamRingPoint(origin, 12.0, g_cvEliteAcidRadius.FloatValue, g_iBeamSprite, g_iHaloSprite, 0, 10, 0.35, 5.0, 0.6, color, 0, 0);
    TE_SendToAll();
}

void ShowStealthFX(int client, bool entering) {
    if (!IsClientInGame(client)) {
        return;
    }

    float pos[3];
    GetClientAbsOrigin(client, pos);
    if (g_iBeamSprite != -1 && g_iHaloSprite != -1) {
        int color[4];
        if (entering) {
            color[0] = 180; color[1] = 255; color[2] = 255; color[3] = 220;
            TE_SetupBeamRingPoint(pos, 8.0, 130.0, g_iBeamSprite, g_iHaloSprite, 0, 8, 0.25, 6.0, 0.5, color, 0, 0);
        } else {
            color[0] = 255; color[1] = 255; color[2] = 255; color[3] = 180;
            TE_SetupBeamRingPoint(pos, 8.0, 90.0, g_iBeamSprite, g_iHaloSprite, 0, 8, 0.2, 4.0, 0.4, color, 0, 0);
        }
        TE_SendToAll();
    }

    EmitSoundToAll("player/spitter/voice/warn/spitter_spot06.wav", client, SNDCHAN_AUTO, SNDLEVEL_NORMAL);
}

public Action Timer_EliteThink(Handle timer) {
    float now = GetGameTime();

    // Restore survivors when slow expires.
    for (int i = 1; i <= MaxClients; i++) {
        if (!g_bForcedSlow[i]) {
            continue;
        }
        if (!IsValidSurvivor(i) || !IsPlayerAlive(i) || now >= g_fSlowEndTime[i]) {
            if (IsValidSurvivor(i)) {
                SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", 1.0);
            }
            g_bForcedSlow[i] = false;
            g_fSlowEndTime[i] = 0.0;
            g_fSlowMultiplier[i] = 1.0;
        }
    }

    // Acid pool damage + slow.
    float acidRadius = g_cvEliteAcidRadius.FloatValue;
    for (int p = 0; p < MAX_ACID_POOLS; p++) {
        if (g_fAcidExpireTime[p] <= 0.0) {
            continue;
        }
        if (now >= g_fAcidExpireTime[p]) {
            g_fAcidExpireTime[p] = 0.0;
            continue;
        }

        float acidPos[3];
        acidPos[0] = g_fAcidPosX[p];
        acidPos[1] = g_fAcidPosY[p];
        acidPos[2] = g_fAcidPosZ[p];

        if (now >= g_fAcidNextFxTime[p]) {
            ShowAcidPoolFX(acidPos);
            g_fAcidNextFxTime[p] = now + 1.0;
        }

        for (int s = 1; s <= MaxClients; s++) {
            if (!IsValidSurvivor(s) || !IsPlayerAlive(s)) {
                continue;
            }

            float pos[3];
            GetClientAbsOrigin(s, pos);
            if (GetVectorDistance(pos, acidPos) > acidRadius) {
                continue;
            }
            if (now < g_fNextAcidTick[s]) {
                continue;
            }

            int owner = GetClientOfUserId(g_iAcidOwnerUserId[p]);
            SDKHooks_TakeDamage(s, owner > 0 ? owner : 0, owner > 0 ? owner : 0, g_cvEliteAcidTickDamage.FloatValue, DMG_POISON);
            ApplySlow(s, g_cvEliteSlowMult.FloatValue, g_cvEliteSlowDuration.FloatValue);
            g_fNextAcidTick[s] = now + 0.45;
        }
    }

    if (!g_cvEliteSpecialEnable.BoolValue) {
        return Plugin_Continue;
    }

    // Per-elite passive move logic.
    for (int i = 1; i <= MaxClients; i++) {
        if (!IsValidInfectedElite(i)) {
            continue;
        }

        int zClass = GetEntProp(i, Prop_Send, "m_zombieClass");
        if (zClass == ZC_BOOMER) {
            // Keep boomer mobile even during vomit animation.
            SetEntPropFloat(i, Prop_Send, "m_flLaggedMovementValue", g_cvEliteSpeed.FloatValue * 1.20);

            if (g_bBoomerIgniteVariant[i] && g_fBoomerAutoExplodeTime[i] > 0.0 && now >= g_fBoomerAutoExplodeTime[i]) {
                g_fBoomerAutoExplodeTime[i] = 0.0;
                if (g_cvEliteDebug.BoolValue) {
                    PrintToChatAll("[Elite] Boomer auto explode: %N", i);
                }
                ForcePlayerSuicide(i);
            }
        } else if (zClass == ZC_SPITTER) {
            if (!g_bSpitterStealth[i] && now >= g_fNextSpitterStealth[i]) {
                EnterSpitterStealth(i);
                g_fNextSpitterStealth[i] = now + g_cvEliteSpitterStealthInterval.FloatValue;
            } else if (g_bSpitterStealth[i] && now >= g_fSpitterStealthEnd[i]) {
                ExitSpitterStealth(i);
            }

            if (now >= g_fNextSpitterTrail[i] && IsClientMovingFast(i, 75.0)) {
                float spitPos[3];
                GetClientAbsOrigin(i, spitPos);
                SpawnAcidPool(spitPos, i, g_cvEliteAcidDuration.FloatValue);
                g_fNextSpitterTrail[i] = now + g_cvEliteAcidTrailInterval.FloatValue;
            }
        } else if (zClass == ZC_CHARGER) {
            int target = GetClientOfUserId(g_iChargerMaulTargetUserId[i]);
            if (IsValidSurvivor(target) && IsPlayerAlive(target) && IsPlayerIncapped(target)) {
                if (now >= g_fNextChargerMaulTick[i]) {
                    SDKHooks_TakeDamage(target, i, i, g_cvEliteChargerMaulDamage.FloatValue, DMG_CLUB);
                    g_fNextChargerMaulTick[i] = now + g_cvEliteChargerMaulTick.FloatValue;
                }
            } else {
                g_iChargerMaulTargetUserId[i] = 0;
                g_fNextChargerMaulTick[i] = 0.0;
            }
        }
    }

    return Plugin_Continue;
}
