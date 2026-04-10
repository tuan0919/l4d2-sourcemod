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
#define HAZARD_CONTEXT_WINDOW 4.0
#define MAX_TRACKED_EDICTS 2048  // L4D2's max entities - no +1 needed for int arrays
#define MAX_SOURCE_EVENTS 128
#define FIRE_SOURCE_MATCH_WINDOW 6.0
#define FIRE_SOURCE_MAX_DIST 350.0

enum AttackerKind
{
    Attacker_Unknown = 0,
    Attacker_Survivor,
    Attacker_SI,
    Attacker_CI
}

enum HazardType
{
    Hazard_None = 0,
    Hazard_Molotov,
    Hazard_Gascan,
    Hazard_Firework,
    Hazard_FuelBarrel,
    Hazard_PropaneTank,
    Hazard_OxygenTank
}

ConVar g_hEnable;
bool g_bEnable;

int g_iAnchorUserId;
Handle g_hAnchorTimer;
Handle g_hBurnWatchTimer;

int g_iLastAttacker[MAXPLAYERS + 1];
int g_iLastInflictor[MAXPLAYERS + 1];
int g_iLastWeapon[MAXPLAYERS + 1];
int g_iLastDmgType[MAXPLAYERS + 1];
float g_fLastDmgTime[MAXPLAYERS + 1];
float g_fLastMolotovThrow[MAXPLAYERS + 1];
int g_iLastHazardType[MAXPLAYERS + 1];
float g_fLastHazardTime[MAXPLAYERS + 1];
int g_iLastHazardEntityRef[MAXPLAYERS + 1];
int g_iLastFireAssistType[MAXPLAYERS + 1];
int g_iLastFireAssistOwner[MAXPLAYERS + 1];
float g_fLastFireAssistTime[MAXPLAYERS + 1];
bool g_bFireAssistLocked[MAXPLAYERS + 1];
bool g_bIsIncappedState[MAXPLAYERS + 1];
float g_fLastIncapTime[MAXPLAYERS + 1];
float g_fLastIncendiaryShot[MAXPLAYERS + 1];
float g_fLastExplosiveShot[MAXPLAYERS + 1];
char g_sLastSpecialBulletWeapon[MAXPLAYERS + 1][64];

Handle g_hIncapTimer[MAXPLAYERS + 1];
bool g_bPendingIncap[MAXPLAYERS + 1];
int g_iPendingAttackerClient[MAXPLAYERS + 1];
int g_iPendingAttackerEnt[MAXPLAYERS + 1];
int g_iPendingDmgType[MAXPLAYERS + 1];
float g_fPendingIncapTime[MAXPLAYERS + 1];
char g_sPendingWeapon[MAXPLAYERS + 1][64];

bool g_bHasEliteNative;
bool g_bHazardHooked[MAX_TRACKED_EDICTS];
int g_iHazardEntType[MAX_TRACKED_EDICTS];
int g_iHazardLastOwner[MAX_TRACKED_EDICTS];
float g_fHazardLastHitTime[MAX_TRACKED_EDICTS];
float g_vHazardLastPos[MAX_TRACKED_EDICTS][3];
bool g_bMolotovProjectile[MAX_TRACKED_EDICTS];
int g_iMolotovOwner[MAX_TRACKED_EDICTS];
float g_vMolotovLastPos[MAX_TRACKED_EDICTS][3];
int g_iFireEntSourceType[MAX_TRACKED_EDICTS];
int g_iFireEntOwner[MAX_TRACKED_EDICTS];
float g_fFireEntMarkTime[MAX_TRACKED_EDICTS];
int g_iSourceType[MAX_SOURCE_EVENTS];
int g_iSourceOwner[MAX_SOURCE_EVENTS];
float g_fSourceTime[MAX_SOURCE_EVENTS];
float g_vSourcePos[MAX_SOURCE_EVENTS][3];
int g_iSourceWrite;

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
    HookEvent("witch_killed", Event_WitchKilled, EventHookMode_Post);

    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamageAlive, OnTakeDamageAlive);
        }
    }

    // OPTIMIZED: Combined timers - 2 timers instead of 4
    g_hAnchorTimer = CreateTimer(5.0, Timer_ConsolidatedUpdate, _, TIMER_REPEAT);
    g_hBurnWatchTimer = CreateTimer(0.25, Timer_ConsolidatedUpdate, _, TIMER_REPEAT);
    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(2.0, Timer_HookExistingHazards, _, TIMER_FLAG_NO_MAPCHANGE);

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

    if (g_hBurnWatchTimer != null)
    {
        delete g_hBurnWatchTimer;
        g_hBurnWatchTimer = null;
    }

    int anchor = GetClientOfUserId(g_iAnchorUserId);
    if (anchor > 0 && anchor <= MaxClients && IsClientInGame(anchor) && IsFakeClient(anchor))
    {
        KickClient(anchor, "Removing anchor bot");
    }
}

