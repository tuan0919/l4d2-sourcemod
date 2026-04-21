#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <left4dhooks>
#include <actions>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_CHARGER 6
#define ELITE_SUBTYPE_CHARGER_UNSTOPPABLE 35

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvCarryMaxDuration;
ConVar g_cvFastCooldown;
ConVar g_cvKnockbackForce;
ConVar g_cvKnockbackUpForce;

bool g_bHasEliteApi;
bool g_bTrackedUnstoppable[MAXPLAYERS + 1];
bool g_bCharging[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Charger Unstoppable",
	author = "OpenCode",
	description = "Unstoppable subtype module for elite Charger bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_charger_unstoppable_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvCarryMaxDuration = CreateConVar("l4d2_elite_si_charger_unstoppable_carry_duration", "1.2", "Max time (seconds) to carry victim before forcing drop.", FCVAR_NOTIFY, true, 0.1, true, 5.0);
	g_cvFastCooldown = CreateConVar("l4d2_elite_si_charger_unstoppable_charge_cooldown", "2.0", "Cooldown time before Charger can charge again.", FCVAR_NOTIFY, true, 0.1, true, 12.0);
	g_cvKnockbackForce = CreateConVar("l4d2_elite_si_charger_unstoppable_knockback_force", "300.0", "Horizontal force applied when Unstoppable charger melees a survivor.", FCVAR_NOTIFY, true, 0.0, true, 1000.0);
	g_cvKnockbackUpForce = CreateConVar("l4d2_elite_si_charger_unstoppable_knockback_up_force", "350.0", "Vertical force applied when Unstoppable charger melees a survivor.", FCVAR_NOTIFY, true, 0.0, true, 1000.0);

	CreateConVar("l4d2_elite_si_charger_unstoppable_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_charger_unstoppable");

	HookEvent("charger_charge_start", Event_ChargeStart, EventHookMode_Post);
	HookEvent("charger_charge_end", Event_ChargeEnd, EventHookMode_Post);
	HookEvent("charger_carry_start", Event_CarryStart, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	HookEvent("round_start", Event_RoundReset, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundReset, EventHookMode_PostNoCopy);

	RefreshEliteState();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}
}

public void OnAllPluginsLoaded()
{
	RefreshEliteState();
}

public void OnMapStart()
{
	ResetAllState();
}

public void OnClientPutInServer(int client)
{
	ResetClientState(client);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SyncTrackedSubtypeForClient(client);
}

public void OnClientDisconnect(int client)
{
	ResetClientState(client);
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void EliteSI_OnEliteAssigned(int client, int zclass, int subtype)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedUnstoppable[client] = (zclass == ZC_CHARGER && subtype == ELITE_SUBTYPE_CHARGER_UNSTOPPABLE);
	g_bCharging[client] = false;
}

public void EliteSI_OnEliteCleared(int client)
{
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedUnstoppable[client] = false;
	
	if (g_bCharging[client])
	{
		g_bCharging[client] = false;
		if (IsClientInGame(client) && IsPlayerAlive(client))
		{
			SetEntityRenderMode(client, RENDER_NORMAL);
			SetEntityRenderColor(client, 255, 255, 255, 255);
		}
	}
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
	ResetAllState();
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	if (g_bCharging[client])
	{
		g_bCharging[client] = false;
		SetEntityRenderMode(client, RENDER_NORMAL);
		SetEntityRenderColor(client, 255, 255, 255, 255);
	}
}

public void Event_ChargeStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int charger = GetClientOfUserId(event.GetInt("userid"));
	if (!IsUnstoppableCharger(charger, true))
	{
		return;
	}

	g_bCharging[charger] = true;
	SetEntityRenderMode(charger, RENDER_TRANSCOLOR);
	SetEntityRenderColor(charger, 120, 80, 80, 150); // 60% opacity roughly
}

public void Event_ChargeEnd(Event event, const char[] name, bool dontBroadcast)
{
	int charger = GetClientOfUserId(event.GetInt("userid"));
	if (!IsUnstoppableCharger(charger, true))
	{
		return;
	}
	
	if (g_bCharging[charger])
	{
		g_bCharging[charger] = false;
		SetEntityRenderMode(charger, RENDER_TRANSCOLOR);
		SetEntityRenderColor(charger, 120, 80, 80, 255); // Restore normal elite color
	}

	if (g_cvEnable.BoolValue)
	{
		int ability = GetEntPropEnt(charger, Prop_Send, "m_customAbility");
		if (IsValidEntity(ability))
		{
			SetEntPropFloat(ability, Prop_Send, "m_timestamp", GetGameTime() + g_cvFastCooldown.FloatValue);
		}
	}
}

