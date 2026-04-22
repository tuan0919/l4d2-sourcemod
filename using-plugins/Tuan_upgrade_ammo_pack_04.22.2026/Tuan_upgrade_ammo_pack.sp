#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION  "2.1.0"
#define MAXENTITIES     2048

#define UPGRADE_NONE        0
#define UPGRADE_INCENDIARY  1
#define UPGRADE_EXPLOSIVE   2

#define UPGBIT_INCENDIARY   (1 << 0)
#define UPGBIT_EXPLOSIVE    (1 << 1)

#define ZC_TANK             8

public Plugin myinfo =
{
    name        = "[L4D2] Tuan Upgrade Ammo Pack",
    author      = "Tuan",
    description = "Upgrade ammo pack makes every bullet fire/explosive via OnTakeDamage.",
    version     = PLUGIN_VERSION,
    url         = ""
};

// --- State per weapon entity ---
bool g_bWeaponUpgraded[MAXENTITIES + 1];
int  g_iWeaponUpgradeType[MAXENTITIES + 1];

ConVar g_hEnable;

bool g_bLateLoad;

// ============================================================
//  Load
// ============================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }
    g_bLateLoad = late;
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hEnable = CreateConVar("tuan_upgrade_ammo_enable", "1", "Enable Tuan Upgrade Ammo Pack plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "Tuan_upgrade_ammo_pack");

    HookEvent("round_start",   Event_RoundStart,  EventHookMode_PostNoCopy);
    HookEvent("player_death",  Event_PlayerDeath,  EventHookMode_Post);
    HookEvent("weapon_drop",   Event_WeaponDrop,   EventHookMode_Post);
    HookEvent("ammo_pickup",   Event_AmmoPickup,   EventHookMode_Pre);

    if (g_bLateLoad)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (IsClientInGame(client))
            {
                SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage_Client);
                SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
            }
        }
        int entity = -1;
        while ((entity = FindEntityByClassname(entity, "infected")) != -1)
        {
            if (entity > 0)
                SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Infected);
        }
        entity = -1;
        while ((entity = FindEntityByClassname(entity, "witch")) != -1)
        {
            if (entity > 0)
                SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Infected);
        }
    }
}

// ============================================================
//  Hook entities for OnTakeDamage + FireBulletsPost
// ============================================================

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage_Client);
    SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity < 1)
        return;

    if (strcmp(classname, "infected", false) == 0 || strcmp(classname, "witch", false) == 0)
    {
        SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage_Infected);
    }
    else if (entity > MaxClients && entity <= MAXENTITIES)
    {
        if (strcmp(classname, "upgrade_ammo_incendiary", false) == 0
         || strcmp(classname, "upgrade_ammo_explosive",  false) == 0)
        {
            RequestFrame(Frame_HookUpgradeEnt, EntIndexToEntRef(entity));
        }
    }
}

public void OnEntityDestroyed(int entity)
{
    if (entity > MaxClients && entity <= MAXENTITIES)
        ClearWeaponState(entity);
}

void Frame_HookUpgradeEnt(int entRef)
{
    int entity = EntRefToEntIndex(entRef);
    if (entity == INVALID_ENT_REFERENCE)
        return;

    SDKHook(entity, SDKHook_Use, OnUpgradeUse);
}

// ============================================================
//  FireBulletsPost: maintain visual tracer after each shot
// ============================================================

void OnFireBulletsPost(int client, int shots, const char[] weaponname)
{
    if (!g_hEnable.BoolValue)
        return;

    if (!IsClientInGame(client) || GetClientTeam(client) != 2 || !IsPlayerAlive(client))
        return;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients || weapon > MAXENTITIES)
        return;

    if (!g_bWeaponUpgraded[weapon])
        return;

    // Sync m_nUpgradedPrimaryAmmoLoaded = clip so game renders upgrade tracer
    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", clip > 0 ? clip : 1);

    // Re-apply upgradeBitVec in case game cleared it
    int upgBit = (g_iWeaponUpgradeType[weapon] == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
    int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    if (!(bits & upgBit))
    {
        bits |= upgBit;
        SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);
    }
}

// ============================================================
//  OnTakeDamage: inject DMG_BURN / DMG_BLAST
// ============================================================

Action OnTakeDamage_Client(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    if (weapon == -1 || attacker < 1 || attacker > MaxClients)
        return Plugin_Continue;

    if (!IsClientInGame(attacker) || GetClientTeam(attacker) != 2 || !IsPlayerAlive(attacker))
        return Plugin_Continue;

    if (!IsClientInGame(victim) || GetClientTeam(victim) != 3)
        return Plugin_Continue;

    return ApplyUpgradeDamage(victim, weapon, damagetype);
}

