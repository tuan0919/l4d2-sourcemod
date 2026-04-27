#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION  "3.3.4"
#define MAXENTITIES     2048

#define UPGRADE_NONE        0
#define UPGRADE_INCENDIARY  1
#define UPGRADE_EXPLOSIVE   2

#define UPGBIT_INCENDIARY   (1 << 0)
#define UPGBIT_EXPLOSIVE    (1 << 1)

#define RELOAD_PROP_GRACE_TIME       0.15
#define RELOAD_FALLBACK_TIME         3.0
#define RELOAD_SHOTGUN_FALLBACK_TIME 8.0

public Plugin myinfo =
{
    name        = "[L4D2] Tuan Upgrade Ammo Pack",
    author      = "Tuan",
    description = "Revamped upgrade ammo: permanent fire/explosive bullets for upgraded weapons.",
    version     = PLUGIN_VERSION,
    url         = ""
};

// --- State per weapon entity ---
bool g_bWeaponUpgraded[MAXENTITIES + 1];
int  g_iWeaponUpgradeType[MAXENTITIES + 1];
bool g_bWeaponReloading[MAXENTITIES + 1];
int  g_iReloadStartClip[MAXENTITIES + 1];
float g_fReloadStartTime[MAXENTITIES + 1];

bool g_bClientReloadWatch[MAXPLAYERS + 1];

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

    HookEvent("ammo_pickup",       Event_AmmoPickup,    EventHookMode_PostNoCopy);
    HookEvent("weapon_reload",     Event_WeaponReload,  EventHookMode_Pre);
    HookEvent("player_spawn",      Event_PlayerSpawn,   EventHookMode_Post);

    if (g_bLateLoad)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (IsClientInGame(client))
            {
                SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
                SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
            }
        }
    }
}

// ============================================================
//  Hook entities
// ============================================================

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_FireBulletsPost, OnFireBulletsPost);
    SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnClientDisconnect(int client)
{
    StopReloadWatch(client);
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= MaxClients || entity > MAXENTITIES)
        return;

    if (strcmp(classname, "upgrade_ammo_incendiary", false) == 0
     || strcmp(classname, "upgrade_ammo_explosive",  false) == 0)
    {
        RequestFrame(Frame_HookUpgradeEnt, EntIndexToEntRef(entity));
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

public void OnWeaponEquipPost(int client, int weapon)
{
    if (!g_hEnable.BoolValue)
        return;

    if (!IsValidClient(client) || GetClientTeam(client) != 2)
        return;

    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return;

    RequestFrame(Frame_ImportWeaponState, EntIndexToEntRef(weapon));
}

void Frame_ImportWeaponState(int weaponRef)
{
    int weapon = EntRefToEntIndex(weaponRef);
    if (weapon == INVALID_ENT_REFERENCE)
        return;

    RefreshWeaponUpgrade(weapon);
}

Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client) != 2)
        return Plugin_Continue;

    CreateTimer(0.5, Timer_ImportCurrentPrimary, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}

public void L4D2_OnSaveWeaponHxGiveC(int client)
{
    if (!g_hEnable.BoolValue)
        return;

    ImportClientPrimaryUpgrade(client);
}

Action Timer_ImportCurrentPrimary(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (IsValidClient(client))
    {
        ImportClientPrimaryUpgrade(client);
    }

    return Plugin_Stop;
}

void ImportClientPrimaryUpgrade(int client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
        return;

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return;

    RefreshWeaponUpgrade(weapon);
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

    if (!g_bWeaponUpgraded[weapon] && !TryImportUpgradeFromWeaponProps(weapon))
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
//  WeaponReload: clear visual while game reloads so HUD shows real ammo
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

    if (!g_bWeaponUpgraded[weapon] && !TryImportUpgradeFromWeaponProps(weapon))
        return Plugin_Continue;

    // Clear upgrade visual during reload so HUD shows the real clip/reserve.
    // The watcher restores it after mag reload completes, shotgun reload ends,
    // or reload gets interrupted by stagger/SI control.
    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    g_iReloadStartClip[weapon] = clip;
    g_fReloadStartTime[weapon] = GetGameTime();
    g_bWeaponReloading[weapon] = true;

    ClearUpgradeVisualNow(weapon);

    // Watch for reload completion via PostThink
    StartReloadWatch(client);

    return Plugin_Continue;
}

