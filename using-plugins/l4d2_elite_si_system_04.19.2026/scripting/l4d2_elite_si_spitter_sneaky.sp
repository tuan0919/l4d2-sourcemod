#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_SPITTER 4

#define ELITE_SUBTYPE_SPITTER_SNEAKY 32

#define SNEAKY_SHOTS_PER_CYCLE 2

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvRetreatRange;
ConVar g_cvRetreatSpeedMultiplier;
ConVar g_cvCloakFadeAlpha;
ConVar g_cvCloakActiveDuration;
ConVar g_cvCloakCooldown;
ConVar g_cvShotInterval;
ConVar g_cvShotSpreadDistance;
ConVar g_cvShotRange;

bool g_bHasEliteApi;
bool g_bTrackedSneaky[MAXPLAYERS + 1];
bool g_bCloaked[MAXPLAYERS + 1];
float g_fCloakUntil[MAXPLAYERS + 1];
float g_fNextCloakAt[MAXPLAYERS + 1];
float g_fNextShotAt[MAXPLAYERS + 1];
int g_iShotsRemaining[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Spitter Sneaky",
	author = "OpenCode",
	description = "Sneaky subtype module for elite Spitter bots.",
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

	MarkNativeAsOptional("EliteSI_IsElite");
	MarkNativeAsOptional("EliteSI_GetSubtype");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_spitter_sneaky_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvRetreatRange = CreateConVar("l4d2_elite_si_spitter_sneaky_retreat_range", "300.0", "Range where Sneaky Spitter tries to retreat from nearby survivors.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvRetreatSpeedMultiplier = CreateConVar("l4d2_elite_si_spitter_sneaky_retreat_speed_multiplier", "1.15", "Movement speed multiplier while Sneaky Spitter repositions away from survivors.", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvCloakFadeAlpha = CreateConVar("l4d2_elite_si_spitter_sneaky_cloak_alpha", "102", "Render alpha while Sneaky Spitter is cloaked. 102 ~= 60 percent fade.", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	g_cvCloakActiveDuration = CreateConVar("l4d2_elite_si_spitter_sneaky_cloak_duration", "5.0", "Duration in seconds of the Sneaky Spitter cloak cycle.", FCVAR_NOTIFY, true, 0.5, true, 30.0);
	g_cvCloakCooldown = CreateConVar("l4d2_elite_si_spitter_sneaky_cloak_cooldown", "7.0", "Cooldown in seconds after cloak ends before Sneaky Spitter starts the next two-shot burst.", FCVAR_NOTIFY, true, 0.5, true, 60.0);
	g_cvShotInterval = CreateConVar("l4d2_elite_si_spitter_sneaky_shot_interval", "0.45", "Delay between the two Sneaky Spitter acid shots.", FCVAR_NOTIFY, true, 0.1, true, 5.0);
	g_cvShotSpreadDistance = CreateConVar("l4d2_elite_si_spitter_sneaky_shot_spread_distance", "140.0", "Offset used to spread the second acid shot away from the first target point.", FCVAR_NOTIFY, true, 10.0, true, 1000.0);
	g_cvShotRange = CreateConVar("l4d2_elite_si_spitter_sneaky_shot_range", "1400.0", "Max range to pick survivor targets for Sneaky Spitter acid bursts.", FCVAR_NOTIFY, true, 100.0, true, 5000.0);

	CreateConVar("l4d2_elite_si_spitter_sneaky_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_spitter_sneaky");

	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
	SyncTrackedSubtypeState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
		SyncTrackedSubtypeState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
	}
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_PreThinkPost, OnSneakyThinkPost);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnSneakyThinkPost);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedSneaky[client] = (zclass == ZC_SPITTER && subtype == ELITE_SUBTYPE_SPITTER_SNEAKY);
	ResetClientState(client);
	g_bTrackedSneaky[client] = (zclass == ZC_SPITTER && subtype == ELITE_SUBTYPE_SPITTER_SNEAKY);
	QueueNextBurst(client, GetGameTime() + 0.6);
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	bool wasSneaky = g_bTrackedSneaky[client];
	ResetClientState(client);
	if (wasSneaky)
	{
		RestoreCloakVisual(client);
	}
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bTrackedSneaky[i])
		{
			RestoreCloakVisual(i);
		}
		ResetClientState(i);
	}
}

public void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsSneakySpitter(victim, true) || !g_bCloaked[victim])
	{
		return;
	}

	BreakCloak(victim, true);
}

public void OnSneakyThinkPost(int client)
{
	if (!IsSneakySpitter(client, true))
	{
		return;
	}

	float now = GetGameTime();
	UpdateCloakState(client, now);
	LockSpitCooldown(client, now);
	TryRetreatFromNearbySurvivor(client);
	TryFireBurstShot(client, now);
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!IsSneakySpitter(victim, true) || damage <= 0.0)
	{
		return Plugin_Continue;
	}

	if (!g_bCloaked[victim])
	{
		return Plugin_Continue;
	}

	if ((damageType & DMG_BULLET) != 0)
	{
		damage = 0.0;
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void UpdateCloakState(int client, float now)
{
	if (g_bCloaked[client])
	{
		if (now >= g_fCloakUntil[client])
		{
			BreakCloak(client, false);
		}
		return;
	}

	if (g_iShotsRemaining[client] <= 0 && now >= g_fNextCloakAt[client])
	{
		EnterCloak(client, now);
	}
}

void EnterCloak(int client, float now)
{
	g_bCloaked[client] = true;
	g_fCloakUntil[client] = now + g_cvCloakActiveDuration.FloatValue;
	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, 120, 255, 180, g_cvCloakFadeAlpha.IntValue);
}

