#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_JOCKEY 5
#define ELITE_SUBTYPE_JOCKEY_HEROIC 37

#define PIPE_MODEL "models/w_models/weapons/w_eq_pipebomb.mdl"

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvExplodeTime;
ConVar g_cvDamage;
ConVar g_cvRadius;
ConVar g_cvSurvivorDamage;

Handle g_hSdkCreatePipe;
bool g_bHasEliteApi;

int g_iFakePipe[MAXPLAYERS + 1];
int g_iActivePipe[MAXPLAYERS + 1];
bool g_bActivePipeAttached[MAXPLAYERS + 1];
bool g_bIsHeroicPipe[2049];

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
	g_cvExplodeTime = CreateConVar("l4d2_elite_si_jockey_heroic_explode_time", "6.0", "Pipebomb fuse time when activated by Heroic Jockey.", FCVAR_NOTIFY, true, 1.0, true, 20.0);
	g_cvDamage = CreateConVar("l4d2_elite_si_jockey_heroic_damage", "800.0", "Engine damage set on the Heroic Jockey pipebomb.", FCVAR_NOTIFY, true, 0.0);
	g_cvRadius = CreateConVar("l4d2_elite_si_jockey_heroic_radius", "400.0", "Damage radius for the Heroic Jockey pipebomb.", FCVAR_NOTIFY, true, 0.0);
	g_cvSurvivorDamage = CreateConVar("l4d2_elite_si_jockey_heroic_survivor_damage", "800.0", "Direct survivor damage in radius when the Heroic Jockey pipebomb explodes. 0=disabled.", FCVAR_NOTIFY, true, 0.0);

	CreateConVar("l4d2_elite_si_jockey_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_jockey_heroic");

	LoadGamedata();

	HookEvent("jockey_ride", Event_JockeyRide, EventHookMode_Post);
	HookEvent("jockey_ride_end", Event_JockeyRideEnd, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();
}

void LoadGamedata()
{
	Handle gameData = LoadGameConfigFile("l4d_pipebomb_shove");
	if (gameData == null)
	{
		SetFailState("Failed to load l4d_pipebomb_shove gamedata.");
	}

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CPipeBombProjectile_Create"))
	{
		SetFailState("Could not load CPipeBombProjectile_Create signature.");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkCreatePipe = EndPrepSDKCall();

	delete gameData;

	if (g_hSdkCreatePipe == null)
	{
		SetFailState("Could not prep CPipeBombProjectile_Create SDKCall.");
	}
}

public void OnMapStart()
{
	PrecacheModel(PIPE_MODEL);
	ResetAllState();
}

public void OnClientDisconnect(int client)
{
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
		CreateFakePipebomb(client);
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	RemoveFakePipebomb(client);
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0 || entity >= sizeof(g_bIsHeroicPipe) || !g_bIsHeroicPipe[entity])
	{
		return;
	}

	g_bIsHeroicPipe[entity] = false;

	float pipePos[3];
	if (!IsValidEdict(entity))
	{
		return;
	}
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pipePos);

	int owner = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iActivePipe[i] != 0 && EntRefToEntIndex(g_iActivePipe[i]) == entity)
		{
			owner = i;
			g_iActivePipe[i] = 0;
			g_bActivePipeAttached[i] = false;
			break;
		}
	}

	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	ApplyManualExplosionDamage(pipePos, owner, entity);
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

	ActivateMouthPipebomb(jockey);
}

void Event_JockeyRideEnd(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bActivePipeAttached[i])
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
	if (!IsHeroicJockey(client, false))
	{
		return;
	}

	if (g_iActivePipe[client] != 0)
	{
		DropAttachedPipebomb(client);
		return;
	}

	RemoveFakePipebomb(client);
	CreateActivePipebomb(client, false);
}

void ActivateMouthPipebomb(int client)
{
	if (g_iActivePipe[client] != 0)
	{
		return;
	}

	RemoveFakePipebomb(client);
	CreateActivePipebomb(client, true);
}

void CreateFakePipebomb(int client)
{
	RemoveFakePipebomb(client);

	if (!IsHeroicJockey(client, true))
	{
		return;
	}

	int entity = CreateEntityByName("prop_dynamic_override");
	if (entity <= 0 || !IsValidEntity(entity))
	{
		return;
	}

	DispatchKeyValue(entity, "model", PIPE_MODEL);
	DispatchKeyValue(entity, "solid", "0");
	DispatchSpawn(entity);

	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", client);
	SetVariantString("mouth");
	AcceptEntityInput(entity, "SetParentAttachment", client);

	g_iFakePipe[client] = EntIndexToEntRef(entity);
}

void RemoveFakePipebomb(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	int entity = EntRefToEntIndex(g_iFakePipe[client]);
	if (entity > 0 && IsValidEntity(entity))
	{
		RemoveEntity(entity);
	}
	g_iFakePipe[client] = 0;
}

