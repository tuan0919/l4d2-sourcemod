#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <left4dhooks>

native int L4D2_IsEliteSI(int client);

#define PLUGIN_VERSION "1.0.0"
#define ANCHOR_NAME "SI_RedAnchor"
#define SNAPSHOT_VALID_WINDOW 1.5
#define INCAP_ANNOUNCE_DELAY 0.45
#define INCAP_KILL_SUPPRESS_WINDOW 1.20

enum AttackerKind
{
    Attacker_Unknown = 0,
    Attacker_Survivor,
    Attacker_SI,
    Attacker_CI
}

ConVar g_hEnable;
bool g_bEnable;

int g_iAnchorUserId;
Handle g_hAnchorTimer;

int g_iLastAttacker[MAXPLAYERS + 1];
int g_iLastInflictor[MAXPLAYERS + 1];
int g_iLastWeapon[MAXPLAYERS + 1];
int g_iLastDmgType[MAXPLAYERS + 1];
float g_fLastDmgTime[MAXPLAYERS + 1];
float g_fLastMolotovThrow[MAXPLAYERS + 1];
bool g_bIsIncappedState[MAXPLAYERS + 1];
float g_fLastIncapTime[MAXPLAYERS + 1];

Handle g_hIncapTimer[MAXPLAYERS + 1];
bool g_bPendingIncap[MAXPLAYERS + 1];
int g_iPendingAttackerClient[MAXPLAYERS + 1];
int g_iPendingAttackerEnt[MAXPLAYERS + 1];
int g_iPendingDmgType[MAXPLAYERS + 1];
float g_fPendingIncapTime[MAXPLAYERS + 1];
char g_sPendingWeapon[MAXPLAYERS + 1][64];

bool g_bHasEliteNative;

public Plugin myinfo =
{
    name = "L4D2 Death/Incap Red Announce",
    author = "Codex + Tuan",
    description = "Announce survivor death/incap with red chat using SI anchor",
    version = PLUGIN_VERSION,
    url = "https://github.com/alliedmodders/sourcemod"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("L4D2_IsEliteSI");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_hEnable = CreateConVar("l4d2_redannounce_enable", "1", "Enable red death/incap announce plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hEnable.AddChangeHook(OnCvarChanged);
    g_bEnable = g_hEnable.BoolValue;

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_incapacitated_start", Event_PlayerIncapStart, EventHookMode_Post);
    HookEvent("revive_success", Event_ReviveSuccess, EventHookMode_Post);
    HookEvent("weapon_fire", Event_WeaponFire, EventHookMode_Post);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
        }
    }

    g_hAnchorTimer = CreateTimer(5.0, Timer_MaintainAnchor, _, TIMER_REPEAT);
    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);

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

    int anchor = GetClientOfUserId(g_iAnchorUserId);
    if (anchor > 0 && anchor <= MaxClients && IsClientInGame(anchor) && IsFakeClient(anchor))
    {
        KickClient(anchor, "Removing anchor bot");
    }
}

public void OnMapStart()
{
    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);
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
    g_bIsIncappedState[client] = false;
    g_fLastIncapTime[client] = 0.0;
}

public void OnCvarChanged(ConVar cvar, const char[] oldValue, const char[] newValue)
{
    g_bEnable = g_hEnable.BoolValue;
}

public Action Timer_DelayedEnsureAnchor(Handle timer)
{
    if (g_bEnable)
    {
        EnsureAnchorClient();
    }
    return Plugin_Stop;
}

public Action Timer_MaintainAnchor(Handle timer)
{
    if (g_bEnable)
    {
        EnsureAnchorClient();
    }
    return Plugin_Continue;
}

public Action OnTakeDamageAlive(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
    if (!IsValidSurvivor(victim))
    {
        return Plugin_Continue;
    }

    g_iLastAttacker[victim] = attacker;
    g_iLastInflictor[victim] = inflictor;
    g_iLastWeapon[victim] = weapon;
    g_iLastDmgType[victim] = damagetype;
    g_fLastDmgTime[victim] = GetGameTime();

    return Plugin_Continue;
}

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

