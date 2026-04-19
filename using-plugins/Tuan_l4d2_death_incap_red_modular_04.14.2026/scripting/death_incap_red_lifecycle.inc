public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("L4D2_IsEliteSI");
    MarkNativeAsOptional("L4D2_GetEliteTypeName");
    MarkNativeAsOptional("EliteSI_Noxious_GetRecentDamageCause");
    MarkNativeAsOptional("EliteSI_Noxious_GetRecentDamageAttacker");
    MarkNativeAsOptional("EliteSI_ToxicGas_GetRecentDamageCause");
    MarkNativeAsOptional("EliteSI_ToxicGas_GetRecentDamageAttacker");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hEnable = CreateConVar("l4d2_redannounce_enable", "1", "Enable red death/incap announce plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hAnnounceEliteSIKill = CreateConVar("l4d2_redannounce_announce_elite_si_kill", "1", "Announce Elite SI tag in SI kill messages (survivor kills SI).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hEnable.AddChangeHook(OnCvarChanged);
    g_hAnnounceEliteSIKill.AddChangeHook(OnCvarChanged);
    g_bEnable = g_hEnable.BoolValue;
    g_bAnnounceEliteSIKill = g_hAnnounceEliteSIKill.BoolValue;

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_incapacitated_start", Event_PlayerIncapStart, EventHookMode_Post);
    HookEvent("revive_success", Event_ReviveSuccess, EventHookMode_Post);
    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);
    HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);
    HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);

    AutoExecConfig(true, "Tuan_l4d2_death_incap_red");

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
        }
    }

    g_hAnchorTimer = CreateTimer(5.0, Timer_ConsolidatedUpdate, _, TIMER_REPEAT);
    g_hBurnWatchTimer = CreateTimer(0.25, Timer_ConsolidatedUpdate, _, TIMER_REPEAT);
    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(2.0, Timer_HookExistingHazards, _, TIMER_FLAG_NO_MAPCHANGE);

    g_bHasEliteNative = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available);
}

public void OnAllPluginsLoaded()
{
    g_bHasEliteNative = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available);
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "l4d2_elite_SI_reward"))
    {
        g_bHasEliteNative = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available);
    }
}

public void OnLibraryRemoved(const char[] name)
{
    if (StrEqual(name, "l4d2_elite_SI_reward"))
    {
        g_bHasEliteNative = false;
    }
}

public void OnPluginEnd()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        ClearPendingIncap(i);
    }

    if (g_hAnchorTimer != null)
    {
        delete g_hAnchorTimer;
        g_hAnchorTimer = null;
    }

    if (g_hBurnWatchTimer != null)
    {
        delete g_hBurnWatchTimer;
        g_hBurnWatchTimer = null;
    }

    int anchor = GetClientOfUserId(g_iAnchorUserId);
    if (anchor > 0 && anchor <= MaxClients && IsClientInGame(anchor) && IsFakeClient(anchor))
    {
        KickClient(anchor, "Removing anchor bot");
    }
}

public void OnMapStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iLastFireAssistType[i] = view_as<int>(Hazard_None);
        g_iLastFireAssistOwner[i] = 0;
        g_fLastFireAssistTime[i] = 0.0;
        g_bFireAssistLocked[i] = false;
        g_fLastIncendiaryShot[i] = 0.0;
        g_fLastExplosiveShot[i] = 0.0;
        g_sLastSpecialBulletWeapon[i][0] = '\0';
        g_iLastStaggerBy[i] = 0;
        g_fLastStaggerTime[i] = 0.0;
    }

    for (int i = 0; i < MAX_TRACKED_EDICTS; i++)
    {
        g_bHazardHooked[i] = false;
        g_iHazardEntType[i] = view_as<int>(Hazard_None);
        g_iHazardLastOwner[i] = 0;
        g_fHazardLastHitTime[i] = 0.0;
        g_vHazardLastPos[i][0] = 0.0;
        g_vHazardLastPos[i][1] = 0.0;
        g_vHazardLastPos[i][2] = 0.0;
        g_bMolotovProjectile[i] = false;
        g_iMolotovOwner[i] = 0;
        g_vMolotovLastPos[i][0] = 0.0;
        g_vMolotovLastPos[i][1] = 0.0;
        g_vMolotovLastPos[i][2] = 0.0;
        g_iFireEntSourceType[i] = view_as<int>(Hazard_None);
        g_iFireEntOwner[i] = 0;
        g_iFireEntSourceConfidence[i] = view_as<int>(FireSourceConfidence_None);
        g_fFireEntMarkTime[i] = 0.0;
        g_bFireEntRecheckQueued[i] = false;
    }

    for (int i = 0; i < MAX_SOURCE_EVENTS; i++)
    {
        g_iSourceType[i] = view_as<int>(Hazard_None);
        g_iSourceOwner[i] = 0;
        g_fSourceTime[i] = 0.0;
        g_vSourcePos[i][0] = 0.0;
        g_vSourcePos[i][1] = 0.0;
        g_vSourcePos[i][2] = 0.0;
    }
    g_iSourceWrite = 0;

    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(2.0, Timer_HookExistingHazards, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
}

public void OnClientDisconnect(int client)
{
    if (GetClientUserId(client) == g_iAnchorUserId)
    {
        g_iAnchorUserId = 0;
    }

    ResetSnapshot(client);
    ClearPendingIncap(client);
    g_fLastMolotovThrow[client] = 0.0;
    g_iLastHazardType[client] = view_as<int>(Hazard_None);
    g_fLastHazardTime[client] = 0.0;
    g_iLastHazardEntityRef[client] = INVALID_ENT_REFERENCE;
    g_iLastFireAssistType[client] = view_as<int>(Hazard_None);
    g_iLastFireAssistOwner[client] = 0;
    g_fLastFireAssistTime[client] = 0.0;
    g_bFireAssistLocked[client] = false;
    g_bIsIncappedState[client] = false;
    g_fLastIncapTime[client] = 0.0;
    g_fLastIncendiaryShot[client] = 0.0;
    g_fLastExplosiveShot[client] = 0.0;
    g_sLastSpecialBulletWeapon[client][0] = '\0';
    g_iLastStaggerBy[client] = 0;
    g_fLastStaggerTime[client] = 0.0;
}

public void OnCvarChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    g_bEnable = g_hEnable.BoolValue;
    g_bAnnounceEliteSIKill = g_hAnnounceEliteSIKill.BoolValue;
}
