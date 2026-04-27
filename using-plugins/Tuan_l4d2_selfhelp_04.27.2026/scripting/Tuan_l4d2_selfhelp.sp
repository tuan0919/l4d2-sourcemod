#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "04.27.2026"
#define CVAR_FLAGS FCVAR_NOTIFY

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define SLOT_MEDICAL 3
#define SLOT_PILLS 4

#define ITEM_NONE -1
#define ITEM_KIT 0
#define ITEM_DEFIB 1
#define ITEM_PILLS 2
#define ITEM_ADREN 3
#define ITEM_COUNT 4

#define ACTION_NONE 0
#define ACTION_SELF 1
#define ACTION_OTHER 2

#define TIMER_TICK 0.1

bool g_bLeft4Dead2;

ConVar g_hEnable;
ConVar g_hButtons;
ConVar g_hPriority;
ConVar g_hDelay;
ConVar g_hPickupRange;
ConVar g_hHelpOtherRange;
ConVar g_hHelpOtherTime;
ConVar g_hHelpOtherHealth;
ConVar g_hMaxIncap;

ConVar g_hItemEnable[ITEM_COUNT];
ConVar g_hItemUseTime[ITEM_COUNT];
ConVar g_hItemIncap[ITEM_COUNT];
ConVar g_hItemHealth[ITEM_COUNT];
ConVar g_hItemPermanent[ITEM_COUNT];
ConVar g_hItemHanging[ITEM_COUNT];
ConVar g_hItemPinned[ITEM_COUNT];

bool g_bEnabled;
int g_iButtons;
int g_iPriority;
float g_fDelay;
float g_fPickupRange;
float g_fHelpOtherRange;
float g_fHelpOtherTime;
float g_fHelpOtherHealth;

bool g_bItemEnabled[ITEM_COUNT];
float g_fItemUseTime[ITEM_COUNT];
bool g_bItemIncap[ITEM_COUNT];
float g_fItemHealth[ITEM_COUNT];
bool g_bItemPermanent[ITEM_COUNT];
bool g_bItemHanging[ITEM_COUNT];
int g_iItemPinned[ITEM_COUNT];

int g_iLastButtons[MAXPLAYERS + 1];
float g_fDistressStarted[MAXPLAYERS + 1];
float g_fNextHint[MAXPLAYERS + 1];
float g_fNextActionHint[MAXPLAYERS + 1];

int g_iAction[MAXPLAYERS + 1];
int g_iActionItem[MAXPLAYERS + 1];
int g_iActionWeaponRef[MAXPLAYERS + 1];
int g_iActionTargetUserId[MAXPLAYERS + 1];
int g_iActionAttackerUserId[MAXPLAYERS + 1];
float g_fActionEnd[MAXPLAYERS + 1];
Handle g_hActionTimer[MAXPLAYERS + 1];

GlobalForward g_hForwardSelfRevived;

