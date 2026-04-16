#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_BOOMER 2

#define ELITE_BOOMER_SUBTYPE_MIN ELITE_SUBTYPE_BOOMER_BILE_BELLY
#define ELITE_BOOMER_SUBTYPE_MAX ELITE_SUBTYPE_BOOMER_FLATULENCE

#define PARTICLE_FLATULENCE "smoker_smokecloud"
#define TRACE_TOLERANCE 25.0

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_ABNORMAL_BEHAVIOR,
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
	ELITE_SUBTYPE_SMOKER_VOID_POCKET,
	ELITE_SUBTYPE_BOOMER_BILE_BELLY,
	ELITE_SUBTYPE_BOOMER_BILE_BLAST,
	ELITE_SUBTYPE_BOOMER_BILE_FEET,
	ELITE_SUBTYPE_BOOMER_BILE_MASK,
	ELITE_SUBTYPE_BOOMER_BILE_PIMPLE,
	ELITE_SUBTYPE_BOOMER_BILE_SHOWER,
	ELITE_SUBTYPE_BOOMER_BILE_SWIPE,
	ELITE_SUBTYPE_BOOMER_BILE_THROW,
	ELITE_SUBTYPE_BOOMER_EXPLOSIVE_DIARRHEA,
	ELITE_SUBTYPE_BOOMER_FLATULENCE
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);
native bool L4D2_IsEliteSI(int client);
native int L4D2_GetEliteSubtype(int client);

ConVar g_cvThinkInterval;

ConVar g_cvBileBellyEnable;
ConVar g_cvBileBellyDamageScale;

ConVar g_cvBileBlastEnable;
ConVar g_cvBileBlastInnerPush;
ConVar g_cvBileBlastOuterPush;
ConVar g_cvBileBlastInnerDamage;
ConVar g_cvBileBlastOuterDamage;
ConVar g_cvBileBlastInnerRange;
ConVar g_cvBileBlastOuterRange;

ConVar g_cvBileFeetEnable;
ConVar g_cvBileFeetSpeed;
ConVar g_cvBileFeetClearVomitFatigue;

ConVar g_cvBileMaskEnable;
ConVar g_cvBileMaskMode;
ConVar g_cvBileMaskAmount;
ConVar g_cvBileMaskDuration;

ConVar g_cvBilePimpleEnable;
ConVar g_cvBilePimpleChance;
ConVar g_cvBilePimpleDamage;
ConVar g_cvBilePimpleRange;
ConVar g_cvBilePimplePeriod;

ConVar g_cvBileShowerEnable;
ConVar g_cvBileShowerCooldown;

ConVar g_cvBileSwipeEnable;
ConVar g_cvBileSwipeChance;
ConVar g_cvBileSwipeDamage;
ConVar g_cvBileSwipeDuration;

ConVar g_cvBileThrowEnable;
ConVar g_cvBileThrowCooldown;
ConVar g_cvBileThrowDamage;
ConVar g_cvBileThrowRange;
ConVar g_cvBileThrowVisionDot;

ConVar g_cvExplosiveDiarrheaEnable;
ConVar g_cvExplosiveDiarrheaRange;
ConVar g_cvExplosiveDiarrheaRearDot;

ConVar g_cvFlatulenceEnable;
ConVar g_cvFlatulenceBileChance;
ConVar g_cvFlatulenceCooldown;
ConVar g_cvFlatulenceDamage;
ConVar g_cvFlatulenceDuration;
ConVar g_cvFlatulencePeriod;
ConVar g_cvFlatulenceRadius;

ConVar g_cvVomitFatigue;

bool g_bHasEliteApi;
bool g_bHasEliteApiLegacy;
bool g_bHasVomitApi;
bool g_bHasFlingApi;

bool g_bBileFeetBoosted[MAXPLAYERS + 1];

bool g_bHudMasked[MAXPLAYERS + 1];
int g_iHudMaskValue[MAXPLAYERS + 1];
float g_fBileMaskExpireAt[MAXPLAYERS + 1];

float g_fNextBilePimpleTick[MAXPLAYERS + 1];
float g_fNextBileShowerAt[MAXPLAYERS + 1];
float g_fNextBileThrowAt[MAXPLAYERS + 1];

int g_iBileSwipeTicks[MAXPLAYERS + 1];
float g_fNextBileSwipeTick[MAXPLAYERS + 1];
int g_iBileSwipeAttackerUserId[MAXPLAYERS + 1];

float g_fNextFlatulenceRelease[MAXPLAYERS + 1];
float g_fFlatulenceCloudUntil[MAXPLAYERS + 1];
float g_fFlatulenceCloudNextDamage[MAXPLAYERS + 1];
float g_vecFlatulenceCloudPos[MAXPLAYERS + 1][3];