public void OnMapStart()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        g_iLastFireAssistType[i] = view_as<int>(Hazard_None);
        g_iLastFireAssistOwner[i] = 0;
        g_fLastFireAssistTime[i] = 0.0;
        g_bFireAssistLocked[i] = false;
        g_fLastIncendiaryShot[i] = 0.0;
        g_fLastExplosiveShot[i] = 0.0;
        g_sLastSpecialBulletWeapon[i][0] = '\0';
    }

    for (int i = 0; i < MAX_TRACKED_EDICTS; i++)
    {
        g_bHazardHooked[i] = false;
        g_iHazardEntType[i] = view_as<int>(Hazard_None);
        g_iHazardLastOwner[i] = 0;
        g_fHazardLastHitTime[i] = 0.0;
        g_vHazardLastPos[i][0] = 0.0;
        g_vHazardLastPos[i][1] = 0.0;
        g_vHazardLastPos[i][2] = 0.0;
        g_bMolotovProjectile[i] = false;
        g_iMolotovOwner[i] = 0;
        g_vMolotovLastPos[i][0] = 0.0;
        g_vMolotovLastPos[i][1] = 0.0;
        g_vMolotovLastPos[i][2] = 0.0;
        g_iFireEntSourceType[i] = view_as<int>(Hazard_None);
        g_iFireEntOwner[i] = 0;
        g_fFireEntMarkTime[i] = 0.0;
    }

    for (int i = 0; i < MAX_SOURCE_EVENTS; i++)
    {
        g_iSourceType[i] = view_as<int>(Hazard_None);
        g_iSourceOwner[i] = 0;
        g_fSourceTime[i] = 0.0;
        g_vSourcePos[i][0] = 0.0;
        g_vSourcePos[i][1] = 0.0;
        g_vSourcePos[i][2] = 0.0;
    }
    g_iSourceWrite = 0;

    CreateTimer(1.0, Timer_DelayedEnsureAnchor, _, TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(2.0, Timer_HookExistingHazards, _, TIMER_FLAG_NO_MAPCHANGE);
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
    g_iLastHazardType[client] = view_as<int>(Hazard_None);
    g_fLastHazardTime[client] = 0.0;
    g_iLastHazardEntityRef[client] = INVALID_ENT_REFERENCE;
    g_iLastFireAssistType[client] = view_as<int>(Hazard_None);
    g_iLastFireAssistOwner[client] = 0;
    g_fLastFireAssistTime[client] = 0.0;
    g_bFireAssistLocked[client] = false;
    g_bIsIncappedState[client] = false;
    g_fLastIncapTime[client] = 0.0;
    g_fLastIncendiaryShot[client] = 0.0;
    g_fLastExplosiveShot[client] = 0.0;
    g_sLastSpecialBulletWeapon[client][0] = '\0';
}

public void OnEntityCreated(int entity, const char[] classname)
{
    if (entity <= MaxClients || entity >= MAX_TRACKED_EDICTS)
    {
        return;
    }

    if (StrContains(classname, "molotov_projectile", false) != -1)
    {
        g_bMolotovProjectile[entity] = true;
        RequestFrame(Frame_InitMolotovProjectile, EntIndexToEntRef(entity));
        return;
    }

    if (StrContains(classname, "inferno", false) != -1 || StrContains(classname, "entityflame", false) != -1)
    {
        RequestFrame(Frame_MarkFireEntitySource, EntIndexToEntRef(entity));
        return;
    }

    if (!ClassnameLooksHazard(classname))
    {
        return;
    }

    RequestFrame(Frame_DelayedHookHazard, EntIndexToEntRef(entity));
}

