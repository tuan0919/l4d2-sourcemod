#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.2.0"
#define ZOMBIE_KILL_CLASS_COUNT 9

public Plugin myinfo =
{
    name = "L4D2 Score/Stats Recovery",
    author = "Antigravity",
    description = "Saves and restores player scores and campaign stats when reconnecting",
    version = PLUGIN_VERSION,
    url = ""
};

ConVar g_cvDebug;
StringMap g_hSavedStats;

static const char g_sSavedProps[][] = {
    "m_checkpointZombieKills", "m_checkpointZombieKills", "m_checkpointZombieKills",
    "m_checkpointZombieKills", "m_checkpointZombieKills", "m_checkpointZombieKills",
    "m_checkpointZombieKills", "m_checkpointZombieKills", "m_checkpointZombieKills",

    "m_missionZombieKills", "m_missionZombieKills", "m_missionZombieKills",
    "m_missionZombieKills", "m_missionZombieKills", "m_missionZombieKills",
    "m_missionZombieKills", "m_missionZombieKills", "m_missionZombieKills",

    "m_checkpointMeleeKills",
    "m_missionMeleeKills",
    "m_checkpointIncaps",
    "m_missionIncaps",
    "m_checkpointDamageTaken",
    "m_missionDamageTaken",
    "m_checkpointDamageToTank",
    "m_checkpointDamageToWitch",
    "m_checkpointReviveOtherCount",
    "m_missionReviveOtherCount",
    "m_checkpointMedkitsUsed",
    "m_missionMedkitsUsed",
    "m_checkpointPillsUsed",
    "m_missionPillsUsed",
    "m_checkpointMolotovsUsed",
    "m_missionMolotovsUsed",
    "m_checkpointPipebombsUsed",
    "m_missionPipebombsUsed",
    "m_checkpointBoomerBilesUsed",
    "m_missionBoomerBilesUsed",
    "m_checkpointAdrenalinesUsed",
    "m_missionAdrenalinesUsed",
    "m_checkpointDefibrillatorsUsed",
    "m_missionDefibrillatorsUsed",
    "m_checkpointFirstAidShared",
    "m_missionFirstAidShared",
    "m_checkpointSurvivorDamage",
    "m_missionSurvivorDamage",
    "m_checkpointHeadshots",
    "m_checkpointHeadshotAccuracy",
    "m_missionHeadshotAccuracy",
    "m_checkpointDeaths",
    "m_missionDeaths"
};

static const int g_iSavedPropElements[] = {
    0, 1, 2, 3, 4, 5, 6, 7, 8,
    0, 1, 2, 3, 4, 5, 6, 7, 8,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1
};

static const char g_sZombieKillClassNames[ZOMBIE_KILL_CLASS_COUNT][] = {
    "Common",
    "Smoker",
    "Boomer",
    "Hunter",
    "Spitter",
    "Jockey",
    "Charger",
    "Witch",
    "Tank"
};

public void OnPluginStart()
{
    g_hSavedStats = new StringMap();

    CreateConVar("l4d2_score_recovery_version", PLUGIN_VERSION, "L4D2 Score/Stats Recovery plugin version.", FCVAR_NOTIFY|FCVAR_DONTRECORD);
    g_cvDebug = CreateConVar("l4d2_score_recovery_debug", "0", "Print saved/restored score stats to server/player console for testing.", FCVAR_NOTIFY);

    RegAdminCmd("sm_score_print", Command_PrintStats, ADMFLAG_GENERIC, "Print current and cached score stats. Usage: sm_score_print [target]");
    RegAdminCmd("sm_score_recovery_print", Command_PrintStats, ADMFLAG_GENERIC, "Print current and cached score stats. Usage: sm_score_recovery_print [target]");

    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    HookEvent("player_bot_replace", Event_PlayerBotReplace, EventHookMode_Pre);
    HookEvent("bot_player_replace", Event_BotPlayerReplace, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);

    AutoExecConfig(true, "l4d2_score_recovery");
}