Handle g_hThinkTimer;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Boomer Nauseating",
	author = "OpenCode",
	description = "Nauseating Boomer subtype branch for Elite SI system.",
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
	MarkNativeAsOptional("L4D2_IsEliteSI");
	MarkNativeAsOptional("L4D2_GetEliteSubtype");

	MarkNativeAsOptional("L4D_CTerrorPlayer_OnVomitedUpon");
	MarkNativeAsOptional("L4D2_CTerrorPlayer_Fling");

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvThinkInterval = CreateConVar("l4d2_elite_boomer_nauseating_think_interval", "0.2", "Main think interval in seconds.", FCVAR_NOTIFY, true, 0.05, true, 1.0);

	g_cvBileBellyEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_belly_enable", "1", "Enable Bile Belly subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileBellyDamageScale = CreateConVar("l4d2_elite_boomer_nauseating_bile_belly_damage_scale", "0.5", "Incoming damage scale while Bile Belly is active.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvBileBlastEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_enable", "1", "Enable Bile Blast subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileBlastInnerPush = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_inner_push", "200.0", "Inner Bile Blast push strength.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);
	g_cvBileBlastOuterPush = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_outer_push", "100.0", "Outer Bile Blast push strength.", FCVAR_NOTIFY, true, 0.0, true, 3000.0);
	g_cvBileBlastInnerDamage = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_inner_damage", "15", "Inner Bile Blast damage.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvBileBlastOuterDamage = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_outer_damage", "5", "Outer Bile Blast damage.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvBileBlastInnerRange = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_inner_range", "250.0", "Inner Bile Blast radius.", FCVAR_NOTIFY, true, 50.0, true, 3000.0);
	g_cvBileBlastOuterRange = CreateConVar("l4d2_elite_boomer_nauseating_bile_blast_outer_range", "400.0", "Outer Bile Blast radius.", FCVAR_NOTIFY, true, 50.0, true, 3000.0);

	g_cvBileFeetEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_feet_enable", "1", "Enable Bile Feet subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileFeetSpeed = CreateConVar("l4d2_elite_boomer_nauseating_bile_feet_speed", "1.5", "Lagged movement multiplier for Bile Feet.", FCVAR_NOTIFY, true, 0.1, true, 4.0);
	g_cvBileFeetClearVomitFatigue = CreateConVar("l4d2_elite_boomer_nauseating_bile_feet_clear_vomit_fatigue", "1", "0=Keep z_vomit_fatigue, 1=force z_vomit_fatigue 0 while Bile Feet active.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	g_cvBileMaskEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_mask_enable", "1", "Enable Bile Mask subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileMaskMode = CreateConVar("l4d2_elite_boomer_nauseating_bile_mask_mode", "1", "0=Use fixed duration, 1=Until bile dries.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileMaskAmount = CreateConVar("l4d2_elite_boomer_nauseating_bile_mask_amount", "200", "HUD hide amount (0-255).", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	g_cvBileMaskDuration = CreateConVar("l4d2_elite_boomer_nauseating_bile_mask_duration", "10.0", "Duration in seconds when mode=0.", FCVAR_NOTIFY, true, 0.1, true, 120.0);

	g_cvBilePimpleEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_pimple_enable", "1", "Enable Bile Pimple subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBilePimpleChance = CreateConVar("l4d2_elite_boomer_nauseating_bile_pimple_chance", "5", "Chance per tick to damage each survivor in range (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvBilePimpleDamage = CreateConVar("l4d2_elite_boomer_nauseating_bile_pimple_damage", "10", "Damage per Bile Pimple proc.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvBilePimpleRange = CreateConVar("l4d2_elite_boomer_nauseating_bile_pimple_range", "500.0", "Bile Pimple radius.", FCVAR_NOTIFY, true, 50.0, true, 3000.0);
	g_cvBilePimplePeriod = CreateConVar("l4d2_elite_boomer_nauseating_bile_pimple_period", "0.5", "Bile Pimple check interval.", FCVAR_NOTIFY, true, 0.1, true, 10.0);

	g_cvBileShowerEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_shower_enable", "1", "Enable Bile Shower subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileShowerCooldown = CreateConVar("l4d2_elite_boomer_nauseating_bile_shower_cooldown", "10.0", "Cooldown between extra mob summons.", FCVAR_NOTIFY, true, 0.0, true, 120.0);

	g_cvBileSwipeEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_swipe_enable", "1", "Enable Bile Swipe subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileSwipeChance = CreateConVar("l4d2_elite_boomer_nauseating_bile_swipe_chance", "100", "Chance to apply Bile Swipe on claw hit (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvBileSwipeDamage = CreateConVar("l4d2_elite_boomer_nauseating_bile_swipe_damage", "1", "Damage per second while Bile Swipe is active.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvBileSwipeDuration = CreateConVar("l4d2_elite_boomer_nauseating_bile_swipe_duration", "10", "Duration of Bile Swipe DoT in seconds.", FCVAR_NOTIFY, true, 1.0, true, 60.0);

	g_cvBileThrowEnable = CreateConVar("l4d2_elite_boomer_nauseating_bile_throw_enable", "1", "Enable Bile Throw subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBileThrowCooldown = CreateConVar("l4d2_elite_boomer_nauseating_bile_throw_cooldown", "8.0", "Cooldown for secondary-attack bile throw.", FCVAR_NOTIFY, true, 0.0, true, 120.0);
	g_cvBileThrowDamage = CreateConVar("l4d2_elite_boomer_nauseating_bile_throw_damage", "10", "Damage dealt by Bile Throw impact.", FCVAR_NOTIFY, true, 0.0, true, 200.0);
	g_cvBileThrowRange = CreateConVar("l4d2_elite_boomer_nauseating_bile_throw_range", "700.0", "Max range for Bile Throw target detection.", FCVAR_NOTIFY, true, 50.0, true, 3000.0);
	g_cvBileThrowVisionDot = CreateConVar("l4d2_elite_boomer_nauseating_bile_throw_vision_dot", "0.73", "Dot threshold for Bile Throw view cone.", FCVAR_NOTIFY, true, -1.0, true, 1.0);

	g_cvExplosiveDiarrheaEnable = CreateConVar("l4d2_elite_boomer_nauseating_explosive_diarrhea_enable", "1", "Enable Explosive Diarrhea subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvExplosiveDiarrheaRange = CreateConVar("l4d2_elite_boomer_nauseating_explosive_diarrhea_range", "100.0", "Range behind boomer affected by Explosive Diarrhea.", FCVAR_NOTIFY, true, 20.0, true, 3000.0);
	g_cvExplosiveDiarrheaRearDot = CreateConVar("l4d2_elite_boomer_nauseating_explosive_diarrhea_rear_dot", "0.73", "Reverse cone threshold for Explosive Diarrhea.", FCVAR_NOTIFY, true, -1.0, true, 1.0);

	g_cvFlatulenceEnable = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_enable", "1", "Enable Flatulence subtype.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvFlatulenceBileChance = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_bile_chance", "20", "Chance to apply vomit per Flatulence cloud tick (0-100).", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvFlatulenceCooldown = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_cooldown", "60.0", "Time between Flatulence cloud releases.", FCVAR_NOTIFY, true, 1.0, true, 300.0);
	g_cvFlatulenceDamage = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_damage", "5", "Damage per Flatulence cloud tick.", FCVAR_NOTIFY, true, 0.0, true, 100.0);
	g_cvFlatulenceDuration = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_duration", "10.0", "Flatulence cloud lifetime.", FCVAR_NOTIFY, true, 0.1, true, 120.0);
	g_cvFlatulencePeriod = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_period", "2.0", "Flatulence cloud damage tick interval.", FCVAR_NOTIFY, true, 0.1, true, 30.0);
	g_cvFlatulenceRadius = CreateConVar("l4d2_elite_boomer_nauseating_flatulence_radius", "100.0", "Flatulence cloud radius.", FCVAR_NOTIFY, true, 20.0, true, 3000.0);

	CreateConVar("l4d2_elite_boomer_nauseating_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_boomer_nauseating");

	g_cvVomitFatigue = FindConVar("z_vomit_fatigue");

	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("ability_use", Event_AbilityUse, EventHookMode_Post);
	HookEvent("player_now_it", Event_PlayerNowIt, EventHookMode_Post);
	HookEvent("player_no_longer_it", Event_PlayerNoLongerIt, EventHookMode_Post);

	g_cvThinkInterval.AddChangeHook(OnThinkIntervalChanged);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	PrecacheParticle(PARTICLE_FLATULENCE);
	RefreshApiState();
	RestartThinkTimer();
}

public void OnMapStart()
{
	PrecacheParticle(PARTICLE_FLATULENCE);
}

public void OnMapEnd()
{
	ResetAllState();
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

	if (!IsValidBoomer(client, true))
	{
		return;
	}

	float now = GetGameTime();
	g_fNextBilePimpleTick[client] = now + GetRandomFloat(0.2, 0.8);
	g_fNextFlatulenceRelease[client] = now + GetRandomFloat(0.8, 1.8);
	g_fNextBileThrowAt[client] = now;
	g_fNextBileShowerAt[client] = now;

	if (ShouldApplySubtype(client, ELITE_SUBTYPE_BOOMER_BILE_FEET, true) && g_cvBileFeetEnable.BoolValue)
	{
		ApplyBileFeet(client, true);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (victim <= 0 || victim > MaxClients)
	{
		return;
	}

	if (IsValidBoomer(victim, false))
	{
		if (ShouldApplySubtype(victim, ELITE_SUBTYPE_BOOMER_BILE_BLAST, false) && g_cvBileBlastEnable.BoolValue)
		{
			TriggerBileBlast(victim);
		}

		ResetBileFeet(victim);
	}

	ClearBileMask(victim);
	ClearBileSwipe(victim);
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidBoomer(client, true))
	{
		return;
	}

	char ability[32];
	event.GetString("ability", ability, sizeof(ability));

	if (StrEqual(ability, "ability_vomit")
		&& ShouldApplySubtype(client, ELITE_SUBTYPE_BOOMER_EXPLOSIVE_DIARRHEA, true)
		&& g_cvExplosiveDiarrheaEnable.BoolValue)
	{
		TriggerExplosiveDiarrhea(client);
	}
}

public void Event_PlayerNowIt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (!IsValidAliveSurvivor(victim) || !IsValidBoomer(attacker, false))
	{
		return;
	}

	if (ShouldApplySubtype(attacker, ELITE_SUBTYPE_BOOMER_BILE_SHOWER, false) && g_cvBileShowerEnable.BoolValue)
	{
		TryTriggerBileShower(attacker);
	}

	if (ShouldApplySubtype(attacker, ELITE_SUBTYPE_BOOMER_BILE_MASK, false) && g_cvBileMaskEnable.BoolValue)
	{
		ApplyBileMask(victim);
	}
}

public void Event_PlayerNoLongerIt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(victim))
	{
		return;
	}

	if (g_bHudMasked[victim] && g_cvBileMaskMode.IntValue != 0)
	{
		ClearBileMask(victim);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	Action action = Plugin_Continue;

	if (damage > 0.0
		&& IsValidBoomer(victim, true)
		&& IsValidAliveSurvivor(attacker)
		&& ShouldApplySubtype(victim, ELITE_SUBTYPE_BOOMER_BILE_BELLY, true)
		&& g_cvBileBellyEnable.BoolValue)
	{
		float scale = g_cvBileBellyDamageScale.FloatValue;
		if (scale < 0.0)
		{
			scale = 0.0;
		}

		if (FloatAbs(scale - 1.0) > 0.0001)
		{
			damage *= scale;
			action = Plugin_Changed;
		}
	}

	if (IsValidBoomer(attacker, true)
		&& IsValidAliveSurvivor(victim)
		&& ShouldApplySubtype(attacker, ELITE_SUBTYPE_BOOMER_BILE_SWIPE, true)
		&& g_cvBileSwipeEnable.BoolValue)
	{
		char weapon[64];
		GetClientWeapon(attacker, weapon, sizeof(weapon));
		if (StrEqual(weapon, "weapon_boomer_claw"))
		{
			TryApplyBileSwipe(victim, attacker);
		}
	}

	return action;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if ((buttons & IN_ATTACK2) == 0)
	{
		return Plugin_Continue;
	}

	if (!g_cvBileThrowEnable.BoolValue || !ShouldApplySubtype(client, ELITE_SUBTYPE_BOOMER_BILE_THROW, true))
	{
		return Plugin_Continue;
	}

	TryBileThrow(client);
	return Plugin_Continue;
}

public Action Timer_MainThink(Handle timer)
{
	if (timer != g_hThinkTimer)
	{
		return Plugin_Stop;
	}

	float now = GetGameTime();

	TickBileSwipe(now);
	TickBileMask(now);
	TickFlatulenceClouds(now);

	for (int boomer = 1; boomer <= MaxClients; boomer++)
	{
		if (!IsValidBoomer(boomer, true))
		{
			ResetBileFeet(boomer);
			continue;
		}

		int subtype = GetBoomerSubtype(boomer);
		switch (subtype)
		{
			case ELITE_SUBTYPE_BOOMER_BILE_FEET:
			{
				if (g_cvBileFeetEnable.BoolValue)
				{
					ApplyBileFeet(boomer, false);
				}
				else
				{
					ResetBileFeet(boomer);
				}
			}

			case ELITE_SUBTYPE_BOOMER_BILE_PIMPLE:
			{
				ResetBileFeet(boomer);
				if (g_cvBilePimpleEnable.BoolValue)
				{
					TickBilePimple(boomer, now);
				}
			}

			case ELITE_SUBTYPE_BOOMER_FLATULENCE:
			{
				ResetBileFeet(boomer);
				if (g_cvFlatulenceEnable.BoolValue)
				{
					TickFlatulenceRelease(boomer, now);
				}
			}

			default:
			{
				ResetBileFeet(boomer);
			}
		}
	}

	return Plugin_Continue;
}

void RefreshApiState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);

	g_bHasEliteApiLegacy = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "L4D2_GetEliteSubtype") == FeatureStatus_Available);

	g_bHasVomitApi = (GetFeatureStatus(FeatureType_Native, "L4D_CTerrorPlayer_OnVomitedUpon") == FeatureStatus_Available);
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

