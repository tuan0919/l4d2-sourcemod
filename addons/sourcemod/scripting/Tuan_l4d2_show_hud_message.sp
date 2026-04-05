#define PLUGIN_VERSION		"1.0"
#define PLUGIN_PREFIX		"l4d2_"
#define PLUGIN_NAME			"show_hud_messages"
#define PLUGIN_NAME_FULL		"[L4D2] Show Message On HUD"
#define PLUGIN_DESCRIPTION	"show extra death messages those not included by game"
#define PLUGIN_AUTHOR		"nqat0919"
#define PLUGIN_LINK			""

#pragma newdecls required
#pragma semicolon 1

#include <sdktools>
#include <sourcemod>
#include <left4dhooks>
#include <Tuan_custom_forwards>
#include <colors>

public Plugin myinfo = {
	name			= PLUGIN_NAME_FULL,
	author			= PLUGIN_AUTHOR,
	description		= PLUGIN_DESCRIPTION,
	version			= PLUGIN_VERSION,
	url				= PLUGIN_LINK
};

// noro.inc start
#define HUD_FLAG_NONE                 0     // no flag
#define HUD_FLAG_PRESTR               1     // do you want a string/value pair to start(pre) with the string (default is PRE)
#define HUD_FLAG_POSTSTR              2     // do you want a string/value pair to end(post) with the string
#define HUD_FLAG_BEEP                 4     // Makes a countdown timer blink
#define HUD_FLAG_BLINK                8     // do you want this field to be blinking
#define HUD_FLAG_AS_TIME              16    // ?
#define HUD_FLAG_COUNTDOWN_WARN       32    // auto blink when the timer gets under 10 seconds
#define HUD_FLAG_NOBG                 64    // dont draw the background box for this UI element
#define HUD_FLAG_ALLOWNEGTIMER        128   // by default Timers stop on 0:00 to avoid briefly going negative over network, this keeps that from happening
#define HUD_FLAG_ALIGN_LEFT           256   // Left justify this text
#define HUD_FLAG_ALIGN_CENTER         512   // Center justify this text
#define HUD_FLAG_ALIGN_RIGHT          768   // Right justify this text
#define HUD_FLAG_TEAM_SURVIVORS       1024  // only show to the survivor team
#define HUD_FLAG_TEAM_INFECTED        2048  // only show to the special infected team
#define HUD_FLAG_TEAM_MASK            3072  // ?
#define HUD_FLAG_UNKNOWN1             4096  // ?
#define HUD_FLAG_TEXT                 8192  // ?
#define HUD_FLAG_NOTVISIBLE           16384 // if you want to keep the slot data but keep it from displaying
#define KILL_HUD_BASE 9
#define KILL_INFO_MAX 6
#define IsClient(%1) ((1 <= %1 <= MaxClients) && IsClientInGame(%1))
#define L4D2_ZOMBIECLASS_TANK		8
#define MAX_HUD_NUMBER	4
#define HUD_TIMEOUT	5.0
#define HUD_WIDTH	0.7
#define HUD_SLOT	4
#define HUD_POSITION_X 0.0
#define CLASSNAME_INFECTED            "Infected"
#define CLASSNAME_WITCH               "witch"
#define TEAM_SURVIVOR		2
#define TEAM_INFECTED		3

#define TYPE_NONE                     0
#define TYPE_GASCAN                   1
#define TYPE_FUEL_BARREL              2
#define TYPE_PROPANECANISTER          3
#define TYPE_OXYGENTANK               4
#define TYPE_BARRICADE_GASCAN         5
#define TYPE_GAS_PUMP                 6
#define TYPE_FIREWORKS_CRATE          7
#define TYPE_OIL_DRUM_EXPLOSIVE       8


static const char WEAPON_NAMES_KEYs[][] = {
	"weapon_adrenaline",
	"weapon_pain_pills",
	"weapon_molotov",
	"weapon_pipe_bomb",
	"weapon_vomitjar",
	"weapon_first_aid_kit",
	"weapon_upgradepack_explosive",
	"weapon_upgradepack_incendiary",
	"weapon_defibrillator"
};

static const char WEAPON_NAMES_VALUEs[][] = {
	"adrenaline",
	"pain pills",
	"molotov",
	"pipebomb",
	"vomitjar",
	"first aid kit",
	"upgradepack explosive",
	"upgradepack incendiary",
	"defibrillator"
};

