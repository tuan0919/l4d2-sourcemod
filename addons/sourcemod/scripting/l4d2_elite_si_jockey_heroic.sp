#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.2"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_JOCKEY 5
#define ELITE_SUBTYPE_JOCKEY_HEROIC 37

#define PIPE_MODEL "models/w_models/weapons/w_eq_pipebomb.mdl"
#define PIPE_ATTACHMENT "rhand"

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvExplodeTime;
ConVar g_cvDamage;
ConVar g_cvRadius;
ConVar g_cvSurvivorDamage;

bool g_bHasEliteApi;
int g_iPipeEnt[MAXPLAYERS + 1];
Handle g_hDetonateTimer[MAXPLAYERS + 1];
Handle g_hStateTimer[MAXPLAYERS + 1];
bool g_bPipeArmed[MAXPLAYERS + 1];
bool g_bPipeAttached[MAXPLAYERS + 1];
bool g_bPipeDecorated[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Jockey Heroic",
	author = "OpenCode",
	description = "Heroic subtype module for elite Jockey bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_jockey_heroic_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvExplodeTime = CreateConVar("l4d2_elite_si_jockey_heroic_explode_time", "6.0", "Pipebomb fuse time after Heroic Jockey catches a survivor or dies.", FCVAR_NOTIFY, true, 1.0, true, 20.0);
	g_cvDamage = CreateConVar("l4d2_elite_si_jockey_heroic_damage", "800.0", "Manual blast damage dealt by the Heroic Jockey pipebomb.", FCVAR_NOTIFY, true, 0.0);
	g_cvRadius = CreateConVar("l4d2_elite_si_jockey_heroic_radius", "400.0", "Damage radius for the Heroic Jockey pipebomb.", FCVAR_NOTIFY, true, 0.0);
	g_cvSurvivorDamage = CreateConVar("l4d2_elite_si_jockey_heroic_survivor_damage", "800.0", "Direct survivor damage in radius when the Heroic Jockey pipebomb explodes. 0=disabled.", FCVAR_NOTIFY, true, 0.0);

	CreateConVar("l4d2_elite_si_jockey_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_jockey_heroic");

	HookEvent("jockey_ride", Event_JockeyRide, EventHookMode_Post);
	HookEvent("jockey_ride_end", Event_JockeyRideEnd, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();
}

public void OnMapStart()
{
	PrecacheModel(PIPE_MODEL);
	ResetAllState();
}

public void OnClientDisconnect(int client)
{
	if (client > 0 && client <= MaxClients && g_bPipeArmed[client])
	{
		DropPipebomb(client);
		StopStateTimer(client);
		g_bPipeAttached[client] = false;
		return;
	}

	ResetClientState(client, true);
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteState();
	}
}

public void EliteSI_OnEliteAssigned(int client, int zClass, int subtype)
{
	if (zClass == ZC_JOCKEY && subtype == ELITE_SUBTYPE_JOCKEY_HEROIC)
	{
		CreatePipeProp(client, true);
		StartStateTimer(client);
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	ResetClientState(client, true);
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0)
	{
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iPipeEnt[i] != 0 && EntRefToEntIndex(g_iPipeEnt[i]) == entity)
		{
			StopDetonateTimer(i);
			StopStateTimer(i);
			g_iPipeEnt[i] = 0;
			g_bPipeArmed[i] = false;
			g_bPipeAttached[i] = false;
			g_bPipeDecorated[i] = false;
			return;
		}
	}
}

void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

void Event_JockeyRide(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int jockey = GetClientOfUserId(event.GetInt("userid"));
	if (!IsHeroicJockey(jockey, true))
	{
		return;
	}

	ArmPipebomb(jockey, true);
}

void Event_JockeyRideEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bPipeArmed[i] && g_bPipeAttached[i])
		{
			RequestFrame(Frame_CheckRideStillActive, GetClientUserId(i));
		}
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients || (!HasTrackedPipe(client) && !IsHeroicJockey(client, false)))
	{
		return;
	}

	if (GetPipeEntity(client) <= 0)
	{
		CreatePipeProp(client, false);
	}

	DropPipebomb(client);
	ArmPipebomb(client, false);
}