void Event_WeaponFire(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (!IsInGameClient(client) || GetClientTeam(client) != 2)
    {
        return;
    }

    char weapon[64];
    event.GetString("weapon", weapon, sizeof(weapon));
    if (StrContains(weapon, "molotov", false) != -1)
    {
        g_fLastMolotovThrow[client] = GetGameTime();
    }
}

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

    if (IsInGameClient(victim) && GetClientTeam(victim) == 3 && IsInGameClient(attackerClient) && GetClientTeam(attackerClient) == 2 && attackerClient != victim)
    {
        char attackerName[64];
        char victimSiName[64];
        char cause[64];
        char line[128];
        GetCleanClientName(attackerClient, attackerName, sizeof(attackerName));
        GetSpecialInfectedName(victim, victimSiName, sizeof(victimSiName));
        ResolveSurvivorKillSICause(attackerClient, attackerEnt, weapon, dmgType, cause, sizeof(cause));
        Format(line, sizeof(line), "%s killed %s", attackerName, victimSiName);
        PrintBlueAllWithOliveCause(attackerClient, line, cause);
        return;
    }

    if (!IsValidSurvivor(victim))
    {
        return;
    }

    bool bleedingOut = IsBleedingOutDeath(victim, attackerClient, attackerEnt, weapon, dmgType);

    if (g_bPendingIncap[victim] && (GetGameTime() - g_fPendingIncapTime[victim]) <= INCAP_KILL_SUPPRESS_WINDOW)
    {
        ClearPendingIncap(victim);
    }

    g_bIsIncappedState[victim] = false;

    PrintOutcome(victim, attackerClient, attackerEnt, weapon, dmgType, false, bleedingOut);
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
        char line[128];
        GetCleanClientName(victim, victimName, sizeof(victimName));
        Format(line, sizeof(line), "%s died", victimName);
        PrintRedAllWithOliveCause(line, "bleeding out");
        return;
    }

    if (isSelf || kind == Attacker_Unknown)
    {
        char victimName[64];
        char line[128];
        GetCleanClientName(victim, victimName, sizeof(victimName));

        if (incap)
        {
            Format(line, sizeof(line), "%s incapped himself", victimName);
            PrintRedAllWithOliveCause(line, cause);
        }
        else
        {
            Format(line, sizeof(line), "%s suicided", victimName);
            PrintRedAllWithOliveCause(line, cause);
        }
        return;
    }

    char victimName[64];
    char line[128];
    GetCleanClientName(victim, victimName, sizeof(victimName));

    if (kind == Attacker_CI)
    {
        if (incap)
        {
            Format(line, sizeof(line), "Common Infected incapped %s", victimName);
            PrintRedAllWithOliveCause(line, cause);
        }
        else
        {
            Format(line, sizeof(line), "Common Infected killed %s", victimName);
            PrintRedAllWithOliveCause(line, cause);
        }
        return;
    }

    if (incap)
    {
        Format(line, sizeof(line), "%s incapped %s", attackerLabel, victimName);
        PrintRedAllWithOliveCause(line, cause);
    }
    else
    {
        Format(line, sizeof(line), "%s killed %s", attackerLabel, victimName);
        PrintRedAllWithOliveCause(line, cause);
    }
}

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
            strcopy(cause, maxlen, "physical");
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