void TickBilePimple(int boomer, float now)
{
	if (now < g_fNextBilePimpleTick[boomer])
	{
		return;
	}

	float period = g_cvBilePimplePeriod.FloatValue;
	if (period < 0.1)
	{
		period = 0.1;
	}
	g_fNextBilePimpleTick[boomer] = now + period;

	int chance = ClampInt(g_cvBilePimpleChance.IntValue, 0, 100);
	int damage = g_cvBilePimpleDamage.IntValue;
	float range = g_cvBilePimpleRange.FloatValue;

	float boomerEye[3];
	GetClientEyePosition(boomer, boomerEye);

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		if (GetRandomInt(1, 100) > chance)
		{
			continue;
		}

		float survivorEye[3];
		GetClientEyePosition(survivor, survivorEye);

		if (GetVectorDistance(boomerEye, survivorEye) <= range)
		{
			DealDamage(survivor, boomer, damage);
		}
	}
}

void TriggerBileBlast(int boomer)
{
	float boomerEye[3];
	GetClientEyePosition(boomer, boomerEye);

	float innerRange = g_cvBileBlastInnerRange.FloatValue;
	float outerRange = g_cvBileBlastOuterRange.FloatValue;
	int innerDamage = g_cvBileBlastInnerDamage.IntValue;
	int outerDamage = g_cvBileBlastOuterDamage.IntValue;
	float innerPush = g_cvBileBlastInnerPush.FloatValue;
	float outerPush = g_cvBileBlastOuterPush.FloatValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor) || IsSurvivorPinned(survivor))
		{
			continue;
		}

		float survivorEye[3];
		GetClientEyePosition(survivor, survivorEye);

		float distance = GetVectorDistance(boomerEye, survivorEye);
		float push = 0.0;
		int damage = 0;

		if (distance <= innerRange)
		{
			push = innerPush;
			damage = innerDamage;
		}
		else if (distance <= outerRange)
		{
			push = outerPush;
			damage = outerDamage;
		}

		if (damage <= 0)
		{
			continue;
		}

		float vecPush[3];
		MakeVectorFromPoints(boomerEye, survivorEye, vecPush);
		ApplyFling(survivor, boomer, vecPush, push);
		DealDamage(survivor, boomer, damage);
	}
}

