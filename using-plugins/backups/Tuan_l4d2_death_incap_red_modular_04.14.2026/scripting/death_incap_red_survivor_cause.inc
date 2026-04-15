
bool ResolveSurvivorCause(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, char[] cause, int maxlen)
{
    char baseWeapon[64];
    bool hasBaseWeapon = GetBestWeaponLabel(victim, eventWeapon, baseWeapon, sizeof(baseWeapon));
    if (!hasBaseWeapon && GetClientActiveWeaponLabel(attackerClient, baseWeapon, sizeof(baseWeapon)))
    {
        hasBaseWeapon = true;
    }

    if (hasBaseWeapon && StrEqual(baseWeapon, "Pistol", false) && IsDualPistolContext(victim, attackerClient))
    {
        strcopy(baseWeapon, sizeof(baseWeapon), "Dual Pistols");
    }

    bool fire = IsFireCause(eventWeapon, dmgType) || IsFireFromEntities(victim, attackerEnt);
    bool explosive = IsExplosiveCause(eventWeapon, dmgType) || IsExplosiveFromEntities(victim, attackerEnt);
    bool bulletFireState = (hasBaseWeapon && ShouldUseBulletState(baseWeapon, eventWeapon, attackerEnt));
    bool bulletExplosiveState = (hasBaseWeapon && ShouldUseBulletState(baseWeapon, eventWeapon, attackerEnt));

    if (fire)
    {
        char primary[64];
        if (TryCauseFromFireEntitySource(victim, attackerEnt, cause, maxlen))
        {
            strcopy(primary, sizeof(primary), cause);
            BuildPrimaryCause(baseWeapon, bulletFireState, true, primary, cause, maxlen);
            return true;
        }
        if (IsGascanSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "gascan", cause, maxlen);
            return true;
        }
        if (IsFireworkSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "firework crate", cause, maxlen);
            return true;
        }
        if (IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "fuel barrel", cause, maxlen);
            return true;
        }
        if (IsMolotovSource(victim, attackerClient, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "molotov", cause, maxlen);
            return true;
        }
        if (TryCauseFromHazardContext(attackerClient, cause, maxlen))
        {
            strcopy(primary, sizeof(primary), cause);
            BuildPrimaryCause(baseWeapon, bulletFireState, true, primary, cause, maxlen);
            return true;
        }
        if (IsLikelyGascanInferno(victim, attackerClient, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "gascan", cause, maxlen);
            return true;
        }
        if (hasBaseWeapon && IsGenericFireLabel(baseWeapon))
        {
            strcopy(cause, maxlen, "fire");
            return true;
        }
        if (bulletFireState)
        {
            BuildPrimaryCause(baseWeapon, true, true, "", cause, maxlen);
            return true;
        }
        if (TryResolveRecentSpecialBullet(attackerClient, true, baseWeapon, sizeof(baseWeapon), hasBaseWeapon))
        {
            BuildPrimaryCause(baseWeapon, true, true, "", cause, maxlen);
            return true;
        }
        if (hasBaseWeapon)
        {
            strcopy(cause, maxlen, baseWeapon);
            return true;
        }

        strcopy(cause, maxlen, "fire");
        return true;
    }

    if (explosive)
    {
        char primary[64];
        if (IsPipeBombSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "pipebomb", cause, maxlen);
            return true;
        }
        if (IsFireworkSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "firework crate", cause, maxlen);
            return true;
        }
        if (IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "fuel barrel", cause, maxlen);
            return true;
        }
        if (IsGascanSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "gascan", cause, maxlen);
            return true;
        }
        if (TryCauseFromHazardContext(attackerClient, cause, maxlen))
        {
            strcopy(primary, sizeof(primary), cause);
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, primary, cause, maxlen);
            return true;
        }
        if (bulletExplosiveState)
        {
            BuildPrimaryCause(baseWeapon, true, false, "", cause, maxlen);
            return true;
        }
        if (TryResolveRecentSpecialBullet(attackerClient, false, baseWeapon, sizeof(baseWeapon), hasBaseWeapon))
        {
            BuildPrimaryCause(baseWeapon, true, false, "", cause, maxlen);
            return true;
        }
        if (hasBaseWeapon)
        {
            strcopy(cause, maxlen, baseWeapon);
            return true;
        }

        strcopy(cause, maxlen, "explosive");
        return true;
    }

    if (hasBaseWeapon)
    {
        strcopy(cause, maxlen, baseWeapon);
        return true;
    }

    if (IsInGameClient(attackerClient))
    {
        int active = GetEntPropEnt(attackerClient, Prop_Send, "m_hActiveWeapon");
        if (IsValidEdict(active))
        {
            char cls[64];
            GetEntityClassname(active, cls, sizeof(cls));
            if (FormatWeaponName(cls, cause, maxlen))
            {
                return true;
            }
        }
    }

    return false;
}

