#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <left4dhooks>

native int L4D2_IsEliteSI(int client);
native bool L4D2_GetEliteTypeName(int client, char[] buffer, int maxlen);
native int EliteSI_Noxious_GetRecentDamageCause(int victim);
native int EliteSI_Noxious_GetRecentDamageAttacker(int victim);

#define PLUGIN_VERSION "1.0.0"
#define ANCHOR_NAME "SI_RedAnchor"
#define SNAPSHOT_VALID_WINDOW 1.5
#define INCAP_ANNOUNCE_DELAY 0.45
#define INCAP_KILL_SUPPRESS_WINDOW 1.20
#define HAZARD_CONTEXT_WINDOW 4.0
#define MAX_TRACKED_EDICTS 2048  // L4D2's max entities - no +1 needed for int arrays
#define MAX_SOURCE_EVENTS 128
#define FIRE_SOURCE_MATCH_WINDOW 12.0
#define FIRE_SOURCE_MAX_DIST 350.0
#define FIRE_SOURCE_CACHE_WINDOW 15.0
#define FIRE_ENTITY_RECHECK_DELAY 0.08
#define FIRE_ENTITY_LINK_SCAN_MAX 24
#define FIRE_ASSIST_STALE_WINDOW 20.0
#define FIRE_ASSIST_UNLOCK_GRACE 2.0
#define STAGGER_MATCH_WINDOW 1.25

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

enum FireSourceConfidence
{
    FireSourceConfidence_None = 0,
    FireSourceConfidence_Heuristic,
    FireSourceConfidence_Deterministic
}

ConVar g_hEnable;
ConVar g_hAnnounceEliteSIKill;
bool g_bEnable;
bool g_bAnnounceEliteSIKill;

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
int g_iLastStaggerBy[MAXPLAYERS + 1];
float g_fLastStaggerTime[MAXPLAYERS + 1];

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
int g_iFireEntSourceConfidence[MAX_TRACKED_EDICTS];
float g_fFireEntMarkTime[MAX_TRACKED_EDICTS];
bool g_bFireEntRecheckQueued[MAX_TRACKED_EDICTS];
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