public Plugin myinfo =
{
    name = "[L4D2] Tuan Self Help",
    author = "Tuan, OpenCode",
    description = "Self-help remake: consume medical items to recover while incapped, ledge-hanging, or pinned.",
    version = PLUGIN_VERSION,
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    EngineVersion engine = GetEngineVersion();
    g_bLeft4Dead2 = (engine == Engine_Left4Dead2);

    if (engine != Engine_Left4Dead2 && engine != Engine_Left4Dead)
    {
        strcopy(error, err_max, "This plugin only supports Left 4 Dead and Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hForwardSelfRevived = CreateGlobalForward("Tuan_OnClient_SelfRevived", ET_Ignore, Param_Cell);

    g_hEnable = CreateConVar("Tuan_l4d2_selfhelp_enable", "1", "0=Off, 1=On.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hButtons = CreateConVar("Tuan_l4d2_selfhelp_buttons", "4", "Buttons required for self-help. 4=Duck, 32=Use, 131072=Shift. Add values for combinations.", CVAR_FLAGS, true, 1.0);
    g_hPriority = CreateConVar("Tuan_l4d2_selfhelp_priority", "1", "0=Use slot 3 before slot 4. 1=Use slot 4 before slot 3.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hDelay = CreateConVar("Tuan_l4d2_selfhelp_delay", "1.0", "Seconds after incap, ledge grab, or pin before self-help is allowed.", CVAR_FLAGS, true, 0.0);
    g_hPickupRange = CreateConVar("Tuan_l4d2_selfhelp_pickup_range", "100.0", "Aim at a medical item and press E while distressed to pick it up. 0=Off.", CVAR_FLAGS, true, 0.0);
    g_hHelpOtherRange = CreateConVar("Tuan_l4d2_selfhelp_help_other_range", "100.0", "Range for an incapped survivor to help another incapped/ledge survivor. 0=Off.", CVAR_FLAGS, true, 0.0);
    g_hHelpOtherTime = CreateConVar("Tuan_l4d2_selfhelp_help_other_time", "3.0", "Seconds required to help another survivor while incapped.", CVAR_FLAGS, true, 0.1);
    g_hHelpOtherHealth = CreateConVar("Tuan_l4d2_selfhelp_help_other_health", "2.0", "Temp health given after incapped-to-incapped help. 0=Keep game default.", CVAR_FLAGS, true, 0.0);

    CreateItemCvars(ITEM_KIT, "kit", "First aid kit", "3.0", "80.0", "1", "1");
    CreateItemCvars(ITEM_DEFIB, "defib", "Defibrillator", "3.0", "80.0", "0", "1");
    CreateItemCvars(ITEM_PILLS, "pills", "Pain pills", "5.0", "60.0", "0", "1");
    CreateItemCvars(ITEM_ADREN, "adren", "Adrenaline", "5.0", "45.0", "0", g_bLeft4Dead2 ? "1" : "0");

    HookCoreCvars();

    g_hMaxIncap = FindConVar("survivor_max_incapacitated_count");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    AutoExecConfig(true, "Tuan_l4d2_selfhelp");
    GetCvars();
}

void CreateItemCvars(int item, const char[] key, const char[] label, const char[] useTime, const char[] health, const char[] permanent, const char[] enabled)
{
    char cvar[96];
    char desc[192];

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_enable", key);
    Format(desc, sizeof(desc), "0=Disable %s self-help, 1=Enable.", label);
    g_hItemEnable[item] = CreateConVar(cvar, enabled, desc, CVAR_FLAGS, true, 0.0, true, 1.0);

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_time", key);
    Format(desc, sizeof(desc), "Seconds required to use %s for self-help.", label);
    g_hItemUseTime[item] = CreateConVar(cvar, useTime, desc, CVAR_FLAGS, true, 0.1);

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_incap", key);
    Format(desc, sizeof(desc), "0=Cannot use %s while incapped, 1=Can use.", label);
    g_hItemIncap[item] = CreateConVar(cvar, "1", desc, CVAR_FLAGS, true, 0.0, true, 1.0);

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_health", key);
    Format(desc, sizeof(desc), "Health after %s self-help. 0=Do not override game health.", label);
    g_hItemHealth[item] = CreateConVar(cvar, health, desc, CVAR_FLAGS, true, 0.0);

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_permanent", key);
    Format(desc, sizeof(desc), "0=%s gives temp health and keeps revive count. 1=Permanent health and reset revive count.", label);
    g_hItemPermanent[item] = CreateConVar(cvar, permanent, desc, CVAR_FLAGS, true, 0.0, true, 1.0);

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_ledge", key);
    Format(desc, sizeof(desc), "0=Cannot use %s while hanging from ledge, 1=Can use.", label);
    g_hItemHanging[item] = CreateConVar(cvar, "1", desc, CVAR_FLAGS, true, 0.0, true, 1.0);

    Format(cvar, sizeof(cvar), "Tuan_l4d2_selfhelp_%s_pinned", key);
    Format(desc, sizeof(desc), "Pinned use for %s. 0=Off, 1=Kill attacker only, 2=Kill attacker and apply health.", label);
    g_hItemPinned[item] = CreateConVar(cvar, "1", desc, CVAR_FLAGS, true, 0.0, true, 2.0);
}

void HookCoreCvars()
{
    g_hEnable.AddChangeHook(ConVarChanged_Cvars);
    g_hButtons.AddChangeHook(ConVarChanged_Cvars);
    g_hPriority.AddChangeHook(ConVarChanged_Cvars);
    g_hDelay.AddChangeHook(ConVarChanged_Cvars);
    g_hPickupRange.AddChangeHook(ConVarChanged_Cvars);
    g_hHelpOtherRange.AddChangeHook(ConVarChanged_Cvars);
    g_hHelpOtherTime.AddChangeHook(ConVarChanged_Cvars);
    g_hHelpOtherHealth.AddChangeHook(ConVarChanged_Cvars);

    for (int i = 0; i < ITEM_COUNT; i++)
    {
        g_hItemEnable[i].AddChangeHook(ConVarChanged_Cvars);
        g_hItemUseTime[i].AddChangeHook(ConVarChanged_Cvars);
        g_hItemIncap[i].AddChangeHook(ConVarChanged_Cvars);
        g_hItemHealth[i].AddChangeHook(ConVarChanged_Cvars);
        g_hItemPermanent[i].AddChangeHook(ConVarChanged_Cvars);
        g_hItemHanging[i].AddChangeHook(ConVarChanged_Cvars);
        g_hItemPinned[i].AddChangeHook(ConVarChanged_Cvars);
    }
}

void ConVarChanged_Cvars(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void GetCvars()
{
    g_bEnabled = g_hEnable.BoolValue;
    g_iButtons = g_hButtons.IntValue;
    g_iPriority = g_hPriority.IntValue;
    g_fDelay = g_hDelay.FloatValue;
    g_fPickupRange = g_hPickupRange.FloatValue;
    g_fHelpOtherRange = g_hHelpOtherRange.FloatValue;
    g_fHelpOtherTime = g_hHelpOtherTime.FloatValue;
    g_fHelpOtherHealth = g_hHelpOtherHealth.FloatValue;

    if (g_iButtons <= 0)
    {
        g_iButtons = IN_DUCK;
    }

    for (int i = 0; i < ITEM_COUNT; i++)
    {
        g_bItemEnabled[i] = g_hItemEnable[i].BoolValue;
        g_fItemUseTime[i] = g_hItemUseTime[i].FloatValue;
        g_bItemIncap[i] = g_hItemIncap[i].BoolValue;
        g_fItemHealth[i] = g_hItemHealth[i].FloatValue;
        g_bItemPermanent[i] = g_hItemPermanent[i].BoolValue;
        g_bItemHanging[i] = g_hItemHanging[i].BoolValue;
        g_iItemPinned[i] = g_hItemPinned[i].IntValue;
    }
}

public void OnClientDisconnect(int client)
{
    ResetClient(client);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    ResetAllClients();
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        ResetClient(client);
    }
}

void ResetAllClients()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        ResetClient(i);
    }
}

void ResetClient(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    StopAction(client, true, true);
    g_iLastButtons[client] = 0;
    g_fDistressStarted[client] = 0.0;
    g_fNextHint[client] = 0.0;
    g_fNextActionHint[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsValidAliveSurvivor(client))
    {
        return Plugin_Continue;
    }

    if (!g_bEnabled)
    {
        g_iLastButtons[client] = buttons;
        return Plugin_Continue;
    }

    bool distressed = UpdateDistressState(client);

    if (distressed && (buttons & IN_USE) && !(g_iLastButtons[client] & IN_USE))
    {
        TryPickupItem(client);
    }

    if (g_iAction[client] == ACTION_NONE && distressed && (buttons & g_iButtons) == g_iButtons && (g_iLastButtons[client] & g_iButtons) != g_iButtons)
    {
        TryStartAction(client);
    }

    g_iLastButtons[client] = buttons;
    return Plugin_Continue;
}

bool UpdateDistressState(int client)
{
    bool distressed = IsIncapped(client) || IsHanging(client) || GetPinnedAttacker(client) > 0;
    if (!distressed)
    {
        g_fDistressStarted[client] = 0.0;
        return false;
    }

    if (g_fDistressStarted[client] <= 0.0)
    {
        g_fDistressStarted[client] = GetGameTime();
    }

    return true;
}

void TryStartAction(int client)
{
    float now = GetGameTime();
    float allowedAt = g_fDistressStarted[client] + g_fDelay;
    if (now < allowedAt)
    {
        ThrottledHint(client, "Self-help ready in %.1f sec", allowedAt - now);
        return;
    }

    bool incapped = IsIncapped(client);
    bool hanging = IsHanging(client);
    int attacker = GetPinnedAttacker(client);
    bool pinned = attacker > 0;

    int weapon = -1;
    int item = GetUsableItem(client, incapped, hanging, pinned, weapon);
    if (item != ITEM_NONE)
    {
        StartSelfAction(client, item, weapon, attacker);
        return;
    }

    if (incapped && !hanging)
    {
        int target = FindHelpOtherTarget(client);
        if (target > 0)
        {
            StartOtherAction(client, target);
            return;
        }
    }

    ThrottledHint(client, "No usable self-help item or nearby incapped teammate");
}

int GetUsableItem(int client, bool incapped, bool hanging, bool pinned, int &weapon)
{
    int firstSlot = g_iPriority == 0 ? SLOT_MEDICAL : SLOT_PILLS;
    int secondSlot = g_iPriority == 0 ? SLOT_PILLS : SLOT_MEDICAL;

    int item = GetUsableItemFromSlot(client, firstSlot, incapped, hanging, pinned, weapon);
    if (item != ITEM_NONE)
    {
        return item;
    }

    return GetUsableItemFromSlot(client, secondSlot, incapped, hanging, pinned, weapon);
}

int GetUsableItemFromSlot(int client, int slot, bool incapped, bool hanging, bool pinned, int &weapon)
{
    int entity = GetPlayerWeaponSlot(client, slot);
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        return ITEM_NONE;
    }

    char classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));

    int item = GetItemFromClassname(classname);
    if (item == ITEM_NONE || !CanUseItemForState(item, incapped, hanging, pinned))
    {
        return ITEM_NONE;
    }

    weapon = entity;
    return item;
}