void ResolveSurvivorKillSICause(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, char[] cause, int maxlen)
{
    char baseWeapon[64];
    bool hasBaseWeapon = false;

    if (FormatWeaponName(eventWeapon, baseWeapon, sizeof(baseWeapon)))
    {
        hasBaseWeapon = true;
    }
    else if (GetClientActiveWeaponLabel(attackerClient, baseWeapon, sizeof(baseWeapon)))
    {
        hasBaseWeapon = true;
    }

    if (hasBaseWeapon && StrEqual(baseWeapon, "Pistol", false) && IsDualPistolContext(0, attackerClient))
    {
        strcopy(baseWeapon, sizeof(baseWeapon), "Dual Pistols");
    }

    bool fire = IsFireCause(eventWeapon, dmgType) || EntityClassMatches(attackerEnt, "inferno") || EntityClassMatches(attackerEnt, "entityflame");
    bool explosive = IsExplosiveCause(eventWeapon, dmgType) || EntityClassMatches(attackerEnt, "pipe_bomb_projectile") || EntityClassMatches(attackerEnt, "grenade_launcher_projectile");
    bool bulletFireState = (hasBaseWeapon && ShouldUseBulletState(baseWeapon, eventWeapon, attackerEnt));
    bool bulletExplosiveState = (hasBaseWeapon && ShouldUseBulletState(baseWeapon, eventWeapon, attackerEnt));

    if (fire)
    {
        char primary[64];
        HazardType assistType = Hazard_None;
        if (attackerClient > 0 && attackerClient <= MaxClients && GetRecentFireAssist(victim, attackerClient, assistType))
        {
            if (HazardTypeToLabel(assistType, cause, maxlen))
            {
                strcopy(primary, sizeof(primary), cause);
                BuildPrimaryCause(baseWeapon, bulletFireState, true, primary, cause, maxlen);
                return;
            }
        }
        if (TryCauseFromFireEntitySource(victim, attackerEnt, cause, maxlen))
        {
            strcopy(primary, sizeof(primary), cause);
            BuildPrimaryCause(baseWeapon, bulletFireState, true, primary, cause, maxlen);
            return;
        }
        bool infernoLike = (
            StrContains(eventWeapon, "inferno", false) != -1 ||
            StrContains(eventWeapon, "entityflame", false) != -1 ||
            EntityClassMatches(attackerEnt, "inferno") ||
            EntityClassMatches(attackerEnt, "entityflame")
        );
        if (IsGascanSource(victim, attackerEnt, eventWeapon))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "gascan", cause, maxlen);
            return;
        }
        if (infernoLike && attackerClient > 0 && attackerClient <= MaxClients && WasRecentMolotovThrow(attackerClient, 8.0))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "molotov", cause, maxlen);
            return;
        }
        if (EntityClassMatches(attackerEnt, "fire_cracker_blast") || EntityClassMatches(attackerEnt, "firework"))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "firework crate", cause, maxlen);
            return;
        }
        if (EntityClassMatches(attackerEnt, "fuel_barrel") || EntityIsFuelBarrel(attackerEnt))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "fuel barrel", cause, maxlen);
            return;
        }
        if (StrContains(eventWeapon, "molotov", false) != -1 || EntityIsMolotovProjectile(attackerEnt))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "molotov", cause, maxlen);
            return;
        }
        if (attackerClient > 0 && attackerClient <= MaxClients && TryCauseFromHazardContext(attackerClient, cause, maxlen))
        {
            strcopy(primary, sizeof(primary), cause);
            BuildPrimaryCause(baseWeapon, bulletFireState, true, primary, cause, maxlen);
            return;
        }
        if (bulletFireState)
        {
            BuildPrimaryCause(baseWeapon, true, true, "", cause, maxlen);
            return;
        }
        if (attackerClient > 0 && attackerClient <= MaxClients && TryResolveRecentSpecialBullet(attackerClient, true, baseWeapon, sizeof(baseWeapon), hasBaseWeapon))
        {
            BuildPrimaryCause(baseWeapon, true, true, "", cause, maxlen);
            return;
        }
        if (hasBaseWeapon && !IsGenericFireLabel(baseWeapon))
        {
            strcopy(cause, maxlen, baseWeapon);
            return;
        }

        strcopy(cause, maxlen, "fire");
        return;
    }

    if (explosive)
    {
        char primary[64];
        if (StrContains(eventWeapon, "pipe", false) != -1 || EntityClassMatches(attackerEnt, "pipe_bomb_projectile"))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "pipebomb", cause, maxlen);
            return;
        }
        if (EntityClassMatches(attackerEnt, "fire_cracker_blast") || EntityClassMatches(attackerEnt, "firework"))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "firework crate", cause, maxlen);
            return;
        }
        if (EntityClassMatches(attackerEnt, "fuel_barrel"))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "fuel barrel", cause, maxlen);
            return;
        }
        if (EntityIsGascan(attackerEnt))
        {
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, "gascan", cause, maxlen);
            return;
        }
        if (attackerClient > 0 && attackerClient <= MaxClients && TryCauseFromHazardContext(attackerClient, cause, maxlen))
        {
            strcopy(primary, sizeof(primary), cause);
            BuildPrimaryCause(baseWeapon, bulletExplosiveState, false, primary, cause, maxlen);
            return;
        }
        if (bulletExplosiveState)
        {
            BuildPrimaryCause(baseWeapon, true, false, "", cause, maxlen);
            return;
        }
        if (attackerClient > 0 && attackerClient <= MaxClients && TryResolveRecentSpecialBullet(attackerClient, false, baseWeapon, sizeof(baseWeapon), hasBaseWeapon))
        {
            BuildPrimaryCause(baseWeapon, true, false, "", cause, maxlen);
            return;
        }
        if (hasBaseWeapon)
        {
            strcopy(cause, maxlen, baseWeapon);
            return;
        }

        strcopy(cause, maxlen, "explosive");
        return;
    }

    if (hasBaseWeapon)
    {
        strcopy(cause, maxlen, baseWeapon);
        return;
    }

    strcopy(cause, maxlen, "physical");
}

