/*
 *  [L4D2] Laser Toggle
 *
 *  Hold USE while holding a primary weapon to toggle laser sight.
 *  Laser ON = -10% primary weapon bullet damage (accuracy tradeoff).
 *  Status shown via per-client instructor hint after toggle.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION      "1.2.0"
#define TEAM_SURVIVOR       2
#define LASER_DAMAGE_MULT   0.9     // 10% damage reduction when laser ON
#define IHFLAG_STATIC       (1 << 8)

// Weapon upgrade bit flags (from Peace-Maker / l4d2 community research)
// Reference: https://forums.alliedmods.net/showthread.php?t=173749
#define L4D2_WEPUPGFLAG_INCENDIARY  (1 << 0)   // 1
#define L4D2_WEPUPGFLAG_EXPLOSIVE   (1 << 1)   // 2
#define L4D2_WEPUPGFLAG_LASER       (1 << 2)   // 4  ← laser sight

// ====================================================================================================
//                  PLUGIN INFO
// ====================================================================================================

public Plugin myinfo =
{
    name        = "[L4D2] Laser Toggle",
    author      = "Tuan",
    description = "Hold USE to toggle laser sight; ON = -10% primary weapon damage",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ====================================================================================================
//                  GLOBALS
// ====================================================================================================

ConVar  g_hCvarHoldSeconds = null;

bool    g_bHoldActive[MAXPLAYERS + 1];
bool    g_bUseLocked[MAXPLAYERS + 1];
float   g_fHoldStartTime[MAXPLAYERS + 1];
int     g_iHoldWeaponRef[MAXPLAYERS + 1];

// ====================================================================================================
//                  PLUGIN START / LATE LOAD
// ====================================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hCvarHoldSeconds = CreateConVar(
        "l4d2_laser_toggle_hold_seconds",
        "1.2",
        "Seconds of holding USE required to toggle laser sight.",
        FCVAR_NOTIFY,
        true, 0.2,
        true, 5.0
    );

    HookEvent("player_death",  Event_PlayerDeath);
    HookEvent("player_spawn",  Event_PlayerSpawn);

    // Late-load: hook already-connected clients
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
            OnClientPutInServer(i);
    }
}

// ====================================================================================================
//                  CLIENT CONNECT / DISCONNECT
// ====================================================================================================

public void OnClientPutInServer(int client)
{
    ClearClientState(client);
    SDKHook(client, SDKHook_WeaponSwitchPost,   Hook_WeaponSwitchPost);
    SDKHook(client, SDKHook_OnTakeDamageAlive,  Hook_SurvivorOnTakeDamage);
}

public void OnClientDisconnecting(int client)
{
    StopHintForClient(client, "laser_toggle_status");
    ClearClientState(client);
    SDKUnhook(client, SDKHook_WeaponSwitchPost,  Hook_WeaponSwitchPost);
    SDKUnhook(client, SDKHook_OnTakeDamageAlive, Hook_SurvivorOnTakeDamage);
}

// ====================================================================================================
//                  ENTITY CREATED — hook damage on infected / witch
// ====================================================================================================

public void OnEntityCreated(int entity, const char[] classname)
{
    if (strncmp(classname, "infected", 8) == 0 ||
        strncmp(classname, "witch",    5) == 0)
    {
        SDKHook(entity, SDKHook_OnTakeDamage, Hook_EntityOnTakeDamage);
    }
}

// ====================================================================================================
//                  HOLD USE DETECTION
// ====================================================================================================

public void OnPlayerRunCmdPost(int client, int buttons)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;
    if (GetClientTeam(client) != TEAM_SURVIVOR)
        return;

    bool eligible = HasLaserEligibleWeapon(client);

    if (!eligible)
    {
        CancelHoldProgress(client);
        g_bUseLocked[client] = false;
        return;
    }

    bool useHeld = (buttons & IN_USE) != 0;
    if (!useHeld)
    {
        g_bUseLocked[client] = false;
        CancelHoldProgress(client);
        return;
    }

    if (g_bUseLocked[client] || IsClientBusy(client))
    {
        CancelHoldProgress(client);
        return;
    }

    int activeWeapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (activeWeapon <= 0 || !IsValidEntity(activeWeapon))
    {
        CancelHoldProgress(client);
        return;
    }

    int weaponRef = EntIndexToEntRef(activeWeapon);
    if (!g_bHoldActive[client] || g_iHoldWeaponRef[client] != weaponRef)
    {
        StartHoldProgress(client, activeWeapon);
        return;
    }

    float holdDuration = g_hCvarHoldSeconds.FloatValue;
    if (GetGameTime() - g_fHoldStartTime[client] >= holdDuration)
    {
        ToggleLaser(client);
        g_bUseLocked[client] = true;
        CancelHoldProgress(client);
    }
}

// ====================================================================================================
//                  WEAPON SWITCH — clear status hint when not eligible
// ====================================================================================================

public void Hook_WeaponSwitchPost(int client, int weapon)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;
    if (GetClientTeam(client) != TEAM_SURVIVOR)
        return;

    if (!HasLaserEligibleWeapon(client))
    {
        StopHintForClient(client, "laser_toggle_status");
        CancelHoldProgress(client);
        g_bUseLocked[client] = false;
    }
}

// ====================================================================================================
//                  DAMAGE HOOKS
// ====================================================================================================

// Survivor taking damage — we need this to intercept damage dealt BY survivors
// We actually hook ON THE VICTIM and check if the attacker has laser on.

// Hook on survivor clients (they can be victims too, but we check attacker)
public Action Hook_SurvivorOnTakeDamage(int victim, int &attacker, int &inflictor,
                                         float &damage, int &damagetype)
{
    return ApplyLaserPenalty(attacker, damage, damagetype);
}

// Hook on infected / witch entities
public Action Hook_EntityOnTakeDamage(int victim, int &attacker, int &inflictor,
                                       float &damage, int &damagetype)
{
    return ApplyLaserPenalty(attacker, damage, damagetype);
}

Action ApplyLaserPenalty(int attacker, float &damage, int damagetype)
{
    if (damage <= 0.0)                              return Plugin_Continue;
    if (attacker < 1 || attacker > MaxClients)      return Plugin_Continue;
    if (!IsClientInGame(attacker))                  return Plugin_Continue;
    if (GetClientTeam(attacker) != TEAM_SURVIVOR)   return Plugin_Continue;
    if (!(damagetype & DMG_BULLET))                 return Plugin_Continue;
    if (!HasLaserEligibleWeapon(attacker))          return Plugin_Continue;
    
    if (!IsLaserOnActiveWeapon(attacker))           return Plugin_Continue;

    damage *= LASER_DAMAGE_MULT;
    return Plugin_Changed;
}

// ====================================================================================================
//                  EVENTS
// ====================================================================================================

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || client > MaxClients) return;

    StopHintForClient(client, "laser_toggle_status");
    ClearClientState(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client < 1 || client > MaxClients) return;

    ClearClientState(client);
}

// ====================================================================================================
//                  LASER TOGGLE LOGIC
// ====================================================================================================

void ToggleLaser(int client)
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEdict(weapon) || !IsValidEntity(weapon)) return;

    char netclass[128];
    GetEntityNetClass(weapon, netclass, sizeof(netclass));
    if (FindSendPropInfo(netclass, "m_upgradeBitVec") < 1) return;

    int bits = GetEntProp(weapon, Prop_Send, "m_upgradeBitVec");
    bool isLaserOn = (bits & L4D2_WEPUPGFLAG_LASER) != 0;
    
    if (!isLaserOn)
    {
        SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits | L4D2_WEPUPGFLAG_LASER);
    }
    else
    {
        SetEntProp(weapon, Prop_Send, "m_upgradeBitVec", bits ^ L4D2_WEPUPGFLAG_LASER);
    }

    StopHintForClient(client, "laser_toggle_status");
    ShowStatusHint(client, !isLaserOn);
}

// ====================================================================================================
//                  HOLD / HELPERS
// ====================================================================================================

bool HasLaserEligibleWeapon(int client)
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEdict(weapon) || !IsValidEntity(weapon)) return false;

    int primary = GetPlayerWeaponSlot(client, 0);
    if (weapon != primary) return false;

    char netclass[128];
    GetEntityNetClass(weapon, netclass, sizeof(netclass));
    if (FindSendPropInfo(netclass, "m_upgradeBitVec") < 1)
        return false;

    return true;
}

bool IsLaserOnActiveWeapon(int client)
{
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= 0 || !IsValidEdict(weapon) || !IsValidEntity(weapon)) return false;

    char netclass[128];
    GetEntityNetClass(weapon, netclass, sizeof(netclass));
    if (FindSendPropInfo(netclass, "m_upgradeBitVec") < 1) return false;

    return (GetEntProp(weapon, Prop_Send, "m_upgradeBitVec") & L4D2_WEPUPGFLAG_LASER) != 0;
}

void ClearClientState(int client)
{
    g_bHoldActive[client]   = false;
    g_bUseLocked[client]    = false;
    g_fHoldStartTime[client]= 0.0;
    g_iHoldWeaponRef[client]= INVALID_ENT_REFERENCE;
    ClearClientHoldProgress(client);
}

void StartHoldProgress(int client, int weapon)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        return;
    }

    g_bHoldActive[client]    = true;
    g_fHoldStartTime[client] = GetGameTime();
    g_iHoldWeaponRef[client] = EntIndexToEntRef(weapon);
    SetClientHoldProgress(client, g_hCvarHoldSeconds.FloatValue, g_fHoldStartTime[client]);
}

void CancelHoldProgress(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (!g_bHoldActive[client])
    {
        return;
    }

    g_bHoldActive[client]    = false;
    g_fHoldStartTime[client] = 0.0;
    g_iHoldWeaponRef[client] = INVALID_ENT_REFERENCE;
    ClearClientHoldProgress(client);
}

bool HasClientHoldProgressProps(int client)
{
    return HasEntProp(client, Prop_Send, "m_flProgressBarDuration")
        && HasEntProp(client, Prop_Send, "m_flProgressBarStartTime");
}

void SetClientHoldProgress(int client, float duration, float startTime)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || !HasClientHoldProgressProps(client))
    {
        return;
    }

    SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", startTime);
    SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", duration);
}

void ClearClientHoldProgress(int client)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client) || !HasClientHoldProgressProps(client))
    {
        return;
    }

    SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
    SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
}

bool IsClientBusy(int client)
{
    int reviveOwner = GetEntPropEnt(client, Prop_Send, "m_reviveOwner");
    return (reviveOwner > 0 && reviveOwner != client)
        || GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0
        || GetEntPropEnt(client, Prop_Send, "m_tongueOwner") > 0
        || GetEntPropEnt(client, Prop_Send, "m_carryAttacker") > 0
        || GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 0;
}

bool CanSendClientHintEvent(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && !IsFakeClient(client);
}

// ====================================================================================================
//                  INSTRUCTOR HINT HELPERS
// ====================================================================================================

/**
 * Send an instructor hint to a single client only (not broadcast).
 */
