bool EntityClassMatches(int entity, const char[] needle)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    return StrContains(cls, needle, false) != -1;
}

void TryHookHazardEntity(int entity)
{
    if (entity <= MaxClients || entity >= MAX_TRACKED_EDICTS || !IsValidEdict(entity))
    {
        return;
    }

    if (g_bHazardHooked[entity])
    {
        return;
    }

    HazardType hazard = GetHazardType(entity);
    if (hazard == Hazard_None)
    {
        return;
    }

    g_iHazardEntType[entity] = view_as<int>(hazard);
    SDKHook(entity, SDKHook_OnTakeDamagePost, OnHazardTakeDamagePost);
    g_bHazardHooked[entity] = true;
}

bool ClassnameLooksHazard(const char[] classname)
{
    return (
        StrContains(classname, "gascan", false) != -1 ||
        StrContains(classname, "firework", false) != -1 ||
        StrContains(classname, "fire_cracker", false) != -1 ||
        StrContains(classname, "fuel_barrel", false) != -1 ||
        StrContains(classname, "propan", false) != -1 ||
        StrContains(classname, "oxygen", false) != -1
    );
}

HazardType GetHazardType(int entity)
{
    if (EntityIsGascan(entity)) return Hazard_Gascan;
    if (EntityIsFireworkCrate(entity)) return Hazard_Firework;
    if (EntityIsFuelBarrel(entity)) return Hazard_FuelBarrel;
    if (EntityIsPropaneTank(entity)) return Hazard_PropaneTank;
    if (EntityIsOxygenTank(entity)) return Hazard_OxygenTank;
    return Hazard_None;
}

int ResolveDamageOwnerClient(int attacker, int inflictor)
{
    if (IsInGameClient(attacker) && GetClientTeam(attacker) == 2) return attacker;
    if (IsInGameClient(inflictor) && GetClientTeam(inflictor) == 2) return inflictor;

    int owner = GetLinkedEntity(inflictor, "m_hOwnerEntity");
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2) return owner;

    owner = GetLinkedEntity(attacker, "m_hOwnerEntity");
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2) return owner;

    return 0;
}

void AddSourceEvent(HazardType type, const float pos[3], int owner)
{
    if (type == Hazard_None)
    {
        return;
    }

    int idx = g_iSourceWrite;
    float now = GetGameTime();
    g_iSourceType[idx] = view_as<int>(type);
    g_iSourceOwner[idx] = owner;
    g_fSourceTime[idx] = now;
    g_vSourcePos[idx][0] = pos[0];
    g_vSourcePos[idx][1] = pos[1];
    g_vSourcePos[idx][2] = pos[2];
    g_iSourceWrite = (g_iSourceWrite + 1) % MAX_SOURCE_EVENTS;

    if (IsInGameClient(owner) && GetClientTeam(owner) == 2 && type != Hazard_Molotov)
    {
        g_iLastHazardType[owner] = view_as<int>(type);
        g_fLastHazardTime[owner] = now;
    }
}

HazardType FindBestFireSource(const float firePos[3], int &owner)
{
    float now = GetGameTime();
    float bestScore = 999999.0;
    HazardType bestType = Hazard_None;
    int bestOwner = 0;

    for (int i = 0; i < MAX_SOURCE_EVENTS; i++)
    {
        HazardType type = view_as<HazardType>(g_iSourceType[i]);
        if (type == Hazard_None)
        {
            continue;
        }

        float age = now - g_fSourceTime[i];
        if (age < 0.0 || age > FIRE_SOURCE_MATCH_WINDOW)
        {
            continue;
        }

        float dist = GetVectorDistance(firePos, g_vSourcePos[i]);
        if (dist > FIRE_SOURCE_MAX_DIST)
        {
            continue;
        }

        float score = dist + (age * 90.0);
        if (score < bestScore)
        {
            bestScore = score;
            bestType = type;
            bestOwner = g_iSourceOwner[i];
        }
    }

    owner = bestOwner;
    return bestType;
}

bool HasFreshFireSourceCache(int fireEnt)
{
    if (fireEnt <= 0 || fireEnt >= MAX_TRACKED_EDICTS || !IsValidEdict(fireEnt))
    {
        return false;
    }

    if (view_as<HazardType>(g_iFireEntSourceType[fireEnt]) == Hazard_None)
    {
        return false;
    }

    float age = GetGameTime() - g_fFireEntMarkTime[fireEnt];
    return (age >= 0.0 && age <= FIRE_SOURCE_CACHE_WINDOW);
}