void BreakCloak(int client, bool shoved)
{
	g_bCloaked[client] = false;
	g_fCloakUntil[client] = 0.0;
	RestoreCloakVisual(client);
	QueueNextBurst(client, GetGameTime() + g_cvCloakCooldown.FloatValue);

	if (shoved)
	{
		g_fNextShotAt[client] = GetGameTime() + g_cvCloakCooldown.FloatValue;
	}
}

void RestoreCloakVisual(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
	{
		return;
	}

	SetEntityRenderMode(client, RENDER_TRANSCOLOR);
	SetEntityRenderColor(client, 120, 255, 180, 255);
}

void LockSpitCooldown(int client, float now)
{
	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (IsValidEntity(ability))
	{
		SetEntPropFloat(ability, Prop_Send, "m_timestamp", now + 9999.0);
	}
}

void TryRetreatFromNearbySurvivor(int client)
{
	int threat = FindClosestSurvivor(client, g_cvRetreatRange.FloatValue);
	if (threat <= 0)
	{
		return;
	}

	float selfOrigin[3];
	float threatOrigin[3];
	GetClientAbsOrigin(client, selfOrigin);
	GetClientAbsOrigin(threat, threatOrigin);

	float direction[3];
	MakeVectorFromPoints(threatOrigin, selfOrigin, direction);
	NormalizeVector(direction, direction);

	float speed = 210.0 * g_cvRetreatSpeedMultiplier.FloatValue;
	float velocity[3];
	velocity[0] = direction[0] * speed;
	velocity[1] = direction[1] * speed;
	velocity[2] = 0.0;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, velocity);
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvRetreatSpeedMultiplier.FloatValue);
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);
}

void TryFireBurstShot(int client, float now)
{
	if (g_bCloaked[client] || g_iShotsRemaining[client] <= 0 || now < g_fNextShotAt[client])
	{
		return;
	}

	int target = FindClosestSurvivor(client, g_cvShotRange.FloatValue);
	if (target <= 0)
	{
		g_fNextShotAt[client] = now + 0.3;
		return;
	}

	float targetPos[3];
	GetClientAbsOrigin(target, targetPos);

	if (g_iShotsRemaining[client] == 1)
	{
		float selfOrigin[3];
		GetClientAbsOrigin(client, selfOrigin);
		float direction[3];
		MakeVectorFromPoints(selfOrigin, targetPos, direction);
		NormalizeVector(direction, direction);

		float right[3];
		right[0] = -direction[1];
		right[1] = direction[0];
		right[2] = 0.0;
		NormalizeVector(right, right);
		ScaleVector(right, g_cvShotSpreadDistance.FloatValue);
		AddVectors(targetPos, right, targetPos);
	}

	FireSpitAtPoint(client, targetPos);
	g_iShotsRemaining[client]--;

	if (g_iShotsRemaining[client] > 0)
	{
		g_fNextShotAt[client] = now + g_cvShotInterval.FloatValue;
		return;
	}

	g_fNextCloakAt[client] = now + 0.2;
	g_fNextShotAt[client] = 0.0;
}

void FireSpitAtPoint(int client, const float targetPos[3])
{
	float selfOrigin[3];
	GetClientAbsOrigin(client, selfOrigin);
	selfOrigin[2] += 40.0;

	float direction[3];
	MakeVectorFromPoints(selfOrigin, targetPos, direction);
	NormalizeVector(direction, direction);
	ScaleVector(direction, 650.0);

	float ang[3];
	GetVectorAngles(direction, ang);
	int projectile = L4D2_SpitterPrj(client, selfOrigin, ang, direction);
	if (projectile <= MaxClients || !IsValidEntity(projectile))
	{
		return;
	}
}

int FindClosestSurvivor(int client, float maxDistance)
{
	float origin[3];
	GetClientAbsOrigin(client, origin);

	int closest = 0;
	float closestDistance = maxDistance;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float targetOrigin[3];
		GetClientAbsOrigin(survivor, targetOrigin);
		float distance = GetVectorDistance(origin, targetOrigin);
		if (distance < closestDistance)
		{
			closestDistance = distance;
			closest = survivor;
		}
	}

	return closest;
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedSneaky[client] = false;
	g_bCloaked[client] = false;
	g_fCloakUntil[client] = 0.0;
	g_fNextCloakAt[client] = 0.0;
	g_fNextShotAt[client] = 0.0;
	g_iShotsRemaining[client] = 0;
}

void QueueNextBurst(int client, float startAt)
{
	g_iShotsRemaining[client] = SNEAKY_SHOTS_PER_CYCLE;
	g_fNextShotAt[client] = startAt;
	g_fNextCloakAt[client] = 0.0;
}

bool IsSneakySpitter(int client, bool requireAlive)
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

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
	{
		return false;
	}

	return g_bTrackedSneaky[client];
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}

void SyncTrackedSubtypeState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		SyncTrackedSubtypeForClient(i);
	}
}

void SyncTrackedSubtypeForClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SPITTER)
	{
		g_bTrackedSneaky[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedSneaky[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SPITTER_SNEAKY;
	if (g_bTrackedSneaky[client] && g_iShotsRemaining[client] <= 0 && g_fNextShotAt[client] <= 0.0)
	{
		QueueNextBurst(client, GetGameTime() + 0.6);
	}
}