// ============================================================
//  PostThink: restore upgrade visual when reload ends or is interrupted
// ============================================================

public void OnPostThink_ReloadWatch(int client)
{
    if (!IsValidClient(client) || !IsPlayerAlive(client))
    {
        StopReloadWatch(client);
        return;
    }

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEntity(weapon) || weapon <= MaxClients || !g_bWeaponUpgraded[weapon])
    {
        StopReloadWatch(client);
        return;
    }

    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    if (!IsShotgunWeapon(weapon) && clip > g_iReloadStartClip[weapon])
    {
        FinishReloadWatch(client, weapon);
        return;
    }

    if (ShouldContinueReloadWatch(client, weapon))
        return;

    FinishReloadWatch(client, weapon);
}

// ============================================================
//  Core: upgrade pack used
// ============================================================

Action OnUpgradeUse(int entity, int activator, int caller, UseType type, float value)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    int client = caller;
    if (!IsValidClient(client))
        client = activator;

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

    // Apply / switch upgrade type freely
    bool isSwitch = g_bWeaponUpgraded[weapon] && g_iWeaponUpgradeType[weapon] != packType;

    g_bWeaponUpgraded[weapon]    = true;
    g_iWeaponUpgradeType[weapon] = packType;
    g_bWeaponReloading[weapon]   = false;

    // Apply visual after game engine processes the pack
    RequestFrame(Frame_ApplyVisual, EntIndexToEntRef(weapon));

    char typeName[32];
    GetUpgradeName(packType, typeName, sizeof(typeName));
    if (isSwitch)
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Switched to \x05%s\x01 ammo.", typeName);
    else
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Weapon upgraded with permanent \x05%s\x01 ammo.", typeName);

    return Plugin_Continue;
}

void Frame_ApplyVisual(int weaponRef)
{
    int weapon = EntRefToEntIndex(weaponRef);
    if (weapon == INVALID_ENT_REFERENCE || !IsValidEntity(weapon))
        return;

    ApplyUpgradeVisualNow(weapon);
}

// ============================================================
//  Ammo pickup
// ============================================================

void Event_AmmoPickup(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_hEnable.BoolValue)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidClient(client) || GetClientTeam(client) != 2)
        return;

    CreateTimer(0.1, Timer_ImportCurrentPrimary, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
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
    g_fReloadStartTime[weapon]   = 0.0;
}

void RefreshWeaponUpgrade(int weapon)
{
    if (!IsValidEntity(weapon) || weapon <= MaxClients || weapon > MAXENTITIES)
        return;

    if (g_bWeaponUpgraded[weapon])
    {
        ApplyUpgradeVisualNow(weapon);
        return;
    }

    TryImportUpgradeFromWeaponProps(weapon);
}

bool TryImportUpgradeFromWeaponProps(int weapon)
{
    if (!IsValidEntity(weapon) || weapon <= MaxClients || weapon > MAXENTITIES)
        return false;

    if (!IsPrimaryWeaponEntity(weapon))
        return false;

    if (!HasEntProp(weapon, Prop_Send, "m_upgradeBitVec"))
        return false;

    int upgradeType = GetUpgradeTypeFromBits(GetEntProp(weapon, Prop_Send, "m_upgradeBitVec"));
    if (upgradeType == UPGRADE_NONE)
        return false;

    g_bWeaponUpgraded[weapon]    = true;
    g_iWeaponUpgradeType[weapon] = upgradeType;
    g_bWeaponReloading[weapon]   = false;

    ApplyUpgradeVisualNow(weapon);
    return true;
}

int GetUpgradeTypeFromBits(int bits)
{
    if (bits & UPGBIT_EXPLOSIVE)
        return UPGRADE_EXPLOSIVE;

    if (bits & UPGBIT_INCENDIARY)
        return UPGRADE_INCENDIARY;

    return UPGRADE_NONE;
}

