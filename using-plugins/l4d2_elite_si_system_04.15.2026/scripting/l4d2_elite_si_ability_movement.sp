#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_HARDSI,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING
}

enum
{
	ENUM_SMOKE = 1,
	ENUM_SPIT = 2,
	ENUM_TANK = 4
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvBotMask;
ConVar g_cvSmokerMode;
ConVar g_cvDelaySmoker;
ConVar g_cvDelaySpitter;
ConVar g_cvDelayTank;
ConVar g_cvSpeedSmoker;
ConVar g_cvSpeedSpitter;
ConVar g_cvSpeedTank;

ConVar g_cvDefaultSmokerSpeed;
ConVar g_cvDefaultSpitterSpeed;
ConVar g_cvDefaultTankSpeed;

bool g_bHasEliteApi;
float g_fActiveUntil[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Ability Movement",
	author = "OpenCode",
	description = "Ability movement branch for elite ability subtype.",
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

	RegPluginLibrary("elite_si_ability_movement");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_ability_move_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvBotMask = CreateConVar("l4d2_elite_ability_move_bot_mask", "7", "1=Smoker, 2=Spitter, 4=Tank. Add values.", FCVAR_NOTIFY, true, 0.0, true, 7.0);
	g_cvSmokerMode = CreateConVar("l4d2_elite_ability_move_smoker_mode", "2", "0=Only on shoot, 1=while pull, 2=while pull + hanging tongue.", FCVAR_NOTIFY, true, 0.0, true, 2.0);

	g_cvDelaySmoker = CreateConVar("l4d2_elite_ability_move_delay_smoker", "0.0", "Delay before smoker movement unlock.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvDelaySpitter = CreateConVar("l4d2_elite_ability_move_delay_spitter", "0.0", "Delay before spitter movement unlock.", FCVAR_NOTIFY, true, 0.0, true, 5.0);
	g_cvDelayTank = CreateConVar("l4d2_elite_ability_move_delay_tank", "0.0", "Delay before tank movement unlock.", FCVAR_NOTIFY, true, 0.0, true, 5.0);

	g_cvSpeedSmoker = CreateConVar("l4d2_elite_ability_move_speed_smoker", "250", "Smoker speed during ability movement window.", FCVAR_NOTIFY, true, 10.0, true, 1000.0);
	g_cvSpeedSpitter = CreateConVar("l4d2_elite_ability_move_speed_spitter", "250", "Spitter speed during ability movement window.", FCVAR_NOTIFY, true, 10.0, true, 1000.0);
	g_cvSpeedTank = CreateConVar("l4d2_elite_ability_move_speed_tank", "250", "Tank speed during ability movement window.", FCVAR_NOTIFY, true, 10.0, true, 1000.0);

	CreateConVar("l4d2_elite_ability_move_version", PLUGIN_VERSION, "Elite ability movement version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_ability_movement");

	g_cvDefaultTankSpeed = FindConVar("z_tank_speed");
	g_cvDefaultSmokerSpeed = FindConVar("tongue_victim_max_speed");
	g_cvDefaultSpitterSpeed = FindConVar("z_spitter_speed");

	HookEvent("ability_use", Event_AbilityUse);
	HookEvent("player_death", Event_ResetState);
	HookEvent("player_team", Event_ResetState);
	HookEvent("tongue_release", Event_ResetState);
	HookEvent("round_start", Event_RoundReset);
	HookEvent("round_end", Event_RoundReset);

	for (int i = 1; i <= MaxClients; i++)
	{
		g_fActiveUntil[i] = 0.0;
	}

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

	if (GetClientTeam(client) == 3)
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
	if (!ShouldApplyAbilityMovement(client))
	{
		return;
	}

	int abilityType = GetAbilityType(event);
	if (abilityType == 0)
	{
		return;
	}

	if (!IsClassAllowedByMask(abilityType))
	{
		return;
	}

	float delay;
	switch (abilityType)
	{
		case ENUM_SMOKE: delay = g_cvDelaySmoker.FloatValue;
		case ENUM_SPIT: delay = g_cvDelaySpitter.FloatValue;
		case ENUM_TANK: delay = g_cvDelayTank.FloatValue;
	}

	if (delay > 0.0)
	{
		DataPack pack = new DataPack();
		pack.WriteCell(GetClientUserId(client));
		pack.WriteCell(abilityType);
		CreateTimer(delay, Timer_EnableMovement, pack, TIMER_FLAG_NO_MAPCHANGE);
	}
	else
	{
		EnableMovementWindow(client, abilityType);
	}
}

public Action Timer_EnableMovement(Handle timer, DataPack pack)
{
	pack.Reset();
	int userId = pack.ReadCell();
	int abilityType = pack.ReadCell();
	delete pack;

	int client = GetClientOfUserId(userId);
	if (!ShouldApplyAbilityMovement(client))
	{
		return Plugin_Stop;
	}

	EnableMovementWindow(client, abilityType);
	return Plugin_Stop;
}

void EnableMovementWindow(int client, int abilityType)
{
	g_fActiveUntil[client] = GetGameTime() + 3.0;

	SDKHook(client, SDKHook_PostThinkPost, OnThinkMovement);
	SDKHook(client, SDKHook_PreThink, OnThinkMovement);
	SDKHook(client, SDKHook_PreThinkPost, OnThinkMovement);

	ApplyAbilitySpeed(client, abilityType);
}

public void OnThinkMovement(int client)
{
	if (!IsClientInGame(client))
	{
		return;
	}

	if (!ShouldApplyAbilityMovement(client))
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

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	if (zClass == 1)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeedSmoker.FloatValue);
		if (!HandleSmokerContinueWindow(client))
		{
			g_fActiveUntil[client] = 0.0;
			UnhookThink(client);
			ResetClientSpeed(client);
			return;
		}
	}
	else if (zClass == 4)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeedSpitter.FloatValue);
	}
	else if (zClass == 8)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeedTank.FloatValue);
	}

	SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
}