void AddLinkedEntityCandidate(int fromEnt, const char[] prop, int queue[FIRE_ENTITY_LINK_SCAN_MAX], int &count)
{
    if (count >= FIRE_ENTITY_LINK_SCAN_MAX)
    {
        return;
    }

    int linked = GetLinkedEntity(fromEnt, prop);
    if (!IsValidEdict(linked) || linked <= MaxClients)
    {
        return;
    }

    for (int i = 0; i < count; i++)
    {
        if (queue[i] == linked)
        {
            return;
        }
    }

    queue[count++] = linked;
}

int ResolveSourceOwnerFromEntity(int sourceEnt, int fireEnt)
{
    int owner = ResolveDamageOwnerClient(GetLinkedEntity(sourceEnt, "m_hOwnerEntity"), GetLinkedEntity(sourceEnt, "m_hPhysicsAttacker"));
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2) return owner;

    owner = ResolveProjectileOwner(sourceEnt);
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2) return owner;

    owner = ResolveDamageOwnerClient(GetLinkedEntity(fireEnt, "m_hOwnerEntity"), GetLinkedEntity(fireEnt, "m_hInflictor"));
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2) return owner;

    owner = ResolveProjectileOwner(fireEnt);
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2) return owner;

    return 0;
}

bool ResolveFireSourceDeterministic(int fireEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (!IsValidEdict(fireEnt))
    {
        return false;
    }

    int queue[FIRE_ENTITY_LINK_SCAN_MAX];
    int count = 0;
    int index = 0;
    queue[count++] = fireEnt;

    while (index < count && count <= FIRE_ENTITY_LINK_SCAN_MAX)
    {
        int ent = queue[index++];
        if (!IsValidEdict(ent))
        {
            continue;
        }

        HazardType hazard = GetHazardType(ent);
        if (hazard != Hazard_None)
        {
            source = hazard;
            sourceOwner = ResolveSourceOwnerFromEntity(ent, fireEnt);
            return true;
        }

        if (EntityIsMolotovProjectile(ent))
        {
            source = Hazard_Molotov;
            sourceOwner = ResolveSourceOwnerFromEntity(ent, fireEnt);
            return true;
        }

        AddLinkedEntityCandidate(ent, "m_hOwnerEntity", queue, count);
        AddLinkedEntityCandidate(ent, "m_hMoveParent", queue, count);
        AddLinkedEntityCandidate(ent, "m_hEffectEntity", queue, count);
        AddLinkedEntityCandidate(ent, "m_hInflictor", queue, count);
        AddLinkedEntityCandidate(ent, "m_hPhysicsAttacker", queue, count);
        AddLinkedEntityCandidate(ent, "m_hThrower", queue, count);
    }

    return false;
}

bool ResolveFireSourceHeuristic(int fireEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (!IsValidEdict(fireEnt))
    {
        return false;
    }

    float origin[3];
    GetEntityAbsPos(fireEnt, origin);

    // 1. Source event ring buffer (existing)
    source = FindBestFireSource(origin, sourceOwner);
    if (source != Hazard_None)
    {
        return true;
    }

    // 2. Molotov destroy ring buffer — deterministic hơn WasRecentMolotovThrow
    int mdOwner = 0;
    if (FindRecentMolotovDestroy(origin, MOLOTOV_DESTROY_MATCH_WINDOW, MOLOTOV_DESTROY_MAX_DIST, mdOwner))
    {
        source = Hazard_Molotov;
        sourceOwner = mdOwner;
        return true;
    }

    // 3. Gascan explode ring buffer
    int geOwner = 0;
    if (FindRecentGascanExplode(origin, GASCAN_EXPLODE_MATCH_WINDOW, GASCAN_EXPLODE_MAX_DIST, geOwner))
    {
        source = Hazard_Gascan;
        sourceOwner = geOwner;
        return true;
    }

    // 4. Fallback: projectile owner + WasRecentMolotovThrow
    int owner = ResolveProjectileOwner(fireEnt);
    if (WasRecentMolotovThrow(owner, 20.0))
    {
        source = Hazard_Molotov;
        sourceOwner = owner;
        return true;
    }

    return false;
}

