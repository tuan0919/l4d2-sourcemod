#define PLUGIN_VERSION		"1.2.0"
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

native bool L4D2_IsEliteSI(int client);

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
#define HUD_FEED_MAX 6
#define LEFT_FEED_BASE 9
#define RIGHT_KILL_BASE 2
#define PLAYERCOUNT_SLOT 0
#define IsClient(%1) ((1 <= %1 <= MaxClients) && IsClientInGame(%1))
#define L4D2_ZOMBIECLASS_TANK		8
#define HUD_TIMEOUT	5.0
#define PLAYERCOUNT_INTERVAL 1.0
#define PLAYERCOUNT_X 0.72
#define PLAYERCOUNT_Y 0.03
#define PLAYERCOUNT_W 0.28
#define PLAYERCOUNT_H 0.04
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

static const char SI_CLASS_NAMES[9][16] = {
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

static float g_LeftHUDPos[HUD_FEED_MAX][4] = {
	{0.00, 0.04, 0.70, 0.04},
	{0.00, 0.08, 0.70, 0.04},
	{0.00, 0.12, 0.70, 0.04},
	{0.00, 0.16, 0.70, 0.04},
	{0.00, 0.20, 0.70, 0.04},
	{0.00, 0.24, 0.70, 0.04}
};

static float g_RightKillHUDPos[HUD_FEED_MAX][4] = {
	{0.58, 0.08, 0.40, 0.04},
	{0.58, 0.12, 0.40, 0.04},
	{0.58, 0.16, 0.40, 0.04},
	{0.58, 0.20, 0.40, 0.04},
	{0.58, 0.24, 0.40, 0.04},
	{0.58, 0.28, 0.40, 0.04}
};

static int g_iHUDFlags_Left_Normal = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static int g_iHUDFlags_Left_Newest = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS | HUD_FLAG_BLINK;
static int g_iHUDFlags_Right_Normal = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_RIGHT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static int g_iHUDFlags_Right_Newest = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_RIGHT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS | HUD_FLAG_BLINK;
static int g_iHUDFlags_PlayerCount = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_RIGHT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static char output[256];
static char g_sLastEliteKiller[64];
static char g_sLastEliteVictim[32];
static float g_fEliteKillSuppressUntil;

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

ArrayList g_hud_info_left;
ArrayList g_hud_kill_right;
Handle g_hInfoHudDecreaseTimer;
Handle g_hKillHudDecreaseTimer;
StringMap mapWeaponName;
bool g_bEliteNativeAvailable;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("L4D2_IsEliteSI");
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar(PLUGIN_NAME ... "_version", PLUGIN_VERSION, "Plugin Version of " ... PLUGIN_NAME_FULL, FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hud_info_left = new ArrayList(ByteCountToCells(128));
	g_hud_kill_right = new ArrayList(ByteCountToCells(128));
	mapWeaponName = new StringMap();
	for (int i = 0; i < sizeof(WEAPON_NAMES_KEYs); i++)
		mapWeaponName.SetString(WEAPON_NAMES_KEYs[i], WEAPON_NAMES_VALUEs[i]);
		
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("defibrillator_used", Event_Defib_Used, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	CreateTimer(PLAYERCOUNT_INTERVAL, Timer_UpdatePlayerCountHUD, _, TIMER_REPEAT);
}

public void OnAllPluginsLoaded()
{
	g_bEliteNativeAvailable = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available);
}

public void OnLibraryAdded(const char[] name)
{
	g_bEliteNativeAvailable = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available);
}

public void OnLibraryRemoved(const char[] name)
{
	g_bEliteNativeAvailable = (GetFeatureStatus(FeatureType_Native, "L4D2_IsEliteSI") == FeatureStatus_Available);
}

