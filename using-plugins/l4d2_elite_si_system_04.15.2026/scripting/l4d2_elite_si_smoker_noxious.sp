#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_SMOKER 1

#define PARTICLE_METHANE_CLOUD "smoker_smokecloud"

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_HARDSI,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING,
	ELITE_SUBTYPE_CHARGER_ACTION,
	ELITE_SUBTYPE_SMOKER_ASPHYXIATION,
	ELITE_SUBTYPE_SMOKER_COLLAPSED_LUNG,
	ELITE_SUBTYPE_SMOKER_METHANE_BLAST,
	ELITE_SUBTYPE_SMOKER_METHANE_LEAK,
	ELITE_SUBTYPE_SMOKER_METHANE_STRIKE,
	ELITE_SUBTYPE_SMOKER_MOON_WALK,
	ELITE_SUBTYPE_SMOKER_RESTRAINED_HOSTAGE,
	ELITE_SUBTYPE_SMOKER_SMOKE_SCREEN,
	ELITE_SUBTYPE_SMOKER_TONGUE_STRIP,
	ELITE_SUBTYPE_SMOKER_TONGUE_WHIP,
	ELITE_SUBTYPE_SMOKER_VOID_POCKET
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvThinkInterval;

ConVar g_cvAsphyxiationEnable;
ConVar g_cvAsphyxiationDamage;
ConVar g_cvAsphyxiationFrequency;
ConVar g_cvAsphyxiationRange;

ConVar g_cvCollapsedLungEnable;
ConVar g_cvCollapsedLungChance;
ConVar g_cvCollapsedLungDamage;
ConVar g_cvCollapsedLungDuration;

ConVar g_cvMethaneBlastEnable;
ConVar g_cvMethaneBlastInnerDamage;
ConVar g_cvMethaneBlastOuterDamage;
ConVar g_cvMethaneBlastInnerRange;
ConVar g_cvMethaneBlastOuterRange;
ConVar g_cvMethaneBlastInnerPush;
ConVar g_cvMethaneBlastOuterPush;

ConVar g_cvMethaneLeakEnable;
ConVar g_cvMethaneLeakCooldown;
ConVar g_cvMethaneLeakDamage;
ConVar g_cvMethaneLeakDuration;
ConVar g_cvMethaneLeakPeriod;
ConVar g_cvMethaneLeakRadius;

ConVar g_cvMethaneStrikeEnable;

ConVar g_cvMoonWalkEnable;
ConVar g_cvMoonWalkSpeed;

ConVar g_cvRestrainedHostageEnable;
ConVar g_cvRestrainedHostageScale;
ConVar g_cvRestrainedHostageDamage;

ConVar g_cvSmokeScreenEnable;
ConVar g_cvSmokeScreenChance;

ConVar g_cvTongueStripEnable;
ConVar g_cvTongueStripChance;

ConVar g_cvTongueWhipEnable;
ConVar g_cvTongueWhipDamage;
ConVar g_cvTongueWhipRange;
ConVar g_cvTongueWhipPush;

ConVar g_cvVoidPocketEnable;
ConVar g_cvVoidPocketCooldown;
ConVar g_cvVoidPocketChance;
ConVar g_cvVoidPocketRange;
ConVar g_cvVoidPocketPull;
ConVar g_cvVoidPocketDamage;

bool g_bHasEliteApi;
bool g_bHasStaggerApi;
bool g_bHasFlingApi;

bool g_bIsChoking[MAXPLAYERS + 1];

float g_fNextAsphyxiationTick[MAXPLAYERS + 1];

float g_fNextMethaneLeakRelease[MAXPLAYERS + 1];
float g_fMethaneCloudUntil[MAXPLAYERS + 1];
float g_fMethaneCloudNextDamage[MAXPLAYERS + 1];
float g_vecMethaneCloudPos[MAXPLAYERS + 1][3];

float g_fNextVoidPocketTick[MAXPLAYERS + 1];

int g_iCollapsedTicks[MAXPLAYERS + 1];
float g_fCollapsedNextTick[MAXPLAYERS + 1];
int g_iCollapsedSmokerUserId[MAXPLAYERS + 1];

