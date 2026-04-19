AttackerKind ResolveAttacker(int victim, int attackerClient, int attackerEnt, int dmgType, const char[] eventWeapon, char[] attackerLabel, int maxlen, bool &isSelf)
{
    isSelf = false;

    if (IsInGameClient(attackerClient))
    {
        if (attackerClient == victim)
        {
            isSelf = true;
            GetCleanClientName(attackerClient, attackerLabel, maxlen);
            return Attacker_Survivor;
        }

        int team = GetClientTeam(attackerClient);
        if (team == 2)
        {
            GetCleanClientName(attackerClient, attackerLabel, maxlen);
            return Attacker_Survivor;
        }

        if (team == 3)
        {
            GetSpecialInfectedName(attackerClient, attackerLabel, maxlen);
            return Attacker_SI;
        }
    }

    if (TryResolveFromEntity(attackerEnt, attackerLabel, maxlen))
    {
        if (StrEqual(attackerLabel, "Common Infected"))
        {
            return Attacker_CI;
        }
        return Attacker_SI;
    }

    if (HasRecentSnapshot(victim))
    {
        int snapAttacker = g_iLastAttacker[victim];
        int snapInflictor = g_iLastInflictor[victim];

        if (IsInGameClient(snapAttacker))
        {
            if (snapAttacker == victim)
            {
                isSelf = true;
                GetCleanClientName(snapAttacker, attackerLabel, maxlen);
                return Attacker_Survivor;
            }

            int team2 = GetClientTeam(snapAttacker);
            if (team2 == 2)
            {
                GetCleanClientName(snapAttacker, attackerLabel, maxlen);
                return Attacker_Survivor;
            }

            if (team2 == 3)
            {
                GetSpecialInfectedName(snapAttacker, attackerLabel, maxlen);
                return Attacker_SI;
            }
        }

        if (TryResolveFromEntity(snapInflictor, attackerLabel, maxlen) || TryResolveFromEntity(snapAttacker, attackerLabel, maxlen))
        {
            if (StrEqual(attackerLabel, "Common Infected"))
            {
                return Attacker_CI;
            }
            return Attacker_SI;
        }
    }

    if (attackerClient <= 0 && ShouldTreatAsSelf(dmgType, eventWeapon))
    {
        isSelf = true;
        GetCleanClientName(victim, attackerLabel, maxlen);
        return Attacker_Survivor;
    }

    attackerLabel[0] = '\0';
    return Attacker_Unknown;
}

bool TryResolveFromEntity(int entity, char[] label, int maxlen)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char classname[64];
    GetEntityClassname(entity, classname, sizeof(classname));

    if (StrEqual(classname, "infected"))
    {
        strcopy(label, maxlen, "Common Infected");
        return true;
    }

    if (StrEqual(classname, "witch"))
    {
        strcopy(label, maxlen, "Witch");
        return true;
    }

    int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    if (IsInGameClient(owner) && GetClientTeam(owner) == 3)
    {
        GetSpecialInfectedName(owner, label, maxlen);
        return true;
    }

    if (StrEqual(classname, "tank_rock"))
    {
        strcopy(label, maxlen, "Tank");
        return true;
    }

    if (StrContains(classname, "_claw", false) != -1)
    {
        if (StrContains(classname, "tank", false) != -1)
        {
            strcopy(label, maxlen, "Tank");
            return true;
        }
        if (StrContains(classname, "hunter", false) != -1)
        {
            strcopy(label, maxlen, "Hunter");
            return true;
        }
        if (StrContains(classname, "smoker", false) != -1)
        {
            strcopy(label, maxlen, "Smoker");
            return true;
        }
        if (StrContains(classname, "boomer", false) != -1)
        {
            strcopy(label, maxlen, "Boomer");
            return true;
        }
        if (StrContains(classname, "spitter", false) != -1)
        {
            strcopy(label, maxlen, "Spitter");
            return true;
        }
        if (StrContains(classname, "jockey", false) != -1)
        {
            strcopy(label, maxlen, "Jockey");
            return true;
        }
        if (StrContains(classname, "charger", false) != -1)
        {
            strcopy(label, maxlen, "Charger");
            return true;
        }
    }

    return false;
}

