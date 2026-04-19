#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.1.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_HUNTER_HEROIC 34

#define MAX_HEROIC_BOMBS (MAXPLAYERS + 1)
#define EXPLOSION_SPRITE "materials/sprites/zerogxplode.vmt"
#define EXPLOSION_SOUND "weapons/hegrenade/explode5.wav"

ConVar g_cvEnable;
ConVar g_cvFuseTime;
ConVar g_cvExplosionDamage;
ConVar g_cvExplosionRadius;
ConVar g_cvDropOffset;

bool g_bTrackedHeroic[MAXPLAYERS + 1];
bool g_bHasPipeAvailable[MAXPLAYERS + 1];
int g_iPinnedVictim[MAXPLAYERS + 1];
int g_iPinnedHunter[MAXPLAYERS + 1];
int g_iHunterBombSlot[MAXPLAYERS + 1];

bool g_bBombActive[MAX_HEROIC_BOMBS];
int g_iBombSerial[MAX_HEROIC_BOMBS];
int g_iBombOwner[MAX_HEROIC_BOMBS];
float g_vecBombOrigin[MAX_HEROIC_BOMBS][3];

int g_iExplosionSprite = -1;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Hunter Heroic",
	author = "OpenCode",
	description = "Heroic subtype module for elite Hunter bots.",
	version = PLUGIN_VERSION,
	url = ""
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errMax)
{
	if (GetEngineVersion() != Engine_Left4Dead2)
	{
		strcopy(error, errMax, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_hunter_heroic_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFuseTime = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_fuse", "3.0", "Fuse time in seconds before Heroic Hunter pipebomb explodes.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvExplosionDamage = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_damage", "220.0", "Base explosion damage dealt by Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 1.0, true, 1000.0);
	g_cvExplosionRadius = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_radius", "320.0", "Explosion radius of Heroic Hunter pipebomb.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvDropOffset = CreateConVar("l4d2_elite_si_hunter_heroic_pipebomb_drop_offset", "28.0", "Offset used when dropping the Heroic Hunter pipebomb near the pinned target.", FCVAR_NOTIFY, true, 0.0, true, 200.0);

	CreateConVar("l4d2_elite_si_hunter_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hunter_heroic");

	HookEvent("lunge_pounce", Event_LungePounce, EventHookMode_Post);
	HookEvent("pounce_end", Event_PounceEnd, EventHookMode_Post);
	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("finale_win", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("mission_lost", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("map_transition", Event_RoundReset, EventHookMode_PostNoCopy);

	PrecacheAssets();
	ResetAllState();
}

public void OnMapStart()
{
	PrecacheAssets();
	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client, true);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client, true);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ClearPinnedState(client);
	g_bTrackedHeroic[client] = (zclass == ZC_HUNTER && subtype == ELITE_SUBTYPE_HUNTER_HEROIC);
	if (g_bTrackedHeroic[client] && IsClientInGame(client) && IsPlayerAlive(client) && g_iHunterBombSlot[client] == -1)
	{
		g_bHasPipeAvailable[client] = true;
	}
	else if (!g_bTrackedHeroic[client])
	{
		g_bHasPipeAvailable[client] = false;
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ClearPinnedState(client);
	g_bTrackedHeroic[client] = false;
	g_bHasPipeAvailable[client] = false;
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

public void Event_LungePounce(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int hunter = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if (!IsHeroicHunter(hunter, true) || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	ClearPinnedState(hunter);
	g_iPinnedVictim[hunter] = victim;
	g_iPinnedHunter[victim] = hunter;

	if (!g_bHasPipeAvailable[hunter] || g_iHunterBombSlot[hunter] != -1)
	{
		return;
	}

	float bombOrigin[3];
	GetBombOriginNearVictim(hunter, victim, bombOrigin);
	ArmHunterBomb(hunter, bombOrigin);
}

public void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("victim"));
	if (victim <= 0 || victim > MaxClients)
	{
		return;
	}

	int hunter = g_iPinnedHunter[victim];
	g_iPinnedHunter[victim] = 0;
	if (hunter > 0 && hunter <= MaxClients)
	{
		g_iPinnedVictim[hunter] = 0;
	}
}

public void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int hunter = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHeroicHunter(hunter, true) || g_iPinnedVictim[hunter] == 0)
	{
		return;
	}

	ClearPinnedState(hunter);
	ReclaimHunterBomb(hunter);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ClearPinnedState(client);

	if (!g_cvEnable.BoolValue || !IsHeroicHunter(client, false))
	{
		return;
	}

	if (!g_bHasPipeAvailable[client] || g_iHunterBombSlot[client] != -1)
	{
		return;
	}

	float bombOrigin[3];
	GetClientAbsOrigin(client, bombOrigin);
	bombOrigin[2] += 6.0;
	ArmHunterBomb(client, bombOrigin);
}

void PrecacheAssets()
{
	g_iExplosionSprite = PrecacheModel(EXPLOSION_SPRITE, true);
	PrecacheSound(EXPLOSION_SOUND, true);
}

void ArmHunterBomb(int hunter, const float origin[3])
{
	int slot = FindFreeBombSlot();
	if (slot == -1)
	{
		return;
	}

	g_bBombActive[slot] = true;
	g_iBombOwner[slot] = hunter;
	g_iBombSerial[slot]++;
	g_vecBombOrigin[slot][0] = origin[0];
	g_vecBombOrigin[slot][1] = origin[1];
	g_vecBombOrigin[slot][2] = origin[2];
	g_iHunterBombSlot[hunter] = slot;
	g_bHasPipeAvailable[hunter] = false;

	DataPack pack = new DataPack();
	pack.WriteCell(slot);
	pack.WriteCell(g_iBombSerial[slot]);
	CreateTimer(g_cvFuseTime.FloatValue, Timer_DetonateBomb, pack, TIMER_FLAG_NO_MAPCHANGE);
}

