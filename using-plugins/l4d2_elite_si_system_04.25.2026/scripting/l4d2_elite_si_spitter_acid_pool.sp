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

#define ELITE_SUBTYPE_SPITTER_ACID_POOL 31

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvSpeedMultiplier;
ConVar g_cvTrailCooldown;
ConVar g_cvJumpCooldown;
ConVar g_cvMeleeCooldown;
ConVar g_cvApproachRange;
ConVar g_cvJumpRange;
ConVar g_cvTrailMinDistance;

bool g_bHasEliteApi;
bool g_bTrackedAcidPool[MAXPLAYERS + 1];
bool g_bIsJumping[MAXPLAYERS + 1];
float g_fNextTrailAt[MAXPLAYERS + 1];
float g_fNextJumpAt[MAXPLAYERS + 1];
float g_fNextMeleePoolAt[MAXPLAYERS + 1];
float g_vecLastTrailOrigin[MAXPLAYERS + 1][3];
bool g_bHasLastTrailOrigin[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Spitter Acid Pool",
	author = "OpenCode",
	description = "Acid Pool subtype module for elite Spitter bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_spitter_acid_pool_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSpeedMultiplier = CreateConVar("l4d2_elite_si_spitter_acid_pool_speed_multiplier", "1.2", "Movement speed multiplier for Acid Pool spitter.", FCVAR_NOTIFY, true, 1.0, true, 3.0);
	g_cvTrailCooldown = CreateConVar("l4d2_elite_si_spitter_acid_pool_trail_cooldown", "2.0", "Cooldown between automatic acid puddles dropped while moving.", FCVAR_NOTIFY, true, 0.1, true, 30.0);
	g_cvJumpCooldown = CreateConVar("l4d2_elite_si_spitter_acid_pool_jump_cooldown", "3.5", "Cooldown between jump-triggered acid puddles.", FCVAR_NOTIFY, true, 0.1, true, 30.0);
	g_cvMeleeCooldown = CreateConVar("l4d2_elite_si_spitter_acid_pool_melee_cooldown", "2.0", "Cooldown between melee-triggered acid puddles.", FCVAR_NOTIFY, true, 0.1, true, 30.0);
	g_cvApproachRange = CreateConVar("l4d2_elite_si_spitter_acid_pool_approach_range", "900.0", "Max range to aggressively approach the nearest survivor.", FCVAR_NOTIFY, true, 100.0, true, 5000.0);
	g_cvJumpRange = CreateConVar("l4d2_elite_si_spitter_acid_pool_jump_range", "250.0", "Range where the spitter will try to hop forward into survivor space.", FCVAR_NOTIFY, true, 50.0, true, 1000.0);
	g_cvTrailMinDistance = CreateConVar("l4d2_elite_si_spitter_acid_pool_trail_min_distance", "110.0", "Minimum distance moved before a new trail puddle can be dropped.", FCVAR_NOTIFY, true, 10.0, true, 1000.0);

	CreateConVar("l4d2_elite_si_spitter_acid_pool_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_spitter_acid_pool");

	HookEvent("player_hurt", Event_PlayerHurt, EventHookMode_Post);
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
	SDKHook(client, SDKHook_PreThinkPost, OnAcidPoolThinkPost);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_PreThinkPost, OnAcidPoolThinkPost);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedAcidPool[client] = (zclass == ZC_SPITTER && subtype == ELITE_SUBTYPE_SPITTER_ACID_POOL);
	g_fNextTrailAt[client] = 0.0;
	g_fNextJumpAt[client] = 0.0;
	g_fNextMeleePoolAt[client] = 0.0;
	g_bHasLastTrailOrigin[client] = false;
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedAcidPool[client] = false;
	g_bHasLastTrailOrigin[client] = false;
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i);
	}
}

public void Event_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	if ((event.GetInt("type") & DMG_CLUB) == 0)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsValidAliveSurvivor(victim) || !IsAcidPoolSpitter(attacker, true))
	{
		return;
	}

	float now = GetGameTime();
	if (now < g_fNextMeleePoolAt[attacker])
	{
		return;
	}

	DropAcidPool(attacker);
	g_fNextMeleePoolAt[attacker] = now + g_cvMeleeCooldown.FloatValue;
}

public void OnAcidPoolThinkPost(int client)
{
	if (!IsAcidPoolSpitter(client, true))
	{
		return;
	}

	float speed = 210.0 * g_cvSpeedMultiplier.FloatValue;
	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", g_cvSpeedMultiplier.FloatValue);
	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", speed);

	int ability = GetEntPropEnt(client, Prop_Send, "m_customAbility");
	if (IsValidEntity(ability))
	{
		SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + 9999.0);
	}

	// Detect landing: clear jump flag once back on ground
	if (g_bIsJumping[client] && (GetEntityFlags(client) & FL_ONGROUND) != 0)
	{
		g_bIsJumping[client] = false;
	}

	TryDropTrailAcid(client);
	TryPressureClosestSurvivor(client);
	TryDropJumpAcid(client);
}

