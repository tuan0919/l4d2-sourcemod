#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_HUNTER 3

#define ELITE_SUBTYPE_HUNTER_HEROIC 34

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvExplodeTime;
ConVar g_cvDamage;
ConVar g_cvRadius;
ConVar g_cvSurvivorDamage;

Handle g_hSdkActivatePipe;
bool g_bHasEliteApi;

int g_iHunterFakePipe[MAXPLAYERS + 1];
int g_iHunterActivePipe[MAXPLAYERS + 1];

// Track active heroic pipe entity refs để identify blast damage
bool g_bIsHeroicPipe[2049];

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

	MarkNativeAsOptional("EliteSI_IsElite");
	MarkNativeAsOptional("EliteSI_GetSubtype");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_hunter_heroic_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvExplodeTime = CreateConVar("l4d2_elite_si_hunter_heroic_explode_time", "6.0", "Pipebomb fuse time when dropped by Heroic hunter.", FCVAR_NOTIFY, true, 1.0, true, 20.0);
	g_cvDamage = CreateConVar("l4d2_elite_si_hunter_heroic_damage", "800.0", "Massive damage dealt by the dropped pipebomb.", FCVAR_NOTIFY, true, 0.0);
	g_cvRadius = CreateConVar("l4d2_elite_si_hunter_heroic_radius", "400.0", "Damage radius for the dropped pipebomb.", FCVAR_NOTIFY, true, 0.0);
	g_cvSurvivorDamage = CreateConVar("l4d2_elite_si_hunter_heroic_survivor_damage", "800.0", "Direct damage applied to survivors in radius when heroic pipe explodes (bypasses difficulty scaling). 0 = disabled.", FCVAR_NOTIFY, true, 0.0);

	CreateConVar("l4d2_elite_si_hunter_heroic_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hunter_heroic");

	LoadGamedata();

	HookEvent("lunge_pounce", Event_LungePounce, EventHookMode_Post);
	HookEvent("pounce_end", Event_PounceEnd, EventHookMode_Post);
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
	PrecacheModel("models/w_models/weapons/w_eq_pipebomb.mdl");
	ResetAllState();
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
}

public void OnEntityDestroyed(int entity)
{
	if (entity <= 0 || entity >= sizeof(g_bIsHeroicPipe))
		return;

	if (!g_bIsHeroicPipe[entity])
		return;

	g_bIsHeroicPipe[entity] = false;

	if (!g_cvEnable.BoolValue)
		return;

	float survivorDmg = g_cvSurvivorDamage.FloatValue;
	if (survivorDmg <= 0.0)
		return;

	float radius = g_cvRadius.FloatValue;
	if (radius <= 0.0)
		return;

	// Lấy vị trí pipe trước khi destroy
	float pipePos[3];
	if (IsValidEdict(entity))
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pipePos);
	else
		return;

	// Tìm owner từ per-client tracking
	int owner = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iHunterActivePipe[i] != 0 && EntRefToEntIndex(g_iHunterActivePipe[i]) == entity)
		{
			owner = i;
			g_iHunterActivePipe[i] = 0;
			break;
		}
	}

	// Gây damage thủ công lên tất cả survivor trong radius
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != TEAM_SURVIVOR)
			continue;

		float survivorPos[3];
		GetClientAbsOrigin(i, survivorPos);
		float dist = GetVectorDistance(pipePos, survivorPos);

		if (dist > radius)
			continue;

		// Scale damage theo khoảng cách (linear falloff)
		float scale = 1.0 - (dist / radius);
		float finalDmg = survivorDmg * scale;
		if (finalDmg < 1.0)
			continue;

		// SDKHooks_TakeDamage bypass difficulty scaling hoàn toàn
		SDKHooks_TakeDamage(i, owner > 0 ? owner : i, owner > 0 ? owner : i, finalDmg, DMG_BLAST);
	}
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core"))
	{
		RefreshEliteState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core"))
	{
		RefreshEliteState();
	}
}

public void EliteSI_OnEliteAssigned(int client, int zClass, int subtype)
{
	if (zClass == ZC_HUNTER && subtype == ELITE_SUBTYPE_HUNTER_HEROIC)
	{
		CreateFakePipebomb(client);
	}
}

public void EliteSI_OnEliteCleared(int client)
{
	RemoveFakePipebomb(client);
	// We don't remove the active pipebomb if they have one dropped, because it's their "legacy".
}

void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

void Event_LungePounce(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue) return;

	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (ShouldApplySubtype(attacker, true))
	{
		// Hunter pinned someone, drop the pipe bomb
		RemoveFakePipebomb(attacker);
		DropActivePipebomb(attacker);
	}
}