void ResolveCause(int victim, const char[] eventWeapon, int dmgType, int attackerClient, int attackerEnt, AttackerKind kind, char[] cause, int maxlen)
{
    if (kind == Attacker_CI)
    {
        strcopy(cause, maxlen, "physical");
        return;
    }

    if (kind == Attacker_SI && ResolveSpecialInfectedCause(victim, attackerClient, attackerEnt, eventWeapon, dmgType, cause, maxlen))
    {
        return;
    }

    if (kind == Attacker_Survivor && ResolveSurvivorCause(victim, attackerClient, attackerEnt, eventWeapon, dmgType, cause, maxlen))
    {
        return;
    }

    if (IsFireCause(eventWeapon, dmgType))
    {
        strcopy(cause, maxlen, "fire");
        return;
    }

    if (IsExplosiveCause(eventWeapon, dmgType))
    {
        strcopy(cause, maxlen, "explosive");
        return;
    }

    if ((dmgType & DMG_FALL) != 0)
    {
        strcopy(cause, maxlen, "falling");
        return;
    }

    if (FormatWeaponName(eventWeapon, cause, maxlen))
    {
        return;
    }

    if (HasRecentSnapshot(victim))
    {
        if (TryCauseFromSnapshotWeapon(victim, cause, maxlen))
        {
            return;
        }

        int snapType = g_iLastDmgType[victim];
        if ((snapType & DMG_BURN) != 0)
        {
            strcopy(cause, maxlen, "fire");
            return;
        }
        if ((snapType & DMG_BLAST) != 0)
        {
            strcopy(cause, maxlen, "explosive");
            return;
        }
        if ((snapType & DMG_FALL) != 0)
        {
            strcopy(cause, maxlen, "falling");
            return;
        }
    }

    if (IsValidEdict(attackerEnt))
    {
        char classname[64];
        GetEntityClassname(attackerEnt, classname, sizeof(classname));
        if (StrEqual(classname, "infected") || StrEqual(classname, "witch"))
        {
            strcopy(cause, maxlen, StrEqual(classname, "witch") ? "Witch claws" : "physical");
            return;
        }
    }

    if (IsInGameClient(attackerClient) && GetClientTeam(attackerClient) == 3)
    {
        strcopy(cause, maxlen, "physical");
        return;
    }

    strcopy(cause, maxlen, "physical");
}

bool TryCauseFromSnapshotWeapon(int victim, char[] cause, int maxlen)
{
    int weapon = g_iLastWeapon[victim];
    if (IsValidEdict(weapon))
    {
        char classname[64];
        GetEntityClassname(weapon, classname, sizeof(classname));

        if (StrEqual(classname, "weapon_melee"))
        {
            char melee[64];
            if (GetEntPropStringSafe(weapon, Prop_Data, "m_strMapSetScriptName", melee, sizeof(melee)) && melee[0] != '\0')
            {
                FormatWeaponName(melee, cause, maxlen);
                return true;
            }
        }

        if (FormatWeaponName(classname, cause, maxlen))
        {
            return true;
        }
    }

    int inflictor = g_iLastInflictor[victim];
    if (IsValidEdict(inflictor))
    {
        char infClass[64];
        GetEntityClassname(inflictor, infClass, sizeof(infClass));
        if (FormatWeaponName(infClass, cause, maxlen))
        {
            return true;
        }
    }

    return false;
}

bool IsFireCause(const char[] weapon, int dmgType)
{
    if ((dmgType & DMG_BURN) != 0)
    {
        return true;
    }

    return (StrContains(weapon, "fire", false) != -1 || StrContains(weapon, "inferno", false) != -1 || StrContains(weapon, "entityflame", false) != -1 || StrContains(weapon, "molotov", false) != -1);
}

bool IsExplosiveCause(const char[] weapon, int dmgType)
{
    if ((dmgType & DMG_BLAST) != 0)
    {
        return true;
    }

    return (StrContains(weapon, "grenade", false) != -1 || StrContains(weapon, "explode", false) != -1 || StrContains(weapon, "pipe", false) != -1 || StrContains(weapon, "propane", false) != -1 || StrContains(weapon, "oxygen", false) != -1 || StrContains(weapon, "launcher", false) != -1);
}

