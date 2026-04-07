#define PLUGIN_VERSION		"1.0"
#define PLUGIN_PREFIX		"l4d2_"
#define PLUGIN_NAME			"Tuan_l4d2_death_incap"
#define PLUGIN_NAME_FULL		"[L4D2] Death & Incap event fire"
#define PLUGIN_DESCRIPTION	"Fire events for other plugin receveid"
#define PLUGIN_AUTHOR		"Tuan"
#define PLUGIN_LINK			""

#pragma newdecls required
#pragma semicolon 1

#include <sdktools>
#include <sourcemod>
#include <left4dhooks>
#include <Tuan_custom_forwards>

public Plugin myinfo = {
	name			= PLUGIN_NAME_FULL,
	author			= PLUGIN_AUTHOR,
	description		= PLUGIN_DESCRIPTION,
	version			= PLUGIN_VERSION,
	url				= PLUGIN_LINK
};

static const char ENTITY_KEYs[][] = {
	"Infected",
	"Witch",
	"CInferno",
	"CPipeBombProjectile",
	"CWorld",
	"CEntityFlame",
	"CInsectSwarm",
	"CBaseTrigger",
};

static const char ENTITY_VALUEs[][] = {
	"Zombie",
	"Witch",
	"Fire",
	"Blast",
	"World",
	"Fire",
	"Spitter",
	"Map",
};

#define IsClient(%1) ((1 <= %1 <= MaxClients) && IsClientInGame(%1))
#define L4D2_ZOMBIECLASS_TANK		8
#define CLASSNAME_INFECTED            "Infected"
#define CLASSNAME_WITCH               "witch"
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3

static char g_ZomNames[9][24] =  {
	"Unknown", 
	"Smoker", 
	"Boomer", 
	"Hunter", 
	"Spitter", 
	"Jockey", 
	"Charger", 
	"Unknown", 
	"Tank"
};

static char g_UnknownWeaponNames[][] = {
	"None",
	"Flame",
	"Explosion",
	"Falling",
	"Bleeding"
};

StringMap mapNetClassToName;
char output[128];
GlobalForward g_OnClientIncapOther;
GlobalForward g_OnClientKillOther;
GlobalForward g_OnClientSelfIncap;
GlobalForward g_OnClientSuicide;
ConVar g_hDIEnable;
ConVar g_hDINotifyIncapOther;
ConVar g_hDINotifyKillOther;
ConVar g_hDINotifyKilledByUnknown;
ConVar g_hDINotifyIncappedByUnknown;
bool g_bDIEnable;
bool g_bDINotifyIncapOther;
bool g_bDINotifyKillOther;
bool g_bDINotifyKilledByUnknown;
bool g_bDINotifyIncappedByUnknown;

void DI_GetCvars() {
	g_bDIEnable = g_hDIEnable.BoolValue;
	g_bDINotifyIncapOther = g_hDINotifyIncapOther.BoolValue;
	g_bDINotifyKillOther = g_hDINotifyKillOther.BoolValue;
	g_bDINotifyKilledByUnknown = g_hDINotifyKilledByUnknown.BoolValue;
	g_bDINotifyIncappedByUnknown = g_hDINotifyIncappedByUnknown.BoolValue;
}

void DI_OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	DI_GetCvars();
}

