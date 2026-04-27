#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <attachments_api>

#define PLUGIN_VERSION "04.27.2026"
#define CVAR_FLAGS FCVAR_NOTIFY

#define TEAM_SURVIVOR 2
#define SLOT_FIRST_AID 3
#define SLOT_PILLS 4

#define ITEM_NONE -1
#define ITEM_FIRST_AID 0
#define ITEM_DEFIB 1
#define ITEM_PILLS 2
#define ITEM_ADREN 3

#define GLOW_NONE 0
#define GLOW_HEALTHY 1
#define GLOW_LOW 2
#define GLOW_BNW 3

#define DEFAULT_SYNC_INTERVAL 0.5
#define MIN_SYNC_INTERVAL 0.1

#define EF_BONEMERGE (1 << 0)
#define EF_NOSHADOW (1 << 4)
#define EF_BONEMERGE_FASTCULL (1 << 7)
#define EF_PARENT_ANIMATES (1 << 9)
#define FSOLID_NOT_SOLID 0x0004

ConVar g_hEnable;
ConVar g_hRange;
ConVar g_hLowHealth;
ConVar g_hSyncInterval;
ConVar g_hMaxIncap;

bool g_bEnabled;
float g_fRange;
float g_fSyncInterval;
int g_iLowHealth;

int g_iHeldHealthItem[MAXPLAYERS + 1];
int g_iLastActiveRef[MAXPLAYERS + 1];
int g_iHealthGlowRef[MAXPLAYERS + 1];
int g_iHealthGlowState[MAXPLAYERS + 1];
Handle g_hSyncTimer;

public Plugin myinfo =
{
    name = "[L4D2] Tuan Health Status Glow",
    author = "Tuan, OpenCode",
    description = "Shows survivor health-state glow to nearby teammates holding health items.",
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
    g_hEnable = CreateConVar("Tuan_l4d2_health_status_glow_enable", "1", "0=Off, 1=On.", CVAR_FLAGS, true, 0.0, true, 1.0);
    g_hRange = CreateConVar("Tuan_l4d2_health_status_glow_range", "650.0", "Maximum distance for health item holders to see teammate health glow.", CVAR_FLAGS, true, 1.0);
    g_hLowHealth = CreateConVar("Tuan_l4d2_health_status_glow_low_health", "40", "Total health at or below this value uses yellow glow.", CVAR_FLAGS, true, 1.0);
    g_hSyncInterval = CreateConVar("Tuan_l4d2_health_status_glow_sync_interval", "0.5", "Seconds between health glow state syncs.", CVAR_FLAGS, true, MIN_SYNC_INTERVAL);

    HookConVarChange(g_hEnable, OnConVarChanged);
    HookConVarChange(g_hRange, OnConVarChanged);
    HookConVarChange(g_hLowHealth, OnConVarChanged);
    HookConVarChange(g_hSyncInterval, OnConVarChanged);

    HookEvent("round_start", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("round_end", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("mission_lost", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_Reset, EventHookMode_PostNoCopy);
    HookEvent("player_death", Event_PlayerRemoved, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerRemoved, EventHookMode_Post);
    HookEvent("heal_success", Event_HealthChanged, EventHookMode_Post);
    HookEvent("revive_success", Event_HealthChanged, EventHookMode_Post);

    g_hMaxIncap = FindConVar("survivor_max_incapacitated_count");

    AutoExecConfig(true, "Tuan_l4d2_health_status_glow");
    RefreshCvars();
    RestartSyncTimer();
}

public void OnMapEnd()
{
    ResetAllClients();
}

public void OnPluginEnd()
{
    delete g_hSyncTimer;
    RemoveAllHealthGlows();
}

public void OnClientPutInServer(int client)
{
    ResetClient(client);
}

public void OnClientDisconnect(int client)
{
    ResetClient(client);
    SyncHealthStatusGlows();
}

void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    RefreshCvars();
    RestartSyncTimer();

    if (!g_bEnabled)
    {
        RemoveAllHealthGlows();
        return;
    }

    SyncHealthStatusGlows();
}

void RefreshCvars()
{
    g_bEnabled = g_hEnable.BoolValue;
    g_fRange = g_hRange.FloatValue;
    g_iLowHealth = g_hLowHealth.IntValue;
    g_fSyncInterval = g_hSyncInterval.FloatValue;

    if (g_fSyncInterval < MIN_SYNC_INTERVAL)
    {
        g_fSyncInterval = MIN_SYNC_INTERVAL;
    }
}

void RestartSyncTimer()
{
    delete g_hSyncTimer;

    if (g_bEnabled)
    {
        g_hSyncTimer = CreateTimer(g_fSyncInterval, Timer_SyncHealthStatusGlows, 0, TIMER_REPEAT);
    }
}

void Event_Reset(Event event, const char[] name, bool dontBroadcast)
{
    ResetAllClients();
}

void Event_PlayerRemoved(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client > 0)
    {
        ResetClient(client);
        SyncHealthStatusGlows();
    }
}

