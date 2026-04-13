#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <Tuan_custom_forwards>
#include <tuan_notify_core>

#define PLUGIN_VERSION "1.0.0"
#define CVAR_PREFIX "tuan_notify_member_evt_"
#define HUD_NAME_VISIBLE 14

#define TYPE_GASCAN 1
#define TYPE_FUEL_BARREL 2
#define TYPE_PROPANECANISTER 3
#define TYPE_OXYGENTANK 4
#define TYPE_BARRICADE_GASCAN 5
#define TYPE_GAS_PUMP 6
#define TYPE_FIREWORKS_CRATE 7
#define TYPE_OIL_DRUM_EXPLOSIVE 8

#define IsClient(%1) ((1 <= %1 <= MaxClients) && IsClientInGame(%1))

ConVar g_hEnable;
ConVar g_hNotifyHealedOther;
ConVar g_hNotifyGoBnW;
ConVar g_hNotifyRevivedOther;
ConVar g_hNotifySelfRevived;
ConVar g_hNotifyThrowMolotov;
ConVar g_hNotifyThrowPipebomb;
ConVar g_hNotifyThrowVomitjar;
ConVar g_hNotifyExplodeGascan;
ConVar g_hNotifyExplodeFuelBarrel;
ConVar g_hNotifyExplodePropane;
ConVar g_hNotifyExplodeOxygen;
ConVar g_hNotifyExplodeBarricade;
ConVar g_hNotifyExplodeGasPump;
ConVar g_hNotifyExplodeFireworks;
ConVar g_hNotifyExplodeOilDrum;
ConVar g_hNotifyGearGive;
ConVar g_hNotifyGearGrab;
ConVar g_hNotifyGearSwap;

bool g_bEnable;
bool g_bNotifyHealedOther;
bool g_bNotifyGoBnW;
bool g_bNotifyRevivedOther;
bool g_bNotifySelfRevived;
bool g_bNotifyThrowMolotov;
bool g_bNotifyThrowPipebomb;
bool g_bNotifyThrowVomitjar;
bool g_bNotifyExplodeGascan;
bool g_bNotifyExplodeFuelBarrel;
bool g_bNotifyExplodePropane;
bool g_bNotifyExplodeOxygen;
bool g_bNotifyExplodeBarricade;
bool g_bNotifyExplodeGasPump;
bool g_bNotifyExplodeFireworks;
bool g_bNotifyExplodeOilDrum;
bool g_bNotifyGearGive;
bool g_bNotifyGearGrab;
bool g_bNotifyGearSwap;
bool g_bCoreReady;

StringMap g_hWeaponNameMap;

static const char WEAPON_NAMES_KEYs[][] = {
    "weapon_adrenaline",
    "weapon_pain_pills",
    "weapon_molotov",
    "weapon_pipe_bomb",
    "weapon_vomitjar",
    "weapon_first_aid_kit",
    "weapon_upgradepack_explosive",
    "weapon_upgradepack_incendiary",
    "weapon_defibrillator"
};

static const char WEAPON_NAMES_VALUEs[][] = {
    "adrenaline",
    "pain pills",
    "molotov",
    "pipebomb",
    "vomitjar",
    "first aid kit",
    "upgradepack explosive",
    "upgradepack incendiary",
    "defibrillator"
};

