#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.10"

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
Handle g_hSdkActivatePipe;
int g_iPipeEnt[MAXPLAYERS + 1];
Handle g_hStateTimer[MAXPLAYERS + 1];
Handle g_hPreDetonateTimer[MAXPLAYERS + 1];
bool g_bPipeArmed[MAXPLAYERS + 1];
bool g_bPipeAttached[MAXPLAYERS + 1];
bool g_bPipeDecorated[MAXPLAYERS + 1];
bool g_bPipeConsumed[MAXPLAYERS + 1];
bool g_bHasPipeLastPos[MAXPLAYERS + 1];
float g_vPipeLastPos[MAXPLAYERS + 1][3];
int g_iForceKillVictimUserId[MAXPLAYERS + 1];
int g_iRecentKillAttackerUserId[MAXPLAYERS + 1];
float g_fRecentKillTime[MAXPLAYERS + 1];

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
	CreateNative("EliteSI_JockeyHeroic_GetRecentDamageCause", Native_GetRecentDamageCause);
	CreateNative("EliteSI_JockeyHeroic_GetRecentDamageAttacker", Native_GetRecentDamageAttacker);
	RegPluginLibrary("l4d2_elite_si_jockey_heroic");
	return APLRes_Success;
}

public any Native_GetRecentDamageCause(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	if (victim <= 0 || victim > MaxClients)
	{
		return 0;
	}

	return (GetGameTime() - g_fRecentKillTime[victim]) <= 4.0 ? 1 : 0;
}

public any Native_GetRecentDamageAttacker(Handle plugin, int numParams)
{
	int victim = GetNativeCell(1);
	if (victim <= 0 || victim > MaxClients || (GetGameTime() - g_fRecentKillTime[victim]) > 4.0)
	{
		return 0;
	}

	return GetClientOfUserId(g_iRecentKillAttackerUserId[victim]);
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
	Handle hGameData = LoadGameConfigFile("l4d_pipebomb_shove");
	if (hGameData == null)
	{
		SetFailState("Failed to load l4d_pipebomb_shove gamedata. Ensure l4d_pipebomb_shove.txt is in gamedata folder.");
	}

	StartPrepSDKCall(SDKCall_Static);
	if (!PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CPipeBombProjectile_Create"))
	{
		SetFailState("Could not load the CPipeBombProjectile_Create gamedata signature.");
	}
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);
	PrepSDKCall_AddParameter(SDKType_CBasePlayer, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSdkActivatePipe = EndPrepSDKCall();

	delete hGameData;

	if (g_hSdkActivatePipe == null)
	{
		SetFailState("Could not prep the CPipeBombProjectile_Create function.");
	}
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
		g_bPipeConsumed[client] = false;
		CreatePipeProp(client, true);
		StartStateTimer(client);
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client > 0 && client <= MaxClients && g_bPipeArmed[client])
	{
		DropPipebomb(client);
		return;
	}

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
			bool wasArmed = g_bPipeArmed[i];
			bool wasAttached = g_bPipeAttached[i];
			int forceKillVictimUserId = g_iForceKillVictimUserId[i];
			float pipePos[3];
			bool hasPipePos = wasArmed && GetExplosionDamagePosition(i, entity, wasAttached, pipePos);

			StopStateTimer(i);
			StopPreDetonateTimer(i);
			g_iPipeEnt[i] = 0;
			g_bPipeArmed[i] = false;
			g_bPipeAttached[i] = false;
			g_bPipeDecorated[i] = false;
			g_bHasPipeLastPos[i] = false;
			g_iForceKillVictimUserId[i] = 0;

			if (wasArmed && g_cvEnable.BoolValue && hasPipePos)
			{
				ApplyManualExplosionDamage(pipePos, i, entity);
				ForceKillRideVictim(forceKillVictimUserId, i, entity);
			}
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

	if (g_bPipeArmed[client])
	{
		DropPipebomb(client);
		return;
	}

	if (g_bPipeConsumed[client])
	{
		return;
	}

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
	UpdatePipeLastPosition(client, false);
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
	UpdatePipeLastPosition(client, true);
}