void ResolveWitchKillCause(int attackerClient, char[] cause, int maxlen)
{
    char weapon[64];
    int active = GetEntPropEnt(attackerClient, Prop_Send, "m_hActiveWeapon");
    if (IsValidEdict(active))
    {
        char cls[64];
        GetEntityClassname(active, cls, sizeof(cls));
        if (FormatWeaponName(cls, weapon, sizeof(weapon)))
        {
            strcopy(cause, maxlen, weapon);
            return;
        }
    }

    if (attackerClient > 0 && attackerClient <= MaxClients && TryCauseFromHazardContext(attackerClient, cause, maxlen))
    {
        return;
    }

    if (attackerClient > 0 && attackerClient <= MaxClients && WasRecentMolotovThrow(attackerClient, 20.0))
    {
        strcopy(cause, maxlen, "molotov");
        return;
    }

    strcopy(cause, maxlen, "physical");
}

void ApplySurvivorKillQualifiers(int attackerClient, int victimClient, const char[] eventWeapon, int dmgType, bool headshot, bool wallbang, char[] cause, int maxlen)
{
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return;
    }

    HazardType fireAssistType = Hazard_None;
    if (GetRecentFireAssist(victimClient, attackerClient, fireAssistType))
    {
        char fireLabel[32];
        if (HazardTypeToLabel(fireAssistType, fireLabel, sizeof(fireLabel)))
        {
            if (StrEqual(cause, "fire", false))
            {
                strcopy(cause, maxlen, fireLabel);
            }
            else
            {
                AppendCauseToken(cause, maxlen, fireLabel);
            }
        }
    }

    if (headshot)
    {
        AppendCauseToken(cause, maxlen, "headshot");
    }

    if (wallbang)
    {
        AppendCauseToken(cause, maxlen, "wallbang");
    }

    if (IsClientDucking(attackerClient))
    {
        AppendCauseToken(cause, maxlen, "duck");
    }

    if (IsClientIncapped(attackerClient))
    {
        AppendCauseToken(cause, maxlen, "incap");
    }

    if (IsClientVomitBlind(attackerClient))
    {
        AppendCauseToken(cause, maxlen, "blind");
    }

    if (IsSniperLikeRange(attackerClient, victimClient, eventWeapon, dmgType))
    {
        AppendCauseToken(cause, maxlen, "snip");
    }

    if (IsVictimStaggeredByAttacker(victimClient, attackerClient))
    {
        AppendCauseToken(cause, maxlen, "stagger");
    }

    if (IsClientAdrenalineActive(victimClient))
    {
        AppendCauseToken(cause, maxlen, "adrenaline");
    }
}

bool GetBestWeaponLabel(int victim, const char[] eventWeapon, char[] outLabel, int maxlen)
{
    if (FormatWeaponName(eventWeapon, outLabel, maxlen))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    if (TryCauseFromSnapshotWeapon(victim, outLabel, maxlen))
    {
        return true;
    }

    return false;
}

bool GetClientActiveWeaponLabel(int client, char[] outLabel, int maxlen)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (!IsValidEdict(active))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(active, cls, sizeof(cls));

    if (StrEqual(cls, "weapon_melee"))
    {
        char melee[64];
        if (GetEntPropStringSafe(active, Prop_Data, "m_strMapSetScriptName", melee, sizeof(melee)) && melee[0] != '\0')
        {
            return FormatWeaponName(melee, outLabel, maxlen);
        }

        strcopy(outLabel, maxlen, "Melee");
        return true;
    }

    return FormatWeaponName(cls, outLabel, maxlen);
}

