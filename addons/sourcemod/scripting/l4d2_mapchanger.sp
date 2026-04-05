/**
 * ============================================================================
 *  l4d2_mapchanger.sp
 *  "Admin Map Changer" for Left 4 Dead 2 (SourceMod 1.11+)
 *
 *  Description:
 *    Provides admins with !cm (chat) / sm_cm (console) commands that open a
 *    fully-paginated panel listing every map on the server — including custom
 *    and workshop maps.  Clicking any map triggers a countdown then changes
 *    the server to that map and announces who triggered the change.
 *
 *  Map list sources (merged, de-duplicated, sorted A-Z):
 *    1. ReadMapList()         → mapcycle.txt / maplists.cfg entries
 *    2. OpenDirectory("maps") → every .bsp on disk (catches workshop maps)
 *
 *  Commands:
 *    !cm  / /cm      (chat)    — Open Map Changer menu  [admin only]
 *    sm_cm           (console) — Open Map Changer menu  [admin only]
 *    sm_reloadmaps   (console) — Force-reload the map list cache
 *
 *  Required admin flag: ADMFLAG_CHANGEMAP  (flag 'd')
 *
 *  CVars  (auto-generated in cfg/sourcemod/l4d2_mapchanger.cfg):
 *    l4d2_mc_countdown      – Seconds before map changes (0 = instant, default 5)
 *    l4d2_mc_maps_per_page  – Maps per page, 1-7 (default 7)
 *
 *  Installation:
 *    1.  addons/sourcemod/scripting/l4d2_mapchanger.sp
 *    2.  spcomp l4d2_mapchanger.sp
 *    3.  addons/sourcemod/plugins/l4d2_mapchanger.smx
 * ============================================================================
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

// ── Plugin metadata ──────────────────────────────────────────────────────────
#define PLUGIN_VERSION   "1.2.0"
#define PLUGIN_TAG       "[MapChanger]"

// ── Panel key layout constants ────────────────────────────────────────────────
// Source Engine panels: keys 1-9 selectable, 0 = exit.
// We reserve 8 = Prev, 9 = Next, 0 = Exit → usable map slots per page = 7.
#define MAX_PER_PAGE     7
#define MAP_NAME_LEN     128

// ── Per-client page tracking ──────────────────────────────────────────────────
int g_iPage[MAXPLAYERS + 1];

// ── Global map list ───────────────────────────────────────────────────────────
ArrayList g_aMapList;
int       g_iMapSerial = -1;

// ── Countdown state ───────────────────────────────────────────────────────────
char   g_sPendingMap[MAP_NAME_LEN];
Handle g_hCountdownTimer = null;
int    g_iCountdownLeft  = 0;

// ── ConVars ───────────────────────────────────────────────────────────────────
ConVar g_cvCountdown;
ConVar g_cvPerPage;

// =============================================================================
public Plugin myinfo =
{
    name        = "L4D2 Admin Map Changer",
    author      = "Custom",
    description = "Paginated admin map-change panel with full custom-map support",
    version     = PLUGIN_VERSION,
    url         = ""
};

// =============================================================================
//  OnPluginStart
// =============================================================================
public void OnPluginStart()
{
    g_cvCountdown = CreateConVar(
        "l4d2_mc_countdown", "5",
        "Seconds of countdown before the map change executes. 0 = instant.",
        FCVAR_NOTIFY, true, 0.0, true, 60.0);

    g_cvPerPage = CreateConVar(
        "l4d2_mc_maps_per_page", "7",
        "Number of maps shown per panel page (1-7).",
        FCVAR_NOTIFY, true, 1.0, true, float(MAX_PER_PAGE));

    AutoExecConfig(true, "l4d2_mapchanger");

    CreateConVar("l4d2_mc_version", PLUGIN_VERSION,
        "Map Changer version", FCVAR_NOTIFY | FCVAR_DONTRECORD);

    RegAdminCmd("sm_cm",         Cmd_MapChanger, ADMFLAG_CHANGEMAP,
        "Open the Admin Map Changer panel");
    RegAdminCmd("sm_reloadmaps", Cmd_ReloadMaps, ADMFLAG_CHANGEMAP,
        "Force-reload the server map list cache");

    AddCommandListener(Listener_SayCmd, "say");
    AddCommandListener(Listener_SayCmd, "say_team");

    g_aMapList = new ArrayList(ByteCountToCells(MAP_NAME_LEN));
    BuildMapList();

    PrintToServer("%s Loaded v%s — %d maps indexed.",
        PLUGIN_TAG, PLUGIN_VERSION, g_aMapList.Length);
}

// =============================================================================
//  OnMapStart – rebuild list each map load so new custom maps appear
// =============================================================================
public void OnMapStart()
{
    BuildMapList();
}

// =============================================================================
//  BuildMapList
//  Merges ReadMapList() (mapcycle/maplists.cfg) with a raw directory scan
//  of maps/*.bsp so workshop/custom maps not in mapcycle are included.
// =============================================================================
void BuildMapList()
{
    ArrayList merged = new ArrayList(ByteCountToCells(MAP_NAME_LEN));

    // ── Source 1: SourceMod ReadMapList ──────────────────────────────────────
    ArrayList smList = new ArrayList(ByteCountToCells(MAP_NAME_LEN));
    ReadMapList(smList, g_iMapSerial, "default",
        MAPLIST_FLAG_CLEARARRAY | MAPLIST_FLAG_MAPSFOLDER);

    int n = smList.Length;
    for (int i = 0; i < n; i++)
    {
        char buf[MAP_NAME_LEN];
        smList.GetString(i, buf, sizeof(buf));
        StripMapExtension(buf, sizeof(buf));
        if (buf[0] != '\0' && merged.FindString(buf) == -1)
            merged.PushString(buf);
    }
    delete smList;

    // ── Source 2: Raw .bsp directory scan ────────────────────────────────────
    // use_valve_fs=true so all mounted search paths (including workshop) are checked.
    DirectoryListing dir = OpenDirectory("maps", true, "GAME");
    if (dir != null)
    {
        char entry[MAP_NAME_LEN];
        FileType ft;

        while (ReadDirEntry(dir, entry, sizeof(entry), ft))
        {
            if (ft != FileType_File) continue;

            int len = strlen(entry);
            if (len <= 4) continue;

            // Only process .bsp files
            if (!StrEqual(entry[len - 4], ".bsp", false)) continue;

            // Strip the .bsp extension
            entry[len - 4] = '\0';

            // Skip dot-entries and empty strings
            if (entry[0] == '\0' || entry[0] == '.') continue;

            if (merged.FindString(entry) == -1)
                merged.PushString(entry);
        }
        delete dir;
    }
    else
    {
        PrintToServer("%s Warning: Could not open maps/ directory for scanning.", PLUGIN_TAG);
    }

    // ── Sort A-Z and publish ──────────────────────────────────────────────────
    merged.Sort(Sort_Ascending, Sort_String);

    delete g_aMapList;
    g_aMapList = merged;

    PrintToServer("%s Map list built: %d maps total.", PLUGIN_TAG, g_aMapList.Length);
}

// =============================================================================
//  StripMapExtension – remove leading "maps/" prefix and trailing ".bsp"
// =============================================================================
void StripMapExtension(char[] name, int maxlen)
{
    if (strncmp(name, "maps/", 5, false) == 0)
        strcopy(name, maxlen, name[5]);

    int len = strlen(name);
    if (len > 4 && StrEqual(name[len - 4], ".bsp", false))
        name[len - 4] = '\0';
}

// =============================================================================
//  Cmd_ReloadMaps
// =============================================================================
public Action Cmd_ReloadMaps(int client, int args)
{
    g_iMapSerial = -1;
    BuildMapList();
    ReplyToCommand(client, "%s Map list reloaded — %d maps found.",
        PLUGIN_TAG, g_aMapList.Length);
    return Plugin_Handled;
}

// =============================================================================
//  Listener_SayCmd – intercept !cm / /cm in chat
// =============================================================================
public Action Listener_SayCmd(int client, const char[] command, int argc)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return Plugin_Continue;

    char text[16];
    GetCmdArg(1, text, sizeof(text));

    if (!StrEqual(text, "!cm", false) && !StrEqual(text, "/cm", false))
        return Plugin_Continue;

    if (!CheckCommandAccess(client, "sm_cm", ADMFLAG_CHANGEMAP))
    {
        PrintToChat(client, "%s You do not have permission to use Map Changer.", PLUGIN_TAG);
        return Plugin_Handled;
    }

    g_iPage[client] = 0;
    OpenMapPanel(client);
    return Plugin_Handled;
}

// =============================================================================
//  Cmd_MapChanger
// =============================================================================
public Action Cmd_MapChanger(int client, int args)
{
    if (client == 0)
    {
        ReplyToCommand(client, "%s This command must be used in-game.", PLUGIN_TAG);
        return Plugin_Handled;
    }
    if (g_aMapList.Length == 0)
    {
        ReplyToCommand(client, "%s No maps available. Try sm_reloadmaps.", PLUGIN_TAG);
        return Plugin_Handled;
    }

    g_iPage[client] = 0;
    OpenMapPanel(client);
    return Plugin_Handled;
}

// =============================================================================
//  OpenMapPanel
//
//  Panel layout (DrawItem assigns keys sequentially starting from 1):
//
//    Title: [ Map Changer ]  Page X/Y  (N maps)
//           Current: <mapname>
//
//    Key 1-7 : map names  (or SPACER if page has fewer than 7 maps)
//    Key 8   : ◄ Previous Page
//    Key 9   : ► Next Page
//    Key 0   : Exit
// =============================================================================
void OpenMapPanel(int client)
{
    int totalMaps   = g_aMapList.Length;
    int perPage     = g_cvPerPage.IntValue;
    if (perPage < 1)            perPage = 1;
    if (perPage > MAX_PER_PAGE)  perPage = MAX_PER_PAGE;

    int totalPages = (totalMaps + perPage - 1) / perPage;
    if (totalPages < 1) totalPages = 1;

    // Clamp page index
    if (g_iPage[client] < 0)            g_iPage[client] = 0;
    if (g_iPage[client] >= totalPages)  g_iPage[client] = totalPages - 1;

    int page     = g_iPage[client];
    int startIdx = page * perPage;
    int endIdx   = startIdx + perPage;
    if (endIdx > totalMaps) endIdx = totalMaps;

    char currentMap[MAP_NAME_LEN];
    GetCurrentMap(currentMap, sizeof(currentMap));

    Panel panel = new Panel();

    // ── Title ─────────────────────────────────────────────────────────────────
    char title[196];
    Format(title, sizeof(title),
        "[ Map Changer ]  Page %d/%d  (%d maps)\nCurrent: %s",
        page + 1, totalPages, totalMaps, currentMap);
    panel.SetTitle(title);

    panel.DrawText(" ");   // visual spacer (no key consumed)

    // ── Map entries (keys 1 … perPage) ───────────────────────────────────────
    int slot = 1;
    for (int i = startIdx; i < endIdx; i++, slot++)
    {
        char mapName[MAP_NAME_LEN];
        g_aMapList.GetString(i, mapName, sizeof(mapName));

        char display[MAP_NAME_LEN + 8];
        if (StrEqual(mapName, currentMap, false))
            Format(display, sizeof(display), "* %s *", mapName);
        else
            strcopy(display, sizeof(display), mapName);

        panel.DrawItem(display);
    }

    // ── Pad empty slots so Prev/Next always land on keys 8 / 9 ───────────────
    while (slot <= MAX_PER_PAGE)
    {
        panel.DrawItem(" ", ITEMDRAW_SPACER);
        slot++;
    }

    panel.DrawText("──────────────────");

    // ── Key 8: Previous ───────────────────────────────────────────────────────
    if (page > 0)
        panel.DrawItem("< Previous Page");
    else
        panel.DrawItem("< Previous Page", ITEMDRAW_DISABLED);

    // ── Key 9: Next ───────────────────────────────────────────────────────────
    if (page < totalPages - 1)
        panel.DrawItem("> Next Page");
    else
        panel.DrawItem("> Next Page", ITEMDRAW_DISABLED);

    // ── Key 0: Exit ───────────────────────────────────────────────────────────
    panel.CurrentKey = 0;
    panel.DrawItem("Exit", ITEMDRAW_CONTROL);

    panel.Send(client, PanelHandler_MapMenu, 30);
    delete panel;
}

// =============================================================================
//  PanelHandler_MapMenu
// =============================================================================
public int PanelHandler_MapMenu(Menu menu, MenuAction action, int client, int key)
{
    if (action == MenuAction_Select)
    {
        int perPage    = g_cvPerPage.IntValue;
        if (perPage < 1)            perPage = 1;
        if (perPage > MAX_PER_PAGE)  perPage = MAX_PER_PAGE;

        int totalMaps  = g_aMapList.Length;
        int totalPages = (totalMaps + perPage - 1) / perPage;

        int PREV_KEY = MAX_PER_PAGE + 1;   // 8
        int NEXT_KEY = MAX_PER_PAGE + 2;   // 9

        if (key == PREV_KEY)
        {
            if (g_iPage[client] > 0) g_iPage[client]--;
            OpenMapPanel(client);
        }
        else if (key == NEXT_KEY)
        {
            if (g_iPage[client] < totalPages - 1) g_iPage[client]++;
            OpenMapPanel(client);
        }
        else if (key >= 1 && key <= MAX_PER_PAGE)
        {
            int mapIdx = g_iPage[client] * perPage + (key - 1);
            if (mapIdx >= 0 && mapIdx < totalMaps)
            {
                char chosenMap[MAP_NAME_LEN];
                g_aMapList.GetString(mapIdx, chosenMap, sizeof(chosenMap));
                InitiateMapChange(client, chosenMap);
            }
            else
            {
                // Spacer was pressed — just reopen
                OpenMapPanel(client);
            }
        }
        // key == 0 → Exit, nothing to do
    }

    return 0;
}

// =============================================================================
//  InitiateMapChange
// =============================================================================
void InitiateMapChange(int client, const char[] mapName)
{
    if (!IsMapValid(mapName))
    {
        PrintToChat(client,
            "%s \"%s\" is not a valid/loaded map on this server.",
            PLUGIN_TAG, mapName);
        OpenMapPanel(client);
        return;
    }

    // Cancel any running countdown first
    if (g_hCountdownTimer != null)
    {
        KillTimer(g_hCountdownTimer);
        g_hCountdownTimer = null;
        PrintToChatAll("%s Previous map change cancelled.", PLUGIN_TAG);
    }

    strcopy(g_sPendingMap, sizeof(g_sPendingMap), mapName);

    char adminName[MAX_NAME_LENGTH];
    GetClientName(client, adminName, sizeof(adminName));

    int countdown = g_cvCountdown.IntValue;

    if (countdown <= 0)
    {
        PrintToChatAll("%s \x04%s\x01 is changing the map to \x05%s\x01 now!",
            PLUGIN_TAG, adminName, mapName);
        LogAction(client, -1,
            "[MapChanger] %L triggered instant map change to \"%s\"", client, mapName);
        CreateTimer(0.8, Timer_DoMapChange, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        g_iCountdownLeft = countdown;
        PrintToChatAll(
            "%s \x04%s\x01 is changing the map to \x05%s\x01 in \x03%d\x01 second(s).",
            PLUGIN_TAG, adminName, mapName, countdown);
        LogAction(client, -1,
            "[MapChanger] %L initiated map change to \"%s\" (countdown %ds)",
            client, mapName, countdown);
        g_hCountdownTimer = CreateTimer(1.0, Timer_Countdown, _,
            TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
    }
}

// =============================================================================
//  Timer_Countdown
// =============================================================================
public Action Timer_Countdown(Handle timer)
{
    g_iCountdownLeft--;

    if (g_iCountdownLeft <= 0)
    {
        g_hCountdownTimer = null;
        PrintToChatAll("%s Changing map to \x05%s\x01 now!", PLUGIN_TAG, g_sPendingMap);
        CreateTimer(0.5, Timer_DoMapChange, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    // Print at 5,4,3,2,1 and every 10s mark to avoid chat spam
    if (g_iCountdownLeft <= 5 || (g_iCountdownLeft % 10) == 0)
    {
        PrintToChatAll("%s Map changing to \x05%s\x01 in \x03%d\x01 second(s)...",
            PLUGIN_TAG, g_sPendingMap, g_iCountdownLeft);
    }

    return Plugin_Continue;
}

// =============================================================================
//  Timer_DoMapChange
// =============================================================================
public Action Timer_DoMapChange(Handle timer)
{
    if (g_sPendingMap[0] != '\0')
        ForceChangeLevel(g_sPendingMap, "Admin Map Change - l4d2_mapchanger");

    return Plugin_Stop;
}

// =============================================================================
//  OnClientDisconnect
// =============================================================================
public void OnClientDisconnect(int client)
{
    g_iPage[client] = 0;
}