static float g_HUDpos[][] = {
    {0.00,0.00,0.00,0.00}, // 0
    {0.00,0.00,0.00,0.00},
    {0.00,0.00,0.00,0.00},
    {0.00,0.00,0.00,0.00},
    {0.00,0.00,0.00,0.00},
    {0.00,0.00,0.00,0.00},
    {0.00,0.00,0.00,0.00},
    {0.00,0.00,0.00,0.00},
	{0.00,0.00,0.00,0.00},

    // kill list
	// {x, y, width, height}
    {HUD_POSITION_X,0.04,HUD_WIDTH,0.04}, // 9
    {HUD_POSITION_X,0.08,HUD_WIDTH,0.04}, // 10
    {HUD_POSITION_X,0.12,HUD_WIDTH,0.04},
    {HUD_POSITION_X,0.16,HUD_WIDTH,0.04},
    {HUD_POSITION_X,0.20,HUD_WIDTH,0.04},
    {HUD_POSITION_X,0.24,HUD_WIDTH,0.04}, // 14
};

static int g_iHUDFlags_Normal = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static int g_iHUDFlags_Newest = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS | HUD_FLAG_BLINK;
static char output[256];

enum struct HUD
{
	int slot;
	float pos[4];
	char info[128];
	void Place(int flag)
	{
		HUDSetLayout(this.slot, flag, this.info);
		HUDPlace(this.slot, this.pos[0], this.pos[1], this.pos[2], this.pos[3]);
	}
}

ArrayList g_hud_info;
Handle g_hHudDecreaseTimer;
StringMap mapWeaponName;

public void OnPluginStart() {
	CreateConVar(PLUGIN_NAME ... "_version", PLUGIN_VERSION, "Plugin Version of " ... PLUGIN_NAME_FULL, FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hud_info = new ArrayList(ByteCountToCells(128));
	mapWeaponName = new StringMap();
	for (int i = 0; i < sizeof(WEAPON_NAMES_KEYs); i++)
		mapWeaponName.SetString(WEAPON_NAMES_KEYs[i], WEAPON_NAMES_VALUEs[i]);
		
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("defibrillator_used", Event_Defib_Used, EventHookMode_Pre);
}

public void Tuan_OnClient_KillOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	bool isSelf = StrEqual(attacker_name, victim_name);
	if (StrEqual(weapon_name, "None")) {
		if (isSelf) {
			FormatEx(output, sizeof(output), "%s suicide", attacker_name);
			DisplayHUD(output);
		} else {
			FormatEx(output, sizeof(output), "%s killed %s", attacker_name, victim_name);
			DisplayHUD(output);
		}
	}
}

public void Tuan_OnClient_KilledByUnknown(char[] victim_name, char[] weapon_name) {
	if (StrEqual(weapon_name, "Flame")) {
		FormatEx(output, sizeof(output), "%s died by flame", victim_name);
	}
	else if (StrEqual(weapon_name, "Explosion")) {
		FormatEx(output, sizeof(output), "%s died by explosion", victim_name);
	}
	else if (StrEqual(weapon_name, "Falling")) {
		FormatEx(output, sizeof(output), "%s died by falling", victim_name);
	}
	else if (StrEqual(weapon_name, "Bleeding")) {
		FormatEx(output, sizeof(output), "%s died by bleeding", victim_name);
	}
	DisplayHUD(output);
}

public void Tuan_OnClient_IncapOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	bool isSelf = StrEqual(attacker_name, victim_name);
	if (StrEqual(weapon_name, "None")) {
		if (isSelf) {
			FormatEx(output, sizeof(output), "%s self-incapacitated", attacker_name);
		} else {
			FormatEx(output, sizeof(output), "%s incapacitated %s", attacker_name, victim_name);
		}
		DisplayHUD(output);
	}
}

public void Tuan_OnClient_IncappedByUnknown(char[] victim_name, char[] weapon_name) {
	if (StrEqual(weapon_name, "Flame")) {
		FormatEx(output, sizeof(output), "%s incapacitated by flame", victim_name);
	}
	else if (StrEqual(weapon_name, "Explosion")) {
		FormatEx(output, sizeof(output), "%s incapacitated by explosion`", victim_name);
	}
	else if (StrEqual(weapon_name, "Falling")) {
		FormatEx(output, sizeof(output), "%s incapacitated by falling", victim_name);
	}
	DisplayHUD(output);
}

