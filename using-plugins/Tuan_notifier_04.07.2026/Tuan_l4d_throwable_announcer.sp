/**
// ====================================================================================================
Change Log:

1.0.8 (05-September-2021)
    - Added Traditional Chinese (zho) translation. (thanks to "in2002")

1.0.7 (11-April-2021)
    - Added Russian (ru) translation. (thanks to "Zheldorg")

1.0.6 (05-March-2021)
    - Fixed fake throw announces. (thanks "KadabraZz" for reporting)

1.0.5 (16-October-2020)
    - Added better cvar handling for L4D1.

1.0.4 (15-October-2020)
    - Added two detection methods. (weapon_fire+molotov_thrown[L4D2])

1.0.3 (30-September-2020)
    - Moved molotov check to "molotov_thrown". (L4D2 only)
    - Updated translation file to be more color friendly and highlighted the throwables.
    - Removed EventHookMode_PostNoCopy from hook events.

1.0.2 (29-September-2020)
    - Changed the validation from weapon name to weapon id.
    - Code optimization. (thanks to "Silvers")
    - Added colors.inc replacer. (thanks to "Silvers")

1.0.1 (29-September-2020)
    - Added Hungarian (hu) translation. (thanks to "KasperH")

1.0.0 (29-September-2020)
    - Initial release.

// ====================================================================================================
*/

// ====================================================================================================
// Plugin Info - define
// ====================================================================================================
#define PLUGIN_NAME                   "[L4D1 & L4D2] Throwable Announcer"
#define PLUGIN_AUTHOR                 "Mart, Fork by Tuan"
#define PLUGIN_DESCRIPTION            "Outputs to the chat who threw a throwable"
#define PLUGIN_VERSION                "1.0.8"
#define PLUGIN_URL                    "https://forums.alliedmods.net/showthread.php?t=327613"

// ====================================================================================================
// Plugin Info
// ====================================================================================================
public Plugin myinfo =
{
    name        = PLUGIN_NAME,
    author      = PLUGIN_AUTHOR,
    description = PLUGIN_DESCRIPTION,
    version     = PLUGIN_VERSION,
    url         = PLUGIN_URL
}

// ====================================================================================================
// Includes
// ====================================================================================================
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <Tuan_custom_forwards>

// ====================================================================================================
// Pragmas
// ====================================================================================================
#pragma semicolon 1
#pragma newdecls required

// ====================================================================================================
// Cvar Flags
// ====================================================================================================
#define CVAR_FLAGS                    FCVAR_NOTIFY
#define CVAR_FLAGS_PLUGIN_VERSION     FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY

// ====================================================================================================
// Filenames
// ====================================================================================================
#define CONFIG_FILENAME               "l4d_throwable_announcer"
#define TRANSLATION_FILENAME          "l4d_throwable_announcer.phrases"

// ====================================================================================================
// Defines
// ====================================================================================================
#define TEAM_SPECTATOR                1
#define TEAM_SURVIVOR                 2
#define TEAM_INFECTED                 3
#define TEAM_HOLDOUT                  4

#define FLAG_TEAM_NONE                (0 << 0) // 0 | 0000
#define FLAG_TEAM_SURVIVOR            (1 << 0) // 1 | 0001
#define FLAG_TEAM_INFECTED            (1 << 1) // 2 | 0010
#define FLAG_TEAM_SPECTATOR           (1 << 2) // 4 | 0100
#define FLAG_TEAM_HOLDOUT             (1 << 3) // 8 | 1000

#define L4D1_WEPID_MOLOTOV            9
#define L4D1_WEPID_PIPE_BOMB          10

#define L4D2_WEPID_PIPE_BOMB          14
#define L4D2_WEPID_VOMITJAR           25

#define TYPE_NONE                     0
#define TYPE_MOLOTOV                  1
#define TYPE_PIPEBOMB                 2
#define TYPE_VOMITJAR                 3

#define SLOT_GRENADE                  2

#define MAXENTITIES                   2048

// ====================================================================================================
// Plugin Cvars
// ====================================================================================================
ConVar g_hCvar_Enabled;
ConVar g_hCvar_FakeThrow;
ConVar g_hCvar_Team;
ConVar g_hCvar_Self;
ConVar g_hCvar_Molotov;
ConVar g_hCvar_Pipebomb;
ConVar g_hCvar_Vomitjar;

// ====================================================================================================
// bool - Plugin Variables
// ====================================================================================================
bool g_bL4D2;
bool g_bEventsHooked;
bool g_bCvar_Enabled;
bool g_bCvar_Self;
bool g_bCvar_Molotov;
bool g_bCvar_Pipebomb;
bool g_bCvar_Vomitjar;

// ====================================================================================================
// int - Plugin Variables
// ====================================================================================================
int g_iCvar_Team;

// ====================================================================================================
// float - Plugin Variables
// ====================================================================================================
float g_fCvar_FakeThrow;