public void Event_CarryStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int charger = GetClientOfUserId(event.GetInt("userid"));
	if (!IsUnstoppableCharger(charger, true))
	{
		return;
	}

	CreateTimer(g_cvCarryMaxDuration.FloatValue, Timer_ForceDropCarry, GetClientUserId(charger), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ForceDropCarry(Handle timer, int userId)
{
	int charger = GetClientOfUserId(userId);
	if (!IsUnstoppableCharger(charger, true))
	{
		return Plugin_Stop;
	}

	int carryVictim = GetEntPropEnt(charger, Prop_Send, "m_carryVictim");
	int pummelVictim = GetEntPropEnt(charger, Prop_Send, "m_pummelVictim");

	if ((carryVictim > 0 && carryVictim <= MaxClients) || (pummelVictim > 0 && pummelVictim <= MaxClients))
	{
		// Hất nó lên một tẹo để ngắt Charge & Carry thay vì dùng Stagger (gây ra lỗi Too much entities hoặc loop)
		float vel[3];
		vel[0] = 0.0;
		vel[1] = 0.0;
		vel[2] = 100.0;
		TeleportEntity(charger, NULL_VECTOR, NULL_VECTOR, vel);
	}

	return Plugin_Stop;
}

public void OnActionCreated(BehaviorAction action, int actor, const char[] name)
{
	if (!g_cvEnable.BoolValue)
		return;

	// Bất tử Charger có thể cố gắng Pummel sau khi Charge trúng tường, block nó luôn
	if (StrContains(name, "Pummel", false) != -1)
	{
		if (IsUnstoppableCharger(actor, true))
		{
			action.OnStart = ChargerPummel_OnStart;
		}
	}
}

Action ChargerPummel_OnStart(BehaviorAction action, int actor, any priorAction, ActionResult result)
{
	result.type = DONE;
	result.SetReason("Unstoppable Charger doesn't pummel");
	return Plugin_Changed;
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damageType)
{
	if (!g_cvEnable.BoolValue)
	{
		return Plugin_Continue;
	}

	if (victim > 0 && victim <= MaxClients && IsClientInGame(victim))
	{
		if (IsUnstoppableCharger(victim, true) && g_bCharging[victim])
		{
			return Plugin_Handled;
		}
	}

	if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker))
	{
		if (IsUnstoppableCharger(attacker, true))
		{
			if (victim > 0 && victim <= MaxClients && IsClientInGame(victim) && GetClientTeam(victim) == TEAM_SURVIVOR)
			{
				if (damageType & DMG_CLUB)
				{
					ApplyMeleeKnockback(victim, attacker);
				}
			}
		}
	}

	return Plugin_Continue;
}

void ApplyMeleeKnockback(int survivor, int charger)
{
	float survivorPos[3], chargerPos[3], dir[3], velocity[3];
	GetClientAbsOrigin(survivor, survivorPos);
	GetClientAbsOrigin(charger, chargerPos);

	MakeVectorFromPoints(chargerPos, survivorPos, dir);
	dir[2] = 0.0;
	NormalizeVector(dir, dir);

	float horizForce = g_cvKnockbackForce.FloatValue;
	float vertForce = g_cvKnockbackUpForce.FloatValue;

	velocity[0] = dir[0] * horizForce;
	velocity[1] = dir[1] * horizForce;
	velocity[2] = vertForce;

	TeleportEntity(survivor, NULL_VECTOR, NULL_VECTOR, velocity);
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
	if (client <= 0 || client > MaxClients)
	{
		return;
	}

	g_bTrackedUnstoppable[client] = false;
	g_bCharging[client] = false;
}

bool IsUnstoppableCharger(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_CHARGER)
	{
		return false;
	}

	return g_bTrackedUnstoppable[client];
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}

void SyncTrackedSubtypeForClient(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_CHARGER)
	{
		g_bTrackedUnstoppable[client] = false;
		return;
	}

	if (!g_bHasEliteApi)
	{
		return;
	}

	g_bTrackedUnstoppable[client] = EliteSI_IsElite(client) && EliteSI_GetSubtype(client) == ELITE_SUBTYPE_CHARGER_UNSTOPPABLE;
}
