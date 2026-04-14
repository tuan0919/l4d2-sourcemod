public Action Timer_DelayedEnsureAnchor(Handle timer)
{
    if (g_bEnable)
    {
        EnsureAnchorClient();
    }
    return Plugin_Stop;
}

public Action Timer_ConsolidatedUpdate(Handle timer)
{
    if (!g_bEnable)
    {
        return Plugin_Continue;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsTrackableVictim(client))
        {
            continue;
        }

        if (!g_bFireAssistLocked[client])
        {
            continue;
        }

        float lockAge = GetGameTime() - g_fLastFireAssistTime[client];
        if (lockAge > FIRE_ASSIST_STALE_WINDOW)
        {
            g_bFireAssistLocked[client] = false;
            g_iLastFireAssistType[client] = view_as<int>(Hazard_None);
            g_iLastFireAssistOwner[client] = 0;
            g_fLastFireAssistTime[client] = 0.0;
            continue;
        }

        if (lockAge <= FIRE_ASSIST_UNLOCK_GRACE)
        {
            continue;
        }

        if (!IsClientCurrentlyOnFire(client))
        {
            g_bFireAssistLocked[client] = false;
            g_iLastFireAssistType[client] = view_as<int>(Hazard_None);
            g_iLastFireAssistOwner[client] = 0;
            g_fLastFireAssistTime[client] = 0.0;
        }
    }

    static int anchorTick = 0;
    anchorTick++;

    if (anchorTick >= 5)
    {
        anchorTick = 0;
        EnsureAnchorClient();
    }

    return Plugin_Continue;
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

    float origin[3];
    GetEntityAbsPos(entity, origin);

    int sourceOwner = 0;
    HazardType source = FindBestFireSource(origin, sourceOwner);
    if (source == Hazard_None)
    {
        if (TryInferHazardFromLinkedFireEntity(entity, source, sourceOwner))
        {
            // linked-entity inference found direct source (gascan/fuel/...)
        }
    }

    if (source == Hazard_None)
    {
        int owner = ResolveProjectileOwner(entity);
        if (WasRecentMolotovThrow(owner, 20.0))
        {
            source = Hazard_Molotov;
            sourceOwner = owner;
        }
    }

    g_iFireEntSourceType[entity] = view_as<int>(source);
    g_iFireEntOwner[entity] = sourceOwner;
    g_fFireEntMarkTime[entity] = GetGameTime();
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
    if (!IsInGameClient(owner) || GetClientTeam(owner) != 2)
    {
        return;
    }

    float pos[3];
    GetEntityAbsPos(entity, pos);
    g_iHazardEntType[entity] = view_as<int>(hazard);
    g_iHazardLastOwner[entity] = owner;
    g_fHazardLastHitTime[entity] = GetGameTime();
    g_vHazardLastPos[entity][0] = pos[0];
    g_vHazardLastPos[entity][1] = pos[1];
    g_vHazardLastPos[entity][2] = pos[2];

    AddSourceEvent(hazard, pos, owner);
    g_iLastHazardType[owner] = view_as<int>(hazard);
    g_fLastHazardTime[owner] = GetGameTime();
    g_iLastHazardEntityRef[owner] = EntIndexToEntRef(entity);
}

public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!IsTrackableVictim(victim))
    {
        return Plugin_Continue;
    }

    g_iLastAttacker[victim] = attacker;
    g_iLastInflictor[victim] = inflictor;
    g_iLastWeapon[victim] = weapon;
    g_iLastDmgType[victim] = damagetype;
    g_fLastDmgTime[victim] = GetGameTime();

    if ((damagetype & DMG_BURN) != 0)
    {
        HazardType fireType = Hazard_None;
        int fireOwner = 0;
        if (!g_bFireAssistLocked[victim] && GetFireSourceMeta(victim, inflictor, fireType, fireOwner) && fireType != Hazard_None)
        {
            g_iLastFireAssistType[victim] = view_as<int>(fireType);
            g_iLastFireAssistOwner[victim] = fireOwner;
            g_fLastFireAssistTime[victim] = GetGameTime();
            g_bFireAssistLocked[victim] = true;
        }
    }

    return Plugin_Continue;
}