void Event_PounceEnd(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue) return;

	int victim = GetClientOfUserId(event.GetInt("victim"));
	if (victim <= 0 || victim > MaxClients) return;
	
	// Wait, we need to find who pinned him, but pounce_end doesn't provide attacker userid in L4D2.
	// Oh, in L4D2 pounce_end DOES NOT have "userid", but lunge_pounce does.
	// Wait, actually, let's just loop all clients to find the hunter who has an active pipe bomb but is no longer pouncing.
	// Or we can just check all hunters.
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (ShouldApplySubtype(i, true))
		{
			// Check if they are carrying an active pipebomb but are NOT pinning anyone anymore
			// Can check m_pounceVictim
			int currentVictim = GetEntPropEnt(i, Prop_Send, "m_pounceVictim");
			if (currentVictim <= 0 && g_iHunterActivePipe[i] != 0)
			{
				PickupPipebomb(i);
			}
		}
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue) return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (ShouldApplySubtype(client, false))
	{
		// If he dies and hasn't dropped it yet, drop it.
		if (g_iHunterActivePipe[client] == 0)
		{
			RemoveFakePipebomb(client);
			DropActivePipebomb(client);
		}
	}
}

void CreateFakePipebomb(int client)
{
	RemoveFakePipebomb(client);

	int ent = CreateEntityByName("prop_dynamic_override");
	if (ent > 0 && IsValidEntity(ent))
	{
		DispatchKeyValue(ent, "model", "models/w_models/weapons/w_eq_pipebomb.mdl");
		DispatchKeyValue(ent, "solid", "0");
		DispatchSpawn(ent);

		SetVariantString("!activator");
		AcceptEntityInput(ent, "SetParent", client);
		SetVariantString("rhand");
		AcceptEntityInput(ent, "SetParentAttachment", client);

		g_iHunterFakePipe[client] = EntIndexToEntRef(ent);
	}
}

void RemoveFakePipebomb(int client)
{
	int entRef = g_iHunterFakePipe[client];
	if (entRef != 0)
	{
		int ent = EntRefToEntIndex(entRef);
		if (ent > 0 && IsValidEntity(ent))
		{
			RemoveEntity(ent);
		}
		g_iHunterFakePipe[client] = 0;
	}
}

void DropActivePipebomb(int client)
{
	// Ensure we only drop one
	if (g_iHunterActivePipe[client] != 0) return;

	float vPos[3], vAng[3];
	GetClientAbsOrigin(client, vPos);
	vPos[2] += 10.0;
	
	// Prepare changing fuse time
	ConVar cvTimer = FindConVar("pipe_bomb_timer_duration");
	float oldFuse = 6.0;
	if (cvTimer != null)
	{
		oldFuse = cvTimer.FloatValue;
		cvTimer.SetFloat(g_cvExplodeTime.FloatValue);
	}

	int entity = SDKCall(g_hSdkActivatePipe, vPos, vAng, vAng, vAng, client, 2.0);

	if (cvTimer != null)
	{
		cvTimer.SetFloat(oldFuse);
	}

	if (entity > 0 && IsValidEntity(entity))
	{
		DispatchKeyValue(entity, "targetname", "elite_hunter_heroic_pipe");

		// Decorate it just in case
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

		float dmg = g_cvDamage.FloatValue;
		float rad = g_cvRadius.FloatValue;
		if (dmg > 0.0) SetEntPropFloat(entity, Prop_Data, "m_flDamage", dmg);
		if (rad > 0.0) SetEntPropFloat(entity, Prop_Data, "m_DmgRadius", rad);

		if (entity < sizeof(g_bIsHeroicPipe))
		{
			g_bIsHeroicPipe[entity] = true;
		}

		g_iHunterActivePipe[client] = EntIndexToEntRef(entity);
	}
}

void PickupPipebomb(int client)
{
	int entRef = g_iHunterActivePipe[client];
	if (entRef != 0)
	{
		int ent = EntRefToEntIndex(entRef);
		if (ent > 0 && IsValidEntity(ent))
		{
			if (ent < sizeof(g_bIsHeroicPipe))
				g_bIsHeroicPipe[ent] = false;
			RemoveEntity(ent);
		}
		g_iHunterActivePipe[client] = 0;
	}
	CreateFakePipebomb(client);
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i);
	}
}

void ResetClientState(int client)
{
	if (client <= 0 || client > MaxClients) return;

	RemoveFakePipebomb(client);
	g_iHunterActivePipe[client] = 0;
}

bool ShouldApplySubtype(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
		return false;

	if (GetClientTeam(client) != TEAM_INFECTED)
		return false;

	if (requireAlive && !IsPlayerAlive(client))
		return false;

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_HUNTER)
		return false;

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
		return false;

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_HUNTER_HEROIC;
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