void CreatePipeProp(int client, bool attachToHand)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	if (GetPipeEntity(client) > 0)
	{
		if (attachToHand)
		{
			AttachPipeToHand(client);
		}
		return;
	}

	int entity = CreateEntityByName("prop_dynamic_override");
	if (entity <= 0 || !IsValidEntity(entity))
	{
		return;
	}

	DispatchKeyValue(entity, "model", PIPE_MODEL);
	DispatchKeyValue(entity, "solid", "0");
	DispatchKeyValue(entity, "targetname", "elite_jockey_heroic_pipe");
	DispatchSpawn(entity);

	g_iPipeEnt[client] = EntIndexToEntRef(entity);
	g_bPipeArmed[client] = false;
	g_bPipeAttached[client] = false;
	g_bPipeDecorated[client] = false;
	DecoratePipebomb(client);
	StartStateTimer(client);

	if (attachToHand)
	{
		AttachPipeToHand(client);
	}
	else
	{
		DropPipebomb(client);
	}
}

void AttachPipeToHand(int client)
{
	int entity = GetPipeEntity(client);
	if (entity <= 0 || !IsClientInGame(client))
	{
		return;
	}

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);
	SetVariantString(PIPE_ATTACHMENT);
	AcceptEntityInput(entity, "SetParentAttachment", client);
	g_bPipeAttached[client] = true;
}