bool CanUseItemForState(int item, bool incapped, bool hanging, bool pinned)
{
    if (item < 0 || item >= ITEM_COUNT || !g_bItemEnabled[item])
    {
        return false;
    }

    if (pinned && g_iItemPinned[item] > 0)
    {
        return true;
    }

    if (hanging && g_bItemHanging[item])
    {
        return true;
    }

    if (incapped && g_bItemIncap[item])
    {
        return true;
    }

    return false;
}

void StartSelfAction(int client, int item, int weapon, int attacker)
{
    StopAction(client, true, true);

    g_iAction[client] = ACTION_SELF;
    g_iActionItem[client] = item;
    g_iActionWeaponRef[client] = EntIndexToEntRef(weapon);
    g_iActionTargetUserId[client] = 0;
    g_iActionAttackerUserId[client] = attacker > 0 ? GetClientUserId(attacker) : 0;
    g_fActionEnd[client] = GetGameTime() + g_fItemUseTime[item];

    ShowProgress(client, g_fItemUseTime[item]);
    PrintHintText(client, "Helping yourself...");
    g_hActionTimer[client] = CreateTimer(TIMER_TICK, Timer_Action, GetClientUserId(client), TIMER_REPEAT);
}

void StartOtherAction(int client, int target)
{
    StopAction(client, true, true);

    g_iAction[client] = ACTION_OTHER;
    g_iActionItem[client] = ITEM_NONE;
    g_iActionWeaponRef[client] = INVALID_ENT_REFERENCE;
    g_iActionTargetUserId[client] = GetClientUserId(target);
    g_iActionAttackerUserId[client] = 0;
    g_fActionEnd[client] = GetGameTime() + g_fHelpOtherTime;

    ShowProgress(client, g_fHelpOtherTime);
    PrintHintText(client, "Helping %N...", target);
    PrintHintText(target, "%N is helping you", client);
    g_hActionTimer[client] = CreateTimer(TIMER_TICK, Timer_Action, GetClientUserId(client), TIMER_REPEAT);
}

