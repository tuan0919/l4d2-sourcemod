#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
#define ZC_TANK 8

#define TRAIT_NONE 0
#define TRAIT_LASER 1
#define TRAIT_FIRE 2
#define TRAIT_EXPLOSIVE 3

#define UPGRADE_INCENDIARY (1 << 0)
#define UPGRADE_EXPLOSIVE  (1 << 1)
#define UPGRADE_LASER      (1 << 2)

#define MAX_WEAPON_ENTS 2048

public Plugin myinfo =
{
    name = "[L4D2] Weapon XP Traits",
    author = "Codex",
    description = "Primary weapon XP + trait unlock with persistence",
    version = PLUGIN_VERSION,
    url = ""
};

ConVar g_hEnable;
ConVar g_hXpCI;
ConVar g_hXpSI;
ConVar g_hXpWitch;
ConVar g_hXpTank;
ConVar g_hReqBase;
ConVar g_hReqStep;
ConVar g_hTraitAmmo;
ConVar g_hGlowR;
ConVar g_hGlowG;
ConVar g_hGlowB;

int g_iWeaponXP[MAX_WEAPON_ENTS + 1];
int g_iWeaponLevel[MAX_WEAPON_ENTS + 1];
int g_iWeaponPending[MAX_WEAPON_ENTS + 1];
int g_iWeaponTrait[MAX_WEAPON_ENTS + 1];

int g_iLastPrimaryRef[MAXPLAYERS + 1];
bool g_bNeedRestore[MAXPLAYERS + 1];
bool g_bMenuMuted[MAXPLAYERS + 1];

bool g_bHasSavedData[MAXPLAYERS + 1];
int g_iSavedXP[MAXPLAYERS + 1];
int g_iSavedLevel[MAXPLAYERS + 1];
int g_iSavedPending[MAXPLAYERS + 1];
int g_iSavedTrait[MAXPLAYERS + 1];
char g_sSavedClass[MAXPLAYERS + 1][64];