bool ResolveSurvivorCause(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, char[] cause, int maxlen)
{
    char baseWeapon[64];
    bool hasBaseWeapon = GetBestWeaponLabel(victim, eventWeapon, baseWeapon, sizeof(baseWeapon));
    if (hasBaseWeapon && StrEqual(baseWeapon, "Pistol", false) && IsDualPistolContext(victim, attackerClient))
    {
        strcopy(baseWeapon, sizeof(baseWeapon), "Dual Pistols");
    }

    bool fire = IsFireCause(eventWeapon, dmgType) || IsFireFromEntities(victim, attackerEnt);
    bool explosive = IsExplosiveCause(eventWeapon, dmgType) || IsExplosiveFromEntities(victim, attackerEnt);

    if (fire)
    {
        if (IsGascanSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "gascan");
            return true;
        }
        if (IsFireworkSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "firework crate");
            return true;
        }
        if (IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "fuel barrel");
            return true;
        }
        if (IsMolotovSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "molotov");
            return true;
        }
        if (IsLikelyGascanInferno(victim, attackerClient, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "gascan");
            return true;
        }
        if (hasBaseWeapon && IsGenericFireLabel(baseWeapon))
        {
            strcopy(cause, maxlen, "fire");
            return true;
        }
        if (hasBaseWeapon)
        {
            Format(cause, maxlen, "%s + fire bullet", baseWeapon);
            return true;
        }

        strcopy(cause, maxlen, "fire");
        return true;
    }

    if (explosive)
    {
        if (IsPipeBombSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "pipebomb");
            return true;
        }
        if (IsFireworkSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "firework crate");
            return true;
        }
        if (IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "fuel barrel");
            return true;
        }
        if (IsGascanSource(victim, attackerEnt, eventWeapon))
        {
            strcopy(cause, maxlen, "gascan");
            return true;
        }
        if (hasBaseWeapon)
        {
            Format(cause, maxlen, "%s + explosive bullet", baseWeapon);
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

void ResolveSurvivorKillSICause(int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, char[] cause, int maxlen)
{
    char baseWeapon[64];
    bool hasBaseWeapon = false;

    if (FormatWeaponName(eventWeapon, baseWeapon, sizeof(baseWeapon)))
    {
        hasBaseWeapon = true;
    }
    else
    {
        int active = GetEntPropEnt(attackerClient, Prop_Send, "m_hActiveWeapon");
        if (IsValidEdict(active))
        {
            char cls[64];
            GetEntityClassname(active, cls, sizeof(cls));
            if (FormatWeaponName(cls, baseWeapon, sizeof(baseWeapon)))
            {
                hasBaseWeapon = true;
            }
        }
    }

    if (hasBaseWeapon && StrEqual(baseWeapon, "Pistol", false) && IsDualPistolContext(0, attackerClient))
    {
        strcopy(baseWeapon, sizeof(baseWeapon), "Dual Pistols");
    }

    bool fire = IsFireCause(eventWeapon, dmgType) || EntityClassMatches(attackerEnt, "inferno") || EntityClassMatches(attackerEnt, "entityflame");
    bool explosive = IsExplosiveCause(eventWeapon, dmgType) || EntityClassMatches(attackerEnt, "pipe_bomb_projectile") || EntityClassMatches(attackerEnt, "grenade_launcher_projectile");

    if (fire)
    {
        if (EntityIsGascan(attackerEnt) || LinkedEntityIsGascan(attackerEnt))
        {
            strcopy(cause, maxlen, "gascan");
            return;
        }
        if (EntityClassMatches(attackerEnt, "fire_cracker_blast") || EntityClassMatches(attackerEnt, "firework"))
        {
            strcopy(cause, maxlen, "firework crate");
            return;
        }
        if (EntityClassMatches(attackerEnt, "fuel_barrel") || EntityIsFuelBarrel(attackerEnt))
        {
            strcopy(cause, maxlen, "fuel barrel");
            return;
        }
        if (StrContains(eventWeapon, "molotov", false) != -1 || EntityIsMolotovProjectile(attackerEnt))
        {
            strcopy(cause, maxlen, "molotov");
            return;
        }
        if (hasBaseWeapon && !IsGenericFireLabel(baseWeapon))
        {
            Format(cause, maxlen, "%s + fire bullet", baseWeapon);
            return;
        }

        strcopy(cause, maxlen, "fire");
        return;
    }

    if (explosive)
    {
        if (StrContains(eventWeapon, "pipe", false) != -1 || EntityClassMatches(attackerEnt, "pipe_bomb_projectile"))
        {
            strcopy(cause, maxlen, "pipebomb");
            return;
        }
        if (EntityClassMatches(attackerEnt, "fire_cracker_blast") || EntityClassMatches(attackerEnt, "firework"))
        {
            strcopy(cause, maxlen, "firework crate");
            return;
        }
        if (EntityClassMatches(attackerEnt, "fuel_barrel"))
        {
            strcopy(cause, maxlen, "fuel barrel");
            return;
        }
        if (EntityIsGascan(attackerEnt))
        {
            strcopy(cause, maxlen, "gascan");
            return;
        }
        if (hasBaseWeapon)
        {
            Format(cause, maxlen, "%s + explosive bullet", baseWeapon);
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

bool IsMolotovSource(int victim, int attackerEnt, const char[] eventWeapon)
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

    if (!HasRecentSnapshot(victim))
    {
        return false;
    }

    if (EntityIsMolotovProjectile(g_iLastInflictor[victim]) || EntityIsMolotovProjectile(g_iLastWeapon[victim]))
    {
        return true;
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

bool ResolveSpecialInfectedCause(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, char[] cause, int maxlen)
{
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
                strcopy(cause, maxlen, (pummel == attackerClient || carry == attackerClient) ? "Charger pump" : "Charger claws");
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

void GetSpecialInfectedName(int client, char[] outName, int maxlen)
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

    if (IsEliteSI(client))
    {
        Format(outName, maxlen, "Elite %s", baseName);
    }
    else
    {
        strcopy(outName, maxlen, baseName);
    }
}

void PrintRedAll(const char[] fmt, any ...)
{
    char msg[256];
    VFormat(msg, sizeof(msg), fmt, 2);

    int author = EnsureAnchorClient();
    if (author <= 0 || author > MaxClients || !IsClientInGame(author) || GetClientTeam(author) != 3)
    {
        PrintToChatAll("%s", msg);
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        CPrintToChatEx(i, author, "{teamcolor}%s{default}", msg);
    }
}

void PrintRedAllWithOliveCause(const char[] messageWithoutCause, const char[] cause)
{
    int author = EnsureAnchorClient();
    if (author <= 0 || author > MaxClients || !IsClientInGame(author) || GetClientTeam(author) != 3)
    {
        PrintToChatAll("%s (%s)", messageWithoutCause, cause);
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        CPrintToChatEx(i, author, "{teamcolor}%s {default}({olive}%s{default})", messageWithoutCause, cause);
    }
}

void PrintBlueAllWithOliveCause(int blueAuthor, const char[] messageWithoutCause, const char[] cause)
{
    int author = blueAuthor;
    if (!IsInGameClient(author) || GetClientTeam(author) != 2)
    {
        author = 0;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        if (author > 0)
        {
            CPrintToChatEx(i, author, "{teamcolor}%s {default}({olive}%s{default})", messageWithoutCause, cause);
        }
        else
        {
            CPrintToChat(i, "{lightblue}%s {default}({olive}%s{default})", messageWithoutCause, cause);
        }
    }
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

bool IsInGameClient(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client));
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

bool EntityIsGascan(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "gascan", false) != -1)
    {
        return true;
    }

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "gascan", false) != -1)
        {
            return true;
        }
    }

    return false;
}

