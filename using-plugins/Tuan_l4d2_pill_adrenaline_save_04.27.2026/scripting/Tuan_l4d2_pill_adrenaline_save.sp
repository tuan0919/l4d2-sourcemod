#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "04.27.2026"
#define CVAR_FLAGS FCVAR_NOTIFY

#define TEAM_SURVIVOR 2
#define SLOT_PILLS 4

#define ITEM_NONE -1
#define ITEM_PILLS 0
#define ITEM_ADREN 1

#define AIM_DOT_MIN 0.985

ConVar g_hEnable;
ConVar g_hRange;
ConVar g_hAnimTime;
ConVar g_hMainHealth;
ConVar g_hTempHealth;
ConVar g_hGodmode;
ConVar g_hChatHint;
ConVar g_hHintCooldown;
ConVar g_hUseHintCooldown;
ConVar g_hReviveTemp;

bool g_bEnabled;
bool g_bGodmode;
bool g_bChatHint;
float g_fRange;
float g_fAnimTime;
float g_fTempHealth;
float g_fHintCooldown;
float g_fUseHintCooldown;
int g_iMainHealth;

int g_iLastButtons[MAXPLAYERS + 1];
int g_iLastActiveRef[MAXPLAYERS + 1];
int g_iSaveHealerUserId[MAXPLAYERS + 1];
int g_iSaveItemType[MAXPLAYERS + 1];
int g_iHealerTargetUserId[MAXPLAYERS + 1];
bool g_bSavingTarget[MAXPLAYERS + 1];
float g_fNextChatHint[MAXPLAYERS + 1];
float g_fNextUseHint[MAXPLAYERS + 1];
Handle g_hSaveTimer[MAXPLAYERS + 1];
GlobalForward g_hForwardRemoteItemSaved;

public Plugin myinfo =
{
    name = "[L4D2] Tuan Pill Adrenaline Save",
    author = "Tuan, OpenCode",
    description = "Use held pills/adrenaline to remotely save aimed incapacitated teammates with get-up animation.",
    version = PLUGIN_VERSION,
    url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    if (GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "This plugin only supports Left 4 Dead 2.");
        return APLRes_SilentFailure;
    }

    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hForwardRemoteItemSaved = CreateGlobalForward("Tuan_OnClient_RemoteItemSaved", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);

    g_hEnable = CreateConVar("Tuan_l4d2_pill_adrenaline_save_enable", "1", "0=Off, 1=On.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hRange = CreateConVar("Tuan_l4d2_pill_adrenaline_save_range", "650.0", "Maximum distance to save an aimed incapacitated teammate.", CVAR_FLAGS, true, 1.0);
    g_hAnimTime = CreateConVar("Tuan_l4d2_pill_adrenaline_save_anim_time", "5.0", "Seconds to keep the target in self-revive get-up animation before the revive is applied.", CVAR_FLAGS, true, 0.1);
    g_hMainHealth = CreateConVar("Tuan_l4d2_pill_adrenaline_save_main_health", "20", "Main health after remote item save. 0=Do not override.", CVAR_FLAGS, true, 0.0);
    g_hTempHealth = CreateConVar("Tuan_l4d2_pill_adrenaline_save_temp_health", "-1.0", "Temp health after remote item save. -1=Use survivor_revive_health, 0=Do not override.", CVAR_FLAGS);
    g_hGodmode = CreateConVar("Tuan_l4d2_pill_adrenaline_save_godmode", "1", "0=Target can take damage during get-up animation, 1=Block damage during animation.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hChatHint = CreateConVar("Tuan_l4d2_pill_adrenaline_save_chat_hint", "1", "0=Off, 1=Tell holder they can use pills/adrenaline to save incapped teammates when switching to that item.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hHintCooldown = CreateConVar("Tuan_l4d2_pill_adrenaline_save_chat_hint_cooldown", "8.0", "Seconds before showing the switch chat hint again.", CVAR_FLAGS, true, 0.0);
    g_hUseHintCooldown = CreateConVar("Tuan_l4d2_pill_adrenaline_save_use_hint_cooldown", "1.0", "Seconds before repeating failed-use hints.", CVAR_FLAGS, true, 0.0);

    HookConVarChange(g_hEnable, OnConVarChanged);
    HookConVarChange(g_hRange, OnConVarChanged);
    HookConVarChange(g_hAnimTime, OnConVarChanged);
    HookConVarChange(g_hMainHealth, OnConVarChanged);
    HookConVarChange(g_hTempHealth, OnConVarChanged);
    HookConVarChange(g_hGodmode, OnConVarChanged);
    HookConVarChange(g_hChatHint, OnConVarChanged);
    HookConVarChange(g_hHintCooldown, OnConVarChanged);
    HookConVarChange(g_hUseHintCooldown, OnConVarChanged);

    HookEvent("round_start", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("mission_lost", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);

    g_hReviveTemp = FindConVar("survivor_revive_health");

    AutoExecConfig(true, "Tuan_l4d2_pill_adrenaline_save");
    RefreshCvars();
}

public void OnMapEnd()
{
    ResetAllClients();
}

public void OnClientPutInServer(int client)
{
    ResetClient(client);
}

public void OnClientDisconnect(int client)
{
    int target = GetClientOfUserId(g_iHealerTargetUserId[client]);
    if (target > 0)
    {
        CancelTargetSave(target, true);
    }

    CancelTargetSave(client, false);
    ResetClient(client);
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshCvars();
}

void RefreshCvars()
{
    g_bEnabled = g_hEnable.BoolValue;
    g_fRange = g_hRange.FloatValue;
    g_fAnimTime = g_hAnimTime.FloatValue;
    g_iMainHealth = g_hMainHealth.IntValue;
    g_fTempHealth = g_hTempHealth.FloatValue;
    g_bGodmode = g_hGodmode.BoolValue;
    g_bChatHint = g_hChatHint.BoolValue;
    g_fHintCooldown = g_hHintCooldown.FloatValue;
    g_fUseHintCooldown = g_hUseHintCooldown.FloatValue;
}

void Event_Reset(Event event, const char[] name, bool dontBroadcast)
{
    ResetAllClients();
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        CancelTargetSave(client, true);
        ResetClient(client);
    }
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        CancelTargetSave(client, true);
        ResetClient(client);
    }
}

void ResetAllClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        CancelTargetSave(client, true);
        ResetClient(client);
    }
}

void ResetClient(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    delete g_hSaveTimer[client];
    g_iLastButtons[client] = 0;
    g_iLastActiveRef[client] = INVALID_ENT_REFERENCE;
    g_iSaveHealerUserId[client] = 0;
    g_iSaveItemType[client] = ITEM_NONE;
    g_iHealerTargetUserId[client] = 0;
    g_bSavingTarget[client] = false;
    g_fNextChatHint[client] = 0.0;
    g_fNextUseHint[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsValidHealer(client))
    {
        if (client >= 1 && client <= MaxClients)
        {
            g_iLastButtons[client] = buttons;
        }
        return Plugin_Continue;
    }

    int activeWeapon;
    int item = GetHeldMedicalItem(client, activeWeapon);
    TrackActiveWeaponSwitch(client, activeWeapon, item);

    if (g_bEnabled && item != ITEM_NONE && (buttons & IN_USE) && !(g_iLastButtons[client] & IN_USE))
    {
        TryStartRemoteSave(client, item, activeWeapon);
    }

    g_iLastButtons[client] = buttons;
    return Plugin_Continue;
}

void TrackActiveWeaponSwitch(int client, int weapon, int item)
{
    int activeRef = INVALID_ENT_REFERENCE;
    if (weapon > MaxClients && IsValidEntity(weapon))
    {
        activeRef = EntIndexToEntRef(weapon);
    }

    if (activeRef == g_iLastActiveRef[client])
    {
        return;
    }

    g_iLastActiveRef[client] = activeRef;

    if (!g_bEnabled || !g_bChatHint || item == ITEM_NONE || !AnyIncappedSurvivor(client))
    {
        return;
    }

    float now = GetGameTime();
    if (now < g_fNextChatHint[client])
    {
        return;
    }

    g_fNextChatHint[client] = now + g_fHintCooldown;

    char itemName[32];
    GetItemDisplayName(item, itemName, sizeof(itemName));
    PrintToChat(client, "\x05[Remote Save]\x01 You can use \x04%s\x01 to save an incapacitated teammate from range. Aim at them and press \x04USE\x01.", itemName);
}

void TryStartRemoteSave(int healer, int item, int weapon)
{
    int currentTarget = GetClientOfUserId(g_iHealerTargetUserId[healer]);
    if (currentTarget > 0 && g_bSavingTarget[currentTarget])
    {
        ThrottledHint(healer, "You are already saving a teammate.");
        return;
    }

    int target = FindAimedIncappedTarget(healer);
    if (target <= 0)
    {
        ThrottledHint(healer, "Aim at an incapacitated teammate within range to save them.");
        return;
    }

    if (g_bSavingTarget[target])
    {
        ThrottledHint(healer, "That teammate is already being saved.");
        return;
    }

    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        ThrottledHint(healer, "Hold pain pills or adrenaline to save a teammate.");
        return;
    }

    RemovePlayerItem(healer, weapon);
    RemoveEntity(weapon);

    StartTargetGetupAnimation(healer, target, item);
}