public void OnPluginStart()
{
    g_hEnable = CreateConVar("l4d2_wxp_enable", "1", "Enable weapon XP trait plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hXpCI = CreateConVar("l4d2_wxp_xp_ci", "1", "XP per Common Infected hit.", FCVAR_NOTIFY, true, 0.0);
    g_hXpSI = CreateConVar("l4d2_wxp_xp_si", "4", "XP per Special Infected hit.", FCVAR_NOTIFY, true, 0.0);
    g_hXpWitch = CreateConVar("l4d2_wxp_xp_witch", "7", "XP per Witch hit.", FCVAR_NOTIFY, true, 0.0);
    g_hXpTank = CreateConVar("l4d2_wxp_xp_tank", "10", "XP per Tank hit.", FCVAR_NOTIFY, true, 0.0);
    g_hReqBase = CreateConVar("l4d2_wxp_req_base", "15", "XP required for level 1.", FCVAR_NOTIFY, true, 1.0);
    g_hReqStep = CreateConVar("l4d2_wxp_req_step", "10", "Additional XP required per next level.", FCVAR_NOTIFY, true, 0.0);
    g_hTraitAmmo = CreateConVar("l4d2_wxp_trait_ammo", "90", "Special ammo amount maintained for fire/explosive traits.", FCVAR_NOTIFY, true, 1.0);
    g_hGlowR = CreateConVar("l4d2_wxp_glow_r", "40", "Glow R for dropped upgraded weapons.", FCVAR_NOTIFY, true, 0.0, true, 255.0);
    g_hGlowG = CreateConVar("l4d2_wxp_glow_g", "170", "Glow G for dropped upgraded weapons.", FCVAR_NOTIFY, true, 0.0, true, 255.0);
    g_hGlowB = CreateConVar("l4d2_wxp_glow_b", "255", "Glow B for dropped upgraded weapons.", FCVAR_NOTIFY, true, 0.0, true, 255.0);

    AutoExecConfig(true, "Tuan_l4d2_weapon_xp_traits");

    RegConsoleCmd("sm_up", Cmd_OpenUpgradeMenu, "Open weapon trait upgrade menu.");

    HookEvent("infected_hurt", Event_InfectedHurt, EventHookMode_Post);
    HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
    HookEvent("weapon_drop", Event_WeaponDrop, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("round_end", Event_SaveAll, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_SaveAll, EventHookMode_PostNoCopy);
    HookEvent("mission_lost", Event_SaveAll, EventHookMode_PostNoCopy);
    HookEvent("finale_vehicle_leaving", Event_SaveAll, EventHookMode_PostNoCopy);

    CreateTimer(0.5, Timer_PollWeapons, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(20.0, Timer_AutoSave, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnMapStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iLastPrimaryRef[i] = INVALID_ENT_REFERENCE;
        if (IsClientInGame(i))
        {
            g_bNeedRestore[i] = true;
        }
    }
}

public void OnClientAuthorized(int client, const char[] auth)
{
    LoadClientSave(client);
    g_bNeedRestore[client] = true;
}

public void OnClientDisconnect(int client)
{
    SaveClientState(client);
    g_iLastPrimaryRef[client] = INVALID_ENT_REFERENCE;
    g_bNeedRestore[client] = false;
}

public void OnEntityDestroyed(int entity)
{
    if (entity < 1 || entity > MAX_WEAPON_ENTS)
    {
        return;
    }

    g_iWeaponXP[entity] = 0;
    g_iWeaponLevel[entity] = 0;
    g_iWeaponPending[entity] = 0;
    g_iWeaponTrait[entity] = TRAIT_NONE;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsSurvivorClient(client, false))
    {
        g_bNeedRestore[client] = true;
    }
    return Plugin_Continue;
}

public Action Event_SaveAll(Event event, const char[] name, bool dontBroadcast)
{
    SaveAllClients();
    return Plugin_Continue;
}

public Action Timer_AutoSave(Handle timer)
{
    SaveAllClients();
    return Plugin_Continue;
}

public Action Event_InfectedHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_hEnable.BoolValue)
    {
        return Plugin_Continue;
    }

    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    int infected = event.GetInt("entityid");
    if (infected > MaxClients && IsValidEdict(infected))
    {
        char classname[32];
        GetEdictClassname(infected, classname, sizeof(classname));
        if (StrEqual(classname, "infected", false))
        {
            AwardXpForShot(attacker, g_hXpCI.IntValue);
        }
        else if (StrEqual(classname, "witch", false))
        {
            AwardXpForShot(attacker, g_hXpWitch.IntValue);
        }
    }
    return Plugin_Continue;
}

public Action Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_hEnable.BoolValue)
    {
        return Plugin_Continue;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidEntityClient(victim) || !IsSurvivorClient(attacker, true))
    {
        return Plugin_Continue;
    }

    if (GetClientTeam(victim) != TEAM_INFECTED)
    {
        return Plugin_Continue;
    }

    int zombieClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
    if (zombieClass == ZC_TANK)
    {
        AwardXpForShot(attacker, g_hXpTank.IntValue);
    }
    else
    {
        AwardXpForShot(attacker, g_hXpSI.IntValue);
    }

    return Plugin_Continue;
}

public Action Event_WeaponDrop(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsSurvivorClient(client, false))
    {
        return Plugin_Continue;
    }

    int weapon = event.GetInt("propid");
    if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
    {
        return Plugin_Continue;
    }

    if (g_iWeaponTrait[weapon] != TRAIT_NONE)
    {
        SetWeaponGlow(weapon, true);
    }

    return Plugin_Continue;
}

public Action Timer_PollWeapons(Handle timer)
{
    if (!g_hEnable.BoolValue)
    {
        return Plugin_Continue;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsSurvivorClient(client, true))
        {
            continue;
        }

        int weapon = GetPlayerWeaponSlot(client, 0);
        int currentRef = IsValidEdict(weapon) ? EntIndexToEntRef(weapon) : INVALID_ENT_REFERENCE;

        if (currentRef != g_iLastPrimaryRef[client])
        {
            HandleClientPrimaryChanged(client, weapon);
            g_iLastPrimaryRef[client] = currentRef;
        }

        if (IsValidEdict(weapon) && IsPrimaryWeaponEntity(weapon))
        {
            MaintainTraitAmmo(weapon);
        }
    }

    return Plugin_Continue;
}

