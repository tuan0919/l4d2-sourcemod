/*
 *  [L4D2] Laser Toggle
 *
 *  Double-tap RELOAD while holding a primary weapon to toggle laser sight.
 *  Laser ON = -10% primary weapon bullet damage (accuracy tradeoff).
 *  Status shown via per-client instructor hints.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION      "1.1.0"
#define TEAM_SURVIVOR       2
#define DOUBLE_TAP_WINDOW   0.4     // seconds between two reload presses
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
    description = "Double-tap reload to toggle laser sight; ON = -10% primary weapon damage",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ====================================================================================================
//                  GLOBALS
// ====================================================================================================

bool    g_bReloadHeld[MAXPLAYERS + 1];
bool    g_bWaitingSecond[MAXPLAYERS + 1];
float   g_fLastReload[MAXPLAYERS + 1];

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
    StopHintForClient(client, "laser_toggle_usage");
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
//                  DOUBLE-TAP RELOAD DETECTION
// ====================================================================================================

public void OnPlayerRunCmdPost(int client, int buttons)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;
    if (GetClientTeam(client) != TEAM_SURVIVOR)
        return;

    bool eligible = HasLaserEligibleWeapon(client);

    // Switched away from primary — reset
    if (!eligible)
    {
        g_bWaitingSecond[client] = false;
        g_bReloadHeld[client]    = false;
        return;
    }

    bool reloadDown = (buttons & IN_RELOAD) != 0;

    // Rising edge: reload just pressed
    if (reloadDown && !g_bReloadHeld[client])
    {
        g_bReloadHeld[client] = true;

        if (!g_bWaitingSecond[client])
        {
            // First press — start window
            g_bWaitingSecond[client] = true;
            g_fLastReload[client]    = GetGameTime();
        }
        else
        {
            // Second press — check window
            float delta = GetGameTime() - g_fLastReload[client];
            if (delta <= DOUBLE_TAP_WINDOW)
                ToggleLaser(client);

            g_bWaitingSecond[client] = false;
        }
    }
    // Falling edge: reload released
    else if (!reloadDown && g_bReloadHeld[client])
    {
        g_bReloadHeld[client] = false;
    }

    // Timeout: first press expired — ignore and reset
    if (g_bWaitingSecond[client] &&
        GetGameTime() - g_fLastReload[client] > DOUBLE_TAP_WINDOW)
    {
        g_bWaitingSecond[client] = false;
    }
}

// ====================================================================================================
//                  WEAPON SWITCH — show / hide usage hint
// ====================================================================================================

public void Hook_WeaponSwitchPost(int client, int weapon)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return;
    if (GetClientTeam(client) != TEAM_SURVIVOR)
        return;

    if (HasLaserEligibleWeapon(client))
    {
        ShowUsageHint(client);

        // Re-show status if laser is already on (carried from previous weapon)
        if (IsLaserOnActiveWeapon(client))
            ShowStatusHint(client, true);
    }
    else
    {
        StopHintForClient(client, "laser_toggle_usage");
        StopHintForClient(client, "laser_toggle_status");
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

    StopHintForClient(client, "laser_toggle_usage");
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
//                  HELPERS
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
    g_bReloadHeld[client]    = false;
    g_bWaitingSecond[client] = false;
    g_fLastReload[client]    = 0.0;
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
    Event ev = CreateEvent("instructor_server_hint_stop", true);
    if (ev == null) return;
    ev.SetString("hint_name", hintName);
    ev.FireToClient(client);
    delete ev;
}

/**
 * Persistent usage hint shown when player equips a laser-eligible weapon.
 */
void ShowUsageHint(int client)
{
    StopHintForClient(client, "laser_toggle_usage");
    ShowInstructorHintToClient(
        client,
        "laser_toggle_usage",
        "Double-tap RELOAD to toggle laser sight",
        "icon_reload",
        "+reload",
        0,            // 0 = persistent
        200, 200, 50  // yellow
    );
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