bool ShouldTreatAsSelf(int dmgType, const char[] weapon)
{
    return ((dmgType & DMG_FALL) != 0 || (dmgType & DMG_BURN) != 0 || (dmgType & DMG_BLAST) != 0 || StrContains(weapon, "world", false) != -1 || StrContains(weapon, "trigger_hurt", false) != -1);
}

bool IsBleedingOutDeath(int victim, int attackerClient, int attackerEnt, const char[] weapon, int dmgType)
{
    if (!g_bIsIncappedState[victim])
    {
        return false;
    }

    if ((GetGameTime() - g_fLastIncapTime[victim]) < 2.0)
    {
        return false;
    }

    if (attackerClient > 0 || attackerEnt > 0)
    {
        return false;
    }

    if (StrEqual(weapon, "world", false) || StrEqual(weapon, "none", false) || StrEqual(weapon, "player", false) || weapon[0] == '\0')
    {
        return true;
    }

    return ((dmgType & DMG_POISON) != 0 || (dmgType & DMG_DIRECT) != 0 || (dmgType & DMG_GENERIC) != 0);
}

bool FormatWeaponName(const char[] inputWeapon, char[] output, int maxlen)
{
    if (inputWeapon[0] == '\0')
    {
        return false;
    }

    char weapon[64];
    strcopy(weapon, sizeof(weapon), inputWeapon);
    TrimString(weapon);
    ToLowerCase(weapon);

    if (
        StrEqual(weapon, "none") ||
        StrEqual(weapon, "world") ||
        StrEqual(weapon, "trigger_hurt") ||
        StrEqual(weapon, "player") ||
        StrEqual(weapon, "infected") ||
        StrEqual(weapon, "entity")
    )
    {
        return false;
    }

    if (strncmp(weapon, "weapon_", 7, false) == 0)
    {
        strcopy(weapon, sizeof(weapon), weapon[7]);
    }

    if (StrEqual(weapon, "melee"))
    {
        return false;
    }

    if (StrEqual(weapon, "witch"))
    {
        strcopy(output, maxlen, "Witch claws");
        return true;
    }

    if (StrEqual(weapon, "rifle_ak47"))
    {
        strcopy(output, maxlen, "AK-47");
        return true;
    }
    if (StrEqual(weapon, "smg"))
    {
        strcopy(output, maxlen, "SMG");
        return true;
    }
    if (StrEqual(weapon, "smg_silenced"))
    {
        strcopy(output, maxlen, "Silenced SMG");
        return true;
    }
    if (StrEqual(weapon, "smg_mp5"))
    {
        strcopy(output, maxlen, "MP5");
        return true;
    }
    if (StrEqual(weapon, "rifle"))
    {
        strcopy(output, maxlen, "M16");
        return true;
    }
    if (StrEqual(weapon, "rifle_desert"))
    {
        strcopy(output, maxlen, "SCAR");
        return true;
    }
    if (StrEqual(weapon, "rifle_sg552"))
    {
        strcopy(output, maxlen, "SG552");
        return true;
    }
    if (StrEqual(weapon, "rifle_m60"))
    {
        strcopy(output, maxlen, "M60");
        return true;
    }
    if (StrEqual(weapon, "molotov"))
    {
        strcopy(output, maxlen, "molotov");
        return true;
    }
    if (StrEqual(weapon, "pipe_bomb"))
    {
        strcopy(output, maxlen, "pipebomb");
        return true;
    }
    if (StrEqual(weapon, "gascan"))
    {
        strcopy(output, maxlen, "gascan");
        return true;
    }
    if (StrEqual(weapon, "tank_claw"))
    {
        strcopy(output, maxlen, "Tank claws");
        return true;
    }
    if (StrEqual(weapon, "tank_rock"))
    {
        strcopy(output, maxlen, "Tank rock");
        return true;
    }
    if (StrEqual(weapon, "knife"))
    {
        strcopy(output, maxlen, "Knife");
        return true;
    }

    if (StrContains(weapon, "_claw", false) != -1)
    {
        if (StrContains(weapon, "hunter", false) != -1) { strcopy(output, maxlen, "Hunter claws"); return true; }
        if (StrContains(weapon, "smoker", false) != -1) { strcopy(output, maxlen, "Smoker claws"); return true; }
        if (StrContains(weapon, "boomer", false) != -1) { strcopy(output, maxlen, "Boomer claws"); return true; }
        if (StrContains(weapon, "spitter", false) != -1) { strcopy(output, maxlen, "Spitter claws"); return true; }
        if (StrContains(weapon, "jockey", false) != -1) { strcopy(output, maxlen, "Jockey claws"); return true; }
        if (StrContains(weapon, "charger", false) != -1) { strcopy(output, maxlen, "Charger claws"); return true; }
    }

    char normalized[64];
    strcopy(normalized, sizeof(normalized), weapon);
    ReplaceString(normalized, sizeof(normalized), "_", " ");
    TitleCase(normalized, sizeof(normalized));

    if (normalized[0] == '\0')
    {
        return false;
    }

    strcopy(output, maxlen, normalized);
    return true;
}