void ArmPipebomb(int client, bool keepAttached)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (g_bPipeArmed[client])
	{
		if (keepAttached)
		{
			AttachPipeToHand(client);
		}
		return;
	}

	RemoveTrackedPipe(client);

	int entity = CreateActivePipebomb(client);
	if (entity <= 0)
	{
		return;
	}

	g_iPipeEnt[client] = EntIndexToEntRef(entity);
	g_bPipeArmed[client] = true;
	g_bPipeAttached[client] = false;
	g_bPipeDecorated[client] = false;
	g_bPipeConsumed[client] = true;
	UpdatePipeLastPosition(client, false);
	DecoratePipebomb(client);
	StartStateTimer(client);
	StartPreDetonateTimer(client);

	if (keepAttached)
	{
		AttachPipeToHand(client);
	}
	else
	{
		DropPipebomb(client);
	}

	if (keepAttached)
	{
		CreateTimer(0.10, Timer_MonitorRide, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
	}
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
		Handle timer = g_hStateTimer[client];
		g_hStateTimer[client] = null;
		KillTimer(timer);
	}
}

void StartPreDetonateTimer(int client)
{
	StopPreDetonateTimer(client);

	float delay = g_cvExplodeTime.FloatValue - 0.12;
	if (delay < 0.10)
	{
		delay = 0.10;
	}

	g_hPreDetonateTimer[client] = CreateTimer(delay, Timer_PreDetonatePipebomb, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

void StopPreDetonateTimer(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (g_hPreDetonateTimer[client] != null)
	{
		Handle timer = g_hPreDetonateTimer[client];
		g_hPreDetonateTimer[client] = null;
		KillTimer(timer);
	}
}

void ClearPreDetonateTimerHandle(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_hPreDetonateTimer[i] == timer)
		{
			g_hPreDetonateTimer[i] = null;
			return;
		}
	}
}

Action Timer_PreDetonatePipebomb(Handle timer, int userId)
{
	ClearPreDetonateTimerHandle(timer);

	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients)
	{
		return Plugin_Stop;
	}

	if (g_bPipeArmed[client] && g_bPipeAttached[client] && GetPipeEntity(client) > 0)
	{
		int victim = GetCurrentRideVictim(client);
		if (victim > 0)
		{
			g_iForceKillVictimUserId[client] = GetClientUserId(victim);
			ScheduleRideVictimKill(victim, client);
		}

		DropPipebomb(client);
	}

	return Plugin_Stop;
}

int CreateActivePipebomb(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return 0;
	}

	float pos[3], ang[3];
	GetClientAbsOrigin(client, pos);
	pos[2] += 10.0;

	ConVar cvTimer = FindConVar("pipe_bomb_timer_duration");
	float oldFuse = 6.0;
	if (cvTimer != null)
	{
		oldFuse = cvTimer.FloatValue;
		cvTimer.SetFloat(g_cvExplodeTime.FloatValue);
	}

	int entity = SDKCall(g_hSdkActivatePipe, pos, ang, ang, ang, client, 2.0);

	if (cvTimer != null)
	{
		cvTimer.SetFloat(oldFuse);
	}

	if (entity <= 0 || !IsValidEntity(entity))
	{
		return 0;
	}

	DispatchKeyValue(entity, "targetname", "elite_jockey_heroic_pipe");

	float dmg = g_cvDamage.FloatValue;
	float rad = g_cvRadius.FloatValue;
	if (dmg > 0.0)
	{
		SetEntPropFloat(entity, Prop_Data, "m_flDamage", dmg);
	}
	if (rad > 0.0)
	{
		SetEntPropFloat(entity, Prop_Data, "m_DmgRadius", rad);
	}

	return entity;
}

void ClearStateTimerHandle(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_hStateTimer[i] == timer)
		{
			g_hStateTimer[i] = null;
			return;
		}
	}
}