public void OnEntityDestroyed(int entity)
{
    if (entity > 0 && entity < MAX_TRACKED_EDICTS)
    {
        g_bHazardHooked[entity] = false;

        if (g_iHazardEntType[entity] != view_as<int>(Hazard_None))
        {
            int owner = 0;
            if ((GetGameTime() - g_fHazardLastHitTime[entity]) <= 3.0)
            {
                owner = g_iHazardLastOwner[entity];
            }
            AddSourceEvent(view_as<HazardType>(g_iHazardEntType[entity]), g_vHazardLastPos[entity], owner);
        }

        if (g_bMolotovProjectile[entity])
        {
            AddSourceEvent(Hazard_Molotov, g_vMolotovLastPos[entity], g_iMolotovOwner[entity]);
        }

        g_iHazardEntType[entity] = view_as<int>(Hazard_None);
        g_iHazardLastOwner[entity] = 0;
        g_fHazardLastHitTime[entity] = 0.0;
        g_vHazardLastPos[entity][0] = 0.0;
        g_vHazardLastPos[entity][1] = 0.0;
        g_vHazardLastPos[entity][2] = 0.0;
        g_bMolotovProjectile[entity] = false;
        g_iMolotovOwner[entity] = 0;
        g_vMolotovLastPos[entity][0] = 0.0;
        g_vMolotovLastPos[entity][1] = 0.0;
        g_vMolotovLastPos[entity][2] = 0.0;
        g_iFireEntSourceType[entity] = view_as<int>(Hazard_None);
        g_iFireEntOwner[entity] = 0;
        g_fFireEntMarkTime[entity] = 0.0;
    }
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

// OPTIMIZED: Consolidated timer - handles both anchor maintenance and fire state watching
public Action Timer_ConsolidatedUpdate(Handle timer)
{
    if (!g_bEnable)
    {
        return Plugin_Continue;
    }

    // Watch burn state (0.25s interval - 4x per second)
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

        if (!IsClientCurrentlyOnFire(client))
        {
            g_bFireAssistLocked[client] = false;
            g_iLastFireAssistType[client] = view_as<int>(Hazard_None);
            g_iLastFireAssistOwner[client] = 0;
            g_fLastFireAssistTime[client] = 0.0;
        }
    }

    // Maintain anchor (every 5th tick of this timer = 1.25s interval)
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

    // OPTIMIZED: Early guard clauses with inverted logic
    if (!IsInGameClient(victim) || GetClientTeam(victim) != 3)
    {
        return;
    }

    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2 || attackerClient == victim)
    {
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
        return;
    }

    // Survivor killed SI - OPTIMIZED: Combined string lookups
    char attackerName[64];
    char victimName[64];
    char cause[192];
    char line[128];

    GetCleanClientName(attackerClient, attackerName, sizeof(attackerName));
    GetClientName(victim, victimName, sizeof(victimName));

    ResolveSurvivorKillSICause(victim, attackerClient, attackerEnt, weapon, dmgType, cause, sizeof(cause));
    ApplySurvivorKillQualifiers(attackerClient, victim, weapon, dmgType, headshot, wallbang, cause, sizeof(cause));

    Format(line, sizeof(line), "%s killed %s", attackerName, victimName);
    PrintBlueAllWithOliveCause(attackerClient, line, cause);
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
    char line[128];
    GetCleanClientName(attackerClient, attackerName, sizeof(attackerName));
    ResolveWitchKillCause(attackerClient, cause, sizeof(cause));
    Format(line, sizeof(line), "%s killed Witch", attackerName);
    PrintBlueAllWithOliveCause(attackerClient, line, cause);
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
        if (GetRecentFireAssist(victim, attackerClient, assistType))
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
        if (infernoLike && WasRecentMolotovThrow(attackerClient, 20.0))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "molotov", cause, maxlen);
            return;
        }
        if (EntityIsGascan(attackerEnt) || LinkedEntityIsGascan(attackerEnt))
        {
            BuildPrimaryCause(baseWeapon, bulletFireState, true, "gascan", cause, maxlen);
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
        if (TryCauseFromHazardContext(attackerClient, cause, maxlen))
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
        if (TryResolveRecentSpecialBullet(attackerClient, true, baseWeapon, sizeof(baseWeapon), hasBaseWeapon))
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
        if (TryCauseFromHazardContext(attackerClient, cause, maxlen))
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
        if (TryResolveRecentSpecialBullet(attackerClient, false, baseWeapon, sizeof(baseWeapon), hasBaseWeapon))
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

    if (TryCauseFromHazardContext(attackerClient, cause, maxlen))
    {
        return;
    }

    if (WasRecentMolotovThrow(attackerClient, 20.0))
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

    if (IsVictimStaggered(victimClient))
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

// OPTIMIZED: Simplified print functions with direct string concatenation
void PrintRedAll(const char[] fmt, any ...)
{
    char msg[256];
    VFormat(msg, sizeof(msg), fmt, 2);

    int author = EnsureAnchorClient();

    // OPTIMIZED: Single pass through clients
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

        // OPTIMIZED: Direct format instead of CPrintToChatEx
        CPrintToChat(i, "{red}%s{default}", msg);
    }
}