public void Tuan_OnClient_KillOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	bool isSelf = StrEqual(attacker_name, victim_name);
	if (StrEqual(weapon_name, "None")) {
		if (GetGameTime() <= g_fEliteKillSuppressUntil
			&& StrEqual(attacker_name, g_sLastEliteKiller, false)
			&& (StrEqual(victim_name, g_sLastEliteVictim, false) || StrContains(victim_name, g_sLastEliteVictim, false) != -1)) {
			return;
		}

		if (isSelf) {
			FormatEx(output, sizeof(output), "%s suicide", attacker_name);
			DisplayKillHUD(output);
		} else {
			FormatEx(output, sizeof(output), "%s killed %s", attacker_name, victim_name);
			DisplayKillHUD(output);
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
	DisplayKillHUD(output);
}

public void Tuan_OnClient_IncapOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	bool isSelf = StrEqual(attacker_name, victim_name);
	if (StrEqual(weapon_name, "None")) {
		if (isSelf) {
			FormatEx(output, sizeof(output), "%s self-incapacitated", attacker_name);
		} else {
			FormatEx(output, sizeof(output), "%s incapacitated %s", attacker_name, victim_name);
		}
		DisplayInfoHUD(output);
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
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_UsedThrowable(int client, int throwable_type) {
	switch (throwable_type) {
		case 0: {
			FormatEx(output, sizeof(output), "%N thrown molotov", client);
			DisplayInfoHUD(output);
		}
		case 1: {
			FormatEx(output, sizeof(output), "%N thrown pipebomb", client);
			DisplayInfoHUD(output);
		}
		case 2: {
			FormatEx(output, sizeof(output), "%N thrown vomitjar", client);
			DisplayInfoHUD(output);
		}
	}
}

public void Tuan_OnClient_HealedOther(int client, int victim) {
	if (client == victim) {
		FormatEx(output, sizeof(output), "%N healed himself and no longer at last life.", client);
	} else {
		FormatEx(output, sizeof(output), "%N was healed by %N and no longer at last life.", victim, client);
	}
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_GoBnW(int client) {
	FormatEx(output, sizeof(output), "%N is at last life", client);
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_RevivedOther(int client, int target) {
	if (client == target) {
		FormatEx(output, sizeof(output), "%N self get up", client);
		DisplayInfoHUD(output);
	} else {
		FormatEx(output, sizeof(output), "%N helped %N to get up", client, target);
		DisplayInfoHUD(output);
	}
}

public void OnMapStart() {
	GameRules_SetProp("m_bChallengeModeActive", true, _, _, true);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	for (int slot = LEFT_FEED_BASE; slot < LEFT_FEED_BASE + HUD_FEED_MAX; slot++)
		RemoveHUD(slot);
	for (int slot = RIGHT_KILL_BASE; slot < RIGHT_KILL_BASE + HUD_FEED_MAX; slot++)
		RemoveHUD(slot);
	RemoveHUD(PLAYERCOUNT_SLOT);

	delete g_hud_info_left;
	g_hud_info_left = new ArrayList(ByteCountToCells(128));
	delete g_hud_kill_right;
	g_hud_kill_right = new ArrayList(ByteCountToCells(128));

	delete g_hInfoHudDecreaseTimer;
	delete g_hKillHudDecreaseTimer;
	UpdatePlayerCountHUD();
}

public void OnMapEnd() {
	delete g_hud_info_left;
	g_hud_info_left = new ArrayList(ByteCountToCells(128));
	delete g_hud_kill_right;
	g_hud_kill_right = new ArrayList(ByteCountToCells(128));

	delete g_hInfoHudDecreaseTimer;
	delete g_hKillHudDecreaseTimer;
	RemoveHUD(PLAYERCOUNT_SLOT);
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
	DisplayInfoHUD(output);
}

public void GearTransfer_OnWeaponGrab(int client, int target, int item) {
	if (IsClient(target)) {
		L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
		char weapon_name[64];
		L4D2_GetWeaponNameByWeaponId(weaponId, weapon_name, sizeof(weapon_name));
		mapWeaponName.GetString(weapon_name, weapon_name, sizeof(weapon_name));
		FormatEx(output, sizeof(output), "%N grabbed %s from %N", client, weapon_name, target);
		DisplayInfoHUD(output);
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
	DisplayInfoHUD(output);
}

//Function-------------------------------

void DisplayInfoHUD(const char[] info) {
	HUD feed;
	g_hud_info_left.PushString(info);
	if (g_hud_info_left.Length > HUD_FEED_MAX) {
		g_hud_info_left.Erase(0);
	}
	for (int index = 0; index < HUD_FEED_MAX && index < g_hud_info_left.Length; index++)
	{
		g_hud_info_left.GetString(index, feed.info, sizeof(feed.info));
		feed.slot = LEFT_FEED_BASE + index;
		feed.pos = g_LeftHUDPos[index];
		feed.Place(index == g_hud_info_left.Length - 1 ? g_iHUDFlags_Left_Newest : g_iHUDFlags_Left_Normal);
	}

	delete g_hInfoHudDecreaseTimer;
	g_hInfoHudDecreaseTimer = CreateTimer(HUD_TIMEOUT, Timer_InfoHUDDecrease, _, TIMER_REPEAT);
}

void DisplayKillHUD(const char[] info) {
	HUD feed;
	g_hud_kill_right.PushString(info);
	if (g_hud_kill_right.Length > HUD_FEED_MAX) {
		g_hud_kill_right.Erase(0);
	}
	for (int index = 0; index < HUD_FEED_MAX && index < g_hud_kill_right.Length; index++)
	{
		g_hud_kill_right.GetString(index, feed.info, sizeof(feed.info));
		feed.slot = RIGHT_KILL_BASE + index;
		feed.pos = g_RightKillHUDPos[index];
		feed.Place(index == g_hud_kill_right.Length - 1 ? g_iHUDFlags_Right_Newest : g_iHUDFlags_Right_Normal);
	}

	delete g_hKillHudDecreaseTimer;
	g_hKillHudDecreaseTimer = CreateTimer(HUD_TIMEOUT, Timer_KillHUDDecrease, _, TIMER_REPEAT);
}

void Event_Defib_Used(Event event, const char[] name, bool dontBroadCast) {
	int client = event.GetInt("userid");
	int subject = event.GetInt("subject");
	client = GetClientOfUserId(client);
	subject = GetClientOfUserId(subject);
	if (client > 0 && subject > 0) {
		FormatEx(output, sizeof(output), "%N brought %N back from dead", client, subject);
		DisplayInfoHUD(output);
	}
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEliteNativeAvailable) {
		return;
	}

	int victim = GetClientOfUserId(event.GetInt("userid"));
	if (!IsClient(victim) || GetClientTeam(victim) != TEAM_INFECTED || !L4D2_IsEliteSI(victim)) {
		return;
	}

	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!IsClient(attacker) || GetClientTeam(attacker) != TEAM_SURVIVOR) {
		return;
	}

	int zClass = GetEntProp(victim, Prop_Send, "m_zombieClass");
	if (zClass < 1 || zClass > 8) {
		zClass = 0;
	}

	FormatEx(output, sizeof(output), "%N killed Elite %s", attacker, SI_CLASS_NAMES[zClass]);
	DisplayKillHUD(output);
	GetClientName(attacker, g_sLastEliteKiller, sizeof(g_sLastEliteKiller));
	strcopy(g_sLastEliteVictim, sizeof(g_sLastEliteVictim), SI_CLASS_NAMES[zClass]);
	g_fEliteKillSuppressUntil = GetGameTime() + 0.35;
}

public void Tuan_OnClient_ExplodeObject(int client, int object_type) {
	switch (object_type) {
		case TYPE_GASCAN:
        {
			FormatEx(output, sizeof(output), "%N exploded a gascan", client);
			DisplayInfoHUD(output);
        }

        case TYPE_FUEL_BARREL:
        {
			FormatEx(output, sizeof(output), "%N exploded a fuel barrel", client);
			DisplayInfoHUD(output);
        }

        case TYPE_PROPANECANISTER:
        {
			FormatEx(output, sizeof(output), "%N exploded a propane canister", client);
			DisplayInfoHUD(output);
        }

        case TYPE_OXYGENTANK:
        {
			FormatEx(output, sizeof(output), "%N exploded an oxygen tank", client);
			DisplayInfoHUD(output);
        }

        case TYPE_BARRICADE_GASCAN:
        {
			FormatEx(output, sizeof(output), "%N exploded a barricade gascan", client);
			DisplayInfoHUD(output);
        }

        case TYPE_GAS_PUMP:
        {
			FormatEx(output, sizeof(output), "%N exploded a gas pump", client);
			DisplayInfoHUD(output);
        }

        case TYPE_FIREWORKS_CRATE:
        {
			FormatEx(output, sizeof(output), "%N exploded a fireworks crate", client);
			DisplayInfoHUD(output);
        }

        case TYPE_OIL_DRUM_EXPLOSIVE:
        {
			FormatEx(output, sizeof(output), "%N exploded an oil drum", client);
			DisplayInfoHUD(output);
        }
	}
}


//Timer-------------------------------

Action Timer_InfoHUDDecrease(Handle timer) {
	if( g_hud_info_left.Length == 0 )
	{
		g_hInfoHudDecreaseTimer = null;
		return Plugin_Stop;
	}

	g_hud_info_left.Erase(0);

	HUD feed;
	int index;
	for(index = 0; index < HUD_FEED_MAX && index < g_hud_info_left.Length; index++)
	{
		g_hud_info_left.GetString(index, feed.info, sizeof(feed.info));
		feed.slot = LEFT_FEED_BASE + index;
		feed.pos  = g_LeftHUDPos[index];
		feed.Place(g_iHUDFlags_Left_Normal);
	}

	while(index < HUD_FEED_MAX)
	{
		RemoveHUD(index + LEFT_FEED_BASE);
		index++;
	}

	return Plugin_Continue;
}

Action Timer_KillHUDDecrease(Handle timer) {
	if( g_hud_kill_right.Length == 0 )
	{
		g_hKillHudDecreaseTimer = null;
		return Plugin_Stop;
	}

	g_hud_kill_right.Erase(0);

	HUD feed;
	int index;
	for(index = 0; index < HUD_FEED_MAX && index < g_hud_kill_right.Length; index++)
	{
		g_hud_kill_right.GetString(index, feed.info, sizeof(feed.info));
		feed.slot = RIGHT_KILL_BASE + index;
		feed.pos  = g_RightKillHUDPos[index];
		feed.Place(g_iHUDFlags_Right_Normal);
	}

	while(index < HUD_FEED_MAX)
	{
		RemoveHUD(index + RIGHT_KILL_BASE);
		index++;
	}

	return Plugin_Continue;
}

Action Timer_UpdatePlayerCountHUD(Handle timer)
{
	UpdatePlayerCountHUD();
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

void UpdatePlayerCountHUD()
{
	int playerCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClient(i) && !IsFakeClient(i)) {
			playerCount++;
		}
	}

	FormatEx(output, sizeof(output), "Players: %d/%d", playerCount, MaxClients);
	HUDSetLayout(PLAYERCOUNT_SLOT, g_iHUDFlags_PlayerCount, output);
	HUDPlace(PLAYERCOUNT_SLOT, PLAYERCOUNT_X, PLAYERCOUNT_Y, PLAYERCOUNT_W, PLAYERCOUNT_H);
}