bool IsFireFromEntities(int victim, int attackerEnt)
{
    if (EntityClassMatches(attackerEnt, "inferno") || EntityClassMatches(attackerEnt, "entityflame"))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    return EntityClassMatches(g_iLastInflictor[victim], "inferno") || EntityClassMatches(g_iLastInflictor[victim], "entityflame");
}

bool IsExplosiveFromEntities(int victim, int attackerEnt)
{
    if (EntityClassMatches(attackerEnt, "pipe_bomb_projectile") || EntityClassMatches(attackerEnt, "grenade_launcher_projectile"))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    return EntityClassMatches(g_iLastInflictor[victim], "pipe_bomb_projectile") || EntityClassMatches(g_iLastInflictor[victim], "grenade_launcher_projectile");
}

bool IsMolotovSource(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon)
{
    if (IsGascanSource(victim, attackerEnt, eventWeapon))
    {
        return false;
    }

    if (IsFireworkSource(victim, attackerEnt, eventWeapon) || IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
    {
        return false;
    }

    if (StrContains(eventWeapon, "molotov", false) != -1)
    {
        return true;
    }

    if (EntityIsMolotovProjectile(attackerEnt))
    {
        return true;
    }

    bool infernoLike = (
        StrContains(eventWeapon, "inferno", false) != -1 ||
        StrContains(eventWeapon, "entityflame", false) != -1 ||
        EntityClassMatches(attackerEnt, "inferno") ||
        EntityClassMatches(attackerEnt, "entityflame")
    );

    if (infernoLike)
    {
        if (WasRecentMolotovThrow(attackerClient, 20.0) || WasRecentMolotovThrow(victim, 20.0))
        {
            return true;
        }
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    if (EntityIsMolotovProjectile(g_iLastInflictor[victim]) || EntityIsMolotovProjectile(g_iLastWeapon[victim]))
    {
        return true;
    }

    if (infernoLike)
    {
        int snapAttacker = g_iLastAttacker[victim];
        if (WasRecentMolotovThrow(snapAttacker, 20.0))
        {
            return true;
        }
    }

    return false;
}

bool IsPipeBombSource(int victim, int attackerEnt, const char[] eventWeapon)
{
    if (StrContains(eventWeapon, "pipe", false) != -1)
    {
        return true;
    }

    if (EntityClassMatches(attackerEnt, "pipe_bomb_projectile"))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    return EntityClassMatches(g_iLastInflictor[victim], "pipe_bomb_projectile");
}

bool IsGascanSource(int victim, int attackerEnt, const char[] eventWeapon)
{
    if (StrContains(eventWeapon, "gascan", false) != -1)
    {
        return true;
    }

    if (EntityIsGascan(attackerEnt) || LinkedEntityIsGascan(attackerEnt))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    return EntityIsGascan(g_iLastInflictor[victim]) || EntityIsGascan(g_iLastWeapon[victim]) || LinkedEntityIsGascan(g_iLastInflictor[victim]) || LinkedEntityIsGascan(g_iLastWeapon[victim]);
}

bool IsFireworkSource(int victim, int attackerEnt, const char[] eventWeapon)
{
    if (StrContains(eventWeapon, "firework", false) != -1 || StrContains(eventWeapon, "fire_cracker", false) != -1)
    {
        return true;
    }

    if (EntityClassMatches(attackerEnt, "fire_cracker_blast") || EntityClassMatches(attackerEnt, "firework") || EntityIsFireworkCrate(attackerEnt))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    return EntityClassMatches(g_iLastInflictor[victim], "fire_cracker_blast") || EntityClassMatches(g_iLastInflictor[victim], "firework") || EntityIsFireworkCrate(g_iLastInflictor[victim]) || EntityIsFireworkCrate(g_iLastWeapon[victim]);
}

bool IsFuelBarrelSource(int victim, int attackerEnt, const char[] eventWeapon)
{
    if (StrContains(eventWeapon, "fuel", false) != -1 || StrContains(eventWeapon, "barrel", false) != -1)
    {
        return true;
    }

    if (EntityClassMatches(attackerEnt, "fuel_barrel") || EntityIsFuelBarrel(attackerEnt))
    {
        return true;
    }

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    return EntityClassMatches(g_iLastInflictor[victim], "fuel_barrel") || EntityClassMatches(g_iLastWeapon[victim], "fuel_barrel") || EntityIsFuelBarrel(g_iLastInflictor[victim]) || EntityIsFuelBarrel(g_iLastWeapon[victim]);
}