void ResolveAndStoreFireEntitySource(int fireEnt, bool isRecheck)
{
    if (fireEnt <= 0 || fireEnt >= MAX_TRACKED_EDICTS || !IsValidEdict(fireEnt))
    {
        return;
    }

    FireSourceConfidence oldConfidence = view_as<FireSourceConfidence>(g_iFireEntSourceConfidence[fireEnt]);
    bool oldFresh = HasFreshFireSourceCache(fireEnt);

    HazardType source = Hazard_None;
    int sourceOwner = 0;
    FireSourceConfidence confidence = FireSourceConfidence_None;

    if (ResolveFireSourceDeterministic(fireEnt, source, sourceOwner))
    {
        confidence = FireSourceConfidence_Deterministic;
    }
    else if (ResolveFireSourceHeuristic(fireEnt, source, sourceOwner))
    {
        confidence = FireSourceConfidence_Heuristic;
    }

    if (oldFresh && oldConfidence == FireSourceConfidence_Deterministic && confidence != FireSourceConfidence_Deterministic)
    {
        if (isRecheck)
        {
            g_fFireEntMarkTime[fireEnt] = GetGameTime();
        }
        return;
    }

    g_iFireEntSourceType[fireEnt] = view_as<int>(source);
    g_iFireEntOwner[fireEnt] = sourceOwner;
    g_iFireEntSourceConfidence[fireEnt] = view_as<int>(confidence);
    g_fFireEntMarkTime[fireEnt] = GetGameTime();
}

bool TryResolveFireSourceFromEntity(int fireEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (fireEnt <= 0 || fireEnt >= MAX_TRACKED_EDICTS || !IsValidEdict(fireEnt))
    {
        return false;
    }

    if (!HasFreshFireSourceCache(fireEnt))
    {
        ResolveAndStoreFireEntitySource(fireEnt, false);
    }

    source = view_as<HazardType>(g_iFireEntSourceType[fireEnt]);
    sourceOwner = g_iFireEntOwner[fireEnt];
    return source != Hazard_None;
}

bool TryCauseFromFireEntitySource(int victim, int attackerEnt, char[] cause, int maxlen)
{
    HazardType source = Hazard_None;
    int sourceOwner = 0;
    if (!GetFireSourceMeta(victim, attackerEnt, source, sourceOwner) || source == Hazard_None)
    {
        return false;
    }

    if (!HazardTypeToLabel(source, cause, maxlen))
    {
        return false;
    }

    if (source == Hazard_Gascan && !HasExplicitGascanEvidence(victim, attackerEnt) && HasExplicitMolotovEvidence(victim, attackerEnt, sourceOwner))
    {
        strcopy(cause, maxlen, "molotov");
    }

    return true;
}

bool HasExplicitGascanEvidence(int victim, int attackerEnt)
{
    if (EntityIsGascan(attackerEnt) || LinkedEntityIsGascan(attackerEnt))
    {
        return true;
    }

    HazardType linkedType = Hazard_None;
    int linkedOwner = 0;
    if (TryInferHazardFromLinkedFireEntity(attackerEnt, linkedType, linkedOwner) && linkedType == Hazard_Gascan)
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    int snapInflictor = g_iLastInflictor[victim];
    int snapWeapon = g_iLastWeapon[victim];
    if (EntityIsGascan(snapInflictor) || LinkedEntityIsGascan(snapInflictor) || EntityIsGascan(snapWeapon) || LinkedEntityIsGascan(snapWeapon))
    {
        return true;
    }

    linkedType = Hazard_None;
    linkedOwner = 0;
    if (TryInferHazardFromLinkedFireEntity(snapInflictor, linkedType, linkedOwner) && linkedType == Hazard_Gascan)
    {
        return true;
    }

    return false;
}

bool HasExplicitMolotovEvidence(int victim, int attackerEnt, int sourceOwner)
{
    if (EntityIsMolotovProjectile(attackerEnt) || LinkedEntityIsMolotovProjectile(attackerEnt))
    {
        return true;
    }

    if (HasRecentSnapshot(victim))
    {
        int snapInflictor = g_iLastInflictor[victim];
        int snapWeapon = g_iLastWeapon[victim];
        if (EntityIsMolotovProjectile(snapInflictor) || LinkedEntityIsMolotovProjectile(snapInflictor)
            || EntityIsMolotovProjectile(snapWeapon) || LinkedEntityIsMolotovProjectile(snapWeapon))
        {
            return true;
        }
    }

    // WasRecentMolotovThrow với distance check — thu hẹp window 3.0 → 2.0s
    if (IsInGameClient(sourceOwner) && GetClientTeam(sourceOwner) == 2)
    {
        float t = g_fLastMolotovThrow[sourceOwner];
        if (t > 0.0 && (GetGameTime() - t) <= 2.0)
        {
            float firePos[3];
            GetEntityAbsPos(attackerEnt, firePos);
            if (firePos[0] != 0.0 || firePos[1] != 0.0 || firePos[2] != 0.0)
            {
                int mdOwner = 0;
                return FindRecentMolotovDestroy(firePos, MOLOTOV_DESTROY_MATCH_WINDOW, MOLOTOV_DESTROY_MAX_DIST, mdOwner);
            }
            return true; // không có fire pos → fallback cũ
        }
    }

    return false;
}