Handle g_hThinkTimer;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Smoker Noxious",
	author = "OpenCode",
	description = "Noxious Smoker subtype branch for elite smoker variants.",
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
	MarkNativeAsOptional("L4D_StaggerPlayer");
	MarkNativeAsOptional("L4D2_CTerrorPlayer_Fling");

	RegPluginLibrary("elite_si_smoker_noxious");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_smoker_noxious_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvThinkInterval = CreateConVar("l4d2_elite_smoker_noxious_think_interval", "0.2", "Main think interval in seconds.", FCVAR_NOTIFY, true, 0.05, true, 1.0);

	g_cvAsphyxiationEnable = CreateConVar("l4d2_elite_smoker_noxious_asphyxiation_enable", "1", "Enable Asphyxiation subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAsphyxiationDamage = CreateConVar("l4d2_elite_smoker_noxious_asphyxiation_damage", "5", "Asphyxiation damage per tick.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvAsphyxiationFrequency = CreateConVar("l4d2_elite_smoker_noxious_asphyxiation_frequency", "1.0", "Asphyxiation tick frequency.", FCVAR_NOTIFY, true, 0.1, true, 10.0);
	g_cvAsphyxiationRange = CreateConVar("l4d2_elite_smoker_noxious_asphyxiation_range", "300.0", "Asphyxiation radius.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);

	g_cvCollapsedLungEnable = CreateConVar("l4d2_elite_smoker_noxious_collapsed_lung_enable", "1", "Enable Collapsed Lung subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvCollapsedLungChance = CreateConVar("l4d2_elite_smoker_noxious_collapsed_lung_chance", "100", "Chance (0-100) to apply Collapsed Lung on tongue release.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvCollapsedLungDamage = CreateConVar("l4d2_elite_smoker_noxious_collapsed_lung_damage", "1", "Collapsed Lung damage per second.", FCVAR_NOTIFY, true, 0.0, true, 50.0);
	g_cvCollapsedLungDuration = CreateConVar("l4d2_elite_smoker_noxious_collapsed_lung_duration", "5", "Collapsed Lung duration in seconds.", FCVAR_NOTIFY, true, 1.0, true, 30.0);

	g_cvMethaneBlastEnable = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_enable", "1", "Enable Methane Blast subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMethaneBlastInnerDamage = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_inner_damage", "15", "Inner Methane Blast damage.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvMethaneBlastOuterDamage = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_outer_damage", "5", "Outer Methane Blast damage.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvMethaneBlastInnerRange = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_inner_range", "75.0", "Inner Methane Blast radius.", FCVAR_NOTIFY, true, 30.0, true, 2000.0);
	g_cvMethaneBlastOuterRange = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_outer_range", "150.0", "Outer Methane Blast radius.", FCVAR_NOTIFY, true, 30.0, true, 2000.0);
	g_cvMethaneBlastInnerPush = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_inner_push", "450.0", "Inner Methane Blast fling strength.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);
	g_cvMethaneBlastOuterPush = CreateConVar("l4d2_elite_smoker_noxious_methane_blast_outer_push", "220.0", "Outer Methane Blast fling strength.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);

	g_cvMethaneLeakEnable = CreateConVar("l4d2_elite_smoker_noxious_methane_leak_enable", "1", "Enable Methane Leak subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMethaneLeakCooldown = CreateConVar("l4d2_elite_smoker_noxious_methane_leak_cooldown", "60.0", "Cooldown between Methane Leak clouds.", FCVAR_NOTIFY, true, 1.0, true, 300.0);
	g_cvMethaneLeakDamage = CreateConVar("l4d2_elite_smoker_noxious_methane_leak_damage", "5", "Damage per methane cloud tick.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvMethaneLeakDuration = CreateConVar("l4d2_elite_smoker_noxious_methane_leak_duration", "10.0", "Methane cloud duration.", FCVAR_NOTIFY, true, 0.5, true, 60.0);
	g_cvMethaneLeakPeriod = CreateConVar("l4d2_elite_smoker_noxious_methane_leak_period", "2.0", "Methane cloud damage period.", FCVAR_NOTIFY, true, 0.1, true, 10.0);
	g_cvMethaneLeakRadius = CreateConVar("l4d2_elite_smoker_noxious_methane_leak_radius", "100.0", "Methane cloud radius.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);

	g_cvMethaneStrikeEnable = CreateConVar("l4d2_elite_smoker_noxious_methane_strike_enable", "1", "Enable Methane Strike subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvMoonWalkEnable = CreateConVar("l4d2_elite_smoker_noxious_moon_walk_enable", "1", "Enable Moon Walk subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvMoonWalkSpeed = CreateConVar("l4d2_elite_smoker_noxious_moon_walk_speed", "1.25", "Lagged movement multiplier while choking.", FCVAR_NOTIFY, true, 0.1, true, 3.0);

	g_cvRestrainedHostageEnable = CreateConVar("l4d2_elite_smoker_noxious_restrained_hostage_enable", "1", "Enable Restrained Hostage subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvRestrainedHostageScale = CreateConVar("l4d2_elite_smoker_noxious_restrained_hostage_scale", "0.5", "Incoming damage scale while smoker is choking.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvRestrainedHostageDamage = CreateConVar("l4d2_elite_smoker_noxious_restrained_hostage_damage", "3", "Damage redirected to hostage each hit.", FCVAR_NOTIFY, true, 0.0, true, 100.0);

	g_cvSmokeScreenEnable = CreateConVar("l4d2_elite_smoker_noxious_smoke_screen_enable", "1", "Enable Smoke Screen subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSmokeScreenChance = CreateConVar("l4d2_elite_smoker_noxious_smoke_screen_chance", "20", "Chance (0-100) to nullify incoming damage.", FCVAR_NOTIFY, true, 0.0, true, 100.0);

	g_cvTongueStripEnable = CreateConVar("l4d2_elite_smoker_noxious_tongue_strip_enable", "1", "Enable Tongue Strip subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTongueStripChance = CreateConVar("l4d2_elite_smoker_noxious_tongue_strip_chance", "50", "Chance (0-100) to strip victim item on grab.", FCVAR_NOTIFY, true, 0.0, true, 100.0);

	g_cvTongueWhipEnable = CreateConVar("l4d2_elite_smoker_noxious_tongue_whip_enable", "1", "Enable Tongue Whip subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvTongueWhipDamage = CreateConVar("l4d2_elite_smoker_noxious_tongue_whip_damage", "10", "Tongue Whip damage.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvTongueWhipRange = CreateConVar("l4d2_elite_smoker_noxious_tongue_whip_range", "500.0", "Tongue Whip radius.", FCVAR_NOTIFY, true, 50.0, true, 2500.0);
	g_cvTongueWhipPush = CreateConVar("l4d2_elite_smoker_noxious_tongue_whip_push", "300.0", "Tongue Whip fling strength.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);

	g_cvVoidPocketEnable = CreateConVar("l4d2_elite_smoker_noxious_void_pocket_enable", "1", "Enable Void Pocket subtype logic.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvVoidPocketCooldown = CreateConVar("l4d2_elite_smoker_noxious_void_pocket_cooldown", "5.0", "Cooldown between Void Pocket casts.", FCVAR_NOTIFY, true, 0.5, true, 120.0);
	g_cvVoidPocketChance = CreateConVar("l4d2_elite_smoker_noxious_void_pocket_chance", "35", "Chance (0-100) each cast window.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvVoidPocketRange = CreateConVar("l4d2_elite_smoker_noxious_void_pocket_range", "200.0", "Void Pocket pull radius.", FCVAR_NOTIFY, true, 50.0, true, 2000.0);
	g_cvVoidPocketPull = CreateConVar("l4d2_elite_smoker_noxious_void_pocket_pull", "350.0", "Void Pocket pull strength.", FCVAR_NOTIFY, true, 0.0, true, 4000.0);
	g_cvVoidPocketDamage = CreateConVar("l4d2_elite_smoker_noxious_void_pocket_damage", "0", "Optional damage per pulled survivor.", FCVAR_NOTIFY, true, 0.0, true, 200.0);

	CreateConVar("l4d2_elite_smoker_noxious_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_smoker_noxious");

	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("choke_start", Event_ChokeStart, EventHookMode_Post);
	HookEvent("choke_end", Event_ChokeEnd, EventHookMode_Post);
	HookEvent("tongue_grab", Event_TongueGrab, EventHookMode_Post);
	HookEvent("tongue_release", Event_TongueRelease, EventHookMode_Post);
	HookEvent("player_shoved", Event_PlayerShoved, EventHookMode_Post);

	g_cvThinkInterval.AddChangeHook(OnThinkIntervalChanged);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	RefreshApiState();
	RestartThinkTimer();
}

public void OnAllPluginsLoaded()
{
	RefreshApiState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward") || StrEqual(name, "left4dhooks"))
	{
		RefreshApiState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward") || StrEqual(name, "left4dhooks"))
	{
		RefreshApiState();
	}
}

public void OnMapEnd()
{
	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client, true);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	ResetClientState(client, true);
}

public void OnThinkIntervalChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	RestartThinkTimer();
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!g_cvEnable.BoolValue || !ShouldApplyAnySmokerSubtype(victim, true))
	{
		return Plugin_Continue;
	}

	int subtype = EliteSI_GetSubtype(victim);

	if (subtype == ELITE_SUBTYPE_SMOKER_RESTRAINED_HOSTAGE && g_cvRestrainedHostageEnable.BoolValue && g_bIsChoking[victim])
	{
		float scale = g_cvRestrainedHostageScale.FloatValue;
		if (scale < 0.0)
		{
			scale = 0.0;
		}

		damage *= scale;

		int hostage = GetEntPropEnt(victim, Prop_Send, "m_tongueVictim");
		if (IsValidAliveSurvivor(hostage))
		{
			DealDamage(hostage, victim, g_cvRestrainedHostageDamage.IntValue);
		}

		return Plugin_Changed;
	}

	if (subtype == ELITE_SUBTYPE_SMOKER_SMOKE_SCREEN && g_cvSmokeScreenEnable.BoolValue && !g_bIsChoking[victim])
	{
		int chance = ClampInt(g_cvSmokeScreenChance.IntValue, 0, 100);
		if (GetRandomInt(1, 100) <= chance)
		{
			damage = 0.0;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	ResetAllState();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	ResetClientState(client, true);

	if (!IsValidSmoker(client, true))
	{
		return;
	}

	float now = GetGameTime();
	g_fNextAsphyxiationTick[client] = now + GetRandomFloat(0.2, 0.8);
	g_fNextMethaneLeakRelease[client] = now + GetRandomFloat(0.8, 1.8);
	g_fMethaneCloudUntil[client] = 0.0;
	g_fMethaneCloudNextDamage[client] = 0.0;
	g_fNextVoidPocketTick[client] = now + GetRandomFloat(1.0, 2.0);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidSmoker(victim, false))
	{
		return;
	}

	if (ShouldApplySubtype(victim, ELITE_SUBTYPE_SMOKER_METHANE_BLAST, false) && g_cvMethaneBlastEnable.BoolValue)
	{
		TriggerMethaneBlast(victim);
	}

	ResetClientState(victim, true);
}

public void Event_ChokeStart(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	if (smoker > 0 && smoker <= MaxClients)
	{
		g_bIsChoking[smoker] = true;
	}
}

public void Event_ChokeEnd(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	if (smoker > 0 && smoker <= MaxClients)
	{
		g_bIsChoking[smoker] = false;
		ResetMoonWalkSpeed(smoker);
	}
}

public void Event_TongueGrab(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));

	if (!IsValidSmoker(smoker, true))
	{
		return;
	}

	g_bIsChoking[smoker] = true;

	if (ShouldApplySubtype(smoker, ELITE_SUBTYPE_SMOKER_TONGUE_STRIP, true) && g_cvTongueStripEnable.BoolValue)
	{
		TriggerTongueStrip(victim);
	}
}

public void Event_TongueRelease(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	int victim = GetClientOfUserId(event.GetInt("victim"));

	if (smoker > 0 && smoker <= MaxClients)
	{
		g_bIsChoking[smoker] = false;
		ResetMoonWalkSpeed(smoker);
	}

	if (!IsValidSmoker(smoker, false))
	{
		return;
	}

	if (ShouldApplySubtype(smoker, ELITE_SUBTYPE_SMOKER_COLLAPSED_LUNG, false) && g_cvCollapsedLungEnable.BoolValue)
	{
		TriggerCollapsedLung(smoker, victim);
	}

	if (ShouldApplySubtype(smoker, ELITE_SUBTYPE_SMOKER_TONGUE_WHIP, false) && g_cvTongueWhipEnable.BoolValue)
	{
		TriggerTongueWhip(smoker, victim);
	}
}

public void Event_PlayerShoved(Event event, const char[] name, bool dontBroadcast)
{
	int smoker = GetClientOfUserId(event.GetInt("userid"));
	int survivor = GetClientOfUserId(event.GetInt("attacker"));

	if (!IsValidSmoker(smoker, true) || !IsValidAliveSurvivor(survivor))
	{
		return;
	}

	if (!ShouldApplySubtype(smoker, ELITE_SUBTYPE_SMOKER_METHANE_STRIKE, true) || !g_cvMethaneStrikeEnable.BoolValue)
	{
		return;
	}

	float sourcePos[3];
	GetClientAbsOrigin(smoker, sourcePos);

	if (g_bHasStaggerApi)
	{
		L4D_StaggerPlayer(survivor, smoker, sourcePos);
	}
	else
	{
		float dir[3];
		float survivorPos[3];
		GetClientAbsOrigin(survivor, survivorPos);
		MakeVectorFromPoints(sourcePos, survivorPos, dir);
		ApplyFling(survivor, smoker, dir, 220.0);
	}
}

public Action Timer_MainThink(Handle timer)
{
	if (timer != g_hThinkTimer)
	{
		return Plugin_Stop;
	}

	if (!g_cvEnable.BoolValue || !g_bHasEliteApi)
	{
		return Plugin_Continue;
	}

	float now = GetGameTime();

	for (int smoker = 1; smoker <= MaxClients; smoker++)
	{
		if (!ShouldApplyAnySmokerSubtype(smoker, true))
		{
			continue;
		}

		int subtype = EliteSI_GetSubtype(smoker);
		switch (subtype)
		{
			case ELITE_SUBTYPE_SMOKER_ASPHYXIATION:
			{
				TickAsphyxiation(smoker, now);
			}
			case ELITE_SUBTYPE_SMOKER_METHANE_LEAK:
			{
				TickMethaneLeak(smoker, now);
			}
			case ELITE_SUBTYPE_SMOKER_MOON_WALK:
			{
				TickMoonWalk(smoker);
			}
			case ELITE_SUBTYPE_SMOKER_VOID_POCKET:
			{
				TickVoidPocket(smoker, now);
			}
			default:
			{
				ResetMoonWalkSpeed(smoker);
			}
		}
	}

	TickCollapsedLung(now);
	return Plugin_Continue;
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	if (zclass != ZC_SMOKER || !IsValidSmoker(client, false))
	{
		return;
	}

	if (subtype >= ELITE_SUBTYPE_SMOKER_ASPHYXIATION && subtype <= ELITE_SUBTYPE_SMOKER_VOID_POCKET)
	{
		PrintToServer("[EliteSI Noxious] Assigned subtype %d to smoker #%d.", subtype, client);
	}
}

void TickAsphyxiation(int smoker, float now)
{
	if (!g_cvAsphyxiationEnable.BoolValue)
	{
		return;
	}

	if (now < g_fNextAsphyxiationTick[smoker])
	{
		return;
	}

	float frequency = g_cvAsphyxiationFrequency.FloatValue;
	if (frequency < 0.1)
	{
		frequency = 0.1;
	}
	g_fNextAsphyxiationTick[smoker] = now + frequency;

	float smokerEye[3];
	GetClientEyePosition(smoker, smokerEye);

	float range = g_cvAsphyxiationRange.FloatValue;
	int damage = g_cvAsphyxiationDamage.IntValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float victimEye[3];
		GetClientEyePosition(survivor, victimEye);

		if (GetVectorDistance(smokerEye, victimEye) <= range)
		{
			DealDamage(survivor, smoker, damage);
		}
	}
}

void TickMethaneLeak(int smoker, float now)
{
	if (!g_cvMethaneLeakEnable.BoolValue)
	{
		return;
	}

	if (now >= g_fNextMethaneLeakRelease[smoker])
	{
		float cooldown = g_cvMethaneLeakCooldown.FloatValue;
		if (cooldown < 0.5)
		{
			cooldown = 0.5;
		}

		float duration = g_cvMethaneLeakDuration.FloatValue;
		if (duration < 0.1)
		{
			duration = 0.1;
		}

		GetClientEyePosition(smoker, g_vecMethaneCloudPos[smoker]);
		g_fMethaneCloudUntil[smoker] = now + duration;
		g_fMethaneCloudNextDamage[smoker] = now;
		g_fNextMethaneLeakRelease[smoker] = now + cooldown;

		ShowParticleAt(g_vecMethaneCloudPos[smoker], PARTICLE_METHANE_CLOUD, duration);
	}

	if (g_fMethaneCloudUntil[smoker] <= now || now < g_fMethaneCloudNextDamage[smoker])
	{
		return;
	}

	float period = g_cvMethaneLeakPeriod.FloatValue;
	if (period < 0.1)
	{
		period = 0.1;
	}
	g_fMethaneCloudNextDamage[smoker] = now + period;

	float radius = g_cvMethaneLeakRadius.FloatValue;
	int damage = g_cvMethaneLeakDamage.IntValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		float pos[3];
		GetClientEyePosition(survivor, pos);
		if (GetVectorDistance(pos, g_vecMethaneCloudPos[smoker]) <= radius)
		{
			DealDamage(survivor, smoker, damage);
		}
	}
}

void TickMoonWalk(int smoker)
{
	if (!g_cvMoonWalkEnable.BoolValue)
	{
		ResetMoonWalkSpeed(smoker);
		return;
	}

	if (g_bIsChoking[smoker])
	{
		SetEntPropFloat(smoker, Prop_Send, "m_flLaggedMovementValue", g_cvMoonWalkSpeed.FloatValue);
	}
	else
	{
		ResetMoonWalkSpeed(smoker);
	}
}

void TickVoidPocket(int smoker, float now)
{
	if (!g_cvVoidPocketEnable.BoolValue)
	{
		return;
	}

	if (now < g_fNextVoidPocketTick[smoker])
	{
		return;
	}

	int chance = ClampInt(g_cvVoidPocketChance.IntValue, 0, 100);
	if (GetRandomInt(1, 100) > chance)
	{
		g_fNextVoidPocketTick[smoker] = now + 0.6;
		return;
	}

	float smokerPos[3];
	GetClientEyePosition(smoker, smokerPos);

	float range = g_cvVoidPocketRange.FloatValue;
	float pull = g_cvVoidPocketPull.FloatValue;
	int damage = g_cvVoidPocketDamage.IntValue;
	int affected = 0;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor) || IsSurvivorPinned(survivor))
		{
			continue;
		}

		float survivorPos[3];
		GetClientEyePosition(survivor, survivorPos);

		if (GetVectorDistance(smokerPos, survivorPos) > range)
		{
			continue;
		}

		float dir[3];
		MakeVectorFromPoints(survivorPos, smokerPos, dir);
		ApplyFling(survivor, smoker, dir, pull);

		if (damage > 0)
		{
			DealDamage(survivor, smoker, damage);
		}

		affected++;
	}

	if (affected <= 0)
	{
		g_fNextVoidPocketTick[smoker] = now + 1.0;
		return;
	}

	float cooldown = g_cvVoidPocketCooldown.FloatValue;
	if (cooldown < 0.5)
	{
		cooldown = 0.5;
	}
	g_fNextVoidPocketTick[smoker] = now + cooldown;
}

void TriggerMethaneBlast(int smoker)
{
	float smokerPos[3];
	GetClientEyePosition(smoker, smokerPos);

	float innerRange = g_cvMethaneBlastInnerRange.FloatValue;
	float outerRange = g_cvMethaneBlastOuterRange.FloatValue;
	int innerDamage = g_cvMethaneBlastInnerDamage.IntValue;
	int outerDamage = g_cvMethaneBlastOuterDamage.IntValue;
	float innerPush = g_cvMethaneBlastInnerPush.FloatValue;
	float outerPush = g_cvMethaneBlastOuterPush.FloatValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor) || IsSurvivorPinned(survivor))
		{
			continue;
		}

		float survivorPos[3];
		GetClientEyePosition(survivor, survivorPos);

		float distance = GetVectorDistance(smokerPos, survivorPos);
		if (distance <= innerRange)
		{
			float dir[3];
			MakeVectorFromPoints(smokerPos, survivorPos, dir);
			ApplyFling(survivor, smoker, dir, innerPush);
			DealDamage(survivor, smoker, innerDamage);
		}
		else if (distance <= outerRange)
		{
			float dir[3];
			MakeVectorFromPoints(smokerPos, survivorPos, dir);
			ApplyFling(survivor, smoker, dir, outerPush);
			DealDamage(survivor, smoker, outerDamage);
		}
	}
}

void TriggerCollapsedLung(int smoker, int victim)
{
	if (!IsValidAliveSurvivor(victim))
	{
		return;
	}

	int chance = ClampInt(g_cvCollapsedLungChance.IntValue, 0, 100);
	if (GetRandomInt(1, 100) > chance)
	{
		return;
	}

	g_iCollapsedTicks[victim] = g_cvCollapsedLungDuration.IntValue;
	g_iCollapsedSmokerUserId[victim] = GetClientUserId(smoker);
	g_fCollapsedNextTick[victim] = GetGameTime() + 1.0;
}

void TickCollapsedLung(float now)
{
	if (!g_cvCollapsedLungEnable.BoolValue)
	{
		return;
	}

	int damage = g_cvCollapsedLungDamage.IntValue;

	for (int victim = 1; victim <= MaxClients; victim++)
	{
		if (g_iCollapsedTicks[victim] <= 0 || now < g_fCollapsedNextTick[victim])
		{
			continue;
		}

		if (!IsValidAliveSurvivor(victim))
		{
			g_iCollapsedTicks[victim] = 0;
			continue;
		}

		int smoker = GetClientOfUserId(g_iCollapsedSmokerUserId[victim]);
		if (!IsValidSmoker(smoker, false))
		{
			smoker = 0;
		}

		DealDamage(victim, smoker, damage);
		g_iCollapsedTicks[victim]--;
		g_fCollapsedNextTick[victim] = now + 1.0;
	}
}

void TriggerTongueStrip(int victim)
{
	if (!IsValidAliveSurvivor(victim))
	{
		return;
	}

	int chance = ClampInt(g_cvTongueStripChance.IntValue, 0, 100);
	if (GetRandomInt(1, 100) > chance)
	{
		return;
	}

	int weapon = GetEntPropEnt(victim, Prop_Send, "m_hActiveWeapon");
	if (weapon <= MaxClients || !IsValidEntity(weapon))
	{
		return;
	}

	char classname[64];
	GetEdictClassname(weapon, classname, sizeof(classname));
	if (StrEqual(classname, "weapon_pistol") || StrEqual(classname, "weapon_pistol_magnum"))
	{
		return;
	}

	SDKHooks_DropWeapon(victim, weapon, NULL_VECTOR, NULL_VECTOR);
}

void TriggerTongueWhip(int smoker, int releasedVictim)
{
	float smokerPos[3];
	GetClientEyePosition(smoker, smokerPos);

	float releasedPos[3];
	if (IsValidAliveSurvivor(releasedVictim))
	{
		GetClientEyePosition(releasedVictim, releasedPos);
	}
	else
	{
		releasedPos[0] = smokerPos[0];
		releasedPos[1] = smokerPos[1];
		releasedPos[2] = smokerPos[2];
	}

	float range = g_cvTongueWhipRange.FloatValue;
	float push = g_cvTongueWhipPush.FloatValue;
	int damage = g_cvTongueWhipDamage.IntValue;

	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsValidAliveSurvivor(target) || IsSurvivorPinned(target) || target == releasedVictim)
		{
			continue;
		}

		float targetPos[3];
		GetClientEyePosition(target, targetPos);

		float distSmoker = GetVectorDistance(targetPos, smokerPos);
		float distVictim = GetVectorDistance(targetPos, releasedPos);
		if (distSmoker > range && distVictim > range)
		{
			continue;
		}

		float dir[3];
		MakeVectorFromPoints(smokerPos, targetPos, dir);
		ApplyFling(target, smoker, dir, push);
		DealDamage(target, smoker, damage);
	}
}

