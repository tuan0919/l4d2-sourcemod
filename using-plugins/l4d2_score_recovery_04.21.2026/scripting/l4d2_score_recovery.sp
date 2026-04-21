#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0"

public Plugin myinfo =
{
    name = "L4D2 Score/Stats Recovery",
    author = "Antigravity",
    description = "Saves and restores player scores and campaign stats when reconnecting",
    version = PLUGIN_VERSION,
    url = ""
};

StringMap g_hSavedStats;

static const char g_sSavedProps[][] = {
    // Current chapter
    "m_zombieKills",
    "m_survivalKills",
    "m_iVersusScore",
    
    // Checkpoints (campaign / end credit stats)
    "m_checkpointZombieKills",
    "m_checkpointMeleeKills",
    "m_checkpointIncaps",
    "m_checkpointDamageTaken",
    "m_checkpointDamageToTanks",
    "m_checkpointRevives",
    "m_checkpointMedkitsUsed",
    "m_checkpointPillsUsed",
    "m_checkpointMolotovsUsed",
    "m_checkpointPipebombsUsed"
};

public void OnPluginStart()
{
    g_hSavedStats = new StringMap();

    HookEvent("player_disconnect", Event_PlayerDisconnect, EventHookMode_Pre);
    HookEvent("player_bot_replace", Event_PlayerBotReplace, EventHookMode_Pre);
    HookEvent("bot_player_replace", Event_BotPlayerReplace, EventHookMode_Post);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    
    HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
    HookEvent("map_transition", Event_RoundEnd, EventHookMode_PostNoCopy);
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
    bool valid = false;

    for (int i = 0; i < sizeof(g_sSavedProps); i++)
    {
        if (HasEntProp(client, Prop_Send, g_sSavedProps[i]))
        {
            stats[i] = GetEntProp(client, Prop_Send, g_sSavedProps[i]);
            if (stats[i] > 0) valid = true; 
        }
    }

    if (valid)
    {
        g_hSavedStats.SetArray(auth, stats, sizeof(stats));
    }
}

void RestoreClientStats(int client)
{
    char auth[32];
    if (!GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth)) || StrEqual(auth, "BOT")) return;
    
    int stats[sizeof(g_sSavedProps)];
    if (g_hSavedStats.GetArray(auth, stats, sizeof(stats)))
    {
        for (int i = 0; i < sizeof(g_sSavedProps); i++)
        {
            if (stats[i] > 0 && HasEntProp(client, Prop_Send, g_sSavedProps[i]))
            {
                SetEntProp(client, Prop_Send, g_sSavedProps[i], stats[i]);
            }
        }
    }
}

bool IsValidSurvivor(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2);
}