void ArmPipebomb(int client, bool keepAttached)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (GetPipeEntity(client) <= 0)
	{
		CreatePipeProp(client, keepAttached);
	}

	if (keepAttached)
	{
		AttachPipeToHand(client);
	}

	if (g_bPipeArmed[client])
	{
		return;
	}

	g_bPipeArmed[client] = true;
	DecoratePipebomb(client);
	StartDetonateTimer(client);

	if (keepAttached)
	{
		CreateTimer(0.10, Timer_MonitorRide, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void StartDetonateTimer(int client)
{
	StopDetonateTimer(client);
	g_hDetonateTimer[client] = CreateTimer(g_cvExplodeTime.FloatValue, Timer_DetonatePipebomb, g_iPipeEnt[client], TIMER_FLAG_NO_MAPCHANGE);
}

void StartStateTimer(int client)
{
	if (client <= 0 || client > MaxClients || g_hStateTimer[client] != null)
	{
		return;
	}

	g_hStateTimer[client] = CreateTimer(0.20, Timer_CheckHeroicState, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void StopStateTimer(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (g_hStateTimer[client] != null)
	{
		KillTimer(g_hStateTimer[client]);
		g_hStateTimer[client] = null;
	}
}

void StopDetonateTimer(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (g_hDetonateTimer[client] != null)
	{
		KillTimer(g_hDetonateTimer[client]);
		g_hDetonateTimer[client] = null;
	}
}

Action Timer_DetonatePipebomb(Handle timer, int pipeRef)
{
	int entity = EntRefToEntIndex(pipeRef);
	if (entity <= 0 || !IsValidEntity(entity))
	{
		return Plugin_Stop;
	}

	int owner = FindPipeOwner(pipeRef);
	if (owner > 0)
	{
		g_hDetonateTimer[owner] = null;
	}

	float pipePos[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pipePos);
	SpawnExplosionEffect(pipePos);
	ApplyManualExplosionDamage(pipePos, owner);

	if (owner > 0)
	{
		ResetClientState(owner, false);
	}
	else
	{
		RemoveEntity(entity);
	}

	return Plugin_Stop;
}

Action Timer_CheckHeroicState(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients)
	{
		return Plugin_Stop;
	}

	if (!HasTrackedPipe(client))
	{
		g_hStateTimer[client] = null;
		return Plugin_Stop;
	}

	if (!IsClientInGame(client))
	{
		g_hStateTimer[client] = null;
		return Plugin_Stop;
	}

	if (!IsPlayerAlive(client))
	{
		DropPipebomb(client);
		ArmPipebomb(client, false);
		return Plugin_Continue;
	}

	if (g_bPipeArmed[client])
	{
		if (g_bPipeAttached[client] && !IsJockeyCurrentlyRiding(client))
		{
			DropPipebomb(client);
		}
		return Plugin_Continue;
	}

	if (IsJockeyCurrentlyRiding(client))
	{
		ArmPipebomb(client, true);
	}

	return Plugin_Continue;
}

Action Timer_MonitorRide(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients || !g_bPipeArmed[client] || !g_bPipeAttached[client])
	{
		return Plugin_Stop;
	}

	if (GetPipeEntity(client) <= 0)
	{
		ResetClientState(client, false);
		return Plugin_Stop;
	}

	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		DropPipebomb(client);
		return Plugin_Stop;
	}

	int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") != client)
	{
		DropPipebomb(client);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void Frame_CheckRideStillActive(int userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients || !g_bPipeArmed[client] || !g_bPipeAttached[client])
	{
		return;
	}

	int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") != client)
	{
		DropPipebomb(client);
	}
}

void DropPipebomb(int client)
{
	int entity = GetPipeEntity(client);
	if (entity <= 0)
	{
		return;
	}

	g_bPipeAttached[client] = false;
	AcceptEntityInput(entity, "ClearParent");

	float pos[3], vel[3];
	if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		GetClientAbsOrigin(client, pos);
		pos[2] += 6.0;
	}
	else
	{
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	}
	TeleportEntity(entity, pos, NULL_VECTOR, vel);
}

void DecoratePipebomb(int client)
{
	if (client <= 0 || client > MaxClients || g_bPipeDecorated[client])
	{
		return;
	}

	int entity = GetPipeEntity(client);
	if (entity <= 0 || !IsValidEntity(entity))
	{
		return;
	}

	g_bPipeDecorated[client] = true;

	int particleFuse = CreateEntityByName("info_particle_system");
	if (particleFuse > 0)
	{
		DispatchKeyValue(particleFuse, "effect_name", "weapon_pipebomb_fuse");
		DispatchSpawn(particleFuse);
		ActivateEntity(particleFuse);
		AcceptEntityInput(particleFuse, "Start");
		SetVariantString("!activator");
		AcceptEntityInput(particleFuse, "SetParent", entity);
		SetVariantString("fuse");
		AcceptEntityInput(particleFuse, "SetParentAttachment", entity);
	}

	int particleLight = CreateEntityByName("info_particle_system");
	if (particleLight > 0)
	{
		DispatchKeyValue(particleLight, "effect_name", "weapon_pipebomb_blinking_light");
		DispatchSpawn(particleLight);
		ActivateEntity(particleLight);
		AcceptEntityInput(particleLight, "Start");
		SetVariantString("!activator");
		AcceptEntityInput(particleLight, "SetParent", entity);
		SetVariantString("pipebomb_light");
		AcceptEntityInput(particleLight, "SetParentAttachment", entity);
	}
}

void SpawnExplosionEffect(const float pos[3])
{
	int explosion = CreateEntityByName("env_explosion");
	if (explosion <= 0 || !IsValidEntity(explosion))
	{
		return;
	}

	DispatchKeyValue(explosion, "iMagnitude", "1");
	DispatchKeyValue(explosion, "spawnflags", "1916");
	DispatchSpawn(explosion);
	TeleportEntity(explosion, pos, NULL_VECTOR, NULL_VECTOR);
	AcceptEntityInput(explosion, "Explode");
	RemoveEntity(explosion);
}

void ApplyManualExplosionDamage(const float pipePos[3], int owner)
{
	float survivorDmg = g_cvSurvivorDamage.FloatValue;
	if (survivorDmg <= 0.0)
	{
		survivorDmg = g_cvDamage.FloatValue;
	}

	float radius = g_cvRadius.FloatValue;
	if (survivorDmg <= 0.0 || radius <= 0.0)
	{
		return;
	}

	int attacker = 0;
	if (owner > 0 && owner <= MaxClients && IsClientInGame(owner))
	{
		attacker = owner;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SURVIVOR)
		{
			continue;
		}

		float survivorPos[3];
		GetClientAbsOrigin(i, survivorPos);
		float dist = GetVectorDistance(pipePos, survivorPos);
		if (dist > radius)
		{
			continue;
		}

		float finalDmg = survivorDmg * (1.0 - (dist / radius));
		if (finalDmg < 1.0)
		{
			continue;
		}

		ApplySurvivorBlastDamage(i, attacker, finalDmg);
	}
}