bool GetFireSourceMeta(int victim, int attackerEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (TryResolveFireSourceFromEntity(attackerEnt, source, sourceOwner))
    {
        return true;
    }

    if (victim > 0 && victim <= MaxClients && HasRecentSnapshot(victim))
    {
        int inflictor = g_iLastInflictor[victim];
        if (TryResolveFireSourceFromEntity(inflictor, source, sourceOwner))
        {
            return true;
        }

        TryInferHazardFromLinkedFireEntity(inflictor, source, sourceOwner);
        if (source != Hazard_None)
        {
            return true;
        }
    }

    if (victim > 0 && victim <= MaxClients && HasRecentSnapshot(victim))
    {
        float victimPos[3];
        GetClientEyePosition(victim, victimPos);
        source = FindBestFireSource(victimPos, sourceOwner);
        if (source != Hazard_None)
        {
            return true;
        }
    }

    return false;
}

bool TryInferHazardFromLinkedFireEntity(int fireEnt, HazardType &source, int &sourceOwner)
{
    return ResolveFireSourceDeterministic(fireEnt, source, sourceOwner);
}

bool HazardTypeToLabel(HazardType type, char[] outLabel, int maxlen)
{
    switch (type)
    {
        case Hazard_Molotov: strcopy(outLabel, maxlen, "molotov");
        case Hazard_Gascan: strcopy(outLabel, maxlen, "gascan");
        case Hazard_Firework: strcopy(outLabel, maxlen, "firework crate");
        case Hazard_FuelBarrel: strcopy(outLabel, maxlen, "fuel barrel");
        case Hazard_PropaneTank: strcopy(outLabel, maxlen, "propane tank");
        case Hazard_OxygenTank: strcopy(outLabel, maxlen, "oxygen tank");
        default: return false;
    }
    return true;
}

int ResolveProjectileOwner(int entity)
{
    int owner = GetLinkedEntity(entity, "m_hThrower");
    if (IsInGameClient(owner)) return owner;
    owner = GetLinkedEntity(entity, "m_hOwnerEntity");
    if (IsInGameClient(owner)) return owner;
    return 0;
}

void GetEntityAbsPos(int entity, float outPos[3])
{
    outPos[0] = 0.0;
    outPos[1] = 0.0;
    outPos[2] = 0.0;
    if (!IsValidEdict(entity))
    {
        return;
    }
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", outPos);
}

bool TryCauseFromHazardContext(int attackerClient, char[] cause, int maxlen)
{
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return false;
    }

    float t = g_fLastHazardTime[attackerClient];
    if (t <= 0.0 || (GetGameTime() - t) > HAZARD_CONTEXT_WINDOW)
    {
        return false;
    }

    switch (view_as<HazardType>(g_iLastHazardType[attackerClient]))
    {
        case Hazard_Gascan: { strcopy(cause, maxlen, "gascan"); return true; }
        case Hazard_Firework: { strcopy(cause, maxlen, "firework crate"); return true; }
        case Hazard_FuelBarrel: { strcopy(cause, maxlen, "fuel barrel"); return true; }
        case Hazard_PropaneTank: { strcopy(cause, maxlen, "propane tank"); return true; }
        case Hazard_OxygenTank: { strcopy(cause, maxlen, "oxygen tank"); return true; }
    }

    return false;
}

bool EntityIsGascan(int entity)
{
    if (!IsValidEdict(entity)) return false;
    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "gascan", false) != -1) return true;

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "gascan", false) != -1) return true;
    }
    return false;
}

bool EntityIsMolotovProjectile(int entity)
{
    if (!IsValidEdict(entity)) return false;
    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    return StrContains(cls, "molotov", false) != -1;
}