void Event_HealthChanged(Event event, const char[] name, bool dontBroadcast)
{
    if (g_bEnabled)
    {
        SyncHealthStatusGlows();
    }
}

void ResetAllClients()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetClient(client);
    }
}

void ResetClient(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    RemoveHealthGlow(client);
    g_iHeldHealthItem[client] = ITEM_NONE;
    g_iLastActiveRef[client] = INVALID_ENT_REFERENCE;
    g_iHealthGlowRef[client] = INVALID_ENT_REFERENCE;
    g_iHealthGlowState[client] = GLOW_NONE;
}

Action Timer_SyncHealthStatusGlows(Handle timer, any data)
{
    SyncHealthStatusGlows();
    return Plugin_Continue;
}

void SyncHealthStatusGlows()
{
    if (!g_bEnabled)
    {
        RemoveAllHealthGlows();
        return;
    }

    bool hasViewer = AnyHealthGlowViewer();
    for (int target = 1; target <= MaxClients; target++)
    {
        if (hasViewer && IsValidGlowTarget(target))
        {
            int state = GetHealthGlowState(target);
            if (state != GLOW_NONE)
            {
                EnsureHealthGlow(target, state);
                continue;
            }
        }

        RemoveHealthGlow(target);
    }
}

bool AnyHealthGlowViewer()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_iHeldHealthItem[client] != ITEM_NONE && IsValidGlowViewer(client))
        {
            return true;
        }
    }

    return false;
}

void EnsureHealthGlow(int target, int state)
{
    int entity = EntRefToEntIndex(g_iHealthGlowRef[target]);
    if (entity > MaxClients && IsValidEntity(entity))
    {
        if (!SetHealthGlowColor(entity, state))
        {
            RemoveHealthGlow(target);
            return;
        }

        g_iHealthGlowState[target] = state;
        return;
    }

    RemoveHealthGlow(target);

    char model[PLATFORM_MAX_PATH];
    GetEntPropString(target, Prop_Data, "m_ModelName", model, sizeof(model));
    if (model[0] == '\0')
    {
        return;
    }

    entity = CreateEntityByName("prop_dynamic_ornament");
    if (entity <= MaxClients || !IsValidEntity(entity))
    {
        return;
    }

    DispatchKeyValue(entity, "targetname", "tuan_health_status_glow");
    SetEntityModel(entity, model);
    if (!DispatchSpawn(entity))
    {
        RemoveEntity(entity);
        return;
    }

    float origin[3];
    GetClientAbsOrigin(target, origin);
    TeleportEntity(entity, origin, NULL_VECTOR, NULL_VECTOR);

    SetEntProp(entity, Prop_Send, "m_CollisionGroup", 0);
    SetEntProp(entity, Prop_Send, "m_nSolidType", 0);
    SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", target);

    if (!SetHealthGlowColor(entity, state))
    {
        RemoveEntity(entity);
        return;
    }

    AcceptEntityInput(entity, "StartGlowing");

    SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
    SetEntityRenderColor(entity, 0, 0, 0, 0);

    AttachGlowProxyToTarget(entity, target);

    SDKHook(entity, SDKHook_SetTransmit, Hook_HealthGlowTransmit);
    g_iHealthGlowRef[target] = EntIndexToEntRef(entity);
    g_iHealthGlowState[target] = state;
}