Action Timer_Action(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client <= 0 || !IsValidAliveSurvivor(client) || !g_bEnabled || g_iAction[client] == ACTION_NONE)
    {
        if (client > 0)
        {
            g_hActionTimer[client] = null;
            StopAction(client, true, false);
        }
        return Plugin_Stop;
    }

    if ((g_iLastButtons[client] & g_iButtons) != g_iButtons || !IsActionStillValid(client))
    {
        g_hActionTimer[client] = null;
        StopAction(client, true, false);
        return Plugin_Stop;
    }

    if (GetGameTime() >= g_fActionEnd[client])
    {
        g_hActionTimer[client] = null;
        FinishAction(client);
        return Plugin_Stop;
    }

    ShowActionCountdown(client);

    return Plugin_Continue;
}

bool IsActionStillValid(int client)
{
    switch (g_iAction[client])
    {
        case ACTION_SELF:
        {
            int item = g_iActionItem[client];
            if (item == ITEM_NONE)
            {
                return false;
            }

            int weapon = EntRefToEntIndex(g_iActionWeaponRef[client]);
            if (weapon <= MaxClients || !IsValidEntity(weapon))
            {
                return false;
            }

            bool incapped = IsIncapped(client);
            bool hanging = IsHanging(client);
            bool pinned = GetPinnedAttacker(client) > 0;
            return CanUseItemForState(item, incapped, hanging, pinned);
        }

        case ACTION_OTHER:
        {
            int target = GetClientOfUserId(g_iActionTargetUserId[client]);
            return IsValidHelpOtherTarget(client, target);
        }
    }

    return false;
}

