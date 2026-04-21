public Action Timer_DelayedEnsureAnchor(Handle timer)
{
    if (g_bEnable)
    {
        EnsureAnchorClient();
    }
    return Plugin_Stop;
}

public Action Timer_EnsureAnchor(Handle timer)
{
    if (g_bEnable)
    {
        EnsureAnchorClient();
    }
    return Plugin_Continue;
}

public Action Timer_BurnWatchUpdate(Handle timer)
{
    bool hasLockedVictim = false;
    float now = GetGameTime();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsTrackableVictim(client) || !g_bFireAssistLocked[client])
        {
            continue;
        }

        float lockAge = now - g_fLastFireAssistTime[client];
        if (lockAge > FIRE_ASSIST_STALE_WINDOW)
        {
            ClearFireAssistLock(client);
            continue;
        }

        if (lockAge <= FIRE_ASSIST_UNLOCK_GRACE)
        {
            hasLockedVictim = true;
            continue;
        }

        if (!IsClientCurrentlyOnFire(client))
        {
            ClearFireAssistLock(client);
            continue;
        }

        hasLockedVictim = true;
    }

    if (!hasLockedVictim)
    {
        g_hBurnWatchTimer = null;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

void ClearFireAssistLock(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bFireAssistLocked[client] = false;
    g_iLastFireAssistType[client] = view_as<int>(Hazard_None);
    g_iLastFireAssistOwner[client] = 0;
    g_fLastFireAssistTime[client] = 0.0;
}

void EnsureBurnWatchTimer()
{
    if (g_hBurnWatchTimer == null)
    {
        g_hBurnWatchTimer = CreateTimer(BURN_WATCH_INTERVAL, Timer_BurnWatchUpdate, _, TIMER_REPEAT);
    }
}

void StopBurnWatchTimerIfIdle()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        if (g_bFireAssistLocked[client] && IsTrackableVictim(client))
        {
            return;
        }
    }

    if (g_hBurnWatchTimer != null)
    {
        delete g_hBurnWatchTimer;
        g_hBurnWatchTimer = null;
    }
}

bool TryReadFreshFireSourceCache(int fireEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (fireEnt <= 0 || fireEnt >= MAX_TRACKED_EDICTS || !IsValidEdict(fireEnt))
    {
        return false;
    }

    if (!HasFreshFireSourceCache(fireEnt))
    {
        return false;
    }

    source = view_as<HazardType>(g_iFireEntSourceType[fireEnt]);
    sourceOwner = g_iFireEntOwner[fireEnt];
    return source != Hazard_None;
}

bool TryGetFireSourceMetaForDamage(int victim, int attackerEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (TryReadFreshFireSourceCache(attackerEnt, source, sourceOwner))
    {
        return true;
    }

    if (victim <= 0 || victim > MaxClients || !HasRecentSnapshot(victim))
    {
        return false;
    }

    int inflictor = g_iLastInflictor[victim];
    if (TryReadFreshFireSourceCache(inflictor, source, sourceOwner))
    {
        return true;
    }

    float victimPos[3];
    GetClientEyePosition(victim, victimPos);
    source = FindBestFireSource(victimPos, sourceOwner);
    return source != Hazard_None;
}

public Action Timer_HookExistingHazards(Handle timer)
{
    int maxEntities = GetMaxEntities();
    if (maxEntities > (MAX_TRACKED_EDICTS + 1))
    {
        maxEntities = MAX_TRACKED_EDICTS + 1;
    }

    for (int ent = MaxClients + 1; ent < maxEntities; ent++)
    {
        if (IsValidEdict(ent))
        {
            TryHookHazardEntity(ent);
        }
    }

    return Plugin_Stop;
}

public void Frame_DelayedHookHazard(any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0)
    {
        return;
    }

    TryHookHazardEntity(entity);
}

public void Frame_InitMolotovProjectile(any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || entity > MAX_TRACKED_EDICTS || !IsValidEdict(entity))
    {
        return;
    }

    g_iMolotovOwner[entity] = ResolveProjectileOwner(entity);
    GetEntityAbsPos(entity, g_vMolotovLastPos[entity]);
}

