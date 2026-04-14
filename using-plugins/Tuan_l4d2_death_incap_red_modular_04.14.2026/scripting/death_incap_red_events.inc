void Event_PlayerIncapStart(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnable)
    {
        return;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    if (!IsValidSurvivor(victim))
    {
        return;
    }

    int attackerClient = GetClientOfUserId(event.GetInt("attacker"));
    int attackerEnt = event.GetInt("attackerentid");
    int dmgType = event.GetInt("type");

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    g_bIsIncappedState[victim] = true;
    g_fLastIncapTime[victim] = GetGameTime();

    ClearPendingIncap(victim);
    g_bPendingIncap[victim] = true;
    g_iPendingAttackerClient[victim] = attackerClient;
    g_iPendingAttackerEnt[victim] = attackerEnt;
    g_iPendingDmgType[victim] = dmgType;
    g_fPendingIncapTime[victim] = GetGameTime();
    strcopy(g_sPendingWeapon[victim], sizeof(g_sPendingWeapon[]), weapon);
    g_hIncapTimer[victim] = CreateTimer(INCAP_ANNOUNCE_DELAY, Timer_AnnounceIncap, GetClientUserId(victim), TIMER_FLAG_NO_MAPCHANGE);
}

void Event_ReviveSuccess(Event event, const char[] name, bool dontBroadcast)
{
    int subject = GetClientOfUserId(event.GetInt("subject"));
    if (subject > 0 && subject <= MaxClients)
    {
        g_bIsIncappedState[subject] = false;
    }
}

// OPTIMIZED: Event_WeaponFire with early guards and reduced lookups
void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    // OPTIMIZED: Early guard clauses
    if (!IsInGameClient(client) || GetClientTeam(client) != 2)
    {
        return;
    }

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));

    // OPTIMIZED: Fast molotov check
    if (StrContains(weapon, "molotov", false) != -1)
    {
        float pos[3];
        GetClientEyePosition(client, pos);
        AddSourceEvent(Hazard_Molotov, pos, client);
        g_fLastMolotovThrow[client] = GetGameTime();
        g_iLastHazardType[client] = view_as<int>(Hazard_None);
        g_fLastHazardTime[client] = 0.0;
        g_iLastHazardEntityRef[client] = INVALID_ENT_REFERENCE;
        return;
    }

    int active = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

    // OPTIMIZED: Skip expensive checks if active weapon is invalid
    if (!IsValidEdict(active))
    {
        return;
    }

    if (!HasEntProp(active, Prop_Send, "m_upgradeBitVec"))
    {
        return;
    }

    int bits = GetEntProp(active, Prop_Send, "m_upgradeBitVec");
    if ((bits & ((1 << 0) | (1 << 1))) == 0)
    {
        return;
    }

    // OPTIMIZED: Only get weapon name if needed
    char label[64];
    FormatWeaponName(weapon, label, sizeof(label));

    strcopy(g_sLastSpecialBulletWeapon[client], sizeof(g_sLastSpecialBulletWeapon[]), label);

    // OPTIMIZED: Simplified update logic
    float now = GetGameTime();
    if ((bits & (1 << 0)) != 0)
    {
        g_fLastIncendiaryShot[client] = now;
    }
    if ((bits & (1 << 1)) != 0)
    {
        g_fLastExplosiveShot[client] = now;
    }
}

// OPTIMIZED: Event_PlayerDeath with early guards and combined lookups
void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnable)
    {
        return;
    }

    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attackerClient = GetClientOfUserId(event.GetInt("attacker"));
    int attackerEnt = event.GetInt("attackerentid");
    int dmgType = event.GetInt("type");

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    bool headshot = event.GetBool("headshot", false);
    bool wallbang = (event.GetInt("penetrated", 0) > 0);

    if (!IsInGameClient(victim))
    {
        return;
    }

    int victimTeam = GetClientTeam(victim);

    // Survivor died ??? announce death with attacker info
    if (victimTeam == 2)
    {
        bool bleedingOut = IsBleedingOutDeath(victim, attackerClient, attackerEnt, weapon, dmgType);

        if (g_bPendingIncap[victim] && (GetGameTime() - g_fPendingIncapTime[victim]) <= INCAP_KILL_SUPPRESS_WINDOW)
        {
            ClearPendingIncap(victim);
        }

        g_bIsIncappedState[victim] = false;

        PrintOutcome(victim, attackerClient, attackerEnt, weapon, dmgType, false, bleedingOut);
        return;
    }

    // SI died ??? announce survivor kill if attacker is a survivor
    if (victimTeam == 3)
    {
        if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2 || attackerClient == victim)
        {
            return;
        }

        char attackerName[64];
        char victimName[64];
        char cause[192];

        GetCleanClientName(attackerClient, attackerName, sizeof(attackerName));
        GetSpecialInfectedName(victim, victimName, sizeof(victimName), g_bAnnounceEliteSIKill);

        ResolveSurvivorKillSICause(victim, attackerClient, attackerEnt, weapon, dmgType, cause, sizeof(cause));
        ApplySurvivorKillQualifiers(attackerClient, victim, weapon, dmgType, headshot, wallbang, cause, sizeof(cause));

        PrintActionWithCause(Attacker_Survivor, attackerName, "killed", victimName, cause);
    }
}