// ====================================================================================================
// entity - Plugin Variables
// ====================================================================================================
int ge_iType[MAXENTITIES+1];
float ge_fLastThrown[MAXENTITIES+1];
GlobalForward g_OnClientUsedThrowable;

// ====================================================================================================
// Plugin Start
// ====================================================================================================
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();

    if (engine != Engine_Left4Dead && engine != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "This plugin only runs in \"Left 4 Dead\" and \"Left 4 Dead 2\" game");
        return APLRes_SilentFailure;
    }

    g_bL4D2 = (engine == Engine_Left4Dead2);

    return APLRes_Success;
}

/****************************************************************************************************/

public void OnPluginStart()
{
    CreateConVar("l4d_throwable_announcer_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, CVAR_FLAGS_PLUGIN_VERSION);
    g_hCvar_Enabled         = CreateConVar("l4d_throwable_announcer_enable", "1", "Enable/Disable the plugin.\n0 = Disable, 1 = Enable.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_FakeThrow       = CreateConVar("l4d_throwable_announcer_fake_throw", "0.3", "How many seconds should the plugin wait to detect if it was a fake throw.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0);
    g_hCvar_Team            = CreateConVar("l4d_throwable_announcer_team", "1", "Which teams should the message be transmitted to.\n0 = NONE, 1 = SURVIVOR, 2 = INFECTED, 4 = SPECTATOR, 8 = HOLDOUT.\nAdd numbers greater than 0 for multiple options.\nExample: \"3\", enables for SURVIVOR and INFECTED.", CVAR_FLAGS, true, 0.0, true, 15.0);
    g_hCvar_Self            = CreateConVar("l4d_throwable_announcer_self", "1", "Should the message be transmitted to those who thrown it.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_Molotov         = CreateConVar("l4d_throwable_announcer_molotov", "1", "Output to the chat every time someone throws a molotov.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hCvar_Pipebomb        = CreateConVar("l4d_throwable_announcer_pipebomb", "1", "Output to the chat every time someone throws a pipe bomb.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);
    if (g_bL4D2)
        g_hCvar_Vomitjar    = CreateConVar("l4d_throwable_announcer_vomitjar", "1", "Output to the chat every time someone throws a vomit jar.\nL4D2 only.\n0 = OFF, 1 = ON.", CVAR_FLAGS, true, 0.0, true, 1.0);

    // Hook plugin ConVars change
    g_hCvar_Enabled.AddChangeHook(Event_ConVarChanged);
    g_hCvar_FakeThrow.AddChangeHook(Event_ConVarChanged);
    g_hCvar_Team.AddChangeHook(Event_ConVarChanged);
    g_hCvar_Self.AddChangeHook(Event_ConVarChanged);
    g_hCvar_Molotov.AddChangeHook(Event_ConVarChanged);
    g_hCvar_Pipebomb.AddChangeHook(Event_ConVarChanged);
    if (g_bL4D2)
        g_hCvar_Vomitjar.AddChangeHook(Event_ConVarChanged);
		
	g_OnClientUsedThrowable = CreateGlobalForward("Tuan_OnClient_UsedThrowable", ET_Event, Param_Cell, Param_Cell);

    // Load plugin configs from .cfg
    AutoExecConfig(true, CONFIG_FILENAME);
}

void FireClientUsedThrowableEvent(int client, int throwable_type) {
    Call_StartForward(g_OnClientUsedThrowable);
    Call_PushCell(client);
	Call_PushCell(throwable_type);
    Call_Finish();
}

/****************************************************************************************************/

public void OnConfigsExecuted()
{
    GetCvars();

    HookEvents();

}

/****************************************************************************************************/

void Event_ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();

    HookEvents();
}

/****************************************************************************************************/

void GetCvars()
{
    g_bCvar_Enabled = g_hCvar_Enabled.BoolValue;
    g_fCvar_FakeThrow = g_hCvar_FakeThrow.FloatValue;
    g_iCvar_Team = g_hCvar_Team.IntValue;
    g_bCvar_Self = g_hCvar_Self.BoolValue;
    g_bCvar_Molotov = g_hCvar_Molotov.BoolValue;
    g_bCvar_Pipebomb = g_hCvar_Pipebomb.BoolValue;
    if (g_bL4D2)
        g_bCvar_Vomitjar = g_hCvar_Vomitjar.BoolValue;
}

/****************************************************************************************************/

void HookEvents()
{
    if (g_bCvar_Enabled && !g_bEventsHooked)
    {
        g_bEventsHooked = true;

        HookEvent("weapon_fire", Event_WeaponFire);

        if (g_bL4D2)
            HookEvent("molotov_thrown", Event_MolotovThrown_L4D2); // L4D1 doesn't have "molotov_thrown" event

        return;
    }

    if (!g_bCvar_Enabled && g_bEventsHooked)
    {
        g_bEventsHooked = false;

        UnhookEvent("weapon_fire", Event_WeaponFire);

        if (g_bL4D2)
            UnhookEvent("molotov_thrown", Event_MolotovThrown_L4D2); // L4D1 doesn't have "molotov_thrown" event

        return;
    }
}

/****************************************************************************************************/

public void OnEntityDestroyed(int entity)
{
    if (entity < 0)
        return;

    ge_iType[entity] = TYPE_NONE;
    ge_fLastThrown[entity] = 0.0;
}

/****************************************************************************************************/

void Event_MolotovThrown_L4D2(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bCvar_Molotov)
        return;

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client == 0)
        return;

    OutputMessage(client, TYPE_MOLOTOV);
}