bool LinkedEntityIsGascan(int entity)
{
    if (!IsValidEdict(entity)) return false;
    int owner = GetLinkedEntity(entity, "m_hOwnerEntity");
    if (EntityIsGascan(owner)) return true;
    int parent = GetLinkedEntity(entity, "m_hMoveParent");
    if (EntityIsGascan(parent)) return true;
    int effect = GetLinkedEntity(entity, "m_hEffectEntity");
    if (EntityIsGascan(effect)) return true;
    return false;
}

bool LinkedEntityIsMolotovProjectile(int entity)
{
    if (!IsValidEdict(entity)) return false;
    int owner = GetLinkedEntity(entity, "m_hOwnerEntity");
    if (EntityIsMolotovProjectile(owner)) return true;
    int parent = GetLinkedEntity(entity, "m_hMoveParent");
    if (EntityIsMolotovProjectile(parent)) return true;
    int effect = GetLinkedEntity(entity, "m_hEffectEntity");
    if (EntityIsMolotovProjectile(effect)) return true;
    int inflictor = GetLinkedEntity(entity, "m_hInflictor");
    if (EntityIsMolotovProjectile(inflictor)) return true;
    return false;
}

bool EntityIsFireworkCrate(int entity)
{
    if (!IsValidEdict(entity)) return false;
    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "firework", false) != -1 || StrContains(cls, "fire_cracker", false) != -1) return true;

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "firework", false) != -1 || StrContains(model, "fire_cracker", false) != -1) return true;
    }
    return false;
}

bool EntityIsFuelBarrel(int entity)
{
    if (!IsValidEdict(entity)) return false;
    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "fuel_barrel", false) != -1) return true;

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "fuel_barrel", false) != -1) return true;
    }
    return false;
}

bool EntityIsPropaneTank(int entity)
{
    if (!IsValidEdict(entity)) return false;
    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "propan", false) != -1) return true;

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "propanecanister", false) != -1 || StrContains(model, "propanetank", false) != -1) return true;
    }
    return false;
}

bool EntityIsOxygenTank(int entity)
{
    if (!IsValidEdict(entity)) return false;
    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "oxygen", false) != -1 || StrContains(cls, "oxygentank", false) != -1) return true;

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "oxygentank", false) != -1) return true;
    }
    return false;
}

bool FindRecentHeroicPipeExplosion(const float pos[3], float window, float maxDist, int &owner)
{
    float now = GetGameTime();
    float bestScore = 999999.0;
    owner = 0;
    bool found = false;

    for (int i = 0; i < MAX_RECENT_HEROIC_PIPES; i++)
    {
        if (g_fHeroicPipeTime[i] <= 0.0) continue;
        float age = now - g_fHeroicPipeTime[i];
        if (age < 0.0 || age > window) continue;
        float dist = GetVectorDistance(pos, g_vHeroicPipePos[i]);
        if (dist > maxDist) continue;
        float score = dist + age * 60.0;
        if (score < bestScore)
        {
            bestScore = score;
            owner = g_iHeroicPipeOwner[i];
            found = true;
        }
    }
    return found;
}

bool FindRecentGascanExplode(const float pos[3], float window, float maxDist, int &owner)
{
    float now = GetGameTime();
    float bestScore = 999999.0;
    owner = 0;
    bool found = false;

    for (int i = 0; i < MAX_RECENT_GASCAN_EXPLODES; i++)
    {
        if (g_fGascanExplodeTime[i] <= 0.0) continue;
        float age = now - g_fGascanExplodeTime[i];
        if (age < 0.0 || age > window) continue;
        float dist = GetVectorDistance(pos, g_vGascanExplodePos[i]);
        if (dist > maxDist) continue;
        float score = dist + age * 60.0;
        if (score < bestScore)
        {
            bestScore = score;
            owner = g_iGascanExplodeOwner[i];
            found = true;
        }
    }
    return found;
}

bool FindRecentMolotovDestroy(const float pos[3], float window, float maxDist, int &owner)
{
    float now = GetGameTime();
    float bestScore = 999999.0;
    owner = 0;
    bool found = false;

    for (int i = 0; i < MAX_RECENT_MOLOTOV_DESTROYS; i++)
    {
        if (g_fMolotovDestroyTime[i] <= 0.0) continue;
        float age = now - g_fMolotovDestroyTime[i];
        if (age < 0.0 || age > window) continue;
        float dist = GetVectorDistance(pos, g_vMolotovDestroyPos[i]);
        if (dist > maxDist) continue;
        float score = dist + age * 60.0;
        if (score < bestScore)
        {
            bestScore = score;
            owner = g_iMolotovDestroyOwner[i];
            found = true;
        }
    }
    return found;
}

