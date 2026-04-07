#pragma semicolon 1
#pragma newdecls required

#define myinfo DI_myinfo
#define OnPluginStart DI_OnPluginStart
#include "Tuan_l4d2_death_incap.sp"
#undef OnPluginStart
#undef myinfo

#define myinfo BW_myinfo
#define OnPluginStart BW_OnPluginStart
#include "Tuan_l4d_blackandwhiteordead.sp"
#undef OnPluginStart
#undef myinfo

#define myinfo EX_myinfo
#define AskPluginLoad2 EX_AskPluginLoad2
#define OnPluginStart EX_OnPluginStart
#define OnMapStart EX_OnMapStart
#define OnConfigsExecuted EX_OnConfigsExecuted
#define Event_ConVarChanged EX_Event_ConVarChanged
#define GetCvars EX_GetCvars
#define HookEvents EX_HookEvents
#define Event_BreakProp EX_Event_BreakProp
#define OnClientDisconnect EX_OnClientDisconnect
#define LateLoad EX_LateLoad
#define OnEntityCreated EX_OnEntityCreated
#define OnEntityDestroyed EX_OnEntityDestroyed
#define OnNextFrameWeaponGascan EX_OnNextFrameWeaponGascan
#define OnNextFrame EX_OnNextFrame
#define OnTakeDamage EX_OnTakeDamage
#define OnKilled EX_OnKilled
#define OutputMessage EX_OutputMessage
#define CmdPrintCvars EX_CmdPrintCvars
#define IsValidClientIndex EX_IsValidClientIndex
#define IsValidClient EX_IsValidClient
#define FireClientExplodedObjectEvent EX_FireClientExplodedObjectEvent
#define AutoExecConfig(%1,%2) AutoExecConfig(%1, "tuan_notifier_unified_explosion")
#include "Tuan_l4d_explosion_announcer.sp"
#undef AutoExecConfig
#undef FireClientExplodedObjectEvent
#undef IsValidClient
#undef IsValidClientIndex
#undef CmdPrintCvars
#undef OutputMessage
#undef OnKilled
#undef OnTakeDamage
#undef OnNextFrame
#undef OnNextFrameWeaponGascan
#undef OnEntityDestroyed
#undef OnEntityCreated
#undef LateLoad
#undef OnClientDisconnect
#undef Event_BreakProp
#undef HookEvents
#undef GetCvars
#undef Event_ConVarChanged
#undef OnConfigsExecuted
#undef OnMapStart
#undef OnPluginStart
#undef AskPluginLoad2
#undef myinfo

#define TH_CVAR_FLAGS FCVAR_NOTIFY
#define TH_CVAR_FLAGS_PLUGIN_VERSION FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY
#define TH_CONFIG_FILENAME "l4d_throwable_announcer"
#define TH_TEAM_SPECTATOR 1
#define TH_TEAM_SURVIVOR 2
#define TH_TEAM_INFECTED 3
#define TH_TEAM_HOLDOUT 4
#define TH_FLAG_TEAM_NONE (0 << 0)
#define TH_FLAG_TEAM_SURVIVOR (1 << 0)
#define TH_FLAG_TEAM_INFECTED (1 << 1)
#define TH_FLAG_TEAM_SPECTATOR (1 << 2)
#define TH_FLAG_TEAM_HOLDOUT (1 << 3)
#define TH_TYPE_NONE 0
#define TH_TYPE_MOLOTOV 1
#define TH_TYPE_PIPEBOMB 2
#define TH_TYPE_VOMITJAR 3
#define TH_SLOT_GRENADE 2
#define TH_MAXENTITIES 2048