void StartTargetGetupAnimation(int healer, int target, int item)
{
    g_bSavingTarget[target] = true;
    g_iSaveHealerUserId[target] = GetClientUserId(healer);
    g_iSaveItemType[target] = item;
    g_iHealerTargetUserId[healer] = GetClientUserId(target);

    if (GetEntPropFloat(target, Prop_Send, "m_TimeForceExternalView") != 99999.3)
    {
        SetEntPropFloat(target, Prop_Send, "m_TimeForceExternalView", GetGameTime() + g_fAnimTime);
    }

    SetEntPropEnt(target, Prop_Send, "m_reviveOwner", target);

    if (g_bGodmode)
    {
        SDKHook(target, SDKHook_OnTakeDamageAlive, OnTakeSaveDamage);
    }

    delete g_hSaveTimer[target];
    g_hSaveTimer[target] = CreateTimer(g_fAnimTime, Timer_RemoteSaveComplete, GetClientUserId(target));

    char itemName[32];
    GetItemDisplayName(item, itemName, sizeof(itemName));
    PrintHintText(healer, "Saving %N with %s...", target, itemName);
    PrintHintText(target, "%N is saving you with %s...", healer, itemName);
}

Action Timer_RemoteSaveComplete(Handle timer, int userid)
{
    int target = GetClientOfUserId(userid);
    if (target <= 0)
    {
        return Plugin_Stop;
    }

    g_hSaveTimer[target] = null;

    int healer = GetClientOfUserId(g_iSaveHealerUserId[target]);
    int item = g_iSaveItemType[target];

    if (!IsValidIncappedTarget(target))
    {
        CancelTargetSave(target, true);
        return Plugin_Stop;
    }

    SetEntPropEnt(target, Prop_Send, "m_reviveOwner", -1);
    L4D_ReviveSurvivor(target);
    ApplyReviveHealth(target);

    FinishTargetSave(target, healer, item);
    return Plugin_Stop;
}

Action OnTakeSaveDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3])
{
    if (victim >= 1 && victim <= MaxClients && g_bSavingTarget[victim] && g_bGodmode)
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

void FinishTargetSave(int target, int healer, int item)
{
    int healerUserId = g_iSaveHealerUserId[target];

    CleanupTargetSave(target, false);

    if (healer > 0 && IsClientInGame(healer))
    {
        g_iHealerTargetUserId[healer] = 0;
        PrintHintText(healer, "Saved %N", target);
    }

    if (IsClientInGame(target))
    {
        PrintHintText(target, "You were saved");
    }

    FireRemoteItemSavedForward(healerUserId, target, item);
}

void CancelTargetSave(int target, bool clearReviveOwner)
{
    if (target < 1 || target > MaxClients)
    {
        return;
    }

    int healer = GetClientOfUserId(g_iSaveHealerUserId[target]);
    if (healer > 0)
    {
        g_iHealerTargetUserId[healer] = 0;
    }

    CleanupTargetSave(target, clearReviveOwner);
}

void CleanupTargetSave(int target, bool clearReviveOwner)
{
    delete g_hSaveTimer[target];

    if (g_bSavingTarget[target])
    {
        SDKUnhook(target, SDKHook_OnTakeDamageAlive, OnTakeSaveDamage);
    }

    if (clearReviveOwner && IsClientInGame(target) && GetEntPropEnt(target, Prop_Send, "m_reviveOwner") == target)
    {
        SetEntPropEnt(target, Prop_Send, "m_reviveOwner", -1);
    }

    g_bSavingTarget[target] = false;
    g_iSaveHealerUserId[target] = 0;
    g_iSaveItemType[target] = ITEM_NONE;
}

void ApplyReviveHealth(int target)
{
    if (g_iMainHealth > 0)
    {
        SetEntityHealth(target, g_iMainHealth);
    }

    float tempHealth = g_fTempHealth;
    if (tempHealth < 0.0)
    {
        tempHealth = g_hReviveTemp != null ? g_hReviveTemp.FloatValue : 0.0;
    }

    if (tempHealth > 0.0)
    {
        SetEntPropFloat(target, Prop_Send, "m_healthBuffer", tempHealth);
        SetEntPropFloat(target, Prop_Send, "m_healthBufferTime", GetGameTime());
    }
}

void FireRemoteItemSavedForward(int healerUserId, int target, int item)
{
    if (g_hForwardRemoteItemSaved == null)
    {
        return;
    }

    int healer = GetClientOfUserId(healerUserId);
    Call_StartForward(g_hForwardRemoteItemSaved);
    Call_PushCell(healer);
    Call_PushCell(target);
    Call_PushCell(item);
    Call_Finish();
}

int FindAimedIncappedTarget(int healer)
{
    int target = GetClientAimTarget(healer, true);
    if (IsValidIncappedTarget(target) && IsTargetInRange(healer, target))
    {
        return target;
    }

    return FindTargetByAimCone(healer);
}

int FindTargetByAimCone(int healer)
{
    float eye[3], angles[3], fwd[3], right[3], up[3];
    GetClientEyePosition(healer, eye);
    GetClientEyeAngles(healer, angles);
    GetAngleVectors(angles, fwd, right, up);
    NormalizeVector(fwd, fwd);

    int bestTarget = 0;
    float bestScore = 0.0;

    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsValidIncappedTarget(target) || target == healer)
        {
            continue;
        }

        float pos[3], toTarget[3];
        GetTargetAimPoint(target, pos);
        MakeVectorFromPoints(eye, pos, toTarget);
        float distance = NormalizeVector(toTarget, toTarget);

        if (distance > g_fRange)
        {
            continue;
        }

        float dot = GetVectorDotProduct(fwd, toTarget);
        if (dot < AIM_DOT_MIN || !HasClearTraceToTarget(healer, target, pos))
        {
            continue;
        }

        float score = dot - (distance / g_fRange * 0.02);
        if (bestTarget == 0 || score > bestScore)
        {
            bestTarget = target;
            bestScore = score;
        }
    }

    return bestTarget;
}