bool IsGenericFireLabel(const char[] label)
{
    return (StrEqual(label, "Inferno", false) || StrEqual(label, "Entityflame", false) || StrEqual(label, "Fire", false));
}

bool WasRecentMolotovThrow(int client, float window)
{
    if (!IsInGameClient(client) || GetClientTeam(client) != 2) return false;
    float t = g_fLastMolotovThrow[client];
    if (t <= 0.0) return false;
    return (GetGameTime() - t) <= window;
}

bool IsLikelyGascanInferno(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon)
{
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return false;
    }

    bool infernoLike = (StrContains(eventWeapon, "inferno", false) != -1
        || StrContains(eventWeapon, "entityflame", false) != -1
        || EntityClassMatches(attackerEnt, "inferno")
        || EntityClassMatches(attackerEnt, "entityflame"));
    if (!infernoLike) return false;

    if (IsFireworkSource(victim, attackerEnt, eventWeapon)
        || IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
        return false;

    // Positive evidence: phải có gascan nổ gần vị trí fire
    float firePos[3];
    GetEntityAbsPos(attackerEnt, firePos);
    if (firePos[0] == 0.0 && firePos[1] == 0.0 && firePos[2] == 0.0)
        GetClientEyePosition(victim, firePos);

    int gascanOwner = 0;
    if (!FindRecentGascanExplode(firePos, GASCAN_EXPLODE_MATCH_WINDOW, GASCAN_EXPLODE_MAX_DIST, gascanOwner))
        return false;

    // Có gascan evidence — nhưng nếu molotov destroy còn gần hơn thì không đủ tự tin
    int molotovOwner = 0;
    if (FindRecentMolotovDestroy(firePos, MOLOTOV_DESTROY_MATCH_WINDOW, MOLOTOV_DESTROY_MAX_DIST, molotovOwner))
        return false;

    return true;
}

void GetCleanClientName(int client, char[] outName, int maxlen)
{
    GetClientName(client, outName, maxlen);
    TrimString(outName);

    if (outName[0] != '(') return;
    int close = FindCharInString(outName, ')');
    if (close <= 1 || close >= strlen(outName) - 1) return;

    bool allDigits = true;
    for (int i = 1; i < close; i++)
    {
        if (!IsCharNumeric(outName[i]))
        {
            allDigits = false;
            break;
        }
    }
    if (!allDigits) return;

    int start = close + 1;
    while (start < strlen(outName) && outName[start] == ' ')
    {
        start++;
    }
    if (start < strlen(outName))
    {
        strcopy(outName, maxlen, outName[start]);
    }

    RemoveNameNumberTags(outName, maxlen);
    ReplaceString(outName, maxlen, " BOT", "", false);
    ReplaceString(outName, maxlen, " Bot", "", false);

    if (IsInGameClient(client) && IsFakeClient(client) && GetClientTeam(client) == 2)
    {
        if (StrContains(outName, " BOT", false) == -1)
        {
            Format(outName, maxlen, "%s BOT", outName);
        }
    }
}

void RemoveNameNumberTags(char[] text, int maxlen)
{
    char tag[8];
    for (int i = 1; i <= 64; i++)
    {
        Format(tag, sizeof(tag), "(%d)", i);
        ReplaceString(text, maxlen, tag, "", false);
    }
    TrimString(text);
}

bool GetEntPropStringSafe(int entity, PropType type, const char[] prop, char[] buffer, int maxlen)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    buffer[0] = '\0';
    GetEntPropString(entity, type, prop, buffer, maxlen);
    return true;
}

int GetLinkedEntity(int entity, const char[] prop)
{
    if (!IsValidEdict(entity))
    {
        return -1;
    }

    if (HasEntProp(entity, Prop_Data, prop)) return GetEntPropEnt(entity, Prop_Data, prop);
    if (HasEntProp(entity, Prop_Send, prop)) return GetEntPropEnt(entity, Prop_Send, prop);
    return -1;
}

void ToLowerCase(char[] text)
{
    int len = strlen(text);
    for (int i = 0; i < len; i++)
    {
        text[i] = CharToLower(text[i]);
    }
}

void TitleCase(char[] text, int maxlen)
{
    bool newWord = true;
    int len = strlen(text);

    for (int i = 0; i < len && i < maxlen; i++)
    {
        if (text[i] == ' ')
        {
            newWord = true;
            continue;
        }

        if (newWord)
        {
            text[i] = CharToUpper(text[i]);
            newWord = false;
        }
    }
}