void ApplySurvivorBlastDamage(int survivor, int attacker, float damage)
{
	int damageAttacker = attacker > 0 ? attacker : survivor;
	bool incapped = HasEntProp(survivor, Prop_Send, "m_isIncapacitated") && GetEntProp(survivor, Prop_Send, "m_isIncapacitated") != 0;

	if (incapped)
	{
		SDKHooks_TakeDamage(survivor, damageAttacker, damageAttacker, damage, DMG_BLAST);
		return;
	}

	float standingHp = float(GetClientHealth(survivor));
	if (damage < standingHp)
	{
		SDKHooks_TakeDamage(survivor, damageAttacker, damageAttacker, damage, DMG_BLAST);
		return;
	}

	float overflow = damage - standingHp;
	SDKHooks_TakeDamage(survivor, damageAttacker, damageAttacker, standingHp + 1.0, DMG_BLAST);

	if (overflow <= 0.0)
	{
		return;
	}

	ConVar cvIncapHp = FindConVar("survivor_incap_health");
	float incapHp = (cvIncapHp != null) ? cvIncapHp.FloatValue : 300.0;
	float incapDmg = overflow;
	if (incapDmg > incapHp)
	{
		incapDmg = incapHp + 1.0;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(survivor));
	pack.WriteCell(attacker > 0 ? GetClientUserId(attacker) : 0);
	pack.WriteFloat(incapDmg);
	RequestFrame(Frame_FinishIncapDamage, pack);
}

public void Frame_FinishIncapDamage(DataPack pack)
{
	pack.Reset();
	int survivorUserId = pack.ReadCell();
	int attackerUserId = pack.ReadCell();
	float damage = pack.ReadFloat();
	delete pack;

	int survivor = GetClientOfUserId(survivorUserId);
	if (survivor <= 0 || !IsClientInGame(survivor) || !IsPlayerAlive(survivor))
	{
		return;
	}

	if (!HasEntProp(survivor, Prop_Send, "m_isIncapacitated") || GetEntProp(survivor, Prop_Send, "m_isIncapacitated") == 0)
	{
		return;
	}

	int attacker = GetClientOfUserId(attackerUserId);
	SDKHooks_TakeDamage(survivor, attacker > 0 ? attacker : survivor, attacker > 0 ? attacker : survivor, damage, DMG_BLAST);
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i, true);
	}
}

void ResetClientState(int client, bool cancelTimer)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (cancelTimer)
	{
		StopDetonateTimer(client);
	}
	StopStateTimer(client);

	int entity = GetPipeEntity(client);
	if (entity > 0)
	{
		g_iPipeEnt[client] = 0;
		RemoveEntity(entity);
	}

	g_iPipeEnt[client] = 0;
	g_bPipeArmed[client] = false;
	g_bPipeAttached[client] = false;
	g_bPipeDecorated[client] = false;
}

bool HasTrackedPipe(int client)
{
	return client > 0 && client <= MaxClients && g_iPipeEnt[client] != 0;
}

bool IsJockeyCurrentlyRiding(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
	return victim > 0 && victim <= MaxClients && IsClientInGame(victim) && GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") == client;
}

int FindPipeOwner(int pipeRef)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iPipeEnt[i] == pipeRef)
		{
			return i;
		}
	}

	return 0;
}

int GetPipeEntity(int client)
{
	if (client <= 0 || client > MaxClients || g_iPipeEnt[client] == 0)
	{
		return 0;
	}

	int entity = EntRefToEntIndex(g_iPipeEnt[client]);
	if (entity <= 0 || !IsValidEntity(entity))
	{
		g_iPipeEnt[client] = 0;
		return 0;
	}

	return entity;
}

bool IsHeroicJockey(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED)
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_JOCKEY)
	{
		return false;
	}

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_JOCKEY_HEROIC;
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