void Event_WitchKilled(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_bEnable)
    {
        return;
    }

    int attackerClient = GetClientOfUserId(event.GetInt("userid"));
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return;
    }

    char attackerName[64];
    char cause[192];
    GetCleanClientName(attackerClient, attackerName, sizeof(attackerName));
    ResolveWitchKillCause(attackerClient, cause, sizeof(cause));
    PrintActionWithCause(Attacker_Survivor, attackerName, "killed", "Witch", cause);
}

void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsInGameClient(victim) || !IsInGameClient(attacker))
    {
        return;
    }

    if (GetClientTeam(victim) != 3 || GetClientTeam(attacker) != 2)
    {
        return;
    }

    g_iLastStaggerBy[victim] = attacker;
    g_fLastStaggerTime[victim] = GetGameTime();
}

public Action Timer_AnnounceIncap(Handle timer, int userid)
{
    int victim = GetClientOfUserId(userid);
    if (!IsValidSurvivor(victim))
    {
        if (victim > 0 && victim <= MaxClients)
        {
            ClearPendingIncap(victim);
        }
        return Plugin_Stop;
    }

    if (g_hIncapTimer[victim] != timer || !g_bPendingIncap[victim])
    {
        return Plugin_Stop;
    }

    g_hIncapTimer[victim] = null;

    if (!IsPlayerAlive(victim))
    {
        ClearPendingIncap(victim);
        return Plugin_Stop;
    }

    PrintOutcome(victim, g_iPendingAttackerClient[victim], g_iPendingAttackerEnt[victim], g_sPendingWeapon[victim], g_iPendingDmgType[victim], true, false);
    ClearPendingIncap(victim);
    return Plugin_Stop;
}

void PrintOutcome(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, bool incap, bool bleedingOut = false)
{
    char attackerLabel[64];
    bool isSelf = false;

    AttackerKind kind = ResolveAttacker(victim, attackerClient, attackerEnt, dmgType, eventWeapon, attackerLabel, sizeof(attackerLabel), isSelf);

    char cause[64];
    ResolveCause(victim, eventWeapon, dmgType, attackerClient, attackerEnt, kind, cause, sizeof(cause));

    if (!incap && bleedingOut)
    {
        char victimName[64];
        GetCleanClientName(victim, victimName, sizeof(victimName));
        PrintActionWithCause(Attacker_Survivor, victimName, "died", "", "bleeding out");
        return;
    }

    if (isSelf || kind == Attacker_Unknown)
    {
        char victimName[64];
        GetCleanClientName(victim, victimName, sizeof(victimName));

        if (incap)
        {
            PrintActionWithCause(Attacker_Survivor, victimName, "incapacitated himself", "", cause);
        }
        else
        {
            PrintActionWithCause(Attacker_Survivor, victimName, "suicided", "", cause);
        }
        return;
    }

    char victimName[64];
    GetCleanClientName(victim, victimName, sizeof(victimName));

    if (kind == Attacker_CI)
    {
        if (incap)
        {
            PrintActionWithCause(Attacker_CI, "Common Infected", "incapacitated", victimName, cause);
        }
        else
        {
            PrintActionWithCause(Attacker_CI, "Common Infected", "killed", victimName, cause);
        }
        return;
    }

    if (incap)
    {
        PrintActionWithCause(kind, attackerLabel, "incapacitated", victimName, cause);
    }
    else
    {
        PrintActionWithCause(kind, attackerLabel, "killed", victimName, cause);
    }
}

void PrintActionWithCause(AttackerKind actorKind, const char[] actorName, const char[] verb, const char[] targetName, const char[] cause)
{
    char causeColored[192];
    FormatCauseForChatColors(cause, causeColored, sizeof(causeColored));

    char verbColor[16];
    if (actorKind == Attacker_Survivor)
    {
        strcopy(verbColor, sizeof(verbColor), "{blue}");
    }
    else
    {
        strcopy(verbColor, sizeof(verbColor), "{red}");
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        if (targetName[0] != '\0')
        {
            CPrintToChat(i, "{olive}%s %s%s {olive}%s {default}({green}%s{default}){default}.", actorName, verbColor, verb, targetName, causeColored);
        }
        else
        {
            CPrintToChat(i, "{olive}%s %s%s {default}({green}%s{default}){default}.", actorName, verbColor, verb, causeColored);
        }
    }
}