void CreateActivePipebomb(int client, bool attachToMouth)
{
	if (g_iActivePipe[client] != 0)
	{
		return;
	}

	float pos[3], ang[3], vel[3], spin[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += attachToMouth ? 45.0 : 8.0;

	ConVar cvTimer = FindConVar("pipe_bomb_timer_duration");
	float oldFuse = 6.0;
	if (cvTimer != null)
	{
		oldFuse = cvTimer.FloatValue;
		cvTimer.SetFloat(g_cvExplodeTime.FloatValue);
	}

	int entity = SDKCall(g_hSdkCreatePipe, pos, ang, vel, spin, client, 2.0);

	if (cvTimer != null)
	{
		cvTimer.SetFloat(oldFuse);
	}

	if (entity <= 0 || !IsValidEntity(entity))
	{
		return;
	}

	DispatchKeyValue(entity, "targetname", "elite_jockey_heroic_pipe");
	DecoratePipebomb(entity);

	float damage = g_cvDamage.FloatValue;
	float radius = g_cvRadius.FloatValue;
	if (damage > 0.0)
	{
		SetEntPropFloat(entity, Prop_Data, "m_flDamage", damage);
	}
	if (radius > 0.0)
	{
		SetEntPropFloat(entity, Prop_Data, "m_DmgRadius", radius);
	}

	if (entity < sizeof(g_bIsHeroicPipe))
	{
		g_bIsHeroicPipe[entity] = true;
	}

	g_iActivePipe[client] = EntIndexToEntRef(entity);
	g_bActivePipeAttached[client] = attachToMouth;

	if (attachToMouth)
	{
		SetVariantString("!activator");
		AcceptEntityInput(entity, "SetParent", client);
		SetVariantString("mouth");
		AcceptEntityInput(entity, "SetParentAttachment", client);
		CreateTimer(0.10, Timer_MonitorRide, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
}

void DecoratePipebomb(int entity)
{
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

Action Timer_MonitorRide(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients || !g_bActivePipeAttached[client])
	{
		return Plugin_Stop;
	}

	int entity = EntRefToEntIndex(g_iActivePipe[client]);
	if (entity <= 0 || !IsValidEntity(entity))
	{
		g_iActivePipe[client] = 0;
		g_bActivePipeAttached[client] = false;
		return Plugin_Stop;
	}

	if (!IsClientInGame(client) || !IsPlayerAlive(client))
	{
		DropAttachedPipebomb(client);
		return Plugin_Stop;
	}

	int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") != client)
	{
		DropAttachedPipebomb(client);
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

void Frame_CheckRideStillActive(int userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients || !g_bActivePipeAttached[client])
	{
		return;
	}

	int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") != client)
	{
		DropAttachedPipebomb(client);
	}
}

void DropAttachedPipebomb(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	int entity = EntRefToEntIndex(g_iActivePipe[client]);
	if (entity <= 0 || !IsValidEntity(entity))
	{
		g_iActivePipe[client] = 0;
		g_bActivePipeAttached[client] = false;
		return;
	}

	g_bActivePipeAttached[client] = false;
	AcceptEntityInput(entity, "ClearParent");

	float pos[3], vel[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += 6.0;
	TeleportEntity(entity, pos, NULL_VECTOR, vel);
}

void ApplyManualExplosionDamage(const float pipePos[3], int owner, int inflictor)
{
	float survivorDmg = g_cvSurvivorDamage.FloatValue;
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

		ApplySurvivorBlastDamage(i, attacker, inflictor, finalDmg);
	}
}

void ApplySurvivorBlastDamage(int survivor, int attacker, int inflictor, float damage)
{
	int damageAttacker = attacker > 0 ? attacker : survivor;
	bool incapped = HasEntProp(survivor, Prop_Send, "m_isIncapacitated") && GetEntProp(survivor, Prop_Send, "m_isIncapacitated") != 0;

	if (incapped)
	{
		SDKHooks_TakeDamage(survivor, damageAttacker, inflictor, damage, DMG_BLAST);
		return;
	}

	float standingHp = float(GetClientHealth(survivor));
	if (damage < standingHp)
	{
		SDKHooks_TakeDamage(survivor, damageAttacker, inflictor, damage, DMG_BLAST);
		return;
	}

	float overflow = damage - standingHp;
	SDKHooks_TakeDamage(survivor, damageAttacker, inflictor, standingHp + 1.0, DMG_BLAST);

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

void ResetClientState(int client, bool removeActivePipe)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	RemoveFakePipebomb(client);

	if (removeActivePipe)
	{
		int entity = EntRefToEntIndex(g_iActivePipe[client]);
		if (entity > 0 && IsValidEntity(entity))
		{
			if (entity < sizeof(g_bIsHeroicPipe))
			{
				g_bIsHeroicPipe[entity] = false;
			}
			RemoveEntity(entity);
		}
	}

	g_iActivePipe[client] = 0;
	g_bActivePipeAttached[client] = false;
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