/****************************************************************************************************/

void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    int weaponid = event.GetInt("weaponid");

    if (client == 0)
        return;

    if (g_bL4D2)
    {
        switch (weaponid)
        {
            case L4D2_WEPID_PIPE_BOMB:
            {
                int entity = GetPlayerWeaponSlot(client, SLOT_GRENADE);

                if (entity == -1)
                    return;

                ge_iType[entity] = TYPE_PIPEBOMB;
                ge_fLastThrown[entity] = GetGameTime();
                RequestFrame(OnNextFrame, EntIndexToEntRef(entity));
            }
            case L4D2_WEPID_VOMITJAR:
            {
                int entity = GetPlayerWeaponSlot(client, SLOT_GRENADE);

                if (entity == -1)
                    return;

                ge_iType[entity] = TYPE_VOMITJAR;
                ge_fLastThrown[entity] = GetGameTime();
                RequestFrame(OnNextFrame, EntIndexToEntRef(entity));
            }
        }
    }
    else
    {
        switch (weaponid)
        {
            case L4D1_WEPID_MOLOTOV:
            {
                int entity = GetPlayerWeaponSlot(client, SLOT_GRENADE);

                if (entity == -1)
                    return;

                ge_iType[entity] = TYPE_MOLOTOV;
                ge_fLastThrown[entity] = GetGameTime();
                RequestFrame(OnNextFrame, EntIndexToEntRef(entity));
            }
            case L4D1_WEPID_PIPE_BOMB:
            {
                int entity = GetPlayerWeaponSlot(client, SLOT_GRENADE);

                if (entity == -1)
                    return;

                ge_iType[entity] = TYPE_PIPEBOMB;
                ge_fLastThrown[entity] = GetGameTime();
                RequestFrame(OnNextFrame, EntIndexToEntRef(entity));
            }
        }
    }
}

/****************************************************************************************************/

void OnNextFrame(int entityRef)
{
    int entity = EntRefToEntIndex(entityRef);

    if (entity == INVALID_ENT_REFERENCE)
        return;

    if (GetGameTime() - ge_fLastThrown[entity] > g_fCvar_FakeThrow) // Probably was a fake thrown, average time to set "m_bRedraw = 1" is 0.24 seconds
        return;

    if (GetEntProp(entity, Prop_Send, "m_bRedraw") == 0)
    {
        RequestFrame(OnNextFrame, EntIndexToEntRef(entity));
        return;
    }

    int client = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");

    if (!IsValidClient(client))
        return;

    OutputMessage(client, ge_iType[entity]);
}

/****************************************************************************************************/

void OutputMessage(int client, int type)
{
    switch (type)
    {
        case TYPE_MOLOTOV:
        {
            if (!g_bCvar_Molotov)
                return;

            FireClientUsedThrowableEvent(client, 0); // 0 for molotov
        }

        case TYPE_PIPEBOMB:
        {
            if (!g_bCvar_Pipebomb)
                return;

            FireClientUsedThrowableEvent(client, 1); // 1 for pipe
        }

        case TYPE_VOMITJAR:
        {
            if (!g_bCvar_Vomitjar)
                return;

            FireClientUsedThrowableEvent(client, 2); // 2 for vomitjar
        }
    }
}

// ====================================================================================================
// Helpers
// ====================================================================================================
/**
 * Validates if is a valid client index.
 *
 * @param client        Client index.
 * @return              True if client index is valid, false otherwise.
 */
bool IsValidClientIndex(int client)
{
    return (1 <= client <= MaxClients);
}

/****************************************************************************************************/

/**
 * Validates if is a valid client.
 *
 * @param client          Client index.
 * @return                True if client index is valid and client is in game, false otherwise.
 */
bool IsValidClient(int client)
{
    return (IsValidClientIndex(client) && IsClientInGame(client));
}

/****************************************************************************************************/

/**
 * Returns the team flag from a team.
 *
 * @param team          Team index.
 * @return              Team flag.
 */
int GetTeamFlag(int team)
{
    switch (team)
    {
        case TEAM_SURVIVOR:
            return FLAG_TEAM_SURVIVOR;
        case TEAM_INFECTED:
            return FLAG_TEAM_INFECTED;
        case TEAM_SPECTATOR:
            return FLAG_TEAM_SPECTATOR;
        case TEAM_HOLDOUT:
            return FLAG_TEAM_HOLDOUT;
        default:
            return FLAG_TEAM_NONE;
    }
}