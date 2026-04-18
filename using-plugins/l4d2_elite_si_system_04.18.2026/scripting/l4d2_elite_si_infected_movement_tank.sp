#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_INFECTED 3
#define ZC_TANK 8

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_ABNORMAL_BEHAVIOR,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvDelay;
ConVar g_cvSpeed;
ConVar g_cvDefaultSpeed;

bool g_bHasEliteApi;
float g_fActiveUntil[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Movement Tank",
	author = "OpenCode",
	description = "Movement subtype module for elite Tank bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_infected_movement_tank_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvDelay = CreateConVar("l4d2_elite_si_infected_movement_tank_delay", "0.0", "Delay before tank movement unlock.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvSpeed = CreateConVar("l4d2_elite_si_infected_movement_tank_speed", "250", "Tank speed during movement window.", FCVAR_NOTIFY, true, 10.0, true, 1000.0);

	CreateConVar("l4d2_elite_si_infected_movement_tank_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_infected_movement_tank");

	g_cvDefaultSpeed = FindConVar("z_tank_speed");

	HookEvent("ability_use", Event_AbilityUse);
	HookEvent("player_death", Event_ResetState);
	HookEvent("player_team", Event_ResetState);
	HookEvent("round_start", Event_RoundReset);
	HookEvent("round_end", Event_RoundReset);

	RefreshEliteState();
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

public void Event_RoundReset(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fActiveUntil[i] = 0.0;
		UnhookThink(i);
	}
}

public void Event_ResetState(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	g_fActiveUntil[client] = 0.0;
	UnhookThink(client);

	if (GetClientTeam(client) == TEAM_INFECTED)
	{
		ResetClientSpeed(client);
	}
}

public void Event_AbilityUse(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplyMovement(client))
	{
		return;
	}

	char ability[16];
	event.GetString("ability", ability, sizeof(ability));
	if (!StrEqual(ability, "ability_throw"))
	{
		return;
	}

	float delay = g_cvDelay.FloatValue;
	if (delay > 0.0)
	{
		CreateTimer(delay, Timer_EnableMovement, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	EnableMovementWindow(client);
}

public Action Timer_EnableMovement(Handle timer, int userId)
{
	int client = GetClientOfUserId(userId);
	if (!ShouldApplyMovement(client))
	{
		return Plugin_Stop;
	}

	EnableMovementWindow(client);
	return Plugin_Stop;
}

void EnableMovementWindow(int client)
{
	g_fActiveUntil[client] = GetGameTime() + 3.0;

	SDKHook(client, SDKHook_PostThinkPost, OnThinkMovement);
	SDKHook(client, SDKHook_PreThink, OnThinkMovement);
	SDKHook(client, SDKHook_PreThinkPost, OnThinkMovement);

	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeed.FloatValue);
}

public void OnThinkMovement(int client)
{
	if (!IsClientInGame(client))
	{
		return;
	}

	if (!ShouldApplyMovement(client))
	{
		g_fActiveUntil[client] = 0.0;
		UnhookThink(client);
		return;
	}

	if (g_fActiveUntil[client] <= GetGameTime())
	{
		g_fActiveUntil[client] = 0.0;
		UnhookThink(client);
		ResetClientSpeed(client);
		return;
	}

	SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeed.FloatValue);
	SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
}

void ResetClientSpeed(int client)
{
	if (!IsClientInGame(client) || g_cvDefaultSpeed == null)
	{
		return;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") == ZC_TANK)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvDefaultSpeed.FloatValue);
	}
}

void UnhookThink(int client)
{
	SDKUnhook(client, SDKHook_PostThinkPost, OnThinkMovement);
	SDKUnhook(client, SDKHook_PreThink, OnThinkMovement);
	SDKUnhook(client, SDKHook_PreThinkPost, OnThinkMovement);
}

bool ShouldApplyMovement(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_TANK)
	{
		return false;
	}

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_ABILITY_MOVEMENT;
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