void FinishAction(int client)
{
    ClearProgress(client);

    switch (g_iAction[client])
    {
        case ACTION_SELF:
        {
            FinishSelfAction(client);
        }

        case ACTION_OTHER:
        {
            FinishOtherAction(client);
        }
    }

    StopAction(client, false, false);
}

void FinishSelfAction(int client)
{
    int item = g_iActionItem[client];
    int weapon = EntRefToEntIndex(g_iActionWeaponRef[client]);
    int attacker = GetClientOfUserId(g_iActionAttackerUserId[client]);

    bool wasIncapped = IsIncapped(client);
    bool wasHanging = IsHanging(client);
    bool wasPinned = GetPinnedAttacker(client) > 0;
    bool shouldApplyHealth = wasIncapped || wasHanging;

    if (!wasIncapped && !wasHanging && !wasPinned)
    {
        return;
    }

    RemoveMedicalItem(client, item, weapon);
    FireItemUsedEvent(client, item);

    if (wasPinned)
    {
        if (!IsValidAliveInfected(attacker) || !IsAttackerOfVictim(attacker, client))
        {
            attacker = GetPinnedAttacker(client);
        }

        if (attacker > 0)
        {
            KillPinnedAttacker(client, attacker);
        }

        if (g_iItemPinned[item] >= 2)
        {
            shouldApplyHealth = true;
        }
    }

    if (wasIncapped || wasHanging)
    {
        L4D_ReviveSurvivor(client);
    }

    if (shouldApplyHealth)
    {
        ApplyConfiguredHealth(client, g_fItemHealth[item], g_bItemPermanent[item], wasIncapped || wasHanging);
        FireSelfRevived(client);
    }

    PrintHintText(client, "Self-help complete");
}

void FinishOtherAction(int client)
{
    int target = GetClientOfUserId(g_iActionTargetUserId[client]);
    if (!IsValidHelpOtherTarget(client, target))
    {
        return;
    }

    L4D_ReviveSurvivor(target);
    if (g_fHelpOtherHealth > 0.0)
    {
        ApplyConfiguredHealth(target, g_fHelpOtherHealth, false, true);
    }

    FireReviveSuccessEvent(client, target);
    PrintHintText(client, "Helped %N get up", target);
    PrintHintText(target, "%N helped you get up", client);
}

void StopAction(int client, bool clearProgress, bool killTimer)
{
    if (killTimer)
    {
        delete g_hActionTimer[client];
    }

    if (clearProgress)
    {
        ClearProgress(client);
    }

    g_iAction[client] = ACTION_NONE;
    g_iActionItem[client] = ITEM_NONE;
    g_iActionWeaponRef[client] = INVALID_ENT_REFERENCE;
    g_iActionTargetUserId[client] = 0;
    g_iActionAttackerUserId[client] = 0;
    g_fActionEnd[client] = 0.0;
}