void ApplyBileFeet(int boomer, bool firstApply)
{
	if (!IsValidBoomer(boomer, true))
	{
		ResetBileFeet(boomer);
		return;
	}

	bool wasBoosted = g_bBileFeetBoosted[boomer];

	float speed = g_cvBileFeetSpeed.FloatValue;
	if (speed < 0.1)
	{
		speed = 0.1;
	}

	SetEntPropFloat(boomer, Prop_Send, "m_flLaggedMovementValue", speed);
	g_bBileFeetBoosted[boomer] = true;

	if (g_cvBileFeetClearVomitFatigue.BoolValue && g_cvVomitFatigue != null && (firstApply || !wasBoosted))
	{
		g_cvVomitFatigue.FloatValue = 0.0;
	}
}

void ResetBileFeet(int boomer)
{
	if (!g_bBileFeetBoosted[boomer])
	{
		return;
	}

	if (IsClientInGame(boomer))
	{
		SetEntPropFloat(boomer, Prop_Send, "m_flLaggedMovementValue", 1.0);
	}

	g_bBileFeetBoosted[boomer] = false;
}

void ApplyBileMask(int survivor)
{
	if (!IsValidAliveSurvivor(survivor))
	{
		return;
	}

	int amount = ClampInt(g_cvBileMaskAmount.IntValue, 0, 255);
	SetEntProp(survivor, Prop_Send, "m_iHideHUD", amount);

	g_bHudMasked[survivor] = true;
	g_iHudMaskValue[survivor] = amount;
	g_fBileMaskExpireAt[survivor] = 0.0;

	if (g_cvBileMaskMode.IntValue == 0)
	{
		float duration = g_cvBileMaskDuration.FloatValue;
		if (duration < 0.1)
		{
			duration = 0.1;
		}

		g_fBileMaskExpireAt[survivor] = GetGameTime() + duration;
	}
}