public void Tuan_OnClient_UsedThrowable(int client, int throwable_type) {
	switch (throwable_type) {
		case 0: {
			FormatEx(output, sizeof(output), "%N thrown molotov", client);
			DisplayHUD(output);
		}
		case 1: {
			FormatEx(output, sizeof(output), "%N thrown pipebomb", client);
			DisplayHUD(output);
		}
		case 2: {
			FormatEx(output, sizeof(output), "%N thrown vomitjar", client);
			DisplayHUD(output);
		}
	}
}

public void Tuan_OnClient_HealedOther(int client, int victim) {
	if (client == victim) {
		FormatEx(output, sizeof(output), "%N healed himself and no longer at last life.", client);
	} else {
		FormatEx(output, sizeof(output), "%N was healed by %N and no longer at last life.", victim, client);
	}
	DisplayHUD(output);
}

public void Tuan_OnClient_GoBnW(int client) {
	FormatEx(output, sizeof(output), "%N is at last life", client);
	DisplayHUD(output);
}

public void Tuan_OnClient_RevivedOther(int client, int target) {
	if (client == target) {
		FormatEx(output, sizeof(output), "%N self get up", client);
		DisplayHUD(output);
	} else {
		FormatEx(output, sizeof(output), "%N helped %N to get up", client, target);
		DisplayHUD(output);
	}
}

public void OnMapStart() {
	GameRules_SetProp("m_bChallengeModeActive", true, _, _, true);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int slot = KILL_HUD_BASE; slot < MAX_HUD_NUMBER; slot++)
		RemoveHUD(slot);

	delete g_hud_info;
	g_hud_info = new ArrayList(ByteCountToCells(128));

	delete g_hHudDecreaseTimer;
}

public void OnMapEnd() {
	delete g_hud_info;
	g_hud_info = new ArrayList(ByteCountToCells(128));

	delete g_hHudDecreaseTimer;
}


// HUD-------------------------------

void HUDSetLayout(int slot, int flags, const char[] dataval, any ...) {
	static char str[128];
	VFormat(str, sizeof str, dataval, 4);

	GameRules_SetProp("m_iScriptedHUDFlags", flags, _, slot, true);
	GameRules_SetPropString("m_szScriptedHUDStringSet", str, true, slot);
}

public void GearTransfer_OnWeaponGive(int client, int target, int item) {
	L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
	char weapon_name[64];
	L4D2_GetWeaponNameByWeaponId(weaponId, weapon_name, sizeof(weapon_name));
	mapWeaponName.GetString(weapon_name, weapon_name, sizeof(weapon_name));
	FormatEx(output, sizeof(output), "%N give %s to %N", client, weapon_name, target);
	DisplayHUD(output);
}

public void GearTransfer_OnWeaponGrab(int client, int target, int item) {
	if (IsClient(target)) {
		L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
		char weapon_name[64];
		L4D2_GetWeaponNameByWeaponId(weaponId, weapon_name, sizeof(weapon_name));
		mapWeaponName.GetString(weapon_name, weapon_name, sizeof(weapon_name));
		FormatEx(output, sizeof(output), "%N grabbed %s from %N", client, weapon_name, target);
		DisplayHUD(output);
	}
}

public void GearTransfer_OnWeaponSwap(int client, int target, int itemGiven, int itemTaken) {
	L4D2WeaponId givenWeaponId = L4D2_GetWeaponId(itemGiven);
	L4D2WeaponId takenWeaponId = L4D2_GetWeaponId(itemTaken);
	char given_weapon_name[64];
	char taken_weapon_name[64];
	L4D2_GetWeaponNameByWeaponId(givenWeaponId, given_weapon_name, sizeof(given_weapon_name));
	L4D2_GetWeaponNameByWeaponId(takenWeaponId, taken_weapon_name, sizeof(taken_weapon_name));
	mapWeaponName.GetString(given_weapon_name, given_weapon_name, sizeof(given_weapon_name));
	mapWeaponName.GetString(taken_weapon_name, taken_weapon_name, sizeof(taken_weapon_name));
	FormatEx(output, sizeof(output), "%N swap %s for %s with %N", client, given_weapon_name, taken_weapon_name, target);
	DisplayHUD(output);
}

//Function-------------------------------

