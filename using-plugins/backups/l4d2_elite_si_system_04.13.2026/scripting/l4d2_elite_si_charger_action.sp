#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_INFECTED 3
#define ZC_CHARGER 6

enum
{
	ELITE_SUBTYPE_NONE = 0,
	ELITE_SUBTYPE_HARDSI,
	ELITE_SUBTYPE_ABILITY_MOVEMENT,
	ELITE_SUBTYPE_CHARGER_STEERING,
	ELITE_SUBTYPE_CHARGER_ACTION
}

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvEliteOnly;
ConVar g_cvSubtype;

bool g_bHasEliteApi;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Charger Action",
	author = "OpenCode",
	description = "Subtype gate wrapper for Charger Action branch.",
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

	CreateNative("EliteSI_IsChargerAction", Native_IsChargerAction);
	RegPluginLibrary("elite_si_charger_action");
	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_charger_action_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvEliteOnly = CreateConVar("l4d2_elite_charger_action_elite_only", "1", "0=Apply for all bot chargers, 1=Only elite subtype chargers.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSubtype = CreateConVar("l4d2_elite_charger_action_subtype", "4", "Elite subtype id for ChargerAction branch.", FCVAR_NOTIFY, true, 0.0, true, 32.0);

	CreateConVar("l4d2_elite_charger_action_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_charger_action");

	RefreshEliteApiState();
}

public void OnAllPluginsLoaded()
{
	RefreshEliteApiState();
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteApiState();
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "elite_si_core") || StrEqual(name, "l4d2_elite_SI_reward"))
	{
		RefreshEliteApiState();
	}
}

public any Native_IsChargerAction(Handle plugin, int numParams)
{
	if (numParams < 1)
	{
		return false;
	}

	int client = GetNativeCell(1);
	return ShouldApplyChargerAction(client, true);
}

bool ShouldApplyChargerAction(int client, bool requireAlive)
{
	if (!g_cvEnable.BoolValue)
	{
		return false;
	}

	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_CHARGER)
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	if (!g_cvEliteOnly.BoolValue)
	{
		return true;
	}

	if (!g_bHasEliteApi)
	{
		return false;
	}

	if (!EliteSI_IsElite(client))
	{
		return false;
	}

	int requiredSubtype = g_cvSubtype.IntValue;
	if (requiredSubtype <= ELITE_SUBTYPE_NONE)
	{
		requiredSubtype = ELITE_SUBTYPE_CHARGER_ACTION;
	}

	return EliteSI_GetSubtype(client) == requiredSubtype;
}

void RefreshEliteApiState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