void ShowInstructorHintToClient(int client,
                                 const char[] hintName,
                                 const char[] caption,
                                 const char[] iconOnScreen,
                                 const char[] binding,
                                 int timeout,
                                 int r, int g, int b)
{
    if (!CanSendClientHintEvent(client))
    {
        return;
    }

    Event ev = CreateEvent("instructor_server_hint_create", true);
    if (ev == null) return;

    char color[16];
    Format(color, sizeof(color), "%d,%d,%d", r, g, b);

    ev.SetString("hint_name",            hintName);
    ev.SetInt   ("hint_target",          0);
    ev.SetString("hint_caption",         caption);
    ev.SetString("hint_color",           color);
    ev.SetString("hint_icon_onscreen",   iconOnScreen);
    ev.SetString("hint_icon_offscreen",  "");
    ev.SetString("hint_binding",         binding);
    ev.SetFloat ("hint_icon_offset",     0.0);
    ev.SetFloat ("hint_range",           0.0);
    ev.SetInt   ("hint_timeout",         timeout);
    ev.SetBool  ("hint_allow_nodraw_target", true);
    ev.SetBool  ("hint_nooffscreen",     true);
    ev.SetBool  ("hint_forcecaption",    true);
    ev.SetInt   ("hint_flags",           IHFLAG_STATIC);

    ev.FireToClient(client);
    delete ev;
}

/**
 * Stop a named instructor hint for a single client only.
 */
void StopHintForClient(int client, const char[] hintName)
{
    if (!CanSendClientHintEvent(client))
    {
        return;
    }

    Event ev = CreateEvent("instructor_server_hint_stop", true);
    if (ev == null) return;
    ev.SetString("hint_name", hintName);
    ev.FireToClient(client);
    delete ev;
}

/**
 * 4-second status hint after toggling.
 */
void ShowStatusHint(int client, bool laserOn)
{
    char caption[64];
    int r, g, b;

    if (laserOn)
    {
        Format(caption, sizeof(caption), "Laser: ON  (-10%% damage)");
        r = 255; g = 80;  b = 80;   // red
    }
    else
    {
        Format(caption, sizeof(caption), "Laser: OFF");
        r = 150; g = 150; b = 150;  // grey
    }

    ShowInstructorHintToClient(
        client,
        "laser_toggle_status",
        caption,
        "icon_tip",
        "",
        4,      // 4-second auto-dismiss
        r, g, b
    );
}
