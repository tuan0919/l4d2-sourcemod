#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION  "3.2.0"
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
    description = "Revamped upgrade ammo: permanent fire/explosive bullets, persists across rounds and maps.",
    version     = PLUGIN_VERSION,
    url         = ""
};

// --- State per weapon entity ---
bool g_bWeaponUpgraded[MAXENTITIES + 1];
int  g_iWeaponUpgradeType[MAXENTITIES + 1];
bool g_bWeaponReloading[MAXENTITIES + 1];
int  g_iReloadStartClip[MAXENTITIES + 1];

// --- Save state per client (for map transition) ---
bool g_bClientHasSave[MAXPLAYERS + 1];
int  g_iClientSaveType[MAXPLAYERS + 1];
char g_sClientSaveWeapon[MAXPLAYERS + 1][64];

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

    HookEvent("ammo_pickup",       Event_AmmoPickup,    EventHookMode_Pre);
    HookEvent("weapon_reload",     Event_WeaponReload,  EventHookMode_Pre);
    HookEvent("map_transition",    Event_SaveAll,       EventHookMode_PostNoCopy);
    HookEvent("mission_lost",      Event_SaveAll,       EventHookMode_PostNoCopy);
    HookEvent("player_spawn",      Event_PlayerSpawn,   EventHookMode_Post);

    if (g_bLateLoad)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (IsClientInGame(client))
            {
                SDKHook(client, SDKHook_OnTakeDamage,    OnTakeDamage_Client);
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
//  Hook entities
// ============================================================

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamage,    OnTakeDamage_Client);
    SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
}

public void OnClientDisconnect(int client)
{
    // Save before disconnect so bot replacement can inherit
    SaveClientUpgradeState(client);
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
//  Save / Restore for map transition
// ============================================================

Action Event_SaveAll(Event event, const char[] name, bool dontBroadcast)
{
    for (int client = 1; client <= MaxClients; client++)
        SaveClientUpgradeState(client);

    return Plugin_Continue;
}

void SaveClientUpgradeState(int client)
{
    g_bClientHasSave[client] = false;

    if (!IsValidClient(client) || GetClientTeam(client) != 2)
        return;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return;

    if (!g_bWeaponUpgraded[weapon])
        return;

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    g_bClientHasSave[client]  = true;
    g_iClientSaveType[client] = g_iWeaponUpgradeType[weapon];
    strcopy(g_sClientSaveWeapon[client], sizeof(g_sClientSaveWeapon[]), classname);
}

Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || IsFakeClient(client) || GetClientTeam(client) != 2)
        return Plugin_Continue;

    if (!g_bClientHasSave[client])
        return Plugin_Continue;

    // Delay restore — weapon may not be ready yet at spawn
    CreateTimer(0.5, Timer_RestoreUpgrade, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}

Action Timer_RestoreUpgrade(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
        return Plugin_Stop;

    if (!g_bClientHasSave[client])
        return Plugin_Stop;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return Plugin_Stop;

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    // Only restore if weapon classname matches saved
    if (!StrEqual(classname, g_sClientSaveWeapon[client], false))
        return Plugin_Stop;

    // Restore upgrade state
    g_bWeaponUpgraded[weapon]    = true;
    g_iWeaponUpgradeType[weapon] = g_iClientSaveType[client];
    g_bWeaponReloading[weapon]   = false;

    // Apply visual
    RequestFrame(Frame_ApplyVisual, EntIndexToEntRef(weapon));

    char typeName[32];
    GetUpgradeName(g_iClientSaveType[client], typeName, sizeof(typeName));
    PrintToChat(client, "\x04[Upgrade Ammo]\x01 Dan \x05%s\x01 da duoc khoi phuc.", typeName);

    g_bClientHasSave[client] = false;

    return Plugin_Stop;
}

// ============================================================
//  FireBulletsPost: sync m_nUpgradedPrimaryAmmoLoaded = clip
// ============================================================

public void OnFireBulletsPost(int client, int shots, const char[] weaponname)
{
    if (!g_hEnable.BoolValue)
        return;

    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
        return;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return;

    if (!g_bWeaponUpgraded[weapon])
        return;

    // Skip sync during reload
    if (g_bWeaponReloading[weapon])
        return;

    // Only sync if active weapon is primary
    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (active != weapon)
        return;

    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", clip > 0 ? clip : 1);

    // Re-apply upgradeBitVec in case game cleared it
    int upgBit = (g_iWeaponUpgradeType[weapon] == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
    int bits   = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    if (!(bits & upgBit))
    {
        bits |= upgBit;
        SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);
    }
}

// ============================================================
//  WeaponReload: clear visual so HUD shows real ammo
// ============================================================

Action Event_WeaponReload(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client) != 2)
        return Plugin_Continue;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return Plugin_Continue;

    if (!g_bWeaponUpgraded[weapon])
        return Plugin_Continue;

    // Save clip at reload start for comparison
    g_iReloadStartClip[weapon] = GetEntProp(weapon, Prop_Send, "m_iClip1");
    g_bWeaponReloading[weapon] = true;

    // Clear upgrade visual so HUD shows real ammo
    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", 0);
    int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits &= ~(UPGBIT_INCENDIARY | UPGBIT_EXPLOSIVE);
    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

    // Watch for reload completion via PostThink
    SDKHook(client, SDKHook_PostThink, OnPostThink_ReloadWatch);

    return Plugin_Continue;
}

// ============================================================
//  PostThink: detect reload complete, restore visual
// ============================================================

public void OnPostThink_ReloadWatch(int client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        SDKUnhook(client, SDKHook_PostThink, OnPostThink_ReloadWatch);
        return;
    }

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients || !g_bWeaponUpgraded[weapon])
    {
        SDKUnhook(client, SDKHook_PostThink, OnPostThink_ReloadWatch);
        return;
    }

    // Reload complete: clip increased from start value
    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    if (clip > g_iReloadStartClip[weapon])
    {
        g_bWeaponReloading[weapon] = false;

        // Restore upgrade visual
        SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", clip);
        int upgBit = (g_iWeaponUpgradeType[weapon] == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
        int bits   = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
        bits |= upgBit;
        SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

        SDKUnhook(client, SDKHook_PostThink, OnPostThink_ReloadWatch);
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

    if (upgradeType == UPGRADE_EXPLOSIVE)
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
    else if (upgradeType == UPGRADE_INCENDIARY)
    {
        damagetype |= DMG_BURN;
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
    g_bWeaponReloading[weapon]   = false;

    // Apply visual after game engine processes the pack
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
    int bits   = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits |= upgBit;
    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

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
//  Helpers
// ============================================================

void ClearWeaponState(int weapon)
{
    g_bWeaponUpgraded[weapon]    = false;
    g_iWeaponUpgradeType[weapon] = UPGRADE_NONE;
    g_bWeaponReloading[weapon]   = false;
    g_iReloadStartClip[weapon]   = 0;
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