void TickBileMask(float now)
{
	if (g_cvBileMaskMode.IntValue != 0)
	{
		return;
	}

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!g_bHudMasked[survivor] || g_fBileMaskExpireAt[survivor] <= 0.0)
		{
			continue;
		}

		if (now >= g_fBileMaskExpireAt[survivor])
		{
			ClearBileMask(survivor);
		}
	}
}

void ClearBileMask(int survivor)
{
	if (survivor <= 0 || survivor > MaxClients)
	{
		return;
	}

	if (g_bHudMasked[survivor] && IsClientInGame(survivor))
	{
		SetEntProp(survivor, Prop_Send, "m_iHideHUD", 0);
	}

	g_bHudMasked[survivor] = false;
	g_iHudMaskValue[survivor] = 0;
	g_fBileMaskExpireAt[survivor] = 0.0;
}

void TryTriggerBileShower(int boomer)
{
	float now = GetGameTime();
	if (now < g_fNextBileShowerAt[boomer])
	{
		return;
	}

	float cooldown = g_cvBileShowerCooldown.FloatValue;
	if (cooldown < 0.0)
	{
		cooldown = 0.0;
	}
	g_fNextBileShowerAt[boomer] = now + cooldown;

	int flags = GetCommandFlags("z_spawn_old");
	if (flags != -1)
	{
		SetCommandFlags("z_spawn_old", flags & ~FCVAR_CHEAT);
	}

	FakeClientCommand(boomer, "z_spawn_old mob auto");

	if (flags != -1)
	{
		SetCommandFlags("z_spawn_old", flags);
	}
}

