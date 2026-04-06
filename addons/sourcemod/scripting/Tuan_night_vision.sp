/**
 * Simplified night vision plugin for L4D2 survivors.
 *
 * Uses a client-only [`light_dynamic`](server-sourcemod/addons/sourcemod/scripting/Tuan_night_vision.sp:151)
 * approach based on the reference night vision plugin, but keeps the feature set minimal:
 * - No chat commands
 * - No mode switching
 * - No color selection
 * - Fixed green dynamic light for better visibility at night
 * - Toggle by double-tapping flashlight
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "2.0.0"
#define PLUGIN_DESCRIPTION "Simple green night vision for survivors"
#define IMPULS_FLASHLIGHT 100
#define NV_TAP_INTERVAL 0.3
#define NV_COLOR "50 255 50 255"
#define NV_BRIGHTNESS "3"
#define NV_DISTANCE 750.0
#define NV_OFFSET_Z 20.0

public Plugin myinfo =
{
	name = "[L4D2] Night Vision",
	author = "Tuan",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://steamcommunity.com/id/Strikeraot/"
};

int g_iPlayerLight[MAXPLAYERS + 1] = {INVALID_ENT_REFERENCE, ...};
float g_fLastFlashlightPress[MAXPLAYERS + 1];
bool g_bNightVisionEnabled[MAXPLAYERS + 1];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("round_start", Event_RoundStart);

	for (int i = 1; i <= MaxClients; i++)
	{
		ResetClientState(i);
	}
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
}

public void OnClientDisconnect(int client)
{
	RemoveClientNightVision(client);
	ResetClientState(client);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!IsAliveSurvivor(client))
	{
		return Plugin_Continue;
	}

	if (impulse != IMPULS_FLASHLIGHT)
	{
		return Plugin_Continue;
	}

	float currentTime = GetEngineTime();
	if (currentTime - g_fLastFlashlightPress[client] <= NV_TAP_INTERVAL)
	{
		ToggleNightVision(client);
	}

	g_fLastFlashlightPress[client] = currentTime;
	return Plugin_Continue;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!IsAliveSurvivor(client))
	{
		return;
	}

	if (g_bNightVisionEnabled[client])
	{
		CreateClientNightVision(client);
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	RemoveClientNightVision(client);
	g_bNightVisionEnabled[client] = false;
	g_fLastFlashlightPress[client] = 0.0;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	RemoveClientNightVision(client);
	g_bNightVisionEnabled[client] = false;
	g_fLastFlashlightPress[client] = 0.0;
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		RemoveClientNightVision(i);
		g_bNightVisionEnabled[i] = false;
		g_fLastFlashlightPress[i] = 0.0;
	}
}

void ToggleNightVision(int client)
{
	g_bNightVisionEnabled[client] = !g_bNightVisionEnabled[client];

	if (!g_bNightVisionEnabled[client])
	{
		RemoveClientNightVision(client);
		PrintToChat(client, "\x04[Night Vision]\x01 Disabled");
		return;
	}

	if (!CreateClientNightVision(client))
	{
		g_bNightVisionEnabled[client] = false;
		PrintToChat(client, "\x04[Night Vision]\x01 Failed to create dynamic light");
		return;
	}

	PrintToChat(client, "\x04[Night Vision]\x01 Enabled");
}

bool CreateClientNightVision(int client)
{
	RemoveClientNightVision(client);

	int light = CreateEntityByName("light_dynamic");
	if (!IsValidEntity(light))
	{
		return false;
	}

	DispatchKeyValue(light, "_light", NV_COLOR);
	DispatchKeyValue(light, "brightness", NV_BRIGHTNESS);
	DispatchKeyValueFloat(light, "spotlight_radius", 32.0);
	DispatchKeyValueFloat(light, "distance", NV_DISTANCE);
	DispatchKeyValue(light, "style", "0");

	DispatchSpawn(light);
	AcceptEntityInput(light, "TurnOn");
	SetVariantString("!activator");
	AcceptEntityInput(light, "SetParent", client);
	TeleportEntity(light, view_as<float>({0.0, 0.0, NV_OFFSET_Z}), view_as<float>({0.0, 0.0, 0.0}), NULL_VECTOR);

	SDKHook(light, SDKHook_SetTransmit, Hook_SetTransmit);
	g_iPlayerLight[client] = EntIndexToEntRef(light);

	if (!CheckEntityLimit(g_iPlayerLight[client]))
	{
		g_iPlayerLight[client] = INVALID_ENT_REFERENCE;
		return false;
	}

	return true;
}

void RemoveClientNightVision(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	if (g_iPlayerLight[client] == INVALID_ENT_REFERENCE)
	{
		return;
	}

	int entity = EntRefToEntIndex(g_iPlayerLight[client]);
	if (entity > MaxClients && IsValidEntity(entity))
	{
		RemoveEntity(entity);
	}

	g_iPlayerLight[client] = INVALID_ENT_REFERENCE;
}

public Action Hook_SetTransmit(int entity, int client)
{
	if (client < 1 || client > MaxClients)
	{
		return Plugin_Handled;
	}

	if (g_iPlayerLight[client] != EntIndexToEntRef(entity))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void ResetClientState(int client)
{
	if (client < 1 || client > MaxClients)
	{
		return;
	}

	g_iPlayerLight[client] = INVALID_ENT_REFERENCE;
	g_fLastFlashlightPress[client] = 0.0;
	g_bNightVisionEnabled[client] = false;
}

bool CheckEntityLimit(int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity == INVALID_ENT_REFERENCE)
	{
		return false;
	}

	if (entity > 2000)
	{
		AcceptEntityInput(entity, "Kill");
		return false;
	}

	return true;
}

bool IsValidSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& !IsFakeClient(client)
		&& GetClientTeam(client) == 2;
}

bool IsAliveSurvivor(int client)
{
	return IsValidSurvivor(client) && IsPlayerAlive(client);
}