void HandleClientPrimaryChanged(int client, int weapon)
{
    if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
    {
        return;
    }

    SetWeaponGlow(weapon, false);

    if (g_bNeedRestore[client] && g_bHasSavedData[client])
    {
        char classname[64];
        GetEdictClassname(weapon, classname, sizeof(classname));

        if (StrEqual(g_sSavedClass[client], "") || StrEqual(classname, g_sSavedClass[client]))
        {
            g_iWeaponXP[weapon] = g_iSavedXP[client];
            g_iWeaponLevel[weapon] = g_iSavedLevel[client];
            g_iWeaponPending[weapon] = g_iSavedPending[client];
            g_iWeaponTrait[weapon] = g_iSavedTrait[client];
            ApplyTraitToWeapon(weapon, g_iWeaponTrait[weapon]);
        }

        g_bNeedRestore[client] = false;
    }

    if (g_iWeaponPending[weapon] > 0 && !g_bMenuMuted[client])
    {
        ShowUpgradeMenu(client);
    }
}

void AwardXpForShot(int client, int amount)
{
    if (amount <= 0 || !IsSurvivorClient(client, true))
    {
        return;
    }

    int weapon = GetClientActivePrimary(client);
    if (!IsValidEdict(weapon))
    {
        return;
    }

    g_iWeaponXP[weapon] += amount;

    bool leveled = false;
    while (g_iWeaponXP[weapon] >= GetRequiredXpForLevel(g_iWeaponLevel[weapon] + 1))
    {
        g_iWeaponLevel[weapon]++;
        g_iWeaponPending[weapon]++;
        leveled = true;
    }

    if (leveled)
    {
        PrintToChat(client, "\x04[WeaponXP]\x01 %N's weapon reached level %d. Pending trait picks: %d.", client, g_iWeaponLevel[weapon], g_iWeaponPending[weapon]);
        if (!g_bMenuMuted[client])
        {
            ShowUpgradeMenu(client);
        }
        else
        {
            PrintToChat(client, "\x04[WeaponXP]\x01 Upgrade panel is hidden. Use !up to open it again.");
        }
    }
}

int GetClientActivePrimary(int client)
{
    if (!IsSurvivorClient(client, true))
    {
        return -1;
    }

    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int primary = GetPlayerWeaponSlot(client, 0);

    if (active <= MaxClients || !IsValidEdict(active) || !IsPrimaryWeaponEntity(active))
    {
        return -1;
    }

    if (active != primary)
    {
        return -1;
    }

    return active;
}

int GetRequiredXpForLevel(int level)
{
    if (level <= 0)
    {
        return 0;
    }

    return g_hReqBase.IntValue + ((level - 1) * g_hReqStep.IntValue);
}

public Action Cmd_OpenUpgradeMenu(int client, int args)
{
    if (!IsSurvivorClient(client, true))
    {
        ReplyToCommand(client, "[WeaponXP] You must be an alive survivor.");
        return Plugin_Handled;
    }

    g_bMenuMuted[client] = false;
    ShowUpgradeMenu(client);
    return Plugin_Handled;
}

void ShowUpgradeMenu(int client)
{
    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
    {
        PrintToChat(client, "\x04[WeaponXP]\x01 No primary weapon found.");
        return;
    }

    if (g_iWeaponPending[weapon] <= 0)
    {
        PrintToChat(client, "\x04[WeaponXP]\x01 No trait points available yet.");
        return;
    }

    Menu menu = new Menu(MenuHandler_Upgrade);
    char title[192];
    Format(title, sizeof(title), "Weapon Upgrade\nLevel: %d | Pending: %d\nChoose 1 trait", g_iWeaponLevel[weapon], g_iWeaponPending[weapon]);
    menu.SetTitle(title);
    menu.AddItem("1", "Laser");
    menu.AddItem("2", "Incendiary Ammo");
    menu.AddItem("3", "Explosive Ammo");
    menu.ExitButton = true;
    menu.Display(client, 20);
}