void TryDropTrailAcid(int client)
{
	float now = GetGameTime();
	if (now < g_fNextTrailAt[client])
	{
		return;
	}

	float origin[3];
	GetClientAbsOrigin(client, origin);

	if (g_bHasLastTrailOrigin[client])
	{
		float moved = GetVectorDistance(origin, g_vecLastTrailOrigin[client]);
		if (moved < g_cvTrailMinDistance.FloatValue)
		{
			return;
		}
	}

	float velocity[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", velocity);
	velocity[2] = 0.0;
	if (GetVectorLength(velocity) < 80.0)
	{
		return;
	}

	DropAcidPoolAt(client, origin);
	g_fNextTrailAt[client] = now + g_cvTrailCooldown.FloatValue;
	g_vecLastTrailOrigin[client] = origin;
	g_bHasLastTrailOrigin[client] = true;
}

void TryPressureClosestSurvivor(int spitter)
{
	int target = FindClosestSurvivor(spitter, g_cvApproachRange.FloatValue);
	if (target <= 0)
	{
		return;
	}

	float spitterOrigin[3];
	float targetOrigin[3];
	GetClientAbsOrigin(spitter, spitterOrigin);
	GetClientAbsOrigin(target, targetOrigin);

	float distance = GetVectorDistance(spitterOrigin, targetOrigin);
	if (distance <= 70.0)
	{
		return;
	}

	float direction[3];
	MakeVectorFromPoints(spitterOrigin, targetOrigin, direction);
	NormalizeVector(direction, direction);

	float speed = 210.0 * g_cvSpeedMultiplier.FloatValue;
	float velocity[3];
	velocity[0] = direction[0] * speed;
	velocity[1] = direction[1] * speed;

	// Preserve vertical velocity while mid-jump, only zero out when grounded
	if (g_bIsJumping[spitter])
	{
		float currentVel[3];
		GetEntPropVector(spitter, Prop_Data, "m_vecVelocity", currentVel);
		velocity[2] = currentVel[2];
	}
	else
	{
		velocity[2] = 0.0;
	}

	TeleportEntity(spitter, NULL_VECTOR, NULL_VECTOR, velocity);
}

void TryDropJumpAcid(int spitter)
{
	float now = GetGameTime();
	if (now < g_fNextJumpAt[spitter])
	{
		return;
	}

	if ((GetEntityFlags(spitter) & FL_ONGROUND) == 0)
	{
		return;
	}

	int target = FindClosestSurvivor(spitter, g_cvApproachRange.FloatValue);
	if (target <= 0)
	{
		return;
	}

	float spitterOrigin[3];
	float targetOrigin[3];
	GetClientAbsOrigin(spitter, spitterOrigin);
	GetClientAbsOrigin(target, targetOrigin);

	float distance = GetVectorDistance(spitterOrigin, targetOrigin);
	if (distance > g_cvJumpRange.FloatValue || distance < 90.0)
	{
		return;
	}

	float direction[3];
	MakeVectorFromPoints(spitterOrigin, targetOrigin, direction);
	NormalizeVector(direction, direction);

	float velocity[3];
	GetEntPropVector(spitter, Prop_Data, "m_vecVelocity", velocity);
	velocity[0] = direction[0] * 260.0;
	velocity[1] = direction[1] * 260.0;
	velocity[2] = 220.0;
	TeleportEntity(spitter, NULL_VECTOR, NULL_VECTOR, velocity);

	g_bIsJumping[spitter] = true;
	DropAcidPoolAt(spitter, spitterOrigin);
	g_fNextJumpAt[spitter] = now + g_cvJumpCooldown.FloatValue;
}

void DropAcidPool(int spitter)
{
	float origin[3];
	GetClientAbsOrigin(spitter, origin);
	DropAcidPoolAt(spitter, origin);
}

void DropAcidPoolAt(int spitter, const float origin[3])
{
	float ang[3] = {90.0, 0.0, 0.0};
	float vel[3] = {0.0, 0.0, -100.0};
	int projectile = L4D2_SpitterPrj(spitter, origin, ang, vel);
	if (projectile <= MaxClients || !IsValidEntity(projectile))
	{
		return;
	}

	L4D_DetonateProjectile(projectile);
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

	g_bTrackedAcidPool[client] = false;
	g_bIsJumping[client] = false;
	g_fNextTrailAt[client] = 0.0;
	g_fNextJumpAt[client] = 0.0;
	g_fNextMeleePoolAt[client] = 0.0;
	g_bHasLastTrailOrigin[client] = false;
	g_vecLastTrailOrigin[client][0] = 0.0;
	g_vecLastTrailOrigin[client][1] = 0.0;
	g_vecLastTrailOrigin[client][2] = 0.0;
}

bool IsAcidPoolSpitter(int client, bool requireAlive)
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

	return g_bTrackedAcidPool[client];
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
		g_bTrackedAcidPool[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedAcidPool[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SPITTER_ACID_POOL;
}