void DisplayHUD(const char[] info) {
	HUD kill_list;
	FormatEx(kill_list.info, sizeof(kill_list.info), "%s", info);
	g_hud_info.PushString(info);
	if( g_hud_info.Length > MAX_HUD_NUMBER ) {
		g_hud_info.Erase(0);
	}
	kill_list.slot = g_hud_info.Length - 1 + KILL_HUD_BASE;
	kill_list.pos  = g_HUDpos[kill_list.slot];
	for(int index = 0; index < KILL_INFO_MAX && index < g_hud_info.Length; index++)
	{
		g_hud_info.GetString(index, kill_list.info, sizeof(kill_list.info));
		kill_list.slot = index+KILL_HUD_BASE;
		kill_list.pos  = g_HUDpos[kill_list.slot];
		kill_list.Place(index == g_hud_info.Length - 1 ? g_iHUDFlags_Newest : g_iHUDFlags_Normal);
	}

	delete g_hHudDecreaseTimer;
	g_hHudDecreaseTimer = CreateTimer(HUD_TIMEOUT, Timer_KillHUDDecrease, _, TIMER_REPEAT);
}

void Event_Defib_Used(Event event, const char[] name, bool dontBroadCast) {
	int client = event.GetInt("userid");
	int subject = event.GetInt("subject");
	client = GetClientOfUserId(client);
	subject = GetClientOfUserId(subject);
	if (client > 0 && subject > 0) {
		FormatEx(output, sizeof(output), "%N brought %N back from dead", client, subject);
		DisplayHUD(output);
	}
}

public void Tuan_OnClient_ExplodeObject(int client, int object_type) {
	switch (object_type) {
		case TYPE_GASCAN:
        {
			FormatEx(output, sizeof(output), "%N exploded a gascan", client);
			DisplayHUD(output);
        }

        case TYPE_FUEL_BARREL:
        {
			FormatEx(output, sizeof(output), "%N exploded a fuel barrel", client);
			DisplayHUD(output);
        }

        case TYPE_PROPANECANISTER:
        {
			FormatEx(output, sizeof(output), "%N exploded a propane canister", client);
			DisplayHUD(output);
        }

        case TYPE_OXYGENTANK:
        {
			FormatEx(output, sizeof(output), "%N exploded an oxygen tank", client);
			DisplayHUD(output);
        }

        case TYPE_BARRICADE_GASCAN:
        {
			FormatEx(output, sizeof(output), "%N exploded a barricade gascan", client);
			DisplayHUD(output);
        }

        case TYPE_GAS_PUMP:
        {
			FormatEx(output, sizeof(output), "%N exploded a gas pump", client);
			DisplayHUD(output);
        }

        case TYPE_FIREWORKS_CRATE:
        {
			FormatEx(output, sizeof(output), "%N exploded a fireworks crate", client);
			DisplayHUD(output);
        }

        case TYPE_OIL_DRUM_EXPLOSIVE:
        {
			FormatEx(output, sizeof(output), "%N exploded an oil drum", client);
			DisplayHUD(output);
        }
	}
}


//Timer-------------------------------

Action Timer_KillHUDDecrease(Handle timer) {
	if( g_hud_info.Length == 0 )
	{
		g_hHudDecreaseTimer = null;
		return Plugin_Stop;
	}

	g_hud_info.Erase(0);

	HUD kill_list;
	int index;
	for(index = 0; index < KILL_INFO_MAX && index < g_hud_info.Length; index++)
	{
		g_hud_info.GetString(index, kill_list.info, sizeof(kill_list.info));
		kill_list.slot = index + KILL_HUD_BASE;
		kill_list.pos  = g_HUDpos[kill_list.slot];
		kill_list.Place(g_iHUDFlags_Normal);
	}

	while(index < KILL_INFO_MAX)
	{
		RemoveHUD(index + KILL_HUD_BASE);
		index++;
	}

	return Plugin_Continue;
}

void HUDPlace(int slot, float x, float y, float width, float height) {
	GameRules_SetPropFloat("m_fScriptedHUDPosX", x, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDPosY", y, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDWidth", width, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDHeight", height, slot, true);
}

void RemoveHUD(int slot) {
	GameRules_SetProp("m_iScriptedHUDInts", 0, _, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDFloats", 0.0, slot, true);
	GameRules_SetProp("m_iScriptedHUDFlags", HUD_FLAG_NOTVISIBLE, _, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDPosX", 0.0, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDPosY", 0.0, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDWidth", 0.0, slot, true);
	GameRules_SetPropFloat("m_fScriptedHUDHeight", 0.0, slot, true);
	GameRules_SetPropString("m_szScriptedHUDStringSet", "", true, slot);
}