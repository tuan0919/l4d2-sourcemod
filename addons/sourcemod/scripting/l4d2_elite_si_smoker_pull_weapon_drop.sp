#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_SMOKER 1

#define ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP 28

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;

bool g_bHasEliteApi;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Smoker Pull Weapon Drop",
	author = "OpenCode",
	description = "Pull Weapon Drop subtype module for elite Smoker bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_smoker_pull_weapon_drop_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	CreateConVar("l4d2_elite_si_smoker_pull_weapon_drop_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_smoker_pull_weapon_drop");

	HookEvent("tongue_grab", Event_TongueGrab, EventHookMode_Post);

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

public void Event_TongueGrab(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("victim"));
	int attacker = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplySubtype(attacker) || !IsValidAliveSurvivor(victim))
	{
		return;
	}

	int weapon = GetClientDroppableWeapon(victim);
	if (weapon == -1)
	{
		return;
	}

	DropVictimWeapon(victim, weapon);
}

bool ShouldApplySubtype(int client)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client) || !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_SMOKER)
	{
		return false;
	}

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_SMOKER_PULL_WEAPON_DROP;
}

bool IsValidAliveSurvivor(int client)
{
	return client > 0
		&& client <= MaxClients
		&& IsClientInGame(client)
		&& GetClientTeam(client) == TEAM_SURVIVOR
		&& IsPlayerAlive(client);
}

int GetClientDroppableWeapon(int client)
{
	int weapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	if (!IsValidWeaponEntity(weapon))
	{
		return -1;
	}

	if (weapon != GetPlayerWeaponSlot(client, 0) && weapon != GetPlayerWeaponSlot(client, 1))
	{
		return -1;
	}

	if (GetEntPropEnt(weapon, Prop_Data, "m_hOwner") != client)
	{
		return -1;
	}

	return weapon;
}

bool IsValidWeaponEntity(int entity)
{
	return entity > MaxClients && IsValidEntity(entity);
}

void DropVictimWeapon(int client, int weapon)
{
	char classname[64];
	GetEntityClassname(weapon, classname, sizeof(classname));

	int ammo = 0;
	if (GetPlayerWeaponSlot(client, 0) == weapon)
	{
		ammo = GetPlayerReserveAmmo(client, weapon);
	}

	SDKHooks_DropWeapon(client, weapon);

	if (ammo > 0 && IsValidWeaponEntity(weapon))
	{
		SetPlayerReserveAmmo(client, weapon, 0);
		SetEntProp(weapon, Prop_Send, "m_iExtraPrimaryAmmo", ammo);
	}

	if (StrEqual(classname, "weapon_defibrillator", false) && IsValidWeaponEntity(weapon))
	{
		int modelindex = GetEntProp(weapon, Prop_Data, "m_nModelIndex");
		SetEntProp(weapon, Prop_Send, "m_iWorldModelIndex", modelindex);
	}
}

int GetPlayerReserveAmmo(int client, int weapon)
{
	int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammoType < 0)
	{
		return 0;
	}

	return GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType);
}

void SetPlayerReserveAmmo(int client, int weapon, int ammo)
{
	int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	if (ammoType < 0)
	{
		return;
	}

	SetEntProp(client, Prop_Send, "m_iAmmo", ammo, _, ammoType);
	ChangeEdictState(client, FindDataMapInfo(client, "m_iAmmo"));
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