public int MenuHandler_Upgrade(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_Cancel)
    {
        if (client > 0 && IsClientInGame(client) && item == MenuCancel_Exit)
        {
            g_bMenuMuted[client] = true;
            PrintToChat(client, "\x04[WeaponXP]\x01 Upgrade menu hidden. Type !up to open again.");
        }
    }
    else if (action == MenuAction_Select)
    {
        if (!IsSurvivorClient(client, true))
        {
            return 0;
        }

        int weapon = GetPlayerWeaponSlot(client, 0);
        if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
        {
            PrintToChat(client, "\x04[WeaponXP]\x01 No valid primary weapon.");
            return 0;
        }

        if (g_iWeaponPending[weapon] <= 0)
        {
            PrintToChat(client, "\x04[WeaponXP]\x01 No pending trait point.");
            return 0;
        }

        char choice[8];
        menu.GetItem(item, choice, sizeof(choice));
        int trait = StringToInt(choice);

        g_iWeaponTrait[weapon] = trait;
        g_iWeaponPending[weapon]--;
        if (g_iWeaponPending[weapon] < 0)
        {
            g_iWeaponPending[weapon] = 0;
        }

        ApplyTraitToWeapon(weapon, trait);
        char traitName[32];
        GetTraitName(trait, traitName, sizeof(traitName));
        PrintToChat(client, "\x04[WeaponXP]\x01 Trait applied to this weapon: %s", traitName);

        if (g_iWeaponPending[weapon] > 0 && !g_bMenuMuted[client])
        {
            ShowUpgradeMenu(client);
        }
    }

    return 0;
}

void ApplyTraitToWeapon(int weapon, int trait)
{
    if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
    {
        return;
    }

    int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bits &= ~(UPGRADE_INCENDIARY | UPGRADE_EXPLOSIVE | UPGRADE_LASER);

    switch (trait)
    {
        case TRAIT_LASER:
        {
            bits |= UPGRADE_LASER;
            SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", 0);
        }
        case TRAIT_FIRE:
        {
            bits |= UPGRADE_INCENDIARY;
            SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", g_hTraitAmmo.IntValue);
        }
        case TRAIT_EXPLOSIVE:
        {
            bits |= UPGRADE_EXPLOSIVE;
            SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", g_hTraitAmmo.IntValue);
        }
        default:
        {
            SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", 0);
        }
    }

    SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits);
}

void MaintainTraitAmmo(int weapon)
{
    int trait = g_iWeaponTrait[weapon];
    if (trait != TRAIT_FIRE && trait != TRAIT_EXPLOSIVE)
    {
        return;
    }

    int current = GetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded");
    if (current <= 0)
    {
        SetEntProp(weapon, Prop_Send, "m_nUpgradedPrimaryAmmoLoaded", g_hTraitAmmo.IntValue);
    }
}

void SetWeaponGlow(int weapon, bool state)
{
    if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
    {
        return;
    }

    if (!state)
    {
        SetEntProp(weapon, Prop_Send, "m_iGlowType", 0);
        SetEntProp(weapon, Prop_Send, "m_glowColorOverride", 0);
        SetEntProp(weapon, Prop_Send, "m_nGlowRange", 0);
        return;
    }

    int r = g_hGlowR.IntValue;
    int g = g_hGlowG.IntValue;
    int b = g_hGlowB.IntValue;
    int color = (r & 0xFF) | ((g & 0xFF) << 8) | ((b & 0xFF) << 16);

    SetEntProp(weapon, Prop_Send, "m_iGlowType", 3);
    SetEntProp(weapon, Prop_Send, "m_glowColorOverride", color);
    SetEntProp(weapon, Prop_Send, "m_nGlowRange", 650);
}

void SaveAllClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        SaveClientState(client);
    }
}

void SaveClientState(int client)
{
    if (!IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) != TEAM_SURVIVOR)
    {
        return;
    }

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
    {
        return;
    }

    int weapon = GetPlayerWeaponSlot(client, 0);
    if (!IsValidEdict(weapon) || !IsPrimaryWeaponEntity(weapon))
    {
        g_bHasSavedData[client] = false;
        WriteClientToKv(steamId, false, 0, 0, 0, 0, "");
        return;
    }

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    g_bHasSavedData[client] = true;
    g_iSavedXP[client] = g_iWeaponXP[weapon];
    g_iSavedLevel[client] = g_iWeaponLevel[weapon];
    g_iSavedPending[client] = g_iWeaponPending[weapon];
    g_iSavedTrait[client] = g_iWeaponTrait[weapon];
    strcopy(g_sSavedClass[client], sizeof(g_sSavedClass[]), classname);

    WriteClientToKv(steamId, true, g_iSavedXP[client], g_iSavedLevel[client], g_iSavedPending[client], g_iSavedTrait[client], classname);
}