Action Timer_CheckHeroicState(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (client <= 0 || client > MaxClients)
	{
		ClearStateTimerHandle(timer);
		return Plugin_Stop;
	}

	if (!HasTrackedPipe(client))
	{
		ClearStateTimerHandle(timer);
		return Plugin_Stop;
	}

	if (!IsClientInGame(client))
	{
		ClearStateTimerHandle(timer);
		return Plugin_Stop;
	}

	if (!IsPlayerAlive(client))
	{
		DropPipebomb(client);
		return Plugin_Continue;
	}

	if (g_bPipeArmed[client])
	{
		UpdatePipeLastPosition(client, g_bPipeAttached[client]);

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

	UpdatePipeLastPosition(client, true);

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
	if (GetLiveJockeyRidePosition(client, pos))
	{
		pos[2] += 6.0;
	}
	else if (client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		GetClientAbsOrigin(client, pos);
		pos[2] += 6.0;
	}
	else
	{
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
	}
	TeleportEntity(entity, pos, NULL_VECTOR, vel);
	StorePipeLastPosition(client, pos);
}

bool GetExplosionDamagePosition(int client, int entity, bool wasAttached, float pos[3])
{
	if (wasAttached && GetLiveJockeyRidePosition(client, pos))
	{
		return true;
	}

	if (wasAttached && client > 0 && client <= MaxClients && IsClientInGame(client))
	{
		GetClientAbsOrigin(client, pos);
		return true;
	}

	if (g_bHasPipeLastPos[client])
	{
		pos[0] = g_vPipeLastPos[client][0];
		pos[1] = g_vPipeLastPos[client][1];
		pos[2] = g_vPipeLastPos[client][2];
		return true;
	}

	if (IsValidEdict(entity))
	{
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
		return true;
	}

	return false;
}

bool GetLiveJockeyRidePosition(int client, float pos[3])
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	int victim = GetCurrentRideVictim(client);
	if (victim > 0)
	{
		GetClientAbsOrigin(victim, pos);
		return true;
	}

	if (IsPlayerAlive(client))
	{
		GetClientAbsOrigin(client, pos);
		return true;
	}

	return false;
}

int GetCurrentRideVictim(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return 0;
	}

	int victim = GetEntPropEnt(client, Prop_Send, "m_jockeyVictim");
	if (victim <= 0 || victim > MaxClients || !IsClientInGame(victim))
	{
		return 0;
	}

	return GetEntPropEnt(victim, Prop_Send, "m_jockeyAttacker") == client ? victim : 0;
}

void UpdatePipeLastPosition(int client, bool attached)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	float pos[3];
	if (attached && GetLiveJockeyRidePosition(client, pos))
	{
		StorePipeLastPosition(client, pos);
		return;
	}

	int entity = GetPipeEntity(client);
	if (entity > 0 && IsValidEdict(entity))
	{
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
		StorePipeLastPosition(client, pos);
	}
}

void StorePipeLastPosition(int client, const float pos[3])
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bHasPipeLastPos[client] = true;
	g_vPipeLastPos[client][0] = pos[0];
	g_vPipeLastPos[client][1] = pos[1];
	g_vPipeLastPos[client][2] = pos[2];
}