void PrintRedAllWithOliveCause(const char[] messageWithoutCause, const char[] cause)
{
    int author = EnsureAnchorClient();

    // OPTIMIZED: Single pass through clients, direct formatting
    if (author <= 0 || author > MaxClients || !IsClientInGame(author) || GetClientTeam(author) != 3)
    {
        PrintToChatAll("%s {default}({olive}%s{default})", messageWithoutCause, cause);
        return;
    }

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || IsFakeClient(i))
        {
            continue;
        }

        CPrintToChat(i, "{red}%s {default}({olive}%s{default})", messageWithoutCause, cause);
    }
}

void PrintBlueAllWithOliveCause(int blueAuthor, const char[] messageWithoutCause, const char[] cause)
{
    int author = blueAuthor;
    if (!IsInGameClient(author) || GetClientTeam(author) != 2)
    {
        author = 0;
    }

    if (author > 0)
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || IsFakeClient(i))
            {
                continue;
            }

            CPrintToChatEx(i, author, "{teamcolor}%s {default}({olive}%s{default})", messageWithoutCause, cause);
        }
    }
    else
    {
        for (int i = 1; i <= MaxClients; i++)
        {
            if (!IsClientInGame(i) || IsFakeClient(i))
            {
                continue;
            }

            CPrintToChat(i, "{lightblue}%s {default}({olive}%s{default})", messageWithoutCause, cause);
        }
    }
}

