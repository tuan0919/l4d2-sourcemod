void FormatCauseForChatColors(const char[] cause, char[] outCause, int maxlen)
{
    strcopy(outCause, maxlen, cause);
    ReplaceString(outCause, maxlen, "/", "{default}/{green}", false);
}

int EnsureAnchorClient()
{
    int anchor = GetClientOfUserId(g_iAnchorUserId);
    if (anchor > 0 && anchor <= MaxClients && IsClientInGame(anchor) && IsFakeClient(anchor) && GetClientTeam(anchor) == 3)
    {
        return anchor;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || GetClientTeam(i) != 3)
        {
            continue;
        }

        char name[64];
        GetClientName(i, name, sizeof(name));
        if (StrEqual(name, ANCHOR_NAME))
        {
            g_iAnchorUserId = GetClientUserId(i);
            return i;
        }
    }

    int bot = CreateFakeClient(ANCHOR_NAME);
    if (bot <= 0 || !IsClientInGame(bot))
    {
        return 0;
    }

    ChangeClientTeam(bot, 3);
    g_iAnchorUserId = GetClientUserId(bot);

    return bot;
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}

bool IsTrackableVictim(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    int team = GetClientTeam(client);
    return (team == 2 || team == 3);
}

bool GetRecentFireAssist(int victimClient, int attackerClient, HazardType &type)
{
    type = Hazard_None;
    if (victimClient <= 0 || victimClient > MaxClients)
    {
        return false;
    }

    if (g_iLastFireAssistOwner[victimClient] != attackerClient)
    {
        return false;
    }

    if ((GetGameTime() - g_fLastFireAssistTime[victimClient]) > FIRE_ASSIST_STALE_WINDOW)
    {
        return false;
    }

    if (!g_bFireAssistLocked[victimClient])
    {
        return false;
    }

    type = view_as<HazardType>(g_iLastFireAssistType[victimClient]);
    return type != Hazard_None;
}

void AppendCauseToken(char[] cause, int maxlen, const char[] token)
{
    if (token[0] == '\0')
    {
        return;
    }

    if (cause[0] == '\0')
    {
        strcopy(cause, maxlen, token);
        return;
    }

    if (StrContains(cause, token, false) != -1)
    {
        return;
    }

    char merged[256];
    Format(merged, sizeof(merged), "%s/%s", cause, token);
    strcopy(cause, maxlen, merged);
}

bool TryResolveRecentSpecialBullet(int attackerClient, bool fireBullet, char[] baseWeapon, int maxlen, bool &hasBaseWeapon)
{
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return false;
    }

    float now = GetGameTime();
    float t = fireBullet ? g_fLastIncendiaryShot[attackerClient] : g_fLastExplosiveShot[attackerClient];
    if (t <= 0.0 || (now - t) > 6.0)
    {
        return false;
    }

    if (!hasBaseWeapon)
    {
        if (g_sLastSpecialBulletWeapon[attackerClient][0] != '\0')
        {
            strcopy(baseWeapon, maxlen, g_sLastSpecialBulletWeapon[attackerClient]);
            hasBaseWeapon = true;
        }
        else
        {
            int active = GetEntPropEnt(attackerClient, Prop_Send, "m_hActiveWeapon");
            if (IsValidEdict(active))
            {
                char cls[64];
                GetEntityClassname(active, cls, sizeof(cls));
                if (FormatWeaponName(cls, baseWeapon, maxlen))
                {
                    hasBaseWeapon = true;
                }
            }
        }
    }

    return hasBaseWeapon && IsBulletWeaponLabel(baseWeapon);
}

void BuildPrimaryCause(const char[] baseWeapon, bool bulletState, bool fireBullet, const char[] primary, char[] cause, int maxlen)
{
    cause[0] = '\0';

    if (bulletState && baseWeapon[0] != '\0')
    {
        strcopy(cause, maxlen, baseWeapon);
        AppendCauseToken(cause, maxlen, fireBullet ? "fire bullet" : "explosive bullet");
    }

    if (primary[0] != '\0')
    {
        AppendCauseToken(cause, maxlen, primary);
    }
}