void ApplyFling(int target, int attacker, float vecDirection[3], float strength)
{
	if (!IsValidAliveSurvivor(target))
	{
		return;
	}

	if (GetVectorLength(vecDirection) <= 0.001)
	{
		return;
	}

	NormalizeVector(vecDirection, vecDirection);
	ScaleVector(vecDirection, strength);

	if (g_bHasFlingApi)
	{
		if (!IsValidSmoker(attacker, false))
		{
			attacker = target;
		}

		L4D2_CTerrorPlayer_Fling(target, attacker, vecDirection);
		return;
	}

	float currentVelocity[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", currentVelocity);
	AddVectors(currentVelocity, vecDirection, currentVelocity);
	TeleportEntity(target, NULL_VECTOR, NULL_VECTOR, currentVelocity);
}

void DealDamage(int victim, int attacker, int amount)
{
	if (amount <= 0 || victim <= 0 || victim > MaxClients || !IsClientInGame(victim) || !IsPlayerAlive(victim))
	{
		return;
	}

	int attackerEntity = 0;
	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		attackerEntity = attacker;
	}

	SDKHooks_TakeDamage(victim, attackerEntity, attackerEntity, float(amount), DMG_GENERIC);
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i, true);
	}
}

void ResetClientState(int client, bool resetSpeed)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bIsChoking[client] = false;
	g_fNextAsphyxiationTick[client] = 0.0;
	g_fNextMethaneLeakRelease[client] = 0.0;
	g_fMethaneCloudUntil[client] = 0.0;
	g_fMethaneCloudNextDamage[client] = 0.0;
	g_fNextVoidPocketTick[client] = 0.0;

	g_iCollapsedTicks[client] = 0;
	g_iCollapsedSmokerUserId[client] = 0;
	g_fCollapsedNextTick[client] = 0.0;

	g_vecMethaneCloudPos[client][0] = 0.0;
	g_vecMethaneCloudPos[client][1] = 0.0;
	g_vecMethaneCloudPos[client][2] = 0.0;

	if (resetSpeed)
	{
		ResetMoonWalkSpeed(client);
	}
}