void ReclaimHunterBomb(int hunter)
{
	int slot = g_iHunterBombSlot[hunter];
	if (slot != -1)
	{
		CancelBombSlot(slot);
	}

	if (IsHeroicHunter(hunter, true))
	{
		g_bHasPipeAvailable[hunter] = true;
	}
}

public Action Timer_DetonateBomb(Handle timer, DataPack pack)
{
	pack.Reset();
	int slot = pack.ReadCell();
	int serial = pack.ReadCell();
	delete pack;

	if (slot < 0 || slot >= MAX_HEROIC_BOMBS)
	{
		return Plugin_Stop;
	}

	if (!g_bBombActive[slot] || g_iBombSerial[slot] != serial)
	{
		return Plugin_Stop;
	}

	int owner = g_iBombOwner[slot];
	float origin[3];
	origin[0] = g_vecBombOrigin[slot][0];
	origin[1] = g_vecBombOrigin[slot][1];
	origin[2] = g_vecBombOrigin[slot][2];

	DeactivateBombSlot(slot);
	DetonateBomb(owner, origin);
	return Plugin_Stop;
}

void DetonateBomb(int owner, const float origin[3])
{
	if (g_iExplosionSprite > 0)
	{
		TE_SetupExplosion(origin, g_iExplosionSprite, 1.0, 1, 0, RoundToNearest(g_cvExplosionRadius.FloatValue), 600);
		TE_SendToAll();
	}

	EmitAmbientSound(EXPLOSION_SOUND, origin, owner, SNDLEVEL_RAIDSIREN);

	float radius = g_cvExplosionRadius.FloatValue;
	float baseDamage = g_cvExplosionDamage.FloatValue;
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float survivorPos[3];
		GetClientAbsOrigin(survivor, survivorPos);
		float distance = GetVectorDistance(origin, survivorPos);
		if (distance > radius)
		{
			continue;
		}

		float damageScale = 1.0 - (distance / radius);
		if (damageScale < 0.15)
		{
			damageScale = 0.15;
		}

		SDKHooks_TakeDamage(survivor, owner, owner, baseDamage * damageScale, DMG_BLAST);
	}
}

void GetBombOriginNearVictim(int hunter, int victim, float origin[3])
{
	GetClientAbsOrigin(victim, origin);

	float hunterPos[3];
	GetClientAbsOrigin(hunter, hunterPos);

	float dir[3];
	MakeVectorFromPoints(hunterPos, origin, dir);
	if (NormalizeVector(dir, dir) < 0.001)
	{
		dir[0] = 1.0;
		dir[1] = 0.0;
		dir[2] = 0.0;
	}

	origin[0] += dir[0] * g_cvDropOffset.FloatValue;
	origin[1] += dir[1] * g_cvDropOffset.FloatValue;
	origin[2] += 6.0;
}

int FindFreeBombSlot()
{
	for (int i = 0; i < MAX_HEROIC_BOMBS; i++)
	{
		if (!g_bBombActive[i])
		{
			return i;
		}
	}

	return -1;
}

void CancelBombSlot(int slot)
{
	if (slot < 0 || slot >= MAX_HEROIC_BOMBS)
	{
		return;
	}

	if (g_bBombActive[slot])
	{
		g_iBombSerial[slot]++;
	}

	DeactivateBombSlot(slot);
}

void DeactivateBombSlot(int slot)
{
	if (slot < 0 || slot >= MAX_HEROIC_BOMBS)
	{
		return;
	}

	int owner = g_iBombOwner[slot];
	if (owner > 0 && owner <= MaxClients && g_iHunterBombSlot[owner] == slot)
	{
		g_iHunterBombSlot[owner] = -1;
	}

	g_bBombActive[slot] = false;
	g_iBombOwner[slot] = 0;
	g_vecBombOrigin[slot][0] = 0.0;
	g_vecBombOrigin[slot][1] = 0.0;
	g_vecBombOrigin[slot][2] = 0.0;
}

void ResetAllState()
{
	for (int i = 0; i < MAX_HEROIC_BOMBS; i++)
	{
		CancelBombSlot(i);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i, false);
	}
}

void ResetClientState(int client, bool cancelBomb)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ClearPinnedState(client);
	if (cancelBomb && g_iHunterBombSlot[client] != -1)
	{
		CancelBombSlot(g_iHunterBombSlot[client]);
	}

	g_bTrackedHeroic[client] = false;
	g_bHasPipeAvailable[client] = false;
	g_iHunterBombSlot[client] = -1;
}

void ClearPinnedState(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	int victim = g_iPinnedVictim[client];
	if (victim > 0 && victim <= MaxClients && g_iPinnedHunter[victim] == client)
	{
		g_iPinnedHunter[victim] = 0;
	}
	g_iPinnedVictim[client] = 0;

	int hunter = g_iPinnedHunter[client];
	if (hunter > 0 && hunter <= MaxClients && g_iPinnedVictim[hunter] == client)
	{
		g_iPinnedVictim[hunter] = 0;
	}
	g_iPinnedHunter[client] = 0;
}

bool IsHeroicHunter(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_HUNTER)
	{
		return false;
	}

	return g_bTrackedHeroic[client];
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}