void ApplyUpgradeVisualNow(int weapon)
{
    if (!IsValidEntity(weapon) || weapon <= MaxClients || !g_bWeaponUpgraded[weapon])
        return;

    int upgBit = (g_iWeaponUpgradeType[weapon] == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
    int bits   = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits |= upgBit;
    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

    int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");
    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", clip > 0 ? clip : 1);
}

void ClearUpgradeVisualNow(int weapon)
{
    if (!IsValidEntity(weapon) || weapon <= MaxClients)
        return;

    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", 0);

    int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits &= ~(UPGBIT_INCENDIARY | UPGBIT_EXPLOSIVE);
    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);
}

void FinishReloadWatch(int client, int weapon)
{
    g_bWeaponReloading[weapon] = false;
    ApplyUpgradeVisualNow(weapon);
    StopReloadWatch(client);
}

void StartReloadWatch(int client)
{
    if (g_bClientReloadWatch[client])
        return;

    g_bClientReloadWatch[client] = true;
    SDKHook(client, SDKHook_PostThink, OnPostThink_ReloadWatch);
}

void StopReloadWatch(int client)
{
    if (!g_bClientReloadWatch[client])
        return;

    g_bClientReloadWatch[client] = false;
    SDKUnhook(client, SDKHook_PostThink, OnPostThink_ReloadWatch);
}

bool ShouldContinueReloadWatch(int client, int weapon)
{
    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (active != weapon)
        return false;

    float elapsed = GetGameTime() - g_fReloadStartTime[weapon];
    if (elapsed < RELOAD_PROP_GRACE_TIME)
        return true;

    bool hasReloadProp = false;
    if (HasEntProp(weapon, Prop_Send, "m_bInReload"))
    {
        hasReloadProp = true;
        if (GetEntProp(weapon, Prop_Send, "m_bInReload") != 0)
            return true;
    }

    if (HasEntProp(weapon, Prop_Send, "m_reloadState"))
    {
        hasReloadProp = true;
        if (GetEntProp(weapon, Prop_Send, "m_reloadState") != 0)
            return true;
    }

    if (hasReloadProp)
        return false;

    return elapsed < (IsShotgunWeapon(weapon) ? RELOAD_SHOTGUN_FALLBACK_TIME : RELOAD_FALLBACK_TIME);
}

bool IsShotgunWeapon(int weapon)
{
    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    return StrEqual(classname, "weapon_pumpshotgun", false)
        || StrEqual(classname, "weapon_shotgun_chrome", false)
        || StrEqual(classname, "weapon_autoshotgun", false)
        || StrEqual(classname, "weapon_shotgun_spas", false);
}

bool IsPrimaryWeaponEntity(int weapon)
{
    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    return StrEqual(classname, "weapon_rifle", false)
        || StrEqual(classname, "weapon_rifle_ak47", false)
        || StrEqual(classname, "weapon_rifle_desert", false)
        || StrEqual(classname, "weapon_rifle_sg552", false)
        || StrEqual(classname, "weapon_rifle_m60", false)
        || StrEqual(classname, "weapon_smg", false)
        || StrEqual(classname, "weapon_smg_silenced", false)
        || StrEqual(classname, "weapon_smg_mp5", false)
        || StrEqual(classname, "weapon_pumpshotgun", false)
        || StrEqual(classname, "weapon_shotgun_chrome", false)
        || StrEqual(classname, "weapon_autoshotgun", false)
        || StrEqual(classname, "weapon_shotgun_spas", false)
        || StrEqual(classname, "weapon_hunting_rifle", false)
        || StrEqual(classname, "weapon_sniper_military", false)
        || StrEqual(classname, "weapon_sniper_scout", false)
        || StrEqual(classname, "weapon_sniper_awp", false);
}

void GetUpgradeName(int upgradeType, char[] buffer, int maxlen)
{
    switch (upgradeType)
    {
        case UPGRADE_INCENDIARY: strcopy(buffer, maxlen, "Incendiary");
        case UPGRADE_EXPLOSIVE:  strcopy(buffer, maxlen, "Explosive");
        default:                 strcopy(buffer, maxlen, "Unknown");
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}