bool HandleSmokerContinueWindow(int client)
{
	int mode = g_cvSmokerMode.IntValue;
	if (mode == 0)
	{
		if (g_fActiveUntil[client] - GetGameTime() > 1.2)
		{
			g_fActiveUntil[client] = GetGameTime() + 1.2;
		}
		return true;
	}

	int sequence = GetEntProp(client, Prop_Send, "m_nSequence");
	if ((mode == 2 || sequence != 31) && (sequence != 2 && sequence != 5))
	{
		g_fActiveUntil[client] = GetGameTime() + 0.5;
		return true;
	}

	return false;
}

void ApplyAbilitySpeed(int client, int abilityType)
{
	switch (abilityType)
	{
		case ENUM_SMOKE: SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeedSmoker.FloatValue);
		case ENUM_SPIT: SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeedSpitter.FloatValue);
		case ENUM_TANK: SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvSpeedTank.FloatValue);
	}
}

void ResetClientSpeed(int client)
{
	if (!IsClientInGame(client))
	{
		return;
	}

	int zClass = GetEntProp(client, Prop_Send, "m_zombieClass");
	if (zClass == 1 && g_cvDefaultSmokerSpeed != null)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvDefaultSmokerSpeed.FloatValue);
	}
	else if (zClass == 4 && g_cvDefaultSpitterSpeed != null)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvDefaultSpitterSpeed.FloatValue);
	}
	else if (zClass == 8 && g_cvDefaultTankSpeed != null)
	{
		SetEntPropFloat(client, Prop_Send, "m_flMaxspeed", g_cvDefaultTankSpeed.FloatValue);
	}
}

void UnhookThink(int client)
{
	SDKUnhook(client, SDKHook_PostThinkPost, OnThinkMovement);
	SDKUnhook(client, SDKHook_PreThink, OnThinkMovement);
	SDKUnhook(client, SDKHook_PreThinkPost, OnThinkMovement);
}

int GetAbilityType(Event event)
{
	char ability[16];
	event.GetString("ability", ability, sizeof(ability));

	if (StrEqual(ability, "ability_tongue"))
	{
		return ENUM_SMOKE;
	}

	if (StrEqual(ability, "ability_spit"))
	{
		return ENUM_SPIT;
	}

	if (StrEqual(ability, "ability_throw"))
	{
		return ENUM_TANK;
	}

	return 0;
}

bool IsClassAllowedByMask(int abilityType)
{
	int mask = g_cvBotMask.IntValue;
	if (abilityType == ENUM_SMOKE)
	{
		return (mask & 1) != 0;
	}

	if (abilityType == ENUM_SPIT)
	{
		return (mask & 2) != 0;
	}

	if (abilityType == ENUM_TANK)
	{
		return (mask & 4) != 0;
	}

	return false;
}

bool ShouldApplyAbilityMovement(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != 3 || !IsFakeClient(client))
	{
		return false;
	}

	if (!g_bHasEliteApi)
	{
		return false;
	}

	if (!EliteSI_IsElite(client))
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