bool SetHealthGlowColor(int entity, int state)
{
    int glowColor[3];
    GetGlowColor(state, glowColor);
    return L4D2_SetEntityGlow(entity, L4D2Glow_Constant, RoundToCeil(g_fRange), 0, glowColor, false);
}

void AttachGlowProxyToTarget(int entity, int target)
{
    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetParent", target);

    SetVariantString("!activator");
    AcceptEntityInput(entity, "SetAttached", target);

    SetEntityMoveType(entity, MOVETYPE_NONE);
    SetEntProp(entity, Prop_Send, "m_fEffects", EF_BONEMERGE | EF_NOSHADOW | EF_BONEMERGE_FASTCULL | EF_PARENT_ANIMATES);

    int solidFlags = GetEntProp(entity, Prop_Data, "m_usSolidFlags", 2);
    solidFlags |= FSOLID_NOT_SOLID;
    SetEntProp(entity, Prop_Data, "m_usSolidFlags", solidFlags, 2);

    float origin[3] = {0.0, 0.0, 0.0};
    float angles[3] = {0.0, 0.0, 0.0};
    TeleportEntity(entity, origin, angles, NULL_VECTOR);
}

void GetGlowColor(int state, int color[3])
{
    switch (state)
    {
        case GLOW_BNW:
        {
            color[0] = 255;
            color[1] = 255;
            color[2] = 255;
        }
        case GLOW_LOW:
        {
            color[0] = 255;
            color[1] = 255;
            color[2] = 0;
        }
        case GLOW_HEALTHY:
        {
            color[0] = 0;
            color[1] = 255;
            color[2] = 0;
        }
        default:
        {
            color[0] = 0;
            color[1] = 0;
            color[2] = 0;
        }
    }
}

void RemoveHealthGlow(int target)
{
    if (target < 1 || target > MaxClients)
    {
        return;
    }

    int entity = EntRefToEntIndex(g_iHealthGlowRef[target]);
    g_iHealthGlowRef[target] = INVALID_ENT_REFERENCE;
    g_iHealthGlowState[target] = GLOW_NONE;

    if (entity > MaxClients && IsValidEntity(entity))
    {
        RemoveEntity(entity);
    }
}

void RemoveAllHealthGlows()
{
    for (int target = 1; target <= MaxClients; target++)
    {
        RemoveHealthGlow(target);
    }
}

public Action Hook_HealthGlowTransmit(int entity, int client)
{
    int target = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (target < 1 || target > MaxClients || g_iHealthGlowRef[target] != EntIndexToEntRef(entity) || !ShouldClientSeeHealthGlow(client, target))
    {
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

bool ShouldClientSeeHealthGlow(int client, int target)
{
    if (!g_bEnabled || client == target || !IsValidGlowViewer(client) || !IsValidGlowTarget(target))
    {
        return false;
    }

    if (g_iHeldHealthItem[client] == ITEM_NONE)
    {
        return false;
    }

    return IsTargetInRange(client, target);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!IsValidGlowViewer(client))
    {
        if (client >= 1 && client <= MaxClients)
        {
            SetHeldHealthItem(client, ITEM_NONE);
            g_iLastActiveRef[client] = INVALID_ENT_REFERENCE;
        }

        return Plugin_Continue;
    }

    int activeWeapon;
    int item = GetHeldHealthItem(client, activeWeapon);
    TrackActiveWeapon(client, activeWeapon, item);
    return Plugin_Continue;
}

public void Attachments_OnWeaponSwitch(int client, int weapon, int ent_views, int ent_world)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    int item = ITEM_NONE;
    if (IsValidGlowViewer(client) && IsWeaponInHealthSlots(client, weapon))
    {
        item = GetHealthItemFromWeapon(weapon);
    }

    SetHeldHealthItem(client, item);
}