void TryApplyBileSwipe(int victim, int attacker)
{
	int chance = ClampInt(g_cvBileSwipeChance.IntValue, 0, 100);
	if (GetRandomInt(1, 100) > chance)
	{
		return;
	}

	int duration = g_cvBileSwipeDuration.IntValue;
	if (duration < 1)
	{
		duration = 1;
	}

	g_iBileSwipeTicks[victim] = duration;
	g_fNextBileSwipeTick[victim] = GetGameTime() + 1.0;
	g_iBileSwipeAttackerUserId[victim] = GetClientUserId(attacker);
}

void TickBileSwipe(float now)
{
	int damage = g_cvBileSwipeDamage.IntValue;

	for (int victim = 1; victim <= MaxClients; victim++)
	{
		if (g_iBileSwipeTicks[victim] <= 0 || now < g_fNextBileSwipeTick[victim])
		{
			continue;
		}

		if (!IsValidAliveSurvivor(victim))
		{
			ClearBileSwipe(victim);
			continue;
		}

		int attacker = GetClientOfUserId(g_iBileSwipeAttackerUserId[victim]);
		if (!IsValidBoomer(attacker, false))
		{
			attacker = 0;
		}

		DealDamage(victim, attacker, damage);
		g_iBileSwipeTicks[victim]--;
		g_fNextBileSwipeTick[victim] = now + 1.0;

		if (g_iBileSwipeTicks[victim] <= 0)
		{
			ClearBileSwipe(victim);
		}
	}
}

void ClearBileSwipe(int victim)
{
	if (victim <= 0 || victim > MaxClients)
	{
		return;
	}

	g_iBileSwipeTicks[victim] = 0;
	g_fNextBileSwipeTick[victim] = 0.0;
	g_iBileSwipeAttackerUserId[victim] = 0;
}

void TryBileThrow(int boomer)
{
	float now = GetGameTime();
	if (now < g_fNextBileThrowAt[boomer])
	{
		return;
	}

	float range = g_cvBileThrowRange.FloatValue;
	float visionDot = g_cvBileThrowVisionDot.FloatValue;
	int damage = g_cvBileThrowDamage.IntValue;

	int hits = 0;
	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		if (!ClientViews(boomer, survivor, range, visionDot))
		{
			continue;
		}

		ApplyVomitToSurvivor(survivor, boomer);
		DealDamage(survivor, boomer, damage);
		hits++;
	}

	if (hits <= 0)
	{
		return;
	}

	float cooldown = g_cvBileThrowCooldown.FloatValue;
	if (cooldown < 0.0)
	{
		cooldown = 0.0;
	}
	g_fNextBileThrowAt[boomer] = now + cooldown;
}

void TriggerExplosiveDiarrhea(int boomer)
{
	float range = g_cvExplosiveDiarrheaRange.FloatValue;
	float rearDot = g_cvExplosiveDiarrheaRearDot.FloatValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidAliveSurvivor(survivor))
		{
			continue;
		}

		if (!ClientViewsReverse(boomer, survivor, range, rearDot))
		{
			continue;
		}

		ApplyVomitToSurvivor(survivor, boomer);
	}
}