bool ResolveSpecialInfectedCause(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, char[] cause, int maxlen)
{
    int toxicGasCause = 0;
    if (GetFeatureStatus(FeatureType_Native, "EliteSI_ToxicGas_GetRecentDamageCause") == FeatureStatus_Available)
    {
        toxicGasCause = EliteSI_ToxicGas_GetRecentDamageCause(victim);
        if (toxicGasCause > 0)
        {
            int toxicGasAttacker = 0;
            if (GetFeatureStatus(FeatureType_Native, "EliteSI_ToxicGas_GetRecentDamageAttacker") == FeatureStatus_Available)
            {
                toxicGasAttacker = EliteSI_ToxicGas_GetRecentDamageAttacker(victim);
            }

            if (toxicGasAttacker > 0 && toxicGasAttacker <= MaxClients && IsClientInGame(toxicGasAttacker) && GetClientTeam(toxicGasAttacker) == 3)
            {
                attackerClient = toxicGasAttacker;
            }

            switch (toxicGasCause)
            {
                case 1:
                {
                    strcopy(cause, maxlen, "Smoker Toxic Gas");
                    return true;
                }
            }
        }
    }

    int noxiousCause = 0;
    if (GetFeatureStatus(FeatureType_Native, "EliteSI_Noxious_GetRecentDamageCause") == FeatureStatus_Available)
    {
        noxiousCause = EliteSI_Noxious_GetRecentDamageCause(victim);
        if (noxiousCause > 0)
        {
            int noxiousAttacker = 0;
            if (GetFeatureStatus(FeatureType_Native, "EliteSI_Noxious_GetRecentDamageAttacker") == FeatureStatus_Available)
            {
                noxiousAttacker = EliteSI_Noxious_GetRecentDamageAttacker(victim);
            }

            if (noxiousAttacker > 0 && noxiousAttacker <= MaxClients && IsClientInGame(noxiousAttacker) && GetClientTeam(noxiousAttacker) == 3)
            {
                attackerClient = noxiousAttacker;
            }

            switch (noxiousCause)
            {
                case 1:
                {
                    strcopy(cause, maxlen, "Smoker Asphyxiation");
                    return true;
                }
                case 2:
                {
                    strcopy(cause, maxlen, "Smoker Collapsed Lung");
                    return true;
                }
                case 3:
                {
                    strcopy(cause, maxlen, "Smoker Methane Blast");
                    return true;
                }
                case 4:
                {
                    strcopy(cause, maxlen, "Smoker Methane Leak");
                    return true;
                }
                case 5:
                {
                    strcopy(cause, maxlen, "Smoker Tongue Whip");
                    return true;
                }
                case 6:
                {
                    strcopy(cause, maxlen, "Smoker Void Pocket");
                    return true;
                }
                case 7:
                {
                    strcopy(cause, maxlen, "Smoker Restrained Hostage");
                    return true;
                }
            }
        }
    }

    if (StrEqual(eventWeapon, "tank_rock", false))
    {
        strcopy(cause, maxlen, "Tank rock");
        return true;
    }

    if (IsInGameClient(attackerClient) && GetClientTeam(attackerClient) == 3)
    {
        int zclass = L4D2_GetPlayerZombieClass(attackerClient);
        switch (zclass)
        {
            case L4D2ZombieClass_Hunter:
            {
                int pounce = GetEntPropEnt(victim, Prop_Send, "m_pounceAttacker");
                strcopy(cause, maxlen, (pounce == attackerClient) ? "Hunter pounce" : "Hunter claws");
                return true;
            }
            case L4D2ZombieClass_Smoker:
            {
                int tongue = GetEntPropEnt(victim, Prop_Send, "m_tongueOwner");
                strcopy(cause, maxlen, (tongue == attackerClient) ? "Smoker choke" : "Smoker claws");
                return true;
            }
            case L4D2ZombieClass_Jockey:
            {
                int jockey = GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker");
                strcopy(cause, maxlen, (jockey == attackerClient) ? "Jockey ride" : "Jockey claws");
                return true;
            }
            case L4D2ZombieClass_Charger:
            {
                int pummel = GetEntPropEnt(victim, Prop_Send, "m_pummelAttacker");
                int carry = GetEntPropEnt(victim, Prop_Send, "m_carryAttacker");
                strcopy(cause, maxlen, (pummel == attackerClient || carry == attackerClient) ? "Charger pummel" : "Charger claws");
                return true;
            }
            case L4D2ZombieClass_Spitter:
            {
                if ((dmgType & DMG_ACID) != 0 || StrContains(eventWeapon, "spit", false) != -1 || StrContains(eventWeapon, "insect_swarm", false) != -1)
                {
                    strcopy(cause, maxlen, "Spitter acid");
                }
                else
                {
                    strcopy(cause, maxlen, "Spitter claws");
                }
                return true;
            }
            case L4D2ZombieClass_Tank:
            {
                strcopy(cause, maxlen, StrEqual(eventWeapon, "tank_rock", false) ? "Tank rock" : "Tank claws");
                return true;
            }
        }
    }

    if (IsValidEdict(attackerEnt))
    {
        char cls[64];
        GetEntityClassname(attackerEnt, cls, sizeof(cls));
        if (StrEqual(cls, "insect_swarm") || StrEqual(cls, "spitter_projectile"))
        {
            strcopy(cause, maxlen, "Spitter acid");
            return true;
        }
        if (StrEqual(cls, "tank_rock"))
        {
            strcopy(cause, maxlen, "Tank rock");
            return true;
        }
    }

    return false;
}