public void Attachments_OnPluginEnd()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        SetHeldHealthItem(client, ITEM_NONE);
    }
}

void TrackActiveWeapon(int client, int weapon, int item)
{
    int activeRef = INVALID_ENT_REFERENCE;
    if (weapon > MaxClients && IsValidEntity(weapon))
    {
        activeRef = EntIndexToEntRef(weapon);
    }

    if (activeRef == g_iLastActiveRef[client] && g_iHeldHealthItem[client] == item)
    {
        return;
    }

    g_iLastActiveRef[client] = activeRef;
    SetHeldHealthItem(client, item);
}

void SetHeldHealthItem(int client, int item)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    if (g_iHeldHealthItem[client] == item)
    {
        return;
    }

    g_iHeldHealthItem[client] = item;
    SyncHealthStatusGlows();
}

int GetHealthGlowState(int target)
{
    if (IsClientBnW(target))
    {
        return GLOW_BNW;
    }

    float totalHealth = float(GetClientHealth(target)) + L4D_GetTempHealth(target);
    if (totalHealth <= float(g_iLowHealth))
    {
        return GLOW_LOW;
    }

    return GLOW_HEALTHY;
}

bool IsClientBnW(int client)
{
    if (HasEntProp(client, Prop_Send, "m_bIsOnThirdStrike") && GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike") != 0)
    {
        return true;
    }

    if (!HasEntProp(client, Prop_Send, "m_currentReviveCount"))
    {
        return false;
    }

    int maxIncap = g_hMaxIncap != null ? g_hMaxIncap.IntValue : 2;
    return GetEntProp(client, Prop_Send, "m_currentReviveCount") >= maxIncap;
}

bool IsValidGlowViewer(int client)
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

bool IsValidGlowTarget(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && GetClientTeam(client) == TEAM_SURVIVOR
        && IsPlayerAlive(client)
        && GetEntProp(client, Prop_Send, "m_isIncapacitated", 1) == 0
        && GetEntProp(client, Prop_Send, "m_isHangingFromLedge", 1) == 0;
}

bool IsTargetInRange(int viewer, int target)
{
    float viewerPos[3], targetPos[3];
    GetClientEyePosition(viewer, viewerPos);
    GetTargetGlowPoint(target, targetPos);
    return GetVectorDistance(viewerPos, targetPos) <= g_fRange;
}

void GetTargetGlowPoint(int target, float pos[3])
{
    GetClientAbsOrigin(target, pos);
    pos[2] += 32.0;
}

int GetHeldHealthItem(int client, int &weapon)
{
    weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsWeaponInHealthSlots(client, weapon))
    {
        return ITEM_NONE;
    }

    return GetHealthItemFromWeapon(weapon);
}

bool IsWeaponInHealthSlots(int client, int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return false;
    }

    return weapon == GetPlayerWeaponSlot(client, SLOT_FIRST_AID) || weapon == GetPlayerWeaponSlot(client, SLOT_PILLS);
}

int GetHealthItemFromWeapon(int weapon)
{
    if (weapon <= MaxClients || !IsValidEntity(weapon))
    {
        return ITEM_NONE;
    }

    char classname[64];
    GetEdictClassname(weapon, classname, sizeof(classname));

    if (StrEqual(classname, "weapon_first_aid_kit"))
    {
        return ITEM_FIRST_AID;
    }

    if (StrEqual(classname, "weapon_defibrillator"))
    {
        return ITEM_DEFIB;
    }

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
