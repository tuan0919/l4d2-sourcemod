#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION  "1.0.0"
#define MAXENTITIES     2048

#define UPGRADE_NONE        0
#define UPGRADE_INCENDIARY  1
#define UPGRADE_EXPLOSIVE   2

#define UPGBIT_INCENDIARY   (1 << 0)
#define UPGBIT_EXPLOSIVE    (1 << 1)

public Plugin myinfo =
{
    name        = "[L4D2] Tuan Upgrade Ammo Pack",
    author      = "Tuan",
    description = "Upgrade ammo pack gives full reserve as fire/explosive rounds. Normal reload blocked.",
    version     = PLUGIN_VERSION,
    url         = ""
};

// --- State ---
bool  g_bWeaponUpgraded[MAXENTITIES + 1];
int   g_iWeaponUpgradeType[MAXENTITIES + 1];  // UPGRADE_INCENDIARY or UPGRADE_EXPLOSIVE
int   g_iWeaponLastClip[MAXENTITIES + 1];     // track clip to detect reload

// --- Offsets ---
int g_iOffsetAmmo         = -1;
int g_iOffsetAmmoType     = -1;

ConVar g_hEnable;

// ============================================================
//  Plugin lifecycle
// ============================================================

public void OnPluginStart()
{
    g_hEnable = CreateConVar("tuan_upgrade_ammo_enable", "1", "Enable Tuan Upgrade Ammo Pack plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    AutoExecConfig(true, "Tuan_upgrade_ammo_pack");

    g_iOffsetAmmo     = FindSendPropInfo("CTerrorPlayer",       "m_iAmmo");
    g_iOffsetAmmoType = FindSendPropInfo("CBaseCombatWeapon",   "m_iPrimaryAmmoType");

    if (g_iOffsetAmmo == -1 || g_iOffsetAmmoType == -1)
        SetFailState("Failed to find required netprop offsets.");

    HookEvent("round_start",   Event_RoundStart,  EventHookMode_PostNoCopy);
    HookEvent("player_death",  Event_PlayerDeath, EventHookMode_Post);
    HookEvent("weapon_drop",   Event_WeaponDrop,  EventHookMode_Post);
    HookEvent("ammo_pickup",   Event_AmmoPickup,  EventHookMode_Pre);

    CreateTimer(0.25, Timer_PollWeapons, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ============================================================
//  Entity hooks — detect upgrade pack entities
// ============================================================

public void OnEntityCreated(int entity, const char[] classname)
{
    if (!IsValidEntityIndex(entity))
        return;

    if (strcmp(classname, "upgrade_ammo_incendiary", false) == 0
     || strcmp(classname, "upgrade_ammo_explosive",  false) == 0)
    {
        // Hook next frame so entity is fully initialised
        RequestFrame(Frame_HookUpgradeEnt, EntIndexToEntRef(entity));
    }
}

void Frame_HookUpgradeEnt(int entRef)
{
    int entity = EntRefToEntIndex(entRef);
    if (entity == INVALID_ENT_REFERENCE)
        return;

    SDKHook(entity, SDKHook_Use, OnUpgradeUse);
}

public void OnEntityDestroyed(int entity)
{
    if (entity < 1 || entity > MAXENTITIES)
        return;

    ClearWeaponState(entity);
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

    // If weapon already upgraded with a DIFFERENT type — notify and bail
    if (g_bWeaponUpgraded[weapon] && g_iWeaponUpgradeType[weapon] != packType)
    {
        char typeName[32];
        GetUpgradeName(g_iWeaponUpgradeType[weapon], typeName, sizeof(typeName));
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Súng đang dùng đạn \x05%s\x01. Không thể đổi loại.", typeName);
        return Plugin_Continue;
    }

    // Calculate total ammo: clip + reserve
    int clip    = GetEntProp(weapon, Prop_Send, "m_iClip1");
    int reserve = GetReserveAmmo(client, weapon);
    int total   = clip + reserve;
    if (total > 254) total = 254;
    if (total < 1)   total = 1;

    // Apply upgrade bits
    int upgBit = (packType == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
    int bits   = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits |= upgBit;
    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);

    // Set upgraded ammo count
    SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", total);

    // Mark weapon state
    bool isRefill = g_bWeaponUpgraded[weapon];
    g_bWeaponUpgraded[weapon]    = true;
    g_iWeaponUpgradeType[weapon] = packType;
    g_iWeaponLastClip[weapon]    = GetEntProp(weapon, Prop_Send, "m_iClip1");

    char typeName[32];
    GetUpgradeName(packType, typeName, sizeof(typeName));

    if (isRefill)
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Refill \x05%d\x01 viên đạn \x05%s\x01.", total, typeName);
    else
        PrintToChat(client, "\x04[Upgrade Ammo]\x01 Nạp \x05%d\x01 viên đạn \x05%s\x01. Chỉ refill bằng pack cùng loại.", total, typeName);

    return Plugin_Continue;
}

// ============================================================
//  Poll timer: sync upgrade ammo after reload / maintain state
// ============================================================

public Action Timer_PollWeapons(Handle timer)
{
    if (!g_hEnable.BoolValue)
        return Plugin_Continue;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidClient(client) || !IsPlayerAlive(client) || GetClientTeam(client) != 2)
            continue;

        int weapon = GetPlayerWeaponSlot(client, 0);
        if (!IsValidEntity(weapon) || weapon <= MaxClients)
            continue;

        if (!g_bWeaponUpgraded[weapon])
            continue;

        int clip = GetEntProp(weapon, Prop_Send, "m_iClip1");

        // Detect reload completed: clip increased from last known value
        if (clip > g_iWeaponLastClip[weapon] && g_iWeaponLastClip[weapon] >= 0)
        {
            // After reload, sync upgrade ammo = new clip size
            SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", clip);
        }

        // Re-apply upgrade bit in case game cleared it
        int upgBit = (g_iWeaponUpgradeType[weapon] == UPGRADE_INCENDIARY) ? UPGBIT_INCENDIARY : UPGBIT_EXPLOSIVE;
        int bits   = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
        if (!(bits & upgBit))
        {
            bits |= upgBit;
            SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);
        }

        g_iWeaponLastClip[weapon] = clip;
    }

    return Plugin_Continue;
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
    if (weapon < 1 || weapon > MAXENTITIES)
        return;

    g_bWeaponUpgraded[weapon]    = false;
    g_iWeaponUpgradeType[weapon] = UPGRADE_NONE;
    g_iWeaponLastClip[weapon]    = -1;
}

int GetReserveAmmo(int client, int weapon)
{
    int ammoTypeOffset = GetEntData(weapon, g_iOffsetAmmoType) * 4;
    return GetEntData(client, g_iOffsetAmmo + ammoTypeOffset);
}

void GetUpgradeName(int upgradeType, char[] buffer, int maxlen)
{
    switch (upgradeType)
    {
        case UPGRADE_INCENDIARY: strcopy(buffer, maxlen, "Lửa");
        case UPGRADE_EXPLOSIVE:  strcopy(buffer, maxlen, "Nổ");
        default:                 strcopy(buffer, maxlen, "Không rõ");
    }
}

bool IsValidClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsValidEntityIndex(int entity)
{
    return (entity > MaxClients && entity <= MAXENTITIES);
}