bool HasClearTraceToTarget(int healer, int target, float targetPos[3])
{
    float start[3];
    GetClientEyePosition(healer, start);

    Handle trace = TR_TraceRayFilterEx(start, targetPos, MASK_SHOT, RayType_EndPoint, TraceFilter_TargetOnly, target);
    bool clear = false;

    if (!TR_DidHit(trace))
    {
        clear = true;
    }
    else
    {
        clear = (TR_GetEntityIndex(trace) == target);
    }

    delete trace;
    return clear;
}

public bool TraceFilter_TargetOnly(int entity, int contentsMask, any data)
{
    if (entity == data)
    {
        return true;
    }

    if (entity > 0 && entity <= MaxClients)
    {
        return false;
    }

    return true;
}

bool IsTargetInRange(int healer, int target)
{
    float healerPos[3], targetPos[3];
    GetClientEyePosition(healer, healerPos);
    GetTargetAimPoint(target, targetPos);
    return GetVectorDistance(healerPos, targetPos) <= g_fRange;
}

void GetTargetAimPoint(int target, float pos[3])
{
    GetClientAbsOrigin(target, pos);
    pos[2] += 32.0;
}

bool AnyIncappedSurvivor(int healer)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (client != healer && IsValidIncappedTarget(client))
        {
            return true;
        }
    }

    return false;
}

bool IsValidHealer(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVOR
        && IsPlayerAlive(client)
        && !IsFakeClient(client)
        && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 0
        && GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) == 0;
}

bool IsValidIncappedTarget(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVOR
        && IsPlayerAlive(client)
        && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) != 0
        && GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) == 0;
}

int GetHeldMedicalItem(int client, int &weapon)
{
    weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon) || weapon != GetPlayerWeaponSlot(client, SLOT_PILLS))
    {
        return ITEM_NONE;
    }

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    if (StrEqual(classname, "weapon_pain_pills"))
    {
        return ITEM_PILLS;
    }

    if (StrEqual(classname, "weapon_adrenaline"))
    {
        return ITEM_ADREN;
    }

    return ITEM_NONE;
}

void GetItemDisplayName(int item, char[] buffer, int maxlen)
{
    switch (item)
    {
        case ITEM_PILLS: strcopy(buffer, maxlen, "pain pills");
        case ITEM_ADREN: strcopy(buffer, maxlen, "adrenaline");
        default: strcopy(buffer, maxlen, "medical item");
    }
}

void ThrottledHint(int client, const char[] message)
{
    float now = GetGameTime();
    if (now < g_fNextUseHint[client])
    {
        return;
    }

    g_fNextUseHint[client] = now + g_fUseHintCooldown;
    PrintHintText(client, message);
}