void LoadClientSave(int client)
{
    g_bHasSavedData[client] = false;
    g_iSavedXP[client] = 0;
    g_iSavedLevel[client] = 0;
    g_iSavedPending[client] = 0;
    g_iSavedTrait[client] = TRAIT_NONE;
    g_sSavedClass[client][0] = '\0';

    if (!IsValidEntityClient(client) || IsFakeClient(client))
    {
        return;
    }

    char steamId[32];
    if (!GetClientAuthId(client, AuthId_Steam2, steamId, sizeof(steamId), true))
    {
        return;
    }

    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/tuan_weapon_xp_traits.txt");

    KeyValues kv = new KeyValues("WeaponXP");
    if (!FileToKeyValues(kv, path))
    {
        delete kv;
        return;
    }

    if (!kv.JumpToKey("players", false) || !kv.JumpToKey(steamId, false))
    {
        delete kv;
        return;
    }

    g_bHasSavedData[client] = true;
    g_iSavedXP[client] = kv.GetNum("xp", 0);
    g_iSavedLevel[client] = kv.GetNum("level", 0);
    g_iSavedPending[client] = kv.GetNum("pending", 0);
    g_iSavedTrait[client] = kv.GetNum("trait", TRAIT_NONE);
    kv.GetString("weapon", g_sSavedClass[client], sizeof(g_sSavedClass[]), "");

    delete kv;
}

void WriteClientToKv(const char[] steamId, bool hasData, int xp, int level, int pending, int trait, const char[] weaponClass)
{
    char path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "data/tuan_weapon_xp_traits.txt");

    KeyValues kv = new KeyValues("WeaponXP");
    FileToKeyValues(kv, path);

    kv.JumpToKey("players", true);

    if (!hasData)
    {
        kv.DeleteKey(steamId);
    }
    else
    {
        kv.JumpToKey(steamId, true);
        kv.SetNum("xp", xp);
        kv.SetNum("level", level);
        kv.SetNum("pending", pending);
        kv.SetNum("trait", trait);
        kv.SetString("weapon", weaponClass);
        kv.GoBack();
    }

    kv.Rewind();
    kv.ExportToFile(path);
    delete kv;
}

bool IsSurvivorClient(int client, bool mustAlive)
{
    if (!IsValidEntityClient(client) || GetClientTeam(client) != TEAM_SURVIVOR)
    {
        return false;
    }

    if (mustAlive && !IsPlayerAlive(client))
    {
        return false;
    }

    return true;
}

bool IsValidEntityClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsPrimaryWeaponEntity(int entity)
{
    if (!IsValidEdict(entity) || entity <= MaxClients)
    {
        return false;
    }

    char classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));
    return IsPrimaryWeaponClass(classname);
}

bool IsPrimaryWeaponClass(const char[] classname)
{
    return StrContains(classname, "weapon_smg", false) == 0
        || StrContains(classname, "weapon_rifle", false) == 0
        || StrContains(classname, "weapon_pumpshotgun", false) == 0
        || StrContains(classname, "weapon_shotgun_chrome", false) == 0
        || StrContains(classname, "weapon_autoshotgun", false) == 0
        || StrContains(classname, "weapon_shotgun_spas", false) == 0
        || StrContains(classname, "weapon_hunting_rifle", false) == 0
        || StrContains(classname, "weapon_sniper", false) == 0
        || StrContains(classname, "weapon_grenade_launcher", false) == 0
        || StrEqual(classname, "weapon_rifle_m60", false);
}

void GetTraitName(int trait, char[] buffer, int maxlen)
{
    switch (trait)
    {
        case TRAIT_LASER: strcopy(buffer, maxlen, "Laser");
        case TRAIT_FIRE: strcopy(buffer, maxlen, "Incendiary");
        case TRAIT_EXPLOSIVE: strcopy(buffer, maxlen, "Explosive");
        default: strcopy(buffer, maxlen, "None");
    }
}