void ShowProgress(int client, float duration)
{
    if (TryShowNetpropProgress(client, duration))
    {
        return;
    }

    TrySendBarTime(client, RoundToCeil(duration));
}

void ClearProgress(int client)
{
    TryClearNetpropProgress(client);
    TrySendBarTime(client, 0);
}

bool TryShowNetpropProgress(int client, float duration)
{
    if (!CanWriteProgressStart(client))
    {
        return false;
    }

    SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);

    if (HasEntProp(client, Prop_Send, "m_iProgressBarDuration"))
    {
        SetEntProp(client, Prop_Send, "m_iProgressBarDuration", RoundToCeil(duration));
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
        return true;
    }

    if (HasEntProp(client, Prop_Send, "m_flProgressBarDuration"))
    {
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", duration);
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", GetGameTime());
        return true;
    }

    return false;
}

void TryClearNetpropProgress(int client)
{
    if (!CanWriteProgressStart(client))
    {
        return;
    }

    SetEntPropFloat(client, Prop_Send, "m_flProgressBarStartTime", 0.0);

    if (HasEntProp(client, Prop_Send, "m_iProgressBarDuration"))
    {
        SetEntProp(client, Prop_Send, "m_iProgressBarDuration", 0);
    }
    else if (HasEntProp(client, Prop_Send, "m_flProgressBarDuration"))
    {
        SetEntPropFloat(client, Prop_Send, "m_flProgressBarDuration", 0.0);
    }
}

bool CanWriteProgressStart(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && HasEntProp(client, Prop_Send, "m_flProgressBarStartTime");
}

bool TrySendBarTime(int client, int seconds)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
    {
        return false;
    }

    if (GetUserMessageType() != UM_BitBuf || GetUserMessageId("BarTime") == INVALID_MESSAGE_ID)
    {
        return false;
    }

    Handle msg = StartMessageOne("BarTime", client, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
    if (msg == null)
    {
        return false;
    }

    BfWriteShort(msg, seconds);
    EndMessage();
    return true;
}

void ShowActionCountdown(int client)
{
    float now = GetGameTime();
    if (now < g_fNextActionHint[client])
    {
        return;
    }

    float remaining = g_fActionEnd[client] - now;
    if (remaining <= 0.0)
    {
        return;
    }

    g_fNextActionHint[client] = now + 0.5;

    char label[32];
    if (g_iAction[client] == ACTION_OTHER)
    {
        strcopy(label, sizeof(label), "Helping");
    }
    else
    {
        strcopy(label, sizeof(label), "Self-help");
    }

    PrintCenterText(client, "%s: %.1f sec", label, remaining);
}

void ApplyConfiguredHealth(int client, float health, bool permanent, bool revived)
{
    if (health <= 0.0)
    {
        return;
    }

    int hp = RoundToCeil(health);
    if (hp < 1)
    {
        hp = 1;
    }

    if (permanent)
    {
        SetEntityHealth(client, hp);
        SetTempHealth(client, 0.0);
        ResetReviveCount(client);
        return;
    }

    if (revived)
    {
        SetEntityHealth(client, 1);
    }
    else if (GetClientHealth(client) < 1)
    {
        SetEntityHealth(client, 1);
    }

    SetTempHealth(client, health);
}

void SetTempHealth(int client, float amount)
{
    SetEntPropFloat(client, Prop_Send, "m_healthBuffer", amount);
    SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}

void ResetReviveCount(int client)
{
    if (HasEntProp(client, Prop_Send, "m_currentReviveCount"))
    {
        SetEntProp(client, Prop_Send, "m_currentReviveCount", 0);
    }

    if (HasEntProp(client, Prop_Send, "m_isGoingToDie"))
    {
        SetEntProp(client, Prop_Send, "m_isGoingToDie", 0);
    }

    if (HasEntProp(client, Prop_Send, "m_bIsOnThirdStrike"))
    {
        SetEntProp(client, Prop_Send, "m_bIsOnThirdStrike", 0);
    }
}

void RemoveMedicalItem(int client, int item, int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        weapon = GetPlayerWeaponSlot(client, GetItemSlot(item));
    }

    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return;
    }

    RemovePlayerItem(client, weapon);
    RemoveEntity(weapon);
}