Action OnTakeDamage_Infected(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    if (weapon == -1 || attacker < 1 || attacker > MaxClients)
        return Plugin_Continue;

    if (!IsClientInGame(attacker) || GetClientTeam(attacker) != 2 || !IsPlayerAlive(attacker))
        return Plugin_Continue;

    return ApplyUpgradeDamage(victim, weapon, damagetype);
}

Action ApplyUpgradeDamage(int victim, int weapon, int &damagetype)
{
    if (!IsValidEntity(weapon) || weapon <= MaxClients || weapon > MAXENTITIES)
        return Plugin_Continue;

    if (!g_bWeaponUpgraded[weapon])
        return Plugin_Continue;

    int upgradeType = g_iWeaponUpgradeType[weapon];
    if (upgradeType == UPGRADE_INCENDIARY)
    {
        damagetype |= DMG_BURN;
        return Plugin_Changed;
    }
    else if (upgradeType == UPGRADE_EXPLOSIVE)
    {
        // Skip DMG_BLAST on Tank — prevents stagger
        if (victim >= 1 && victim <= MaxClients && IsClientInGame(victim))
        {
            if (GetEntProp(victim, Prop_Send, "m_zombieClass") == ZC_TANK)
                return Plugin_Continue;
        }
        damagetype |= DMG_BLAST;
        return Plugin_Changed;
    }

    return Plugin_Continue;
}

// ============================================================
//  Core: upgrade pack used
// ============================================================

Action OnUpgradeUse(int entity, int activator, int caller, UseType type, float value)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    int client = caller;
    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
        return Plugin_Continue;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return Plugin_Continue;

    // Determine pack type
    char classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));
    int packType = (strcmp(classname, "upgrade_ammo_explosive", false) == 0)
                    ? UPGRADE_EXPLOSIVE
                    : UPGRADE_INCENDIARY;

    // Already upgraded with different type — block
    if (g_bWeaponUpgraded[weapon] && g_iWeaponUpgradeType[weapon] != packType)
    {
        char typeName[32];
        GetUpgradeName(g_iWeaponUpgradeType[weapon], typeName, sizeof(typeName));
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Sung dang dung dan \x05%s\x01. Khong the doi loai.", typeName);
        return Plugin_Continue;
    }

    // Already upgraded with same type — no-op
    if (g_bWeaponUpgraded[weapon])
    {
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Sung da duoc nang cap roi.");
        return Plugin_Continue;
    }

    // Mark weapon state
    g_bWeaponUpgraded[weapon]    = true;
    g_iWeaponUpgradeType[weapon] = packType;

    // Apply visual via RequestFrame (after game engine processes the pack)
    RequestFrame(Frame_ApplyVisual, EntIndexToEntRef(weapon));

    char typeName[32];
    GetUpgradeName(packType, typeName, sizeof(typeName));
    PrintToChat(client, "\x04[Upgrade Ammo]\x01 Nap dan \x05%s\x01 vinh vien cho sung nay.", typeName);

    return Plugin_Continue;
}

void Frame_ApplyVisual(int weaponRef)
{
    int weapon = EntRefToEntIndex(weaponRef);
    if (weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
        return;

    if (!g_bWeaponUpgraded[weapon])
        return;

    int upgBit = (g_iWeaponUpgradeType[weapon] == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
    int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits |= upgBit;
    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

    // Also set initial m_nUpgradedPrimaryAmmoLoaded for immediate visual
    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", clip > 0 ? clip : 1);
}

// ============================================================
//  Block ammo pile pickup
// ============================================================

Action Event_AmmoPickup(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client) != 2)
        return Plugin_Continue;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return Plugin_Continue;

    if (g_bWeaponUpgraded[weapon])
        return Plugin_Handled;

    return Plugin_Continue;
}

// ============================================================
//  Reset on drop / death / round
// ============================================================

Action Event_WeaponDrop(Event event, const char[] name, bool dontBroadcast)
{
    int weapon = event.GetInt("propid");
    if (IsValidEntity(weapon) && weapon > MaxClients)
        ClearWeaponState(weapon);

    return Plugin_Continue;
}

Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client))
        return Plugin_Continue;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (IsValidEntity(weapon) && weapon > MaxClients)
        ClearWeaponState(weapon);

    return Plugin_Continue;
}

Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for (int i = 1; i <= MAXENTITIES; i++)
        ClearWeaponState(i);

    return Plugin_Continue;
}

// ============================================================
//  Helpers
// ============================================================

void ClearWeaponState(int weapon)
{
    g_bWeaponUpgraded[weapon]    = false;
    g_iWeaponUpgradeType[weapon] = UPGRADE_NONE;
}

void GetUpgradeName(int upgradeType, char[] buffer, int maxlen)
{
    switch (upgradeType)
    {
        case UPGRADE_INCENDIARY: strcopy(buffer, maxlen, "Lua");
        case UPGRADE_EXPLOSIVE:  strcopy(buffer, maxlen, "No");
        default:                 strcopy(buffer, maxlen, "Khong ro");
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}