void FormatCauseForChatColors(const char[] cause, char[] outCause, int maxlen)
{
    strcopy(outCause, maxlen, cause);
    ReplaceString(outCause, maxlen, "/", "{default}/{olive}", false);
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

bool IsTrackableVictim(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    int team = GetClientTeam(client);
    return (team == 2 || team == 3);
}

bool GetRecentFireAssist(int victimClient, int attackerClient, HazardType &type)
{
    type = Hazard_None;
    if (victimClient <= 0 || victimClient > MaxClients)
    {
        return false;
    }

    if (g_iLastFireAssistOwner[victimClient] != attackerClient)
    {
        return false;
    }

    if (!g_bFireAssistLocked[victimClient])
    {
        return false;
    }

    type = view_as<HazardType>(g_iLastFireAssistType[victimClient]);
    return type != Hazard_None;
}

void AppendCauseToken(char[] cause, int maxlen, const char[] token)
{
    if (token[0] == '\0')
    {
        return;
    }

    if (cause[0] == '\0')
    {
        strcopy(cause, maxlen, token);
        return;
    }

    if (StrContains(cause, token, false) != -1)
    {
        return;
    }

    char merged[256];
    Format(merged, sizeof(merged), "%s/%s", cause, token);
    strcopy(cause, maxlen, merged);
}

bool TryResolveRecentSpecialBullet(int attackerClient, bool fireBullet, char[] baseWeapon, int maxlen, bool &hasBaseWeapon)
{
    if (!IsInGameClient(attackerClient) || GetClientTeam(attackerClient) != 2)
    {
        return false;
    }

    float now = GetGameTime();
    float t = fireBullet ? g_fLastIncendiaryShot[attackerClient] : g_fLastExplosiveShot[attackerClient];
    if (t <= 0.0 || (now - t) > 6.0)
    {
        return false;
    }

    if (!hasBaseWeapon)
    {
        if (g_sLastSpecialBulletWeapon[attackerClient][0] != '\0')
        {
            strcopy(baseWeapon, maxlen, g_sLastSpecialBulletWeapon[attackerClient]);
            hasBaseWeapon = true;
        }
        else
        {
            int active = GetEntPropEnt(attackerClient, Prop_Send, "m_hActiveWeapon");
            if (IsValidEdict(active))
            {
                char cls[64];
                GetEntityClassname(active, cls, sizeof(cls));
                if (FormatWeaponName(cls, baseWeapon, maxlen))
                {
                    hasBaseWeapon = true;
                }
            }
        }
    }

    return hasBaseWeapon && IsBulletWeaponLabel(baseWeapon);
}

void BuildPrimaryCause(const char[] baseWeapon, bool bulletState, bool fireBullet, const char[] primary, char[] cause, int maxlen)
{
    cause[0] = '\0';

    if (bulletState && baseWeapon[0] != '\0')
    {
        strcopy(cause, maxlen, baseWeapon);
        AppendCauseToken(cause, maxlen, fireBullet ? "fire bullet" : "explosive bullet");
    }

    if (primary[0] != '\0')
    {
        AppendCauseToken(cause, maxlen, primary);
    }
}

bool ShouldUseBulletState(const char[] baseWeapon, const char[] eventWeapon, int attackerEnt)
{
    if (!IsBulletWeaponLabel(baseWeapon))
    {
        return false;
    }

    if (IsGrenadeLauncherContext(baseWeapon, eventWeapon, attackerEnt))
    {
        return false;
    }

    return true;
}

bool IsGrenadeLauncherContext(const char[] baseWeapon, const char[] eventWeapon, int attackerEnt)
{
    if (StrContains(baseWeapon, "Grenade Launcher", false) != -1)
    {
        return true;
    }

    if (StrContains(eventWeapon, "grenade_launcher", false) != -1 || StrContains(eventWeapon, "grenade launcher", false) != -1)
    {
        return true;
    }

    return EntityClassMatches(attackerEnt, "grenade_launcher_projectile");
}

bool IsBulletWeaponLabel(const char[] label)
{
    if (label[0] == '\0')
    {
        return false;
    }

    if (StrEqual(label, "molotov", false) || StrEqual(label, "pipebomb", false) || StrEqual(label, "gascan", false))
    {
        return false;
    }

    if (IsGenericFireLabel(label) || StrEqual(label, "fire", false) || StrEqual(label, "explosive", false))
    {
        return false;
    }

    if (StrContains(label, "Launcher", false) != -1 || StrContains(label, "Melee", false) != -1 || StrContains(label, "Chainsaw", false) != -1 || StrContains(label, "Knife", false) != -1)
    {
        return false;
    }

    return true;
}

bool IsClientDucking(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_bDucked") && GetEntProp(client, Prop_Send, "m_bDucked") != 0)
    {
        return true;
    }

    return (GetEntityFlags(client) & FL_DUCKING) != 0;
}

bool IsClientIncapped(int client)
{
    return (IsInGameClient(client) && HasEntProp(client, Prop_Send, "m_isIncapacitated") && GetEntProp(client, Prop_Send, "m_isIncapacitated") != 0);
}

bool IsClientVomitBlind(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (!HasEntProp(client, Prop_Send, "m_vomitStart"))
    {
        return false;
    }

    float vomitStart = GetEntPropFloat(client, Prop_Send, "m_vomitStart");
    if (vomitStart <= 0.0)
    {
        return false;
    }

    return (GetGameTime() - vomitStart) <= 20.0;
}

bool IsSniperLikeRange(int attackerClient, int victimClient, const char[] eventWeapon, int dmgType)
{
    if (!IsInGameClient(attackerClient) || !IsInGameClient(victimClient))
    {
        return false;
    }

    if ((dmgType & DMG_BULLET) == 0 && StrContains(eventWeapon, "sniper", false) == -1 && StrContains(eventWeapon, "hunting_rifle", false) == -1)
    {
        return false;
    }

    float aPos[3];
    float vPos[3];
    GetClientEyePosition(attackerClient, aPos);
    GetClientEyePosition(victimClient, vPos);

    return GetVectorDistance(aPos, vPos) >= 1200.0;
}

bool IsVictimStaggered(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_staggerTimer"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_staggerTimer") > 0.0;
    }

    if (HasEntProp(client, Prop_Send, "m_staggerDist"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_staggerDist") > 0.0;
    }

    if (HasEntProp(client, Prop_Send, "m_staggerStart"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_staggerStart") > 0.0;
    }

    return false;
}

bool IsClientAdrenalineActive(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_bAdrenalineActive"))
    {
        if (GetEntProp(client, Prop_Send, "m_bAdrenalineActive") != 0)
        {
            return true;
        }
    }

    if (HasEntProp(client, Prop_Send, "m_flAdrenalineTime"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_flAdrenalineTime") > GetGameTime();
    }

    return false;
}

bool IsClientCurrentlyOnFire(int client)
{
    if (!IsInGameClient(client))
    {
        return false;
    }

    if (HasEntProp(client, Prop_Send, "m_bIsBurning"))
    {
        return GetEntProp(client, Prop_Send, "m_bIsBurning") != 0;
    }

    if (HasEntProp(client, Prop_Send, "m_flFlameBurnTime"))
    {
        return GetEntPropFloat(client, Prop_Send, "m_flFlameBurnTime") > GetGameTime();
    }

    return false;
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

    if (GetHazardType(entity) == Hazard_None)
    {
        return;
    }

    g_iHazardEntType[entity] = view_as<int>(GetHazardType(entity));
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
    if (EntityIsGascan(entity))
    {
        return Hazard_Gascan;
    }
    if (EntityIsFireworkCrate(entity))
    {
        return Hazard_Firework;
    }
    if (EntityIsFuelBarrel(entity))
    {
        return Hazard_FuelBarrel;
    }
    if (EntityIsPropaneTank(entity))
    {
        return Hazard_PropaneTank;
    }
    if (EntityIsOxygenTank(entity))
    {
        return Hazard_OxygenTank;
    }

    return Hazard_None;
}

int ResolveDamageOwnerClient(int attacker, int inflictor)
{
    if (IsInGameClient(attacker) && GetClientTeam(attacker) == 2)
    {
        return attacker;
    }

    if (IsInGameClient(inflictor) && GetClientTeam(inflictor) == 2)
    {
        return inflictor;
    }

    int owner = GetLinkedEntity(inflictor, "m_hOwnerEntity");
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2)
    {
        return owner;
    }

    owner = GetLinkedEntity(attacker, "m_hOwnerEntity");
    if (IsInGameClient(owner) && GetClientTeam(owner) == 2)
    {
        return owner;
    }

    return 0;
}

void AddSourceEvent(HazardType type, const float pos[3], int owner)
{
    if (type == Hazard_None)
    {
        return;
    }

    int idx = g_iSourceWrite;
    g_iSourceType[idx] = view_as<int>(type);
    g_iSourceOwner[idx] = owner;
    g_fSourceTime[idx] = GetGameTime();
    g_vSourcePos[idx][0] = pos[0];
    g_vSourcePos[idx][1] = pos[1];
    g_vSourcePos[idx][2] = pos[2];
    g_iSourceWrite = (g_iSourceWrite + 1) % MAX_SOURCE_EVENTS;

    if (IsInGameClient(owner) && GetClientTeam(owner) == 2 && type != Hazard_Molotov)
    {
        g_iLastHazardType[owner] = view_as<int>(type);
        g_fLastHazardTime[owner] = GetGameTime();
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

    if (source == Hazard_Gascan && WasRecentMolotovThrow(sourceOwner, 20.0))
    {
        strcopy(cause, maxlen, "molotov");
    }

    return true;
}

bool GetFireSourceMeta(int victim, int attackerEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (attackerEnt > 0 && attackerEnt < MAX_TRACKED_EDICTS && IsValidEdict(attackerEnt))
    {
        source = view_as<HazardType>(g_iFireEntSourceType[attackerEnt]);
        sourceOwner = g_iFireEntOwner[attackerEnt];
    }

    if (source == Hazard_None && victim > 0 && victim <= MaxClients && HasRecentSnapshot(victim))
    {
        int inflictor = g_iLastInflictor[victim];
        if (inflictor > 0 && inflictor < MAX_TRACKED_EDICTS && IsValidEdict(inflictor))
        {
            source = view_as<HazardType>(g_iFireEntSourceType[inflictor]);
            sourceOwner = g_iFireEntOwner[inflictor];
            if (source == Hazard_None)
            {
                TryInferHazardFromLinkedFireEntity(inflictor, source, sourceOwner);
            }
        }
    }

    if (source == Hazard_None && victim > 0 && victim <= MaxClients && HasRecentSnapshot(victim))
    {
        float victimPos[3];
        GetClientEyePosition(victim, victimPos);
        source = FindBestFireSource(victimPos, sourceOwner);
    }

    return source != Hazard_None;
}

bool TryInferHazardFromLinkedFireEntity(int fireEnt, HazardType &source, int &sourceOwner)
{
    source = Hazard_None;
    sourceOwner = 0;

    if (!IsValidEdict(fireEnt))
    {
        return false;
    }

    int links[4];
    links[0] = GetLinkedEntity(fireEnt, "m_hOwnerEntity");
    links[1] = GetLinkedEntity(fireEnt, "m_hMoveParent");
    links[2] = GetLinkedEntity(fireEnt, "m_hEffectEntity");
    links[3] = GetLinkedEntity(fireEnt, "m_hInflictor");

    for (int i = 0; i < sizeof(links); i++)
    {
        int ent = links[i];
        if (!IsValidEdict(ent))
        {
            continue;
        }

        HazardType t = GetHazardType(ent);
        if (t != Hazard_None)
        {
            source = t;
            sourceOwner = ResolveDamageOwnerClient(GetLinkedEntity(ent, "m_hOwnerEntity"), GetLinkedEntity(ent, "m_hPhysicsAttacker"));
            if (sourceOwner == 0)
            {
                sourceOwner = ResolveProjectileOwner(ent);
            }
            return true;
        }
    }

    return false;
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
    if (IsInGameClient(owner))
    {
        return owner;
    }

    owner = GetLinkedEntity(entity, "m_hOwnerEntity");
    if (IsInGameClient(owner))
    {
        return owner;
    }

    return 0;
}

void GetEntityAbsPos(int entity, float outPos[3])
{
    outPos[0] = 0.0;
    outPos[1] = 0.0;
    outPos[2] = 0.0;

    // OPTIMIZED: Bounds check removed - function should only be called with valid entities
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
        case Hazard_Gascan:
        {
            strcopy(cause, maxlen, "gascan");
            return true;
        }
        case Hazard_Firework:
        {
            strcopy(cause, maxlen, "firework crate");
            return true;
        }
        case Hazard_FuelBarrel:
        {
            strcopy(cause, maxlen, "fuel barrel");
            return true;
        }
        case Hazard_PropaneTank:
        {
            strcopy(cause, maxlen, "propane tank");
            return true;
        }
        case Hazard_OxygenTank:
        {
            strcopy(cause, maxlen, "oxygen tank");
            return true;
        }
    }

    return false;
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

bool EntityIsPropaneTank(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "propan", false) != -1)
    {
        return true;
    }

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "propanecanister", false) != -1 || StrContains(model, "propanetank", false) != -1)
        {
            return true;
        }
    }

    return false;
}

bool EntityIsOxygenTank(int entity)
{
    if (!IsValidEdict(entity))
    {
        return false;
    }

    char cls[64];
    GetEntityClassname(entity, cls, sizeof(cls));
    if (StrContains(cls, "oxygen", false) != -1 || StrContains(cls, "oxygentank", false) != -1)
    {
        return true;
    }

    char model[PLATFORM_MAX_PATH];
    if (GetEntPropStringSafe(entity, Prop_Data, "m_ModelName", model, sizeof(model)))
    {
        if (StrContains(model, "oxygentank", false) != -1)
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

    ReplaceString(outName, maxlen, " BOT", "", false);
    ReplaceString(outName, maxlen, " Bot", "", false);

    if (IsInGameClient(client) && IsFakeClient(client) && GetClientTeam(client) == 2)
    {
        if (StrContains(outName, " Bot", false) == -1)
        {
            Format(outName, maxlen, "%s Bot", outName);
        }
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
