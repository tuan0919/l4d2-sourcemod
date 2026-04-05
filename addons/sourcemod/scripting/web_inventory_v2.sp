/**
 * web_inventory_v2.sp — L4D2 Web Dashboard Survivor Tracker (Event-Driven)
 *
 * Replaces polling-based web_inventory.sp with event-driven updates.
 * Updates are triggered only when game state actually changes.
 * A 0.5s debounce timer batches rapid events into a single file write.
 * A 10s safety fallback scan catches any missed events.
 *
 * Exports (per survivor, L4D2 team==2 only):
 *   name, model, alive, health, tempHealth, slot0..4
 *
 * Dependencies:
 *   - left4dhooks (Silvers) — weapon/incap/takeover forwards
 *   - SDKHooks — weapon switch hook
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION   "2.0.0"
#define OUTPUT_FILE      "data/web_players.json"
#define DEBOUNCE_DELAY   0.5    // seconds: max wait before writing JSON
#define SAFETY_INTERVAL  10.0   // seconds: fallback scan interval

// ─── Data Structures ────────────────────────────────────────────────────────

enum struct SurvivorState
{
    char name[64];
    char model[64];
    bool alive;
    int  health;
    int  tempHealth;
    char slot0[64];
    char slot1[64];
    char slot2[64];
    char slot3[64];
    char slot4[64];
    bool dirty;     // true = needs JSON update
}

// ─── Globals ─────────────────────────────────────────────────────────────────

StringMap g_Cache;          // Key: "1".."64" (client index), Value: SurvivorState
Handle    g_WriteTimer;     // Debounce write timer handle
bool      g_PendingWrite;   // True when a write is already scheduled
Handle    g_SafetyTimer;    // Periodic fallback scan timer

public Plugin myinfo =
{
    name        = "[L4D2] Web Dashboard Inventory Tracker v2",
    author      = "l4d2-dashboard",
    description = "Event-driven survivor state export to web_players.json",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ─── Lifecycle ───────────────────────────────────────────────────────────────

public void OnPluginStart()
{
    g_Cache        = new StringMap();
    g_WriteTimer   = null;
    g_PendingWrite = false;
    g_SafetyTimer  = null;

    // Ensure output directory exists
    char sDataDir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sDataDir, sizeof(sDataDir), "data");
    if (!DirExists(sDataDir))
        CreateDirectory(sDataDir, 511);

    // Game events
    HookEvent("player_hurt",       Event_PlayerHurt);
    HookEvent("player_death",      Event_PlayerDeath);
    HookEvent("player_spawn",      Event_PlayerSpawn);
    HookEvent("player_team",       Event_PlayerTeam);
    HookEvent("revive_success",    Event_ReviveSuccess);
    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);

    LogMessage("[WebDash] web_inventory_v2 loaded.");

    // Support hot-reload mid-game
    char mapName[64];
    GetCurrentMap(mapName, sizeof(mapName));
    if (mapName[0] != '\0')
        OnMapStart();
}

public void OnMapStart()
{
    // Clear cache on each new map
    g_Cache.Clear();

    // Cancel any pending timers
    if (g_WriteTimer != null)  { KillTimer(g_WriteTimer);  g_WriteTimer  = null; }
    if (g_SafetyTimer != null) { KillTimer(g_SafetyTimer); g_SafetyTimer = null; }
    g_PendingWrite = false;

    // Safety fallback — catches missed events every 10s
    g_SafetyTimer = CreateTimer(SAFETY_INTERVAL, Timer_SafetyScan, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    // Seed cache for any clients already in game (hot-reload case)
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && GetClientTeam(i) == 2)
        {
            InitializeSurvivorCache(i);
            SDKHook(i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
        }
    }

    // Write initial state if survivors already present
    if (g_Cache.Size > 0)
        ScheduleWrite();
}

public void OnMapEnd()
{
    if (g_WriteTimer  != null) { KillTimer(g_WriteTimer);  g_WriteTimer  = null; }
    if (g_SafetyTimer != null) { KillTimer(g_SafetyTimer); g_SafetyTimer = null; }
    g_PendingWrite = false;
    g_Cache.Clear();
}

public void OnClientPutInServer(int client)
{
    if (!IsClientInGame(client)) return;

    // Delay init slightly — team assignment may not be set yet at this callback
    DataPack dp = new DataPack();
    dp.WriteCell(client);
    CreateTimer(0.5, Timer_LateClientInit, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public Action Timer_LateClientInit(Handle timer, DataPack dp)
{
    dp.Reset();
    int client = dp.ReadCell();
    if (!IsClientInGame(client)) return Plugin_Stop;
    if (GetClientTeam(client) == 2)
    {
        InitializeSurvivorCache(client);
        SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
        MarkDirty(client);
        ScheduleWrite();
    }
    return Plugin_Stop;
}

public void OnClientDisconnecting(int client)
{
    SDKUnhook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);

    char key[8];
    IntToString(client, key, sizeof(key));
    g_Cache.Remove(key);

    // Write updated state without this client
    ScheduleWrite();
}

// ─── Left4DHooks Forwards ────────────────────────────────────────────────────

// Fires when a survivor dies and drops weapons
// left4dhooks.inc:3066
public void L4D_OnDeathDroppedWeapons(int client, int weapons[6])
{
    if (!IsValidSurvivor(client)) return;
    // Delay: engine processes weapon removal after this forward fires
    DataPack dp = new DataPack();
    dp.WriteCell(client);
    CreateTimer(0.1, Timer_DelayedEquipmentUpdate, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

// Fires when a bot/player picks up a scavenge item
// left4dhooks.inc:3114
public Action L4D2_OnFindScavengeItem(int client, int &item)
{
    if (!IsValidSurvivor(client)) return Plugin_Continue;
    DataPack dp = new DataPack();
    dp.WriteCell(client);
    CreateTimer(0.1, Timer_DelayedEquipmentUpdate, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return Plugin_Continue;
}

// Fires when a player starts using a backpack item (medkit, pills, adrenaline, defib)
// left4dhooks.inc:4022
public Action L4D2_BackpackItem_StartAction(int client, int entity, any type)
{
    if (!IsValidSurvivor(client)) return Plugin_Continue;
    DataPack dp = new DataPack();
    dp.WriteCell(client);
    CreateTimer(0.1, Timer_DelayedEquipmentUpdate, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return Plugin_Continue;
}

// Fires after a survivor is incapacitated
// left4dhooks.inc:3033
public void L4D_OnIncapacitated_Post(int client, int inflictor, int attacker, float damage, int damagetype)
{
    if (!IsValidSurvivor(client)) return;
    UpdateSurvivorHealth(client);
    MarkDirty(client);
    ScheduleWrite();
}

// Fires after a player takes over a bot (or bot takes over player)
// left4dhooks.inc:1659
public void L4D_OnTakeOverBot_Post(int client, bool success)
{
    if (!success) return;
    // Update state for all survivors — name/bot status may have changed
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsValidSurvivor(i))
        {
            UpdateSurvivorState(i);
            MarkDirty(i);
        }
    }
    ScheduleWrite();
}

// ─── SDKHooks ────────────────────────────────────────────────────────────────

// Fires after weapon switch completes (post = final state is set)
public void Hook_WeaponSwitchPost(int client, int weapon)
{
    if (!IsValidSurvivor(client)) return;
    UpdateSurvivorEquipment(client);
    MarkDirty(client);
    ScheduleWrite();
}

// ─── Game Events ─────────────────────────────────────────────────────────────

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidSurvivor(client)) return;
    UpdateSurvivorHealth(client);
    MarkDirty(client);
    ScheduleWrite();
}

public void Event_ReviveSuccess(Event event, const char[] name, bool dontBroadcast)
{
    // "subject" = the player who was revived
    int client = GetClientOfUserId(event.GetInt("subject"));
    if (!IsValidSurvivor(client)) return;
    UpdateSurvivorHealth(client);
    MarkDirty(client);
    ScheduleWrite();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidSurvivor(client)) return;
    UpdateSurvivorState(client);
    MarkDirty(client);
    ScheduleWrite();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;
    // Team may just be assigned — check after a frame
    DataPack dp = new DataPack();
    dp.WriteCell(client);
    CreateTimer(0.1, Timer_DelayedFullUpdate, dp, TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0 || !IsClientInGame(client)) return;
    int newTeam = event.GetInt("team");

    if (newTeam == 2)
    {
        // Joined survivor team
        InitializeSurvivorCache(client);
        SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
        MarkDirty(client);
        ScheduleWrite();
    }
    else
    {
        // Left survivor team — remove from cache
        char key[8];
        IntToString(client, key, sizeof(key));
        g_Cache.Remove(key);
        SDKUnhook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
        ScheduleWrite();
    }
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client <= 0) return;
    char key[8];
    IntToString(client, key, sizeof(key));
    g_Cache.Remove(key);
    SDKUnhook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
    ScheduleWrite();
}

// ─── Delayed Timer Callbacks ─────────────────────────────────────────────────

public Action Timer_DelayedEquipmentUpdate(Handle timer, DataPack dp)
{
    dp.Reset();
    int client = dp.ReadCell();
    if (!IsValidSurvivor(client)) return Plugin_Stop;
    UpdateSurvivorEquipment(client);
    MarkDirty(client);
    ScheduleWrite();
    return Plugin_Stop;
}

public Action Timer_DelayedFullUpdate(Handle timer, DataPack dp)
{
    dp.Reset();
    int client = dp.ReadCell();
    if (client <= 0 || !IsClientInGame(client)) return Plugin_Stop;
    if (GetClientTeam(client) == 2)
    {
        UpdateSurvivorState(client);
        MarkDirty(client);
        ScheduleWrite();
    }
    return Plugin_Stop;
}

// ─── Safety Fallback Timer ────────────────────────────────────────────────────

// Runs every 10s to catch any events that slipped through
public Action Timer_SafetyScan(Handle timer)
{
    bool anyDirty = false;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || GetClientTeam(i) != 2) continue;

        char key[8];
        IntToString(i, key, sizeof(key));

        SurvivorState cached;
        bool inCache = g_Cache.GetArray(key, cached, sizeof(cached));

        if (!inCache)
        {
            // New survivor not in cache yet
            InitializeSurvivorCache(i);
            SDKHook(i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
            MarkDirty(i);
            anyDirty = true;
            continue;
        }

        // Compare current state against cache
        if (HasStateChanged(i, cached))
        {
            UpdateSurvivorState(i);
            MarkDirty(i);
            anyDirty = true;
        }
    }

    if (anyDirty)
        ScheduleWrite();

    return Plugin_Continue;
}

// ─── Cache Management ────────────────────────────────────────────────────────

void InitializeSurvivorCache(int client)
{
    char key[8];
    IntToString(client, key, sizeof(key));

    SurvivorState state;
    GetClientName(client, state.name, sizeof(state.name));
    GetClientModel(client, state.model, sizeof(state.model));
    state.alive      = IsPlayerAlive(client);
    state.health     = state.alive ? GetClientHealth(client) : 0;
    state.tempHealth = state.alive ? RoundToFloor(GetEntPropFloat(client, Prop_Send, "m_healthBuffer")) : 0;
    ReadWeaponSlots(client, state);
    state.dirty = true;

    g_Cache.SetArray(key, state, sizeof(state));
}

// Update all fields for a survivor
void UpdateSurvivorState(int client)
{
    char key[8];
    IntToString(client, key, sizeof(key));

    SurvivorState state;
    if (!g_Cache.GetArray(key, state, sizeof(state)))
    {
        InitializeSurvivorCache(client);
        return;
    }

    GetClientName(client, state.name, sizeof(state.name));
    GetClientModel(client, state.model, sizeof(state.model));
    state.alive      = IsPlayerAlive(client);
    state.health     = state.alive ? GetClientHealth(client) : 0;
    state.tempHealth = state.alive ? RoundToFloor(GetEntPropFloat(client, Prop_Send, "m_healthBuffer")) : 0;
    ReadWeaponSlots(client, state);

    g_Cache.SetArray(key, state, sizeof(state));
}

// Update only health/alive fields
void UpdateSurvivorHealth(int client)
{
    char key[8];
    IntToString(client, key, sizeof(key));

    SurvivorState state;
    if (!g_Cache.GetArray(key, state, sizeof(state)))
    {
        InitializeSurvivorCache(client);
        return;
    }

    state.alive      = IsPlayerAlive(client);
    state.health     = state.alive ? GetClientHealth(client) : 0;
    state.tempHealth = state.alive ? RoundToFloor(GetEntPropFloat(client, Prop_Send, "m_healthBuffer")) : 0;

    g_Cache.SetArray(key, state, sizeof(state));
}

// Update only equipment/weapon slots
void UpdateSurvivorEquipment(int client)
{
    char key[8];
    IntToString(client, key, sizeof(key));

    SurvivorState state;
    if (!g_Cache.GetArray(key, state, sizeof(state)))
    {
        InitializeSurvivorCache(client);
        return;
    }

    ReadWeaponSlots(client, state);

    g_Cache.SetArray(key, state, sizeof(state));
}

void MarkDirty(int client)
{
    char key[8];
    IntToString(client, key, sizeof(key));

    SurvivorState state;
    if (!g_Cache.GetArray(key, state, sizeof(state))) return;
    state.dirty = true;
    g_Cache.SetArray(key, state, sizeof(state));
}

// Returns true if live game state differs from cached state
bool HasStateChanged(int client, const SurvivorState cached)
{
    bool liveAlive = IsPlayerAlive(client);
    if (liveAlive != cached.alive) return true;

    if (liveAlive)
    {
        if (GetClientHealth(client) != cached.health) return true;
        int tempHp = RoundToFloor(GetEntPropFloat(client, Prop_Send, "m_healthBuffer"));
        if (tempHp != cached.tempHealth) return true;
    }

    // Check weapons
    SurvivorState live;
    ReadWeaponSlots(client, live);
    if (!StrEqual(live.slot0, cached.slot0)) return true;
    if (!StrEqual(live.slot1, cached.slot1)) return true;
    if (!StrEqual(live.slot2, cached.slot2)) return true;
    if (!StrEqual(live.slot3, cached.slot3)) return true;
    if (!StrEqual(live.slot4, cached.slot4)) return true;

    return false;
}

// ─── Debounce Write Scheduler ────────────────────────────────────────────────

void ScheduleWrite()
{
    if (g_PendingWrite) return;  // Already scheduled — debounce active

    g_PendingWrite = true;

    if (g_WriteTimer != null)
    {
        KillTimer(g_WriteTimer);
        g_WriteTimer = null;
    }

    g_WriteTimer = CreateTimer(DEBOUNCE_DELAY, Timer_WriteJSON, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_WriteJSON(Handle timer)
{
    g_WriteTimer   = null;
    g_PendingWrite = false;
    WriteJSONFile();
    return Plugin_Stop;
}

void WriteJSONFile()
{
    char jsonPath[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, jsonPath, sizeof(jsonPath), OUTPUT_FILE);

    File f = OpenFile(jsonPath, "w");
    if (f == null)
    {
        LogError("[WebDash] Cannot open %s for writing", jsonPath);
        return;
    }

    f.WriteString("[\n", false);

    bool firstEntry = true;
    StringMapSnapshot snap = g_Cache.Snapshot();

    for (int i = 0; i < snap.Length; i++)
    {
        char key[8];
        snap.GetKey(i, key, sizeof(key));

        SurvivorState state;
        if (!g_Cache.GetArray(key, state, sizeof(state))) continue;

        int client = StringToInt(key);
        if (!IsClientInGame(client)) continue;

        if (!firstEntry) f.WriteString(",\n", false);
        firstEntry = false;

        char nameEscaped[128];
        strcopy(nameEscaped, sizeof(nameEscaped), state.name);
        EscapeJsonString(nameEscaped, sizeof(nameEscaped));

        char modelShort[64];
        ExtractModelName(state.model, modelShort, sizeof(modelShort));

        int  isBot   = IsFakeClient(client) ? 1 : 0;
        char aliveStr[8];
        aliveStr = state.alive ? "true" : "false";

        char entry[1024];
        FormatEx(entry, sizeof(entry),
            "  {\"name\":\"%s\",\"bot\":%d,\"model\":\"%s\",\"alive\":%s,\"hp\":%d,\"tempHp\":%d,\"slot0\":\"%s\",\"slot1\":\"%s\",\"slot2\":\"%s\",\"slot3\":\"%s\",\"slot4\":\"%s\"}",
            nameEscaped, isBot, modelShort, aliveStr, state.health, state.tempHealth,
            state.slot0, state.slot1, state.slot2, state.slot3, state.slot4
        );
        f.WriteString(entry, false);

        // Clear dirty flag after write
        state.dirty = false;
        g_Cache.SetArray(key, state, sizeof(state));
    }

    delete snap;
    f.WriteString("\n]\n", false);
    delete f;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

// Returns true if client is a valid in-game survivor
bool IsValidSurvivor(int client)
{
    return (client > 0
         && client <= MaxClients
         && IsClientInGame(client)
         && GetClientTeam(client) == 2);
}

// Reads all 5 weapon slots into a SurvivorState struct
void ReadWeaponSlots(int client, SurvivorState state)
{
    char slotBuf[64];
    int  wpn;

    // Reset to "null" (means empty slot in JSON)
    state.slot0 = "null";
    state.slot1 = "null";
    state.slot2 = "null";
    state.slot3 = "null";
    state.slot4 = "null";

    // Slot 0: primary weapon
    wpn = GetPlayerWeaponSlot(client, 0);
    if (wpn != -1)
    {
        GetEntityClassname(wpn, slotBuf, sizeof(slotBuf));
        StripWeaponPrefix(slotBuf, state.slot0, sizeof(state.slot0));
    }

    // Slot 1: secondary / melee
    wpn = GetPlayerWeaponSlot(client, 1);
    if (wpn != -1)
    {
        GetEntityClassname(wpn, slotBuf, sizeof(slotBuf));
        StripWeaponPrefix(slotBuf, state.slot1, sizeof(state.slot1));
    }

    // Slot 2: throwable
    wpn = GetPlayerWeaponSlot(client, 2);
    if (wpn != -1)
    {
        GetEntityClassname(wpn, slotBuf, sizeof(slotBuf));
        StripWeaponPrefix(slotBuf, state.slot2, sizeof(state.slot2));
    }

    // Slot 3: medkit / defibrillator
    wpn = GetPlayerWeaponSlot(client, 3);
    if (wpn != -1)
    {
        GetEntityClassname(wpn, slotBuf, sizeof(slotBuf));
        StripWeaponPrefix(slotBuf, state.slot3, sizeof(state.slot3));
    }

    // Slot 4: pills / adrenaline
    wpn = GetPlayerWeaponSlot(client, 4);
    if (wpn != -1)
    {
        GetEntityClassname(wpn, slotBuf, sizeof(slotBuf));
        StripWeaponPrefix(slotBuf, state.slot4, sizeof(state.slot4));
    }
}

// Strip "weapon_" prefix and copy to out
void StripWeaponPrefix(const char[] wpnName, char[] out, int outLen)
{
    if (strncmp(wpnName, "weapon_", 7) == 0)
        strcopy(out, outLen, wpnName[7]);
    else
        strcopy(out, outLen, wpnName);
}

// In-place JSON string escaping (double-quotes and backslashes)
void EscapeJsonString(char[] s, int maxlen)
{
    char buf[256];
    int  j = 0;
    for (int i = 0; i < strlen(s) && j < maxlen - 2; i++)
    {
        if (s[i] == '"' || s[i] == '\\')
            buf[j++] = '\\';
        buf[j++] = s[i];
    }
    buf[j] = '\0';
    strcopy(s, maxlen, buf);
}

// Extract short model name from full path
// e.g. "models/survivors/survivor_gambler.mdl" → "gambler"
void ExtractModelName(const char[] fullPath, char[] out, int outLen)
{
    int lastSlash = -1;
    for (int i = strlen(fullPath) - 1; i >= 0; i--)
    {
        if (fullPath[i] == '/') { lastSlash = i; break; }
    }
    char filename[64];
    strcopy(filename, sizeof(filename), fullPath[lastSlash + 1]);
    int dot = FindCharInString(filename, '.', true);
    if (dot != -1) filename[dot] = '\0';
    if (strncmp(filename, "survivor_", 9) == 0)
        strcopy(out, outLen, filename[9]);
    else
        strcopy(out, outLen, filename);
}