#define myinfo TH_myinfo
#define AskPluginLoad2 TH_AskPluginLoad2
#define OnPluginStart TH_OnPluginStart
#define OnConfigsExecuted TH_OnConfigsExecuted
#define Event_ConVarChanged TH_Event_ConVarChanged
#define GetCvars TH_GetCvars
#define HookEvents TH_HookEvents
#define OnEntityDestroyed TH_OnEntityDestroyed
#define Event_MolotovThrown_L4D2 TH_Event_MolotovThrown_L4D2
#define Event_WeaponFire TH_Event_WeaponFire
#define OnNextFrame TH_OnNextFrame
#define OutputMessage TH_OutputMessage
#define IsValidClientIndex TH_IsValidClientIndex
#define IsValidClient TH_IsValidClient
#define GetTeamFlag TH_GetTeamFlag
#define FireClientUsedThrowableEvent TH_FireClientUsedThrowableEvent
#define CVAR_FLAGS TH_CVAR_FLAGS
#define CVAR_FLAGS_PLUGIN_VERSION TH_CVAR_FLAGS_PLUGIN_VERSION
#define CONFIG_FILENAME TH_CONFIG_FILENAME
#define TEAM_SPECTATOR TH_TEAM_SPECTATOR
#define TEAM_SURVIVOR TH_TEAM_SURVIVOR
#define TEAM_INFECTED TH_TEAM_INFECTED
#define TEAM_HOLDOUT TH_TEAM_HOLDOUT
#define FLAG_TEAM_NONE TH_FLAG_TEAM_NONE
#define FLAG_TEAM_SURVIVOR TH_FLAG_TEAM_SURVIVOR
#define FLAG_TEAM_INFECTED TH_FLAG_TEAM_INFECTED
#define FLAG_TEAM_SPECTATOR TH_FLAG_TEAM_SPECTATOR
#define FLAG_TEAM_HOLDOUT TH_FLAG_TEAM_HOLDOUT
#define TYPE_NONE TH_TYPE_NONE
#define TYPE_MOLOTOV TH_TYPE_MOLOTOV
#define TYPE_PIPEBOMB TH_TYPE_PIPEBOMB
#define TYPE_VOMITJAR TH_TYPE_VOMITJAR
#define SLOT_GRENADE TH_SLOT_GRENADE
#define MAXENTITIES TH_MAXENTITIES
#define g_bL4D2 th_g_bL4D2
#define g_bEventsHooked th_g_bEventsHooked
#define g_hCvar_Enabled th_g_hCvar_Enabled
#define g_hCvar_FakeThrow th_g_hCvar_FakeThrow
#define g_hCvar_Team th_g_hCvar_Team
#define g_hCvar_Self th_g_hCvar_Self
#define g_hCvar_Molotov th_g_hCvar_Molotov
#define g_hCvar_Pipebomb th_g_hCvar_Pipebomb
#define g_hCvar_Vomitjar th_g_hCvar_Vomitjar
#define g_bCvar_Enabled th_g_bCvar_Enabled
#define g_bCvar_Self th_g_bCvar_Self
#define g_bCvar_Molotov th_g_bCvar_Molotov
#define g_bCvar_Pipebomb th_g_bCvar_Pipebomb
#define g_bCvar_Vomitjar th_g_bCvar_Vomitjar
#define g_iCvar_Team th_g_iCvar_Team
#define g_fCvar_FakeThrow th_g_fCvar_FakeThrow
#define ge_iType th_ge_iType
#define ge_fLastThrown th_ge_fLastThrown
#define g_OnClientUsedThrowable th_g_OnClientUsedThrowable
#define AutoExecConfig(%1,%2) AutoExecConfig(%1, "tuan_notifier_unified_throwable")
#include "Tuan_l4d_throwable_announcer.sp"
#undef AutoExecConfig
#undef g_OnClientUsedThrowable
#undef ge_fLastThrown
#undef ge_iType
#undef g_fCvar_FakeThrow
#undef g_iCvar_Team
#undef g_bCvar_Vomitjar
#undef g_bCvar_Pipebomb
#undef g_bCvar_Molotov
#undef g_bCvar_Self
#undef g_bCvar_Enabled
#undef g_hCvar_Vomitjar
#undef g_hCvar_Pipebomb
#undef g_hCvar_Molotov
#undef g_hCvar_Self
#undef g_hCvar_Team
#undef g_hCvar_FakeThrow
#undef g_hCvar_Enabled
#undef g_bEventsHooked
#undef g_bL4D2
#undef MAXENTITIES
#undef SLOT_GRENADE
#undef TYPE_VOMITJAR
#undef TYPE_PIPEBOMB
#undef TYPE_MOLOTOV
#undef TYPE_NONE
#undef FLAG_TEAM_HOLDOUT
#undef FLAG_TEAM_SPECTATOR
#undef FLAG_TEAM_INFECTED
#undef FLAG_TEAM_SURVIVOR
#undef FLAG_TEAM_NONE
#undef TEAM_HOLDOUT
#undef TEAM_INFECTED
#undef TEAM_SURVIVOR
#undef TEAM_SPECTATOR
#undef CONFIG_FILENAME
#undef CVAR_FLAGS_PLUGIN_VERSION
#undef CVAR_FLAGS
#undef FireClientUsedThrowableEvent
#undef GetTeamFlag
#undef IsValidClient
#undef IsValidClientIndex
#undef OutputMessage
#undef OnNextFrame
#undef Event_WeaponFire
#undef Event_MolotovThrown_L4D2
#undef OnEntityDestroyed
#undef HookEvents
#undef GetCvars
#undef Event_ConVarChanged
#undef OnConfigsExecuted
#undef OnPluginStart
#undef AskPluginLoad2
#undef myinfo

public Plugin myinfo =
{
    name = "[L4D1/L4D2] Tuan Notifier Unified",
    author = "Tuan + merge",
    description = "Unified notifier plugin",
    version = "1.0",
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    APLRes res = EX_AskPluginLoad2(myself, late, error, err_max);
    th_g_bL4D2 = g_bL4D2;
    return res;
}

public void OnPluginStart()
{
    DI_OnPluginStart();
    BW_OnPluginStart();
    EX_OnPluginStart();
    th_g_bL4D2 = g_bL4D2;
    TH_OnPluginStart();
}

public void OnMapStart()
{
    EX_OnMapStart();
}

public void OnConfigsExecuted()
{
    EX_OnConfigsExecuted();
    TH_OnConfigsExecuted();
}

public void OnEntityCreated(int entity, const char[] classname)
{
    EX_OnEntityCreated(entity, classname);
}

public void OnEntityDestroyed(int entity)
{
    EX_OnEntityDestroyed(entity);
    TH_OnEntityDestroyed(entity);
}

public void OnClientDisconnect(int client)
{
    EX_OnClientDisconnect(client);
}