bool ShouldUseBulletState(const char[] baseWeapon, const char[] eventWeapon, int attackerEnt)
{
    if (!IsBulletWeaponLabel(baseWeapon))
    {
        return false;
    }

    if (IsGrenadeLauncherContext(baseWeapon, eventWeapon, attackerEnt))
    {
        return false;
    }

    return true;
}

bool IsGrenadeLauncherContext(const char[] baseWeapon, const char[] eventWeapon, int attackerEnt)
{
    if (StrContains(baseWeapon, "Grenade Launcher", false) != -1)
    {
        return true;
    }

    if (StrContains(eventWeapon, "grenade_launcher", false) != -1 || StrContains(eventWeapon, "grenade launcher", false) != -1)
    {
        return true;
    }

    return EntityClassMatches(attackerEnt, "grenade_launcher_projectile");
}

bool IsBulletWeaponLabel(const char[] label)
{
    if (label[0] == '\0')
    {
        return false;
    }

    if (StrEqual(label, "molotov", false) || StrEqual(label, "pipebomb", false) || StrEqual(label, "gascan", false))
    {
        return false;
    }

    if (IsGenericFireLabel(label) || StrEqual(label, "fire", false) || StrEqual(label, "explosive", false))
    {
        return false;
    }

    if (StrContains(label, "Launcher", false) != -1 || StrContains(label, "Melee", false) != -1 || StrContains(label, "Chainsaw", false) != -1 || StrContains(label, "Knife", false) != -1)
    {
        return false;
    }

    return true;
}

bool IsClientDucking(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_bDucked") && GetEntProp(client, Prop_Send, "m_bDucked") != 0)
    {
        return true;
    }

    return (GetEntityFlags(client) & FL_DUCKING) != 0;
}

bool IsClientIncapped(int client)
{
    return (IsInGameClient(client) && HasEntProp(client, Prop_Send, "m_isIncapacitated") && GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0);
}

bool IsClientVomitBlind(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (!HasEntProp(client, Prop_Send, "m_vomitStart"))
    {
        return false;
    }

    float vomitStart = GetEntPropFloat(client, Prop_Send, "m_vomitStart");
    if (vomitStart <= 0.0)
    {
        return false;
    }

    return (GetGameTime() - vomitStart) <= 20.0;
}

bool IsSniperLikeRange(int attackerClient, int victimClient, const char[] eventWeapon, int dmgType)
{
    if (!IsInGameClient(attackerClient) || !IsInGameClient(victimClient))
    {
        return false;
    }

    if ((dmgType & DMG_BULLET) == 0 && StrContains(eventWeapon, "sniper", false) == -1 && StrContains(eventWeapon, "hunting_rifle", false) == -1)
    {
        return false;
    }

    float aPos[3];
    float vPos[3];
    GetClientEyePosition(attackerClient, aPos);
    GetClientEyePosition(victimClient, vPos);

    return GetVectorDistance(aPos, vPos) >= 1200.0;
}

bool IsVictimStaggeredByAttacker(int victimClient, int attackerClient)
{
    if (!IsInGameClient(victimClient) || !IsInGameClient(attackerClient))
    {
        return false;
    }

    if (GetClientTeam(victimClient) != 3 || GetClientTeam(attackerClient) != 2)
    {
        return false;
    }

    if (!IsClientCurrentlyStaggered(victimClient))
    {
        return false;
    }

    if (g_iLastStaggerBy[victimClient] != attackerClient)
    {
        return false;
    }

    return (GetGameTime() - g_fLastStaggerTime[victimClient]) <= STAGGER_MATCH_WINDOW;
}