public Action Command_PrintStats(int client, int args)
{
    if (args < 1)
    {
        if (client <= 0)
        {
            ReplyToCommand(client, "[ScoreRecovery] Usage: sm_score_print <target>");
            return Plugin_Handled;
        }

        PrintClientStats(client, client);
        return Plugin_Handled;
    }

    char arg[64], targetName[MAX_TARGET_LENGTH];
    int targets[MAXPLAYERS], targetCount;
    bool tnIsMl;

    GetCmdArg(1, arg, sizeof(arg));
    targetCount = ProcessTargetString(arg, client, targets, sizeof(targets), 0, targetName, sizeof(targetName), tnIsMl);
    if (targetCount <= 0)
    {
        ReplyToTargetError(client, targetCount);
        return Plugin_Handled;
    }

    for (int i = 0; i < targetCount; i++)
    {
        PrintClientStats(client, targets[i]);
    }

    return Plugin_Handled;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    g_hSavedStats.Clear();
}

public void Event_PlayerDisconnect(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidSurvivor(client) && !IsFakeClient(client))
    {
        SaveClientStats(client);
    }
}

public void Event_PlayerBotReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    if (IsValidSurvivor(player) && !IsFakeClient(player))
    {
        SaveClientStats(player);
    }
}

public void Event_BotPlayerReplace(Event event, const char[] name, bool dontBroadcast)
{
    int player = GetClientOfUserId(event.GetInt("player"));
    if (IsValidSurvivor(player) && !IsFakeClient(player))
    {
        RestoreClientStats(player);
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (IsValidSurvivor(client) && !IsFakeClient(client))
    {
        RestoreClientStats(client);
    }
}

void SaveClientStats(int client)
{
    char auth[32];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || StrEqual(auth, "BOT")) return;

    int stats[sizeof(g_sSavedProps)];
    bool valid = CaptureClientStats(client, stats);

    if (valid)
    {
        g_hSavedStats.SetArray(auth, stats, sizeof(stats));

        if (g_cvDebug.BoolValue)
        {
            PrintStatsToServer("Saved", client, auth, stats);
        }
    }
    else if (g_cvDebug.BoolValue)
    {
        PrintToServer("[ScoreRecovery] Skip saving %N <%s>: all tracked stats are zero or unavailable.", client, auth);
    }
}

void RestoreClientStats(int client)
{
    char auth[32];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || StrEqual(auth, "BOT")) return;

    int stats[sizeof(g_sSavedProps)];
    if (g_hSavedStats.GetArray(auth, stats, sizeof(stats)))
    {
        bool restored = false;

        for (int i = 0; i < sizeof(g_sSavedProps); i++)
        {
            if (!HasEntProp(client, Prop_Send, g_sSavedProps[i]))
            {
                continue;
            }

            if (IsZombieKillProp(g_sSavedProps[i]))
            {
                SetEntProp(client, Prop_Send, g_sSavedProps[i], stats[i], 4, g_iSavedPropElements[i]);
            }
            else
            {
                SetEntProp(client, Prop_Send, g_sSavedProps[i], stats[i]);
            }

            restored = true;
        }

        if (g_cvDebug.BoolValue)
        {
            PrintStatsToServer("Restored", client, auth, stats);
            PrintStatsToClientConsole(client, "Restored cached stats", stats);

            if (restored)
            {
                PrintToChat(client, "[ScoreRecovery] Restored cached stats. Check console for values.");
            }
        }
    }
    else if (g_cvDebug.BoolValue)
    {
        PrintToServer("[ScoreRecovery] No cached stats for %N <%s>.", client, auth);
    }
}

bool CaptureClientStats(int client, int[] stats)
{
    bool valid = false;

    for (int i = 0; i < sizeof(g_sSavedProps); i++)
    {
        stats[i] = 0;

        if (!HasEntProp(client, Prop_Send, g_sSavedProps[i]))
        {
            continue;
        }

        if (IsZombieKillProp(g_sSavedProps[i]))
        {
            stats[i] = GetEntProp(client, Prop_Send, g_sSavedProps[i], 4, g_iSavedPropElements[i]);
        }
        else
        {
            stats[i] = GetEntProp(client, Prop_Send, g_sSavedProps[i]);
        }

        if (stats[i] > 0)
        {
            valid = true;
        }
    }

    return valid;
}