void FireItemUsedEvent(int client, int item)
{
    switch (item)
    {
        case ITEM_PILLS:
        {
            Event event = CreateEvent("pills_used", true);
            if (event != null)
            {
                event.SetInt("userid", GetClientUserId(client));
                event.Fire();
            }
        }

        case ITEM_ADREN:
        {
            if (g_bLeft4Dead2)
            {
                L4D2_UseAdrenaline(client, 15.0, false);
            }
        }
    }
}

void FireSelfRevived(int client)
{
    if (g_hForwardSelfRevived == null)
    {
        return;
    }

    Call_StartForward(g_hForwardSelfRevived);
    Call_PushCell(client);
    Call_Finish();
}

void FireReviveSuccessEvent(int client, int target)
{
    Event event = CreateEvent("revive_success", true);
    if (event == null)
    {
        return;
    }

    event.SetInt("userid", GetClientUserId(client));
    event.SetInt("subject", GetClientUserId(target));
    event.SetBool("lastlife", IsOnLastLife(target));
    event.Fire();
}

bool IsOnLastLife(int client)
{
    if (HasEntProp(client, Prop_Send, "m_bIsOnThirdStrike") && GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike") != 0)
    {
        return true;
    }

    int maxIncap = g_hMaxIncap != null ? g_hMaxIncap.IntValue : 2;
    return HasEntProp(client, Prop_Send, "m_currentReviveCount") && GetEntProp(client, Prop_Send, "m_currentReviveCount") >= maxIncap;
}

void KillPinnedAttacker(int client, int attacker)
{
    if (!IsValidAliveInfected(attacker))
    {
        return;
    }

    SDKHooks_TakeDamage(attacker, client, client, 10000.0, DMG_GENERIC);
    if (IsClientInGame(attacker) && IsPlayerAlive(attacker))
    {
        ForcePlayerSuicide(attacker);
    }
}

void TryPickupItem(int client)
{
    if (g_fPickupRange <= 0.0)
    {
        return;
    }

    int entity = GetClientAimTarget(client, false);
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        return;
    }

    char classname[64];
    GetEdictClassname(entity, classname, sizeof(classname));

    int item = GetItemFromClassname(classname);
    if (item == ITEM_NONE || !g_bItemEnabled[item])
    {
        return;
    }

    int slot = GetItemSlot(item);
    if (GetPlayerWeaponSlot(client, slot) != -1)
    {
        ThrottledHint(client, "Your matching item slot is already occupied");
        return;
    }

    float clientPos[3];
    float itemPos[3];
    GetClientAbsOrigin(client, clientPos);
    GetEntPropVector(entity, Prop_Send, "m_vecOrigin", itemPos);

    if (GetVectorDistance(clientPos, itemPos) > g_fPickupRange)
    {
        return;
    }

    if (AcceptEntityInput(entity, "Use", client, client))
    {
        char itemName[32];
        GetItemName(item, itemName, sizeof(itemName));
        PrintHintText(client, "Picked up %s", itemName);
    }
}

int FindHelpOtherTarget(int client)
{
    if (g_fHelpOtherRange <= 0.0)
    {
        return 0;
    }

    int aimTarget = GetClientAimTarget(client, true);
    if (IsValidHelpOtherTarget(client, aimTarget))
    {
        return aimTarget;
    }

    float clientPos[3];
    GetClientAbsOrigin(client, clientPos);

    int bestTarget = 0;
    float bestDistance = g_fHelpOtherRange + 1.0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHelpOtherTarget(client, i))
        {
            continue;
        }

        float targetPos[3];
        GetClientAbsOrigin(i, targetPos);
        float distance = GetVectorDistance(clientPos, targetPos);
        if (distance <= g_fHelpOtherRange && distance < bestDistance)
        {
            bestTarget = i;
            bestDistance = distance;
        }
    }

    return bestTarget;
}