void TickFlatulenceRelease(int boomer, float now)
{
	if (now < g_fNextFlatulenceRelease[boomer])
	{
		return;
	}

	float cooldown = g_cvFlatulenceCooldown.FloatValue;
	if (cooldown < 0.5)
	{
		cooldown = 0.5;
	}

	float duration = g_cvFlatulenceDuration.FloatValue;
	if (duration < 0.1)
	{
		duration = 0.1;
	}

	GetClientAbsOrigin(boomer, g_vecFlatulenceCloudPos[boomer]);
	g_fFlatulenceCloudUntil[boomer] = now + duration;
	g_fFlatulenceCloudNextDamage[boomer] = now;
	g_fNextFlatulenceRelease[boomer] = now + cooldown;

	ShowParticleAt(g_vecFlatulenceCloudPos[boomer], PARTICLE_FLATULENCE, duration);
}

void TickFlatulenceClouds(float now)
{
	int damage = g_cvFlatulenceDamage.IntValue;
	int bileChance = ClampInt(g_cvFlatulenceBileChance.IntValue, 0, 100);
	float radius = g_cvFlatulenceRadius.FloatValue;

	for (int owner = 1; owner <= MaxClients; owner++)
	{
		if (g_fFlatulenceCloudUntil[owner] <= now || now < g_fFlatulenceCloudNextDamage[owner])
		{
			continue;
		}

		float period = g_cvFlatulencePeriod.FloatValue;
		if (period < 0.1)
		{
			period = 0.1;
		}
		g_fFlatulenceCloudNextDamage[owner] = now + period;

		int attacker = IsValidBoomer(owner, false) ? owner : 0;

		for (int survivor = 1; survivor <= MaxClients; survivor++)
		{
			if (!IsValidAliveSurvivor(survivor))
			{
				continue;
			}

			float eye[3];
			GetClientEyePosition(survivor, eye);

			if (GetVectorDistance(eye, g_vecFlatulenceCloudPos[owner]) > radius)
			{
				continue;
			}

			if (!IsVisibleTo(g_vecFlatulenceCloudPos[owner], eye))
			{
				continue;
			}

			DealDamage(survivor, attacker, damage);

			if (GetRandomInt(1, 100) <= bileChance)
			{
				ApplyVomitToSurvivor(survivor, attacker);
			}
		}
	}
}

void ApplyVomitToSurvivor(int victim, int attacker)
{
	if (!g_bHasVomitApi || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	if (!IsValidBoomer(attacker, false))
	{
		attacker = victim;
	}

	L4D_CTerrorPlayer_OnVomitedUpon(victim, attacker);
}

void ApplyFling(int target, int attacker, float direction[3], float strength)
{
	if (!IsValidAliveSurvivor(target) || strength <= 0.0)
	{
		return;
	}

	if (GetVectorLength(direction) <= 0.001)
	{
		return;
	}

	NormalizeVector(direction, direction);
	ScaleVector(direction, strength);

	if (g_bHasFlingApi)
	{
		if (!IsValidBoomer(attacker, false))
		{
			attacker = target;
		}

		L4D2_CTerrorPlayer_Fling(target, attacker, direction);
		return;
	}

	float velocity[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", velocity);
	AddVectors(velocity, direction, velocity);
	TeleportEntity(target, NULL_VECTOR, NULL_VECTOR, velocity);
}

void DealDamage(int victim, int attacker, int amount)
{
	if (amount <= 0 || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	int source = 0;
	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		source = attacker;
	}

	char targetName[32];
	char damageStr[16];
	Format(targetName, sizeof(targetName), "elite_boomer_nauseating_hurt_%d", victim);
	IntToString(amount, damageStr, sizeof(damageStr));

	int pointHurt = CreateEntityByName("point_hurt");
	if (pointHurt > MaxClients && IsValidEntity(pointHurt))
	{
		DispatchKeyValue(victim, "targetname", targetName);
		DispatchKeyValue(pointHurt, "DamageTarget", targetName);
		DispatchKeyValue(pointHurt, "Damage", damageStr);
		DispatchKeyValue(pointHurt, "DamageType", "0");
		DispatchSpawn(pointHurt);

		float pos[3];
		GetClientEyePosition(victim, pos);
		TeleportEntity(pointHurt, pos, NULL_VECTOR, NULL_VECTOR);

		int activator = -1;
		if (source > 0 && source <= MaxClients && IsClientInGame(source))
		{
			activator = source;
		}

		AcceptEntityInput(pointHurt, "Hurt", activator);
		DispatchKeyValue(victim, "targetname", "null");
		RemoveEntity(pointHurt);
		return;
	}

	SDKHooks_TakeDamage(victim, source, source, float(amount), DMG_GENERIC);
}

bool ShouldApplySubtype(int client, int subtype, bool requireAlive)
{
	if (!IsValidBoomer(client, requireAlive))
	{
		return false;
	}

	return GetBoomerSubtype(client) == subtype;
}

int GetBoomerSubtype(int client)
{
	if (!IsValidBoomer(client, false))
	{
		return ELITE_SUBTYPE_NONE;
	}

	if (g_bHasEliteApi && EliteSI_IsElite(client))
	{
		int subtype = EliteSI_GetSubtype(client);
		if (subtype >= ELITE_BOOMER_SUBTYPE_MIN && subtype <= ELITE_BOOMER_SUBTYPE_MAX)
		{
			return subtype;
		}
	}

	if (g_bHasEliteApiLegacy && L4D2_IsEliteSI(client))
	{
		int subtype = L4D2_GetEliteSubtype(client);
		if (subtype >= ELITE_BOOMER_SUBTYPE_MIN && subtype <= ELITE_BOOMER_SUBTYPE_MAX)
		{
			return subtype;
		}
	}

	return ELITE_SUBTYPE_NONE;
}

bool IsValidBoomer(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED)
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_BOOMER)
	{
		return false;
	}

	if (requireAlive)
	{
		if (!IsPlayerAlive(client))
		{
			return false;
		}

		if (GetEntProp(client, Prop_Send, "m_isGhost") == 1)
		{
			return false;
		}
	}

	return true;
}