void PrintClientStats(int issuer, int target)
{
    if (target <= 0 || target > MaxClients || !IsClientInGame(target))
    {
        ReplyToCommand(issuer, "[ScoreRecovery] Target is not in game.");
        return;
    }

    char auth[32];
    if (!GetClientAuthId(target, AuthId_Steam2, auth, sizeof(auth)))
    {
        strcopy(auth, sizeof(auth), "unknown");
    }

    ReplyToCommand(issuer, "[ScoreRecovery] Current stats for %N <%s>:", target, auth);
    PrintCurrentStatsToCommand(issuer, target);

    int cached[sizeof(g_sSavedProps)];
    if (!StrEqual(auth, "unknown") && !StrEqual(auth, "BOT") && g_hSavedStats.GetArray(auth, cached, sizeof(cached)))
    {
        ReplyToCommand(issuer, "[ScoreRecovery] Cached stats for %N <%s>:", target, auth);
        PrintStatsToCommand(issuer, cached);
    }
    else
    {
        ReplyToCommand(issuer, "[ScoreRecovery] No cached stats for %N <%s>.", target, auth);
    }
}

void PrintCurrentStatsToCommand(int issuer, int target)
{
    for (int i = 0; i < sizeof(g_sSavedProps); i++)
    {
        if (!HasEntProp(target, Prop_Send, g_sSavedProps[i]))
        {
            PrintStatUnavailable(issuer, i);
            continue;
        }

        int value;
        if (IsZombieKillProp(g_sSavedProps[i]))
        {
            value = GetEntProp(target, Prop_Send, g_sSavedProps[i], 4, g_iSavedPropElements[i]);
        }
        else
        {
            value = GetEntProp(target, Prop_Send, g_sSavedProps[i]);
        }

        PrintStatValue(issuer, i, value);
    }
}

void PrintStatsToCommand(int issuer, int[] stats)
{
    for (int i = 0; i < sizeof(g_sSavedProps); i++)
    {
        PrintStatValue(issuer, i, stats[i]);
    }
}

void PrintStatsToServer(const char[] action, int client, const char[] auth, int[] stats)
{
    PrintToServer("[ScoreRecovery] %s stats for %N <%s>:", action, client, auth);
    for (int i = 0; i < sizeof(g_sSavedProps); i++)
    {
        char label[96];
        BuildStatLabel(i, label, sizeof(label));
        PrintToServer("[ScoreRecovery]   %s = %d", label, stats[i]);
    }
}

void PrintStatsToClientConsole(int client, const char[] title, int[] stats)
{
    if (client <= 0 || client > MaxClients || !IsClientInGame(client))
    {
        return;
    }

    PrintToConsole(client, "[ScoreRecovery] %s:", title);
    for (int i = 0; i < sizeof(g_sSavedProps); i++)
    {
        char label[96];
        BuildStatLabel(i, label, sizeof(label));
        PrintToConsole(client, "[ScoreRecovery]   %s = %d", label, stats[i]);
    }
}

void PrintStatValue(int issuer, int index, int value)
{
    char label[96];
    BuildStatLabel(index, label, sizeof(label));
    ReplyToCommand(issuer, "[ScoreRecovery]   %s = %d", label, value);
}

void PrintStatUnavailable(int issuer, int index)
{
    char label[96];
    BuildStatLabel(index, label, sizeof(label));
    ReplyToCommand(issuer, "[ScoreRecovery]   %s = unavailable", label);
}

void BuildStatLabel(int index, char[] buffer, int maxlen)
{
    if (IsZombieKillProp(g_sSavedProps[index]))
    {
        int element = g_iSavedPropElements[index];
        Format(buffer, maxlen, "%s[%d] %s", g_sSavedProps[index], element, g_sZombieKillClassNames[element]);
        return;
    }

    strcopy(buffer, maxlen, g_sSavedProps[index]);
}

bool IsZombieKillProp(const char[] prop)
{
    return StrEqual(prop, "m_checkpointZombieKills") || StrEqual(prop, "m_missionZombieKills");
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