void DecoratePipebomb(int client)
{
	if (client <= 0 || client > MaxClients || !g_bPipeArmed[client] || g_bPipeDecorated[client])
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
void ApplyManualExplosionDamage(const float pipePos[3], int owner, int inflictor)
{
	float survivorDmg = g_cvSurvivorDamage.FloatValue;
	if (survivorDmg <= 0.0)
	{
		return;
	}

	float radius = g_cvRadius.FloatValue;
	if (radius <= 0.0)
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

	int ci = -1;
	while ((ci = FindEntityByClassname(ci, "infected")) != -1)
	{
		if (!IsValidEdict(ci))
		{
			continue;
		}

		float ciPos[3];
		GetEntPropVector(ci, Prop_Data, "m_vecAbsOrigin", ciPos);
		float dist = GetVectorDistance(pipePos, ciPos);
		if (dist > radius)
		{
			continue;
		}

		float ciDmg = survivorDmg * (1.0 - (dist / radius));
		if (ciDmg < 1.0)
		{
			continue;
		}

		SDKHooks_TakeDamage(ci, attacker > 0 ? attacker : ci, inflictor, ciDmg, DMG_BLAST);
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

void ForceKillRideVictim(int victimUserId, int attacker, int inflictor)
{
	if (victimUserId <= 0)
	{
		return;
	}

	int victim = GetClientOfUserId(victimUserId);
	if (victim <= 0 || !IsClientInGame(victim) || !IsPlayerAlive(victim) || GetClientTeam(victim) != TEAM_SURVIVOR)
	{
		return;
	}

	int damageAttacker = (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker)) ? attacker : victim;
	bool incapped = HasEntProp(victim, Prop_Send, "m_isIncapacitated") && GetEntProp(victim, Prop_Send, "m_isIncapacitated") != 0;

	if (incapped)
	{
		SDKHooks_TakeDamage(victim, damageAttacker, inflictor, 10000.0, DMG_BLAST);
		return;
	}

	SDKHooks_TakeDamage(victim, damageAttacker, inflictor, float(GetClientHealth(victim)) + 1.0, DMG_BLAST);

	DataPack pack = new DataPack();
	pack.WriteCell(victimUserId);
	pack.WriteCell(attacker > 0 ? GetClientUserId(attacker) : 0);
	RequestFrame(Frame_ForceKillRideVictim, pack);
}

void ScheduleRideVictimKill(int victim, int attacker)
{
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(victim));
	pack.WriteCell(attacker > 0 ? GetClientUserId(attacker) : 0);
	CreateTimer(0.18, Timer_ForceKillRideVictim, pack, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ForceKillRideVictim(Handle timer, DataPack pack)
{
	pack.Reset();
	int victimUserId = pack.ReadCell();
	int attackerUserId = pack.ReadCell();
	delete pack;

	ForceKillRideVictimNow(victimUserId, attackerUserId, false);
	return Plugin_Stop;
}

public void Frame_ForceKillRideVictim(DataPack pack)
{
	pack.Reset();
	int victimUserId = pack.ReadCell();
	int attackerUserId = pack.ReadCell();
	delete pack;

	ForceKillRideVictimNow(victimUserId, attackerUserId, true);
}

void ForceKillRideVictimNow(int victimUserId, int attackerUserId, bool allowSuicideFallback)
{
	int victim = GetClientOfUserId(victimUserId);
	if (victim <= 0 || !IsClientInGame(victim) || !IsPlayerAlive(victim) || GetClientTeam(victim) != TEAM_SURVIVOR)
	{
		return;
	}

	int attacker = GetClientOfUserId(attackerUserId);
	g_iRecentKillAttackerUserId[victim] = attackerUserId;
	g_fRecentKillTime[victim] = GetGameTime();

	int damageAttacker = attacker > 0 ? attacker : victim;
	SDKHooks_TakeDamage(victim, damageAttacker, damageAttacker, 10000.0, DMG_BLAST);

	if (!allowSuicideFallback)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(victimUserId);
		pack.WriteCell(attackerUserId);
		RequestFrame(Frame_ForceKillRideVictim, pack);
		return;
	}

	if (IsClientInGame(victim) && IsPlayerAlive(victim))
	{
		ForcePlayerSuicide(victim);
	}
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
		g_bPipeArmed[client] = false;
		g_bPipeConsumed[client] = false;
	}
	StopStateTimer(client);
    StopPreDetonateTimer(client);

	RemoveTrackedPipe(client);
}

void RemoveTrackedPipe(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

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
	g_bHasPipeLastPos[client] = false;
	g_iForceKillVictimUserId[client] = 0;
	g_iRecentKillAttackerUserId[client] = 0;
	g_fRecentKillTime[client] = 0.0;
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
