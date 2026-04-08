#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

#define PLUGIN_VERSION "1.0.0"
#define ANCHOR_NAME "SI_RedAnchor"
#define SNAPSHOT_VALID_WINDOW 1.5

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

public Plugin myinfo =
{
    name = "L4D2 Death/Incap Red Announce",
    author = "Codex + Tuan",
    description = "Announce survivor death/incap with red chat using SI anchor",
    version = PLUGIN_VERSION,
    url = "https://github.com/alliedmodders/sourcemod"
};

public void OnPluginStart()
{
    g_hEnable = CreateConVar("l4d2_redannounce_enable", "1", "Enable red death/incap announce plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_hEnable.AddChangeHook(OnCvarChanged);
    g_bEnable = g_hEnable.BoolValue;

    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_incapacitated_start", Event_PlayerIncapStart, EventHookMode_Post);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
        }
    }

    g_hAnchorTimer = CreateTimer(5.0, Timer_MaintainAnchor, _, TIMER_REPEAT);
    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnPluginEnd()
{
    if (g_hAnchorTimer != null)
    {
        delete g_hAnchorTimer;
        g_hAnchorTimer = null;
    }

    int anchor = GetClientOfUserId(g_iAnchorUserId);
    if (IsClientInGame(anchor) && IsFakeClient(anchor))
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

    PrintOutcome(victim, attackerClient, attackerEnt, weapon, dmgType, true);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
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

    PrintOutcome(victim, attackerClient, attackerEnt, weapon, dmgType, false);
}

void PrintOutcome(int victim, int attackerClient, int attackerEnt, const char[] eventWeapon, int dmgType, bool incap)
{
    char attackerLabel[64];
    bool isSelf = false;

    AttackerKind kind = ResolveAttacker(victim, attackerClient, attackerEnt, dmgType, eventWeapon, attackerLabel, sizeof(attackerLabel), isSelf);

    char cause[64];
    ResolveCause(victim, eventWeapon, dmgType, attackerClient, attackerEnt, cause, sizeof(cause));

    if (isSelf || kind == Attacker_Unknown)
    {
        if (incap)
        {
            PrintRedAll("[%N] has incapacitated himself (%s).", victim, cause);
        }
        else
        {
            PrintRedAll("[%N] has suicide (%s).", victim, cause);
        }
        return;
    }

    if (kind == Attacker_CI)
    {
        if (incap)
        {
            PrintRedAll("Common Infected has incapacitated [%N] (%s).", victim, cause);
        }
        else
        {
            PrintRedAll("Common Infected has killed [%N] (%s).", victim, cause);
        }
        return;
    }

    if (incap)
    {
        PrintRedAll("%s has incapacitated [%N] (%s).", attackerLabel, victim, cause);
    }
    else
    {
        PrintRedAll("%s has killed [%N] (%s).", attackerLabel, victim, cause);
    }
}

AttackerKind ResolveAttacker(int victim, int attackerClient, int attackerEnt, int dmgType, const char[] eventWeapon, char[] attackerLabel, int maxlen, bool &isSelf)
{
    isSelf = false;

    if (IsClientInGame(attackerClient))
    {
        if (attackerClient == victim)
        {
            isSelf = true;
            Format(attackerLabel, maxlen, "[%N]", victim);
            return Attacker_Survivor;
        }

        int team = GetClientTeam(attackerClient);
        if (team == 2)
        {
            Format(attackerLabel, maxlen, "[%N]", attackerClient);
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

        if (IsClientInGame(snapAttacker))
        {
            if (snapAttacker == victim)
            {
                isSelf = true;
                Format(attackerLabel, maxlen, "[%N]", victim);
                return Attacker_Survivor;
            }

            int team2 = GetClientTeam(snapAttacker);
            if (team2 == 2)
            {
                Format(attackerLabel, maxlen, "[%N]", snapAttacker);
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
        Format(attackerLabel, maxlen, "[%N]", victim);
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
    if (IsClientInGame(owner) && GetClientTeam(owner) == 3)
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

void ResolveCause(int victim, const char[] eventWeapon, int dmgType, int attackerClient, int attackerEnt, char[] cause, int maxlen)
{
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

    if (IsClientInGame(attackerClient) && GetClientTeam(attackerClient) == 3)
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

    if (StrEqual(weapon, "none") || StrEqual(weapon, "world") || StrEqual(weapon, "trigger_hurt"))
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
    if (StrEqual(weapon, "tank_claw"))
    {
        strcopy(output, maxlen, "tank claws");
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

void GetSpecialInfectedName(int client, char[] outName, int maxlen)
{
    int zclass = GetEntProp(client, Prop_Send, "m_zombieClass");
    switch (zclass)
    {
        case 1: strcopy(outName, maxlen, "Smoker");
        case 2: strcopy(outName, maxlen, "Boomer");
        case 3: strcopy(outName, maxlen, "Hunter");
        case 4: strcopy(outName, maxlen, "Spitter");
        case 5: strcopy(outName, maxlen, "Jockey");
        case 6: strcopy(outName, maxlen, "Charger");
        case 8: strcopy(outName, maxlen, "Tank");
        default: strcopy(outName, maxlen, "Special Infected");
    }
}

void PrintRedAll(const char[] fmt, any ...)
{
    char msg[256];
    VFormat(msg, sizeof(msg), fmt, 2);

    int author = EnsureAnchorClient();
    if (!IsClientInGame(author) || GetClientTeam(author) != 3)
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

        CPrintToChatEx(i, author, "{red}%s{default}", msg);
    }
}

int EnsureAnchorClient()
{
    int anchor = GetClientOfUserId(g_iAnchorUserId);
    if (IsClientInGame(anchor) && IsFakeClient(anchor) && GetClientTeam(anchor) == 3)
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