public void Frame_MarkFireEntitySource(any entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || entity > MAX_TRACKED_EDICTS || !IsValidEdict(entity))
    {
        return;
    }

    ResolveAndStoreFireEntitySource(entity, false);

    if (view_as<HazardType>(g_iFireEntSourceType[entity]) == Hazard_None && !g_bFireEntRecheckQueued[entity])
    {
        g_bFireEntRecheckQueued[entity] = true;
        CreateTimer(FIRE_ENTITY_RECHECK_DELAY, Timer_RecheckFireEntitySource, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_RecheckFireEntitySource(Handle timer, int entityRef)
{
    int entity = EntRefToEntIndex(entityRef);
    if (entity == INVALID_ENT_REFERENCE || entity <= 0 || entity > MAX_TRACKED_EDICTS || !IsValidEdict(entity))
    {
        return Plugin_Stop;
    }

    g_bFireEntRecheckQueued[entity] = false;
    ResolveAndStoreFireEntitySource(entity, true);
    return Plugin_Stop;
}

public void OnHazardTakeDamagePost(int entity, int attacker, int inflictor, float damage, int damagetype)
{
    if (damage <= 0.0)
    {
        return;
    }

    HazardType hazard = GetHazardType(entity);
    if (hazard == Hazard_None)
    {
        return;
    }

    int owner = ResolveDamageOwnerClient(attacker, inflictor);

    // Nếu không tìm được owner trực tiếp, thử resolve qua fire source cache
    // (trường hợp chain fire: inferno từ molotov/gascan cháy lan sang hazard khác)
    if (!IsInGameClient(owner) || GetClientTeam(owner) != 2)
    {
        // Check attacker là inferno/entityflame → lookup fire source cache để lấy owner gốc
        if (IsValidEdict(attacker) && attacker > MaxClients)
        {
            HazardType fireSource = Hazard_None;
            int fireOwner = 0;
            if (TryReadFreshFireSourceCache(attacker, fireSource, fireOwner)
                && IsInGameClient(fireOwner) && GetClientTeam(fireOwner) == 2)
            {
                owner = fireOwner;
            }
        }

        // Fallback: check inflictor
        if ((!IsInGameClient(owner) || GetClientTeam(owner) != 2)
            && IsValidEdict(inflictor) && inflictor > MaxClients)
        {
            HazardType fireSource = Hazard_None;
            int fireOwner = 0;
            if (TryReadFreshFireSourceCache(inflictor, fireSource, fireOwner)
                && IsInGameClient(fireOwner) && GetClientTeam(fireOwner) == 2)
            {
                owner = fireOwner;
            }
        }
    }

    if (!IsInGameClient(owner) || GetClientTeam(owner) != 2)
    {
        return;
    }

    float now = GetGameTime();
    float pos[3];
    GetEntityAbsPos(entity, pos);
    g_iHazardEntType[entity] = view_as<int>(hazard);
    g_iHazardLastOwner[entity] = owner;
    g_fHazardLastHitTime[entity] = now;
    g_vHazardLastPos[entity][0] = pos[0];
    g_vHazardLastPos[entity][1] = pos[1];
    g_vHazardLastPos[entity][2] = pos[2];

    AddSourceEvent(hazard, pos, owner);
    g_iLastHazardType[owner] = view_as<int>(hazard);
    g_fLastHazardTime[owner] = now;
    g_iLastHazardEntityRef[owner] = EntIndexToEntRef(entity);
}

public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!IsTrackableVictim(victim))
    {
        return Plugin_Continue;
    }

    float now = GetGameTime();
    g_iLastAttacker[victim] = attacker;
    g_iLastInflictor[victim] = inflictor;
    g_sLastInflictorTargetname[victim][0] = '\0';
    if (IsValidEdict(inflictor))
    {
        GetEntPropStringSafe(inflictor, Prop_Data, "m_iName", g_sLastInflictorTargetname[victim], sizeof(g_sLastInflictorTargetname[]));
    }
    g_iLastWeapon[victim] = weapon;
    g_iLastDmgType[victim] = damagetype;
    g_fLastDmgTime[victim] = now;

    // Survivor fire assist tracking
    if (GetClientTeam(victim) == 2 && (damagetype & DMG_BURN) != 0 && !g_bFireAssistLocked[victim])
    {
        HazardType fireType = Hazard_None;
        int fireOwner = 0;
        if (TryGetFireSourceMetaForDamage(victim, inflictor, fireType, fireOwner) && fireType != Hazard_None)
        {
            g_iLastFireAssistType[victim] = view_as<int>(fireType);
            g_iLastFireAssistOwner[victim] = fireOwner;
            g_fLastFireAssistTime[victim] = now;
            g_bFireAssistLocked[victim] = true;
            EnsureBurnWatchTimer();
        }
    }

    // SI/Tank fire source tracking — luôn update khi nhận DMG_BURN
    if (GetClientTeam(victim) == 3 && (damagetype & DMG_BURN) != 0)
    {
        HazardType fireType = Hazard_None;
        int fireOwner = 0;
        if (TryGetFireSourceMetaForDamage(victim, inflictor, fireType, fireOwner) && fireType != Hazard_None)
        {
            g_iSIFireSourceType[victim] = view_as<int>(fireType);
            g_iSIFireSourceOwner[victim] = fireOwner;
            g_fSIFireSourceTime[victim] = now;
            g_bSIWasOnFire[victim] = true;
        }
        else if (!g_bSIWasOnFire[victim])
        {
            // Lần cháy mới nhưng không resolve được source — clear snapshot cũ
            ClearSIFireSnapshot(victim);
            g_bSIWasOnFire[victim] = true;
        }
    }

    // SI/Tank hết cháy — clear snapshot để lần cháy tiếp theo resolve lại
    if (GetClientTeam(victim) == 3 && (damagetype & DMG_BURN) == 0 && g_bSIWasOnFire[victim])
    {
        if (!IsClientCurrentlyOnFire(victim))
        {
            ClearSIFireSnapshot(victim);
        }
    }

    return Plugin_Continue;
}

void ClearSIFireSnapshot(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_iSIFireSourceType[client] = view_as<int>(Hazard_None);
    g_iSIFireSourceOwner[client] = 0;
    g_fSIFireSourceTime[client] = 0.0;
    g_bSIWasOnFire[client] = false;
}

bool GetSIFireSnapshot(int victim, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (victim <= 0 || victim > MaxClients)
    {
        return false;
    }

    if (view_as<HazardType>(g_iSIFireSourceType[victim]) == Hazard_None)
    {
        return false;
    }

    // Snapshot còn fresh trong 30s (SI/Tank có thể cháy lâu)
    if ((GetGameTime() - g_fSIFireSourceTime[victim]) > 30.0)
    {
        return false;
    }

    source = view_as<HazardType>(g_iSIFireSourceType[victim]);
    sourceOwner = g_iSIFireSourceOwner[victim];
    return true;
}