bool EntityIsMolotovProjectile(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    return StrContains(cls, "molotov", false) != -1;
}

bool LinkedEntityIsGascan(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    int owner = GetLinkedEntity(entity, "m_hOwnerEntity");
    if (EntityIsGascan(owner))
    {
        return true;
    }

    int parent = GetLinkedEntity(entity, "m_hMoveParent");
    if (EntityIsGascan(parent))
    {
        return true;
    }

    int effect = GetLinkedEntity(entity, "m_hEffectEntity");
    if (EntityIsGascan(effect))
    {
        return true;
    }

    return false;
}

bool EntityIsFireworkCrate(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "firework", false) != -1 || StrContains(cls, "fire_cracker", false) != -1)
    {
        return true;
    }

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "firework", false) != -1 || StrContains(model, "fire_cracker", false) != -1)
        {
            return true;
        }
    }

    return false;
}

bool EntityIsFuelBarrel(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "fuel_barrel", false) != -1)
    {
        return true;
    }

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "fuel_barrel", false) != -1)
        {
            return true;
        }
    }

    return false;
}

bool IsGenericFireLabel(const char[] label)
{
    return (
        StrEqual(label, "Inferno", false) ||
        StrEqual(label, "Entityflame", false) ||
        StrEqual(label, "Fire", false)
    );
}

bool WasRecentMolotovThrow(int client, float window)
{
    if (!IsInGameClient(client) || GetClientTeam(client) != 2)
    {
        return false;
    }

    float t = g_fLastMolotovThrow[client];
    if (t <= 0.0)
    {
        return false;
    }

    return (GetGameTime() - t) <= window;
}

bool IsLikelyGascanInferno(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon)
{
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return false;
    }

    bool infernoLike = (StrContains(eventWeapon, "inferno", false) != -1 || StrContains(eventWeapon, "entityflame", false) != -1 || EntityClassMatches(attackerEnt, "inferno") || EntityClassMatches(attackerEnt, "entityflame"));
    if (!infernoLike)
    {
        return false;
    }

    if (WasRecentMolotovThrow(attackerClient, 12.0))
    {
        return false;
    }

    if (IsFireworkSource(victim, attackerEnt, eventWeapon) || IsFuelBarrelSource(victim, attackerEnt, eventWeapon))
    {
        return false;
    }

    return true;
}

void GetCleanClientName(int client, char[] outName, int maxlen)
{
    GetClientName(client, outName, maxlen);
    TrimString(outName);

    if (outName[0] != '(')
    {
        return;
    }

    int close = FindCharInString(outName, ')');
    if (close <= 1 || close >= strlen(outName) - 1)
    {
        return;
    }

    bool allDigits = true;
    for (int i = 1; i < close; i++)
    {
        if (!IsCharNumeric(outName[i]))
        {
            allDigits = false;
            break;
        }
    }

    if (!allDigits)
    {
        return;
    }

    int start = close + 1;
    while (start < strlen(outName) && outName[start] == ' ')
    {
        start++;
    }

    if (start < strlen(outName))
    {
        strcopy(outName, maxlen, outName[start]);
    }
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

    if (HasEntProp(entity, Prop_Data, prop))
    {
        return GetEntPropEnt(entity, Prop_Data, prop);
    }

    if (HasEntProp(entity, Prop_Send, prop))
    {
        return GetEntPropEnt(entity, Prop_Send, prop);
    }

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