public Plugin myinfo =
{
    name = "Tuan Notify Member - Events",
    author = "Codex",
    description = "Publishes BW/throwable/explosion/gear notifications into tuan_notify_core",
    version = PLUGIN_VERSION,
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("TuanNotify_PublishInfo");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hEnable = CreateConVar(CVAR_PREFIX ... "enable", "1", "Enable Events member plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyHealedOther = CreateConVar(CVAR_PREFIX ... "notify_healed_other", "1", "Publish healed-other notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyGoBnW = CreateConVar(CVAR_PREFIX ... "notify_go_bnw", "1", "Publish go-black-and-white notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyRevivedOther = CreateConVar(CVAR_PREFIX ... "notify_revived_other", "1", "Publish revived-other notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifySelfRevived = CreateConVar(CVAR_PREFIX ... "notify_self_revived", "1", "Publish self-revived notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hNotifyThrowMolotov = CreateConVar(CVAR_PREFIX ... "notify_throw_molotov", "1", "Publish molotov throw notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyThrowPipebomb = CreateConVar(CVAR_PREFIX ... "notify_throw_pipebomb", "1", "Publish pipebomb throw notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyThrowVomitjar = CreateConVar(CVAR_PREFIX ... "notify_throw_vomitjar", "1", "Publish vomitjar throw notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hNotifyExplodeGascan = CreateConVar(CVAR_PREFIX ... "notify_explode_gascan", "1", "Publish gascan explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodeFuelBarrel = CreateConVar(CVAR_PREFIX ... "notify_explode_fuel_barrel", "1", "Publish fuel barrel explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodePropane = CreateConVar(CVAR_PREFIX ... "notify_explode_propanecanister", "1", "Publish propane canister explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodeOxygen = CreateConVar(CVAR_PREFIX ... "notify_explode_oxygentank", "1", "Publish oxygen tank explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodeBarricade = CreateConVar(CVAR_PREFIX ... "notify_explode_barricade_gascan", "1", "Publish barricade gascan explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodeGasPump = CreateConVar(CVAR_PREFIX ... "notify_explode_gas_pump", "1", "Publish gas pump explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodeFireworks = CreateConVar(CVAR_PREFIX ... "notify_explode_fireworks_crate", "1", "Publish fireworks crate explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyExplodeOilDrum = CreateConVar(CVAR_PREFIX ... "notify_explode_oil_drum", "1", "Publish oil drum explosion notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_hNotifyGearGive = CreateConVar(CVAR_PREFIX ... "notify_gear_give", "1", "Publish gear give notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyGearGrab = CreateConVar(CVAR_PREFIX ... "notify_gear_grab", "1", "Publish gear grab notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hNotifyGearSwap = CreateConVar(CVAR_PREFIX ... "notify_gear_swap", "1", "Publish gear swap notifications.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

    HookConVarChange(g_hEnable, OnConVarChanged);
    HookConVarChange(g_hNotifyHealedOther, OnConVarChanged);
    HookConVarChange(g_hNotifyGoBnW, OnConVarChanged);
    HookConVarChange(g_hNotifyRevivedOther, OnConVarChanged);
    HookConVarChange(g_hNotifySelfRevived, OnConVarChanged);
    HookConVarChange(g_hNotifyThrowMolotov, OnConVarChanged);
    HookConVarChange(g_hNotifyThrowPipebomb, OnConVarChanged);
    HookConVarChange(g_hNotifyThrowVomitjar, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeGascan, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeFuelBarrel, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodePropane, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeOxygen, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeBarricade, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeGasPump, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeFireworks, OnConVarChanged);
    HookConVarChange(g_hNotifyExplodeOilDrum, OnConVarChanged);
    HookConVarChange(g_hNotifyGearGive, OnConVarChanged);
    HookConVarChange(g_hNotifyGearGrab, OnConVarChanged);
    HookConVarChange(g_hNotifyGearSwap, OnConVarChanged);

    g_hWeaponNameMap = new StringMap();
    for (int i = 0; i < sizeof(WEAPON_NAMES_KEYs); i++)
    {
        g_hWeaponNameMap.SetString(WEAPON_NAMES_KEYs[i], WEAPON_NAMES_VALUEs[i]);
    }

    RefreshConVars();
    g_bCoreReady = (GetFeatureStatus(FeatureType_Native, "TuanNotify_PublishInfo") == FeatureStatus_Available);
    AutoExecConfig(true, "tuan_notify_member_events");
}

public void OnAllPluginsLoaded()
{
    g_bCoreReady = (GetFeatureStatus(FeatureType_Native, "TuanNotify_PublishInfo") == FeatureStatus_Available);
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, TUAN_NOTIFY_LIBRARY))
    {
        g_bCoreReady = true;
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, TUAN_NOTIFY_LIBRARY))
    {
        g_bCoreReady = false;
    }
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshConVars();
}

void RefreshConVars()
{
    g_bEnable = g_hEnable.BoolValue;
    g_bNotifyHealedOther = g_hNotifyHealedOther.BoolValue;
    g_bNotifyGoBnW = g_hNotifyGoBnW.BoolValue;
    g_bNotifyRevivedOther = g_hNotifyRevivedOther.BoolValue;
    g_bNotifySelfRevived = g_hNotifySelfRevived.BoolValue;
    g_bNotifyThrowMolotov = g_hNotifyThrowMolotov.BoolValue;
    g_bNotifyThrowPipebomb = g_hNotifyThrowPipebomb.BoolValue;
    g_bNotifyThrowVomitjar = g_hNotifyThrowVomitjar.BoolValue;
    g_bNotifyExplodeGascan = g_hNotifyExplodeGascan.BoolValue;
    g_bNotifyExplodeFuelBarrel = g_hNotifyExplodeFuelBarrel.BoolValue;
    g_bNotifyExplodePropane = g_hNotifyExplodePropane.BoolValue;
    g_bNotifyExplodeOxygen = g_hNotifyExplodeOxygen.BoolValue;
    g_bNotifyExplodeBarricade = g_hNotifyExplodeBarricade.BoolValue;
    g_bNotifyExplodeGasPump = g_hNotifyExplodeGasPump.BoolValue;
    g_bNotifyExplodeFireworks = g_hNotifyExplodeFireworks.BoolValue;
    g_bNotifyExplodeOilDrum = g_hNotifyExplodeOilDrum.BoolValue;
    g_bNotifyGearGive = g_hNotifyGearGive.BoolValue;
    g_bNotifyGearGrab = g_hNotifyGearGrab.BoolValue;
    g_bNotifyGearSwap = g_hNotifyGearSwap.BoolValue;
}

bool IsReady()
{
    return g_bEnable && g_bCoreReady;
}

void PublishInfo(const char[] message)
{
    if (!IsReady() || message[0] == '\0')
    {
        return;
    }

    TuanNotify_PublishInfo(message);
}

void GetShortHudNameFromRaw(const char[] name, char[] buffer, int maxlen)
{
    if (strlen(name) > HUD_NAME_VISIBLE)
    {
        char shortName[HUD_NAME_VISIBLE + 1];
        strcopy(shortName, sizeof(shortName), name);
        shortName[HUD_NAME_VISIBLE] = '\0';
        FormatEx(buffer, maxlen, "%s...", shortName);
    }
    else
    {
        strcopy(buffer, maxlen, name);
    }
}

void FormatHudNameFromClient(int client, char[] buffer, int maxlen)
{
    char name[MAX_NAME_LENGTH];
    char shortName[64];
    GetClientName(client, name, sizeof(name));
    GetShortHudNameFromRaw(name, shortName, sizeof(shortName));
    FormatEx(buffer, maxlen, "[%s]", shortName);
}

void GetGearTransferWeaponNameById(int weaponid, char[] buffer, int maxlen)
{
    switch (weaponid)
    {
        case 23: strcopy(buffer, maxlen, "adrenaline");
        case 15: strcopy(buffer, maxlen, "pain pills");
        default: FormatEx(buffer, maxlen, "weapon #%d", weaponid);
    }
}

public void Tuan_OnClient_HealedOther(int client, int victim)
{
    if (!g_bNotifyHealedOther || !IsClient(client) || !IsClient(victim))
    {
        return;
    }

    char clientFmt[32];
    char victimFmt[32];
    char line[128];
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatHudNameFromClient(victim, victimFmt, sizeof(victimFmt));

    if (client == victim)
    {
        FormatEx(line, sizeof(line), "%s healed himself and no longer at last life.", clientFmt);
    }
    else
    {
        FormatEx(line, sizeof(line), "%s was healed by %s and no longer at last life.", victimFmt, clientFmt);
    }

    PublishInfo(line);
}

public void Tuan_OnClient_GoBnW(int client)
{
    if (!g_bNotifyGoBnW || !IsClient(client))
    {
        return;
    }

    char clientFmt[32];
    char line[128];
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatEx(line, sizeof(line), "%s is at last life", clientFmt);
    PublishInfo(line);
}

public void Tuan_OnClient_RevivedOther(int client, int target)
{
    if (!g_bNotifyRevivedOther || !IsClient(client) || !IsClient(target) || client == target)
    {
        return;
    }

    char clientFmt[32];
    char targetFmt[32];
    char line[128];
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatHudNameFromClient(target, targetFmt, sizeof(targetFmt));
    FormatEx(line, sizeof(line), "%s helped %s to get up", clientFmt, targetFmt);
    PublishInfo(line);
}

public void Tuan_OnClient_SelfRevived(int client)
{
    if (!g_bNotifySelfRevived || !IsClient(client))
    {
        return;
    }

    char clientFmt[32];
    char line[128];
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatEx(line, sizeof(line), "%s self revived", clientFmt);
    PublishInfo(line);
}

public void Tuan_OnClient_UsedThrowable(int client, int throwable_type)
{
    if (!IsClient(client))
    {
        return;
    }

    char clientFmt[32];
    char line[128];
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));

    switch (throwable_type)
    {
        case 0:
        {
            if (!g_bNotifyThrowMolotov) return;
            FormatEx(line, sizeof(line), "%s thrown molotov", clientFmt);
        }
        case 1:
        {
            if (!g_bNotifyThrowPipebomb) return;
            FormatEx(line, sizeof(line), "%s thrown pipebomb", clientFmt);
        }
        case 2:
        {
            if (!g_bNotifyThrowVomitjar) return;
            FormatEx(line, sizeof(line), "%s thrown vomitjar", clientFmt);
        }
        default:
        {
            return;
        }
    }

    PublishInfo(line);
}

public void Tuan_OnClient_ExplodeObject(int client, int object_type)
{
    if (!IsClient(client))
    {
        return;
    }

    char clientFmt[32];
    char line[128];
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));

    switch (object_type)
    {
        case TYPE_GASCAN:
        {
            if (!g_bNotifyExplodeGascan) return;
            FormatEx(line, sizeof(line), "%s exploded a gascan", clientFmt);
        }
        case TYPE_FUEL_BARREL:
        {
            if (!g_bNotifyExplodeFuelBarrel) return;
            FormatEx(line, sizeof(line), "%s exploded a fuel barrel", clientFmt);
        }
        case TYPE_PROPANECANISTER:
        {
            if (!g_bNotifyExplodePropane) return;
            FormatEx(line, sizeof(line), "%s exploded a propane canister", clientFmt);
        }
        case TYPE_OXYGENTANK:
        {
            if (!g_bNotifyExplodeOxygen) return;
            FormatEx(line, sizeof(line), "%s exploded an oxygen tank", clientFmt);
        }
        case TYPE_BARRICADE_GASCAN:
        {
            if (!g_bNotifyExplodeBarricade) return;
            FormatEx(line, sizeof(line), "%s exploded a barricade gascan", clientFmt);
        }
        case TYPE_GAS_PUMP:
        {
            if (!g_bNotifyExplodeGasPump) return;
            FormatEx(line, sizeof(line), "%s exploded a gas pump", clientFmt);
        }
        case TYPE_FIREWORKS_CRATE:
        {
            if (!g_bNotifyExplodeFireworks) return;
            FormatEx(line, sizeof(line), "%s exploded a fireworks crate", clientFmt);
        }
        case TYPE_OIL_DRUM_EXPLOSIVE:
        {
            if (!g_bNotifyExplodeOilDrum) return;
            FormatEx(line, sizeof(line), "%s exploded an oil drum", clientFmt);
        }
        default:
        {
            return;
        }
    }

    PublishInfo(line);
}

public void GearTransfer_OnWeaponGive(int client, int target, int item)
{
    if (!g_bNotifyGearGive || !IsClient(client) || !IsClient(target))
    {
        return;
    }

    L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
    char weaponName[64];
    char clientFmt[32];
    char targetFmt[32];
    char line[128];
    L4D2_GetWeaponNameByWeaponId(weaponId, weaponName, sizeof(weaponName));
    g_hWeaponNameMap.GetString(weaponName, weaponName, sizeof(weaponName));
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatHudNameFromClient(target, targetFmt, sizeof(targetFmt));
    FormatEx(line, sizeof(line), "%s give %s to %s", clientFmt, weaponName, targetFmt);
    PublishInfo(line);
}

public void GearTransfer_OnWeaponGivenEvent(int client, int target, int weaponid)
{
    if (!g_bNotifyGearGive || !IsClient(client) || !IsClient(target))
    {
        return;
    }

    char weaponName[64];
    char clientFmt[32];
    char targetFmt[32];
    char line[128];
    GetGearTransferWeaponNameById(weaponid, weaponName, sizeof(weaponName));
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatHudNameFromClient(target, targetFmt, sizeof(targetFmt));
    FormatEx(line, sizeof(line), "%s give %s to %s", clientFmt, weaponName, targetFmt);
    PublishInfo(line);
}

public void GearTransfer_OnWeaponGrab(int client, int target, int item)
{
    if (!g_bNotifyGearGrab || !IsClient(client) || !IsClient(target))
    {
        return;
    }

    L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
    char weaponName[64];
    char clientFmt[32];
    char targetFmt[32];
    char line[128];
    L4D2_GetWeaponNameByWeaponId(weaponId, weaponName, sizeof(weaponName));
    g_hWeaponNameMap.GetString(weaponName, weaponName, sizeof(weaponName));
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatHudNameFromClient(target, targetFmt, sizeof(targetFmt));
    FormatEx(line, sizeof(line), "%s grabbed %s from %s", clientFmt, weaponName, targetFmt);
    PublishInfo(line);
}

public void GearTransfer_OnWeaponSwap(int client, int target, int itemGiven, int itemTaken)
{
    if (!g_bNotifyGearSwap || !IsClient(client) || !IsClient(target))
    {
        return;
    }

    L4D2WeaponId givenWeaponId = L4D2_GetWeaponId(itemGiven);
    L4D2WeaponId takenWeaponId = L4D2_GetWeaponId(itemTaken);
    char givenWeaponName[64];
    char takenWeaponName[64];
    char clientFmt[32];
    char targetFmt[32];
    char line[128];

    L4D2_GetWeaponNameByWeaponId(givenWeaponId, givenWeaponName, sizeof(givenWeaponName));
    L4D2_GetWeaponNameByWeaponId(takenWeaponId, takenWeaponName, sizeof(takenWeaponName));
    g_hWeaponNameMap.GetString(givenWeaponName, givenWeaponName, sizeof(givenWeaponName));
    g_hWeaponNameMap.GetString(takenWeaponName, takenWeaponName, sizeof(takenWeaponName));
    FormatHudNameFromClient(client, clientFmt, sizeof(clientFmt));
    FormatHudNameFromClient(target, targetFmt, sizeof(targetFmt));

    FormatEx(line, sizeof(line), "%s swap %s for %s with %s", clientFmt, givenWeaponName, takenWeaponName, targetFmt);
    PublishInfo(line);
}