bool IsValidClient(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client));
}

bool IsValidAliveSurvivor(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client) && GetClientTeam(client) == TEAM_SURVIVOR);
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

bool ClientViews(int viewer, int target, float maxDistance, float threshold)
{
	return CheckClientViewCone(viewer, target, maxDistance, threshold, true);
}

bool ClientViewsReverse(int viewer, int target, float maxDistance, float threshold)
{
	return CheckClientViewCone(viewer, target, maxDistance, threshold, false);
}

bool CheckClientViewCone(int viewer, int target, float maxDistance, float threshold, bool isForwardCone)
{
	if (!IsClientInGame(viewer) || !IsPlayerAlive(viewer) || !IsValidAliveSurvivor(target))
	{
		return false;
	}

	float viewPos[3];
	float targetPos[3];
	GetClientEyePosition(viewer, viewPos);
	GetClientEyePosition(target, targetPos);

	float distVec[3];
	MakeVectorFromPoints(viewPos, targetPos, distVec);

	if (maxDistance > 0.0 && GetVectorLength(distVec) > maxDistance)
	{
		return false;
	}

	if (GetVectorLength(distVec) <= 0.001)
	{
		return false;
	}

	float viewAng[3];
	GetClientEyeAngles(viewer, viewAng);
	viewAng[0] = 0.0;
	viewAng[2] = 0.0;

	float viewDir[3];
	GetAngleVectors(viewAng, viewDir, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(viewDir, viewDir);

	NormalizeVector(distVec, distVec);
	float dot = GetVectorDotProduct(viewDir, distVec);

	if (isForwardCone)
	{
		if (dot < threshold)
		{
			return false;
		}
	}
	else
	{
		if (dot > threshold)
		{
			return false;
		}
	}

	return IsVisibleTo(viewPos, targetPos);
}

bool IsVisibleTo(const float start[3], const float target[3])
{
	float angles[3];
	float look[3];
	MakeVectorFromPoints(start, target, look);
	GetVectorAngles(look, angles);

	Handle trace = TR_TraceRayFilterEx(start, angles, MASK_SHOT, RayType_Infinite, TraceFilter_WorldOnly);
	bool visible = false;

	if (TR_DidHit(trace))
	{
		float hitPos[3];
		TR_GetEndPosition(hitPos, trace);
		if ((GetVectorDistance(start, hitPos, false) + TRACE_TOLERANCE) >= GetVectorDistance(start, target))
		{
			visible = true;
		}
	}
	else
	{
		visible = true;
	}

	delete trace;
	return visible;
}

public bool TraceFilter_WorldOnly(int entity, int contentsMask)
{
	return (entity == 0 || entity > MaxClients);
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

void PrecacheParticle(const char[] effectName)
{
	int table = FindStringTable("ParticleEffectNames");
	if (table == INVALID_STRING_TABLE)
	{
		return;
	}

	bool lock = LockStringTables(false);
	AddToStringTable(table, effectName);
	LockStringTables(lock);
}

void ResetAllState()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i, true);
	}
}

void ResetClientState(int client, bool resetMovement)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_fNextBilePimpleTick[client] = 0.0;
	g_fNextBileShowerAt[client] = 0.0;
	g_fNextBileThrowAt[client] = 0.0;

	ClearBileSwipe(client);
	ClearBileMask(client);

	g_fNextFlatulenceRelease[client] = 0.0;
	g_fFlatulenceCloudUntil[client] = 0.0;
	g_fFlatulenceCloudNextDamage[client] = 0.0;
	g_vecFlatulenceCloudPos[client][0] = 0.0;
	g_vecFlatulenceCloudPos[client][1] = 0.0;
	g_vecFlatulenceCloudPos[client][2] = 0.0;

	if (resetMovement)
	{
		ResetBileFeet(client);
	}
}