public void OnPluginStart() {
	mapNetClassToName = new StringMap();
	for (int i = 0; i < sizeof(ENTITY_KEYs); i++)
		mapNetClassToName.SetString(ENTITY_KEYs[i], ENTITY_VALUEs[i]);

	HookEvent("player_incapacitated", Event_PlayerIncapaciatedInfo_Post);
	HookEvent("player_death",Event_PlayerDeathInfo_Pre, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeathInfo_Post);
	
	g_OnClientIncapOther = CreateGlobalForward("Tuan_OnClient_IncapOther", ET_Event, Param_String, Param_String, Param_String);
	g_OnClientKillOther = CreateGlobalForward("Tuan_OnClient_KillOther", ET_Event, Param_String, Param_String, Param_String);
	g_OnClientSuicide = CreateGlobalForward("Tuan_OnClient_KilledByUnknown", ET_Event, Param_String, Param_String);
	g_OnClientSelfIncap = CreateGlobalForward("Tuan_OnClient_IncappedByUnknown", ET_Event, Param_String, Param_String);
	g_hDIEnable = CreateConVar("tuan_notifier_di_enable", "1", "Enable death/incap notifier forwards.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hDINotifyIncapOther = CreateConVar("tuan_notifier_di_notify_incap_other", "1", "Notify Tuan_OnClient_IncapOther.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hDINotifyKillOther = CreateConVar("tuan_notifier_di_notify_kill_other", "1", "Notify Tuan_OnClient_KillOther.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hDINotifyKilledByUnknown = CreateConVar("tuan_notifier_di_notify_killed_by_unknown", "1", "Notify Tuan_OnClient_KilledByUnknown.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hDINotifyIncappedByUnknown = CreateConVar("tuan_notifier_di_notify_incapped_by_unknown", "1", "Notify Tuan_OnClient_IncappedByUnknown.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hDIEnable.AddChangeHook(DI_OnConVarChanged);
	g_hDINotifyIncapOther.AddChangeHook(DI_OnConVarChanged);
	g_hDINotifyKillOther.AddChangeHook(DI_OnConVarChanged);
	g_hDINotifyKilledByUnknown.AddChangeHook(DI_OnConVarChanged);
	g_hDINotifyIncappedByUnknown.AddChangeHook(DI_OnConVarChanged);
	DI_GetCvars();
	AutoExecConfig(true, "tuan_notifier_unified_death_incap");
}

void FireEventOnClientIncapOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	if (!g_bDIEnable || !g_bDINotifyIncapOther) return;
	Call_StartForward(g_OnClientIncapOther);
	Call_PushString(attacker_name);
	Call_PushString(victim_name);
	Call_PushString(weapon_name);
    Call_Finish();
}

void FireEventOnClientKillOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	if (!g_bDIEnable || !g_bDINotifyKillOther) return;
	Call_StartForward(g_OnClientKillOther);
	Call_PushString(attacker_name);
	Call_PushString(victim_name);
	Call_PushString(weapon_name);
    Call_Finish();
}

void FireEventOnClientKilledByUnknown(char[] victim_name, char[] weapon_name) {
	if (!g_bDIEnable || !g_bDINotifyKilledByUnknown) return;
	Call_StartForward(g_OnClientSuicide);
	Call_PushString(victim_name);
	Call_PushString(weapon_name);
    Call_Finish();
}

void FireEventOnClientIncappedByUnknown(char[] victim_name, char[] weapon_name) {
	if (!g_bDIEnable || !g_bDINotifyIncappedByUnknown) return;
	Call_StartForward(g_OnClientSelfIncap);
	Call_PushString(victim_name);
	Call_PushString(weapon_name);
    Call_Finish();
}

char[] GetEntityTranslatedName(int entity) {

	static char result[32];

	if (IsClient(entity)) {

		if (GetEntProp(entity, Prop_Send, "m_zombieClass") == L4D2_ZOMBIECLASS_TANK && IsFakeClient(entity))
			result = "Tank";
		else
			FormatEx(result, sizeof(result), "%N", entity);

	} else {
		GetEntityNetClass(entity, result, sizeof(result));
		mapNetClassToName.GetString(result, result, sizeof(result));
	}

	return result;
}


void Event_PlayerDeathInfo_Pre(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true; // by prehook, set this to prevent the red font of kill info.
}

void Event_PlayerDeathInfo_Post(Event event, const char[] name, bool dontBroadcast) {
	// PrintToChatAll("Event_PlayerDeathInfo_Post");
	int victim = GetClientOfUserId(event.GetInt("userid")),
		attacker = GetClientOfUserId(event.GetInt("attacker"));
	bool bDetectedVictim = false;
	bool bDetectedAttacker = false;
	int damagetype = event.GetInt("type");
	static char victim_name[128];
	static char attacker_name[128];
	static char sWeapon[64];
	if (attacker == 0) {
		attacker = event.GetInt("attackerentid");
	}
	if (IsClient(victim)) {
		// victim is survivor
		if ( GetClientTeam(victim) == TEAM_SURVIVOR) {
			FormatEx(victim_name,sizeof(victim_name),"%N",victim);
			bDetectedVictim = true;
		}
		// victim is special infected
		else if (GetClientTeam(victim) == TEAM_INFECTED) {
			int zom_type = GetEntProp(victim, Prop_Send, "m_zombieClass");
			FormatEx(victim_name, sizeof(victim_name), g_ZomNames[zom_type]);
			bDetectedVictim = true;
		}
	}
	else {
		// something is victim
		int entityid = event.GetInt("entityid");
		if ( IsWitch(entityid) ) { // maybe victim is Witch
			FormatEx(victim_name,sizeof(victim_name),"Witch");
			bDetectedVictim = true;
		}
	}
	if (IsClient(attacker)) {
		if (GetClientTeam(attacker) == TEAM_INFECTED) {
			int zom_type = GetEntProp(attacker, Prop_Send, "m_zombieClass");
			FormatEx(attacker_name, sizeof(attacker_name), g_ZomNames[zom_type]);
		} else {
			FormatEx(attacker_name, sizeof(attacker_name), "%N", attacker);
		}
		bDetectedAttacker = true;
	} else {
		// something is attacker
		int attackid = event.GetInt("attackerentid");
		if ( IsWitch(attackid) ) { // maybe is Witch
			FormatEx(attacker_name,sizeof(attacker_name),"Witch");
			bDetectedAttacker = true;
		} else if ( IsCommonInfected(attackid) ) { // maybe is Common Infected
			FormatEx(attacker_name,sizeof(attacker_name),"Common Infected");
			bDetectedAttacker = true;
		}
	}
	// PrintToChatAll("bDetectedAttacker : %s, bDetectedVictim: %s", bDetectedAttacker ? "true" : "false", bDetectedVictim ? "true" : "false");
	if (bDetectedAttacker && bDetectedVictim) {
		FireEventOnClientKillOther(attacker_name, victim_name, g_UnknownWeaponNames[0]);
	} else if (bDetectedVictim) { // detected victim but unsure about attacker
		int attackid = event.GetInt("attackerentid");
		event.GetString("weapon", sWeapon,sizeof(sWeapon));
		if(damagetype & DMG_BURN) { // victim died by burn
			FireEventOnClientKilledByUnknown(victim_name, g_UnknownWeaponNames[1]);
		}
		else if(damagetype & DMG_FALL) { // victim died by falling
			FireEventOnClientKilledByUnknown(victim_name, g_UnknownWeaponNames[3]);
		}
		else if(damagetype & DMG_BLAST) { // victim died by an explosion
			FireEventOnClientKilledByUnknown(victim_name, g_UnknownWeaponNames[2]);
		}
		else if(damagetype == (DMG_PREVENT_PHYSICS_FORCE + DMG_NEVERGIB) && strcmp(sWeapon, "world", false) == 0) {
			FireEventOnClientKilledByUnknown(victim_name, g_UnknownWeaponNames[4]);
		}
		else if( strncmp(sWeapon, "world", 5, false) == 0 || // "world", "worldspawn" 
			strncmp(sWeapon, "trigger_hurt", 12, false) == 0 ) // "trigger_hurt", "trigger_hurt_ghost"
		{
			FireEventOnClientKilledByUnknown(victim_name, g_UnknownWeaponNames[4]);
		}
	}
}

void Event_PlayerIncapaciatedInfo_Post(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(event.GetInt("userid")),
		attacker = GetClientOfUserId(event.GetInt("attacker"));
	bool bDetectedVictim = false;
	bool bDetectedAttacker = false;
	int damagetype = event.GetInt("type");
	static char victim_name[128];
	static char attacker_name[128];
	static char sWeapon[64];
	if (attacker == 0) {
		attacker = event.GetInt("attackerentid");
	}
	if (IsClient(victim)) {
		// victim is survivor
		if ( GetClientTeam(victim) == TEAM_SURVIVOR) {
			FormatEx(victim_name,sizeof(victim_name),"%N",victim);
			bDetectedVictim = true;
		}
	}
	if (IsClient(attacker)) {
		if (GetClientTeam(attacker) == TEAM_INFECTED) {
			int zom_type = GetEntProp(attacker, Prop_Send, "m_zombieClass");
			FormatEx(attacker_name, sizeof(attacker_name), g_ZomNames[zom_type]);
		} else {
			FormatEx(attacker_name, sizeof(attacker_name), "%N", attacker);
		}
		bDetectedAttacker = true;
	} else {
		// something is attacker
		int attackid = event.GetInt("attackerentid");
		if ( IsWitch(attackid) ) { // maybe is Witch
			FormatEx(attacker_name,sizeof(attacker_name),"Witch");
			bDetectedAttacker = true;
		} else if ( IsCommonInfected(attackid) ) { // maybe is Common Infected
			FormatEx(attacker_name,sizeof(attacker_name),"Common Infected");
			bDetectedAttacker = true;
		}
	}
	if (bDetectedAttacker && bDetectedVictim) {
		FireEventOnClientIncapOther(attacker_name, victim_name, g_UnknownWeaponNames[0]);
	} else if (bDetectedVictim) { // detected victim but unsure about attacker
		int attackid = event.GetInt("attackerentid");
		event.GetString("weapon", sWeapon,sizeof(sWeapon));
		if(damagetype & DMG_BURN) { // victim died by burn
			FireEventOnClientIncappedByUnknown(victim_name, g_UnknownWeaponNames[1]);
		}
		else if(damagetype & DMG_FALL) { // victim died by falling
			FireEventOnClientIncappedByUnknown(victim_name, g_UnknownWeaponNames[3]);
		}
		else if(damagetype & DMG_BLAST) { // victim died by an explosion
			FireEventOnClientIncappedByUnknown(victim_name, g_UnknownWeaponNames[2]);
		}
	}
}

bool IsWitch(int entity)
{
    if (entity > 0 && IsValidEntity(entity))
    {
        char strClassName[64];
        GetEntityClassname(entity, strClassName, sizeof(strClassName));
        return strcmp(strClassName, CLASSNAME_WITCH, false) == 0;
    }
    return false;
}

bool IsCommonInfected(int entity)
{
	if (entity > 0 && IsValidEntity(entity))
	{
		char entType[64];
		GetEntityNetClass(entity, entType, sizeof(entType));
		return StrEqual(entType, CLASSNAME_INFECTED);
	}
	return false;
}