bool IsClientCurrentlyStaggered(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_staggerTimer"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_staggerTimer") > 0.0;
    }

    if (HasEntProp(client, Prop_Send, "m_staggerDist"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_staggerDist") > 0.0;
    }

    if (HasEntProp(client, Prop_Send, "m_staggerStart"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_staggerStart") > 0.0;
    }

    return false;
}

bool IsClientAdrenalineActive(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_bAdrenalineActive"))
    {
        if (GetEntProp(client, Prop_Send, "m_bAdrenalineActive") != 0)
        {
            return true;
        }
    }

    if (HasEntProp(client, Prop_Send, "m_flAdrenalineTime"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_flAdrenalineTime") > GetGameTime();
    }

    return false;
}

bool IsClientCurrentlyOnFire(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_bIsBurning"))
    {
        return GetEntProp(client, Prop_Send, "m_bIsBurning") != 0;
    }

    if (HasEntProp(client, Prop_Send, "m_flFlameBurnTime"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_flFlameBurnTime") > GetGameTime();
    }

    if (HasEntProp(client, Prop_Send, "m_burnPercent"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_burnPercent") > 0.0;
    }

    if (HasEntProp(client, Prop_Data, "m_fFlags"))
    {
        return (GetEntProp(client, Prop_Data, "m_fFlags") & FL_ONFIRE) != 0;
    }

    return false;
}

bool IsInGameClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

public bool TraceFilter_IgnorePlayers(int entity, int contentsMask)
{
    return entity > MaxClients;
}

bool IsWallbangKill(int attacker, int victim)
{
    if (!IsInGameClient(attacker) || !IsInGameClient(victim))
    {
        return false;
    }

    float eyePos[3], victimPos[3], dir[3], eyeAng[3];
    GetClientEyePosition(attacker, eyePos);
    GetClientAbsOrigin(victim, victimPos);
    victimPos[2] += 36.0; // center mass

    SubtractVectors(victimPos, eyePos, dir);
    GetVectorAngles(dir, eyeAng);

    Handle trace = TR_TraceRayFilterEx(eyePos, eyeAng, MASK_SHOT, RayType_Infinite, TraceFilter_IgnorePlayers);

    bool hitWorld = false;
    if (TR_DidHit(trace))
    {
        float hitPos[3];
        TR_GetEndPosition(hitPos, trace);
        float distToHit    = GetVectorDistance(eyePos, hitPos);
        float distToVictim = GetVectorDistance(eyePos, victimPos);

        // Ray hit world trước victim và không quá gần attacker (tránh false positive)
        if (distToHit < distToVictim && distToHit > 20.0)
        {
            hitWorld = true;
        }
    }

    delete trace;
    return hitWorld;
}

bool IsEliteSI(int client)
{
    if (!g_bHasEliteNative || !IsInGameClient(client) || GetClientTeam(client) != 3)
    {
        return false;
    }

    return L4D2_IsEliteSI(client) != 0;
}

bool IsDualPistolContext(int victim, int attackerClient)
{
    if (IsDualPistolEntity(g_iLastWeapon[victim]))
    {
        return true;
    }

    if (IsInGameClient(attackerClient))
    {
        int active = GetEntPropEnt(attackerClient, Prop_Send, "m_hActiveWeapon");
        if (IsDualPistolEntity(active))
        {
            return true;
        }
    }

    return false;
}

bool IsDualPistolEntity(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (!StrEqual(cls, "weapon_pistol", false))
    {
        return false;
    }

    return GetEntProp(entity, Prop_Send, "m_isDualWielding") > 0;
}

bool HasRecentSnapshot(int victim)
{
    return (GetGameTime() - g_fLastDmgTime[victim]) <= SNAPSHOT_VALID_WINDOW;
}

void ResetSnapshot(int client)
{
    g_iLastAttacker[client] = 0;
    g_iLastInflictor[client] = 0;
    g_iLastWeapon[client] = 0;
    g_iLastDmgType[client] = 0;
    g_fLastDmgTime[client] = 0.0;
}

void ClearPendingIncap(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (g_hIncapTimer[client] != null)
    {
        delete g_hIncapTimer[client];
        g_hIncapTimer[client] = null;
    }

    g_bPendingIncap[client] = false;
    g_iPendingAttackerClient[client] = 0;
    g_iPendingAttackerEnt[client] = 0;
    g_iPendingDmgType[client] = 0;
    g_fPendingIncapTime[client] = 0.0;
    g_sPendingWeapon[client][0] = '\0';
}