void ResetMoonWalkSpeed(int client)
{
	if (!IsValidSmoker(client, false))
	{
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flLaggedMovementValue", 1.0);
}

void RefreshApiState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);

	g_bHasStaggerApi = (GetFeatureStatus(FeatureType_Native, "L4D_StaggerPlayer") == FeatureStatus_Available);
	g_bHasFlingApi = (GetFeatureStatus(FeatureType_Native, "L4D2_CTerrorPlayer_Fling") == FeatureStatus_Available);
}

void RestartThinkTimer()
{
	if (g_hThinkTimer != null)
	{
		KillTimer(g_hThinkTimer);
		g_hThinkTimer = null;
	}

	float interval = g_cvThinkInterval.FloatValue;
	if (interval < 0.05)
	{
		interval = 0.05;
	}

	g_hThinkTimer = CreateTimer(interval, Timer_MainThink, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

bool ShouldApplyAnySmokerSubtype(int client, bool requireAlive)
{
	if (!IsValidSmoker(client, requireAlive) || !g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	int subtype = EliteSI_GetSubtype(client);
	return subtype >= ELITE_SUBTYPE_SMOKER_ASPHYXIATION && subtype <= ELITE_SUBTYPE_SMOKER_VOID_POCKET;
}

bool ShouldApplySubtype(int client, int subtype, bool requireAlive)
{
	if (!ShouldApplyAnySmokerSubtype(client, requireAlive))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == subtype;
}

bool IsValidSmoker(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED)
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_isGhost") == 1)
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	return GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_SMOKER;
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SURVIVOR;
}

bool IsSurvivorPinned(int client)
{
	int attacker = GetEntPropEnt(client, Prop_Send, "m_pummelAttacker");
	if (attacker > 0 && attacker != client)
	{
		return true;
	}

	attacker = GetEntPropEnt(client, Prop_Send, "m_carryAttacker");
	if (attacker > 0 && attacker != client)
	{
		return true;
	}

	attacker = GetEntPropEnt(client, Prop_Send, "m_pounceAttacker");
	if (attacker > 0 && attacker != client)
	{
		return true;
	}

	attacker = GetEntPropEnt(client, Prop_Send, "m_tongueOwner");
	if (attacker > 0 && attacker != client)
	{
		return true;
	}

	attacker = GetEntPropEnt(client, Prop_Send, "m_jockeyAttacker");
	if (attacker > 0 && attacker != client)
	{
		return true;
	}

	return false;
}

int ClampInt(int value, int minValue, int maxValue)
{
	if (value < minValue)
	{
		return minValue;
	}

	if (value > maxValue)
	{
		return maxValue;
	}

	return value;
}

void ShowParticleAt(const float pos[3], const char[] particleName, float lifetime)
{
	int particle = CreateEntityByName("info_particle_system");
	if (particle <= 0 || !IsValidEntity(particle))
	{
		return;
	}

	TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
	DispatchKeyValue(particle, "effect_name", particleName);
	DispatchKeyValue(particle, "targetname", "elite_smoker_noxious_cloud");
	DispatchSpawn(particle);
	ActivateEntity(particle);
	AcceptEntityInput(particle, "start");

	if (lifetime < 0.1)
	{
		lifetime = 0.1;
	}

	CreateTimer(lifetime, Timer_KillEntity, EntIndexToEntRef(particle), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_KillEntity(Handle timer, int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE && IsValidEntity(entity))
	{
		AcceptEntityInput(entity, "Kill");
	}

	return Plugin_Stop;
}