bool IsValidHelpOtherTarget(int client, int target)
{
    if (target < 1 || target > MaxClients || target == client || !IsValidAliveSurvivor(target))
    {
        return false;
    }

    if (!IsIncapped(target) && !IsHanging(target))
    {
        return false;
    }

    float clientPos[3];
    float targetPos[3];
    GetClientAbsOrigin(client, clientPos);
    GetClientAbsOrigin(target, targetPos);

    return GetVectorDistance(clientPos, targetPos) <= g_fHelpOtherRange;
}

int GetPinnedAttacker(int client)
{
    int attacker = GetEntPropEnt(client, Prop_Send, "m_tongueOwner");
    if (IsValidAliveInfected(attacker))
    {
        return attacker;
    }

    attacker = GetEntPropEnt(client, Prop_Send, "m_pounceAttacker");
    if (IsValidAliveInfected(attacker))
    {
        return attacker;
    }

    if (g_bLeft4Dead2)
    {
        attacker = GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker");
        if (IsValidAliveInfected(attacker))
        {
            return attacker;
        }

        attacker = GetEntPropEnt(client, Prop_Send, "m_pummelAttacker");
        if (IsValidAliveInfected(attacker))
        {
            return attacker;
        }

        attacker = GetEntPropEnt(client, Prop_Send, "m_carryAttacker");
        if (IsValidAliveInfected(attacker))
        {
            return attacker;
        }

        attacker = L4D2_GetSpecialInfectedDominatingMe(client);
        if (IsValidAliveInfected(attacker))
        {
            return attacker;
        }
    }

    return 0;
}

bool IsAttackerOfVictim(int attacker, int victim)
{
    if (!IsValidAliveInfected(attacker) || !IsValidAliveSurvivor(victim))
    {
        return false;
    }

    if (GetEntPropEnt(victim, Prop_Send, "m_tongueOwner") == attacker || GetEntPropEnt(victim, Prop_Send, "m_pounceAttacker") == attacker)
    {
        return true;
    }

    if (!g_bLeft4Dead2)
    {
        return false;
    }

    return GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") == attacker
        || GetEntPropEnt(victim, Prop_Send, "m_pummelAttacker") == attacker
        || GetEntPropEnt(victim, Prop_Send, "m_carryAttacker") == attacker;
}

bool IsValidAliveSurvivor(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVOR
        && IsPlayerAlive(client);
}

bool IsValidAliveInfected(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_INFECTED
        && IsPlayerAlive(client);
}

bool IsIncapped(int client)
{
    return HasEntProp(client, Prop_Send, "m_isIncapacitated") && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 0;
}

bool IsHanging(int client)
{
    return HasEntProp(client, Prop_Send, "m_isHangingFromLedge") && GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) != 0;
}

int GetItemFromClassname(const char[] classname)
{
    if (strncmp(classname, "weapon_first_aid_kit", 20, false) == 0)
    {
        return ITEM_KIT;
    }

    if (strncmp(classname, "weapon_defibrillator", 20, false) == 0)
    {
        return ITEM_DEFIB;
    }

    if (strncmp(classname, "weapon_pain_pills", 17, false) == 0)
    {
        return ITEM_PILLS;
    }

    if (strncmp(classname, "weapon_adrenaline", 17, false) == 0)
    {
        return ITEM_ADREN;
    }

    return ITEM_NONE;
}

int GetItemSlot(int item)
{
    return (item == ITEM_KIT || item == ITEM_DEFIB) ? SLOT_MEDICAL : SLOT_PILLS;
}

void GetItemName(int item, char[] buffer, int size)
{
    switch (item)
    {
        case ITEM_KIT:
        {
            strcopy(buffer, size, "first aid kit");
        }
        case ITEM_DEFIB:
        {
            strcopy(buffer, size, "defibrillator");
        }
        case ITEM_PILLS:
        {
            strcopy(buffer, size, "pain pills");
        }
        case ITEM_ADREN:
        {
            strcopy(buffer, size, "adrenaline");
        }
        default:
        {
            strcopy(buffer, size, "item");
        }
    }
}

void ThrottledHint(int client, const char[] format, any ...)
{
    float now = GetGameTime();
    if (now < g_fNextHint[client])
    {
        return;
    }

    g_fNextHint[client] = now + 1.0;

    char buffer[192];
    VFormat(buffer, sizeof(buffer), format, 3);
    PrintHintText(client, "%s", buffer);
}