void GetSpecialInfectedName(int client, char[] outName, int maxlen, bool includeEliteTag = true)
{
    char baseName[32];

    int zclass = L4D2_GetPlayerZombieClass(client);
    switch (zclass)
    {
        case L4D2ZombieClass_Smoker: strcopy(baseName, sizeof(baseName), "Smoker");
        case L4D2ZombieClass_Boomer: strcopy(baseName, sizeof(baseName), "Boomer");
        case L4D2ZombieClass_Hunter: strcopy(baseName, sizeof(baseName), "Hunter");
        case L4D2ZombieClass_Spitter: strcopy(baseName, sizeof(baseName), "Spitter");
        case L4D2ZombieClass_Jockey: strcopy(baseName, sizeof(baseName), "Jockey");
        case L4D2ZombieClass_Charger: strcopy(baseName, sizeof(baseName), "Charger");
        case L4D2ZombieClass_Tank: strcopy(baseName, sizeof(baseName), "Tank");
        default: strcopy(baseName, sizeof(baseName), "Special Infected");
    }

    if (includeEliteTag && IsEliteSI(client))
    {
        char eliteTypeName[64];
        eliteTypeName[0] = '\0';

        if (GetFeatureStatus(FeatureType_Native, "L4D2_GetEliteTypeName") == FeatureStatus_Available && L4D2_GetEliteTypeName(client, eliteTypeName, sizeof(eliteTypeName)) && eliteTypeName[0] != '\0')
        {
            Format(outName, maxlen, "Elite %s (%s)", baseName, eliteTypeName);
        }
        else
        {
            Format(outName, maxlen, "Elite %s", baseName);
        }
    }
    else
    {
        strcopy(outName, maxlen, baseName);
    }
}
