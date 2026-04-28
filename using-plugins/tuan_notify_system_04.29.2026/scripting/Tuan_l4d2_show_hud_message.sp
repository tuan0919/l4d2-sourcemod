#define PLUGIN_VERSION		"2.0.1-tuan-notify-core-2026-04-29"
#define PLUGIN_PREFIX		"tuan_notify_core_"
#define PLUGIN_NAME			"show_hud_messages"
#define PLUGIN_NAME_FULL		"[L4D2] Show Message On HUD [GearPatch]"
#define PLUGIN_DESCRIPTION	"show extra death messages + global HUD feedback with short bracket names"
#define PLUGIN_AUTHOR		"nqat0919 | Patch: Roo for Tuan (2026-04-06)"
#define PLUGIN_LINK			""

#pragma newdecls required
#pragma semicolon 1

#include <sdktools>
#include <sourcemod>
#include <left4dhooks>
#include <Tuan_custom_forwards>
#include <colors>

#define TUAN_NOTIFY_LIBRARY "tuan_notify_core"
#define TUAN_NOTIFY_FWD_PUBLISHED "TuanNotify_OnPublished"

public Plugin myinfo = {
	name			= PLUGIN_NAME_FULL,
	author			= PLUGIN_AUTHOR,
	description		= PLUGIN_DESCRIPTION,
	version			= PLUGIN_VERSION,
	url				= PLUGIN_LINK
};

/*
 * Patch Changelog:
 * - 1.3.0-tuan-gearpatch (2026-04-06)
 *   + Added support for gear transfer HUD feedback from custom gives and game-native pills/adrenaline gives.
 *   + Force player names in all HUD feedback messages to always render as bracketed format: [name].
 *   + Added name shortening for long names in HUD-safe style.
 *   + Marked plugin metadata (name/version/author/description) for easier identification.
 */

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
#define TOTALSURVIVORS_SLOT 1
#define IsClient(%1) ((1 <= %1 <= MaxClients) && IsClientInGame(%1))
#define L4D2_ZOMBIECLASS_TANK		8
#define HUD_TIMEOUT	5.0
#define PLAYERCOUNT_INTERVAL 1.0
#define PLAYERCOUNT_X 0.00
#define PLAYERCOUNT_Y 0.03
#define PLAYERCOUNT_W 0.70
#define PLAYERCOUNT_H 0.05
#define TOTALSURVIVORS_X 0.72
#define TOTALSURVIVORS_Y 0.03
#define TOTALSURVIVORS_W 0.28
#define TOTALSURVIVORS_H 0.11
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
#define TUAN_NOTIFY_CHANNEL_INFO      "info"
#define TUAN_NOTIFY_CHANNEL_KILL      "kill"

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
	{0.00, 0.10, 0.70, 0.04},
	{0.00, 0.14, 0.70, 0.04},
	{0.00, 0.18, 0.70, 0.04},
	{0.00, 0.22, 0.70, 0.04},
	{0.00, 0.26, 0.70, 0.04},
	{0.00, 0.30, 0.70, 0.04}
};

static float g_RightKillHUDPos[HUD_FEED_MAX][4] = {
	{0.58, 0.10, 0.40, 0.04},
	{0.58, 0.14, 0.40, 0.04},
	{0.58, 0.18, 0.40, 0.04},
	{0.58, 0.22, 0.40, 0.04},
	{0.58, 0.26, 0.40, 0.04},
	{0.58, 0.30, 0.40, 0.04}
};

static int g_iHUDFlags_Left_Normal = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static int g_iHUDFlags_Left_Newest = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS | HUD_FLAG_BLINK;
static int g_iHUDFlags_Right_Normal = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_RIGHT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static int g_iHUDFlags_Right_Newest = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_RIGHT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS | HUD_FLAG_BLINK;
static int g_iHUDFlags_PlayerCount = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_LEFT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static int g_iHUDFlags_TotalSurvivors = HUD_FLAG_TEXT | HUD_FLAG_ALIGN_RIGHT | HUD_FLAG_NOBG | HUD_FLAG_TEAM_SURVIVORS;
static char output[256];
static float g_fMapStartTime;
ConVar g_hCvarMaxSpecials;
ConVar g_hCvarTankHealth;
ConVar g_hCvarZCommonLimit;
ConVar g_hCvarInfBotsCurrentAliveSurvivor;
ConVar g_hCvarInfBotsCurrentSILimit;
ConVar g_hCvarInfBotsCurrentTankHP;
ConVar g_hCvarSvVisibleMaxPlayers;
ConVar g_hCvarSvMaxPlayers;
ConVar g_hCvarChatNotification;
ConVar g_hCvarScreenHudNotification;
ConVar g_hCvarLegacyForwardMode;
ConVar g_hCvarKillFeed;
GlobalForward g_hForwardPublished;
bool g_bChatNotificationEnabled;
bool g_bScreenHudNotificationEnabled;
bool g_bLegacyForwardMode;
bool g_bKillFeedEnabled;
#define HUD_NAME_VISIBLE 14

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

public void OnPluginStart() {
	CreateConVar(PLUGIN_PREFIX ... "version", PLUGIN_VERSION, "Plugin version.", FCVAR_SPONLY|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);
	g_hCvarChatNotification = CreateConVar(PLUGIN_PREFIX ... "chat_notification", "0", "Enable chat notification output.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarScreenHudNotification = CreateConVar(PLUGIN_PREFIX ... "screen_hud_notification", "1", "Enable screen HUD notification output.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarLegacyForwardMode = CreateConVar(PLUGIN_PREFIX ... "legacy_forward_mode", "0", "Enable legacy Tuan_custom_forwards handlers in core.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarKillFeed = CreateConVar(PLUGIN_PREFIX ... "kill_feed", "1", "Enable right-side kill feed HUD messages.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hCvarChatNotification.AddChangeHook(OnCvarChanged);
	g_hCvarScreenHudNotification.AddChangeHook(OnCvarChanged);
	g_hCvarLegacyForwardMode.AddChangeHook(OnCvarChanged);
	g_hCvarKillFeed.AddChangeHook(OnCvarChanged);
	g_bChatNotificationEnabled = g_hCvarChatNotification.BoolValue;
	g_bScreenHudNotificationEnabled = g_hCvarScreenHudNotification.BoolValue;
	g_bLegacyForwardMode = g_hCvarLegacyForwardMode.BoolValue;
	g_bKillFeedEnabled = g_hCvarKillFeed.BoolValue;
	g_hForwardPublished = CreateGlobalForward(TUAN_NOTIFY_FWD_PUBLISHED, ET_Event, Param_String, Param_String, Param_Cell);
	CreateNative("TuanNotify_PublishInfo", Native_PublishInfo);
	CreateNative("TuanNotify_PublishKill", Native_PublishKill);
	CreateNative("TuanNotify_IsChatNotificationEnabled", Native_IsChatNotificationEnabled);
	CreateNative("TuanNotify_IsScreenHudNotificationEnabled", Native_IsScreenHudNotificationEnabled);
	CreateNative("TuanNotify_IsKillFeedEnabled", Native_IsKillFeedEnabled);
	RegPluginLibrary(TUAN_NOTIFY_LIBRARY);
	g_hud_info_left = new ArrayList(ByteCountToCells(128));
	g_hud_kill_right = new ArrayList(ByteCountToCells(128));
	g_hCvarInfBotsCurrentAliveSurvivor = FindConVar("l4d_infectedbots_current_alive_survivor");
	g_hCvarInfBotsCurrentSILimit = FindConVar("l4d_infectedbots_current_si_limit");
	g_hCvarInfBotsCurrentTankHP = FindConVar("l4d_infectedbots_current_tank_hp");
	g_hCvarSvVisibleMaxPlayers = FindConVar("sv_visiblemaxplayers");
	g_hCvarSvMaxPlayers = FindConVar("sv_maxplayers");
	g_hCvarMaxSpecials = FindConVar("z_max_player_zombies");
	g_hCvarTankHealth = FindConVar("z_tank_health");
	g_hCvarZCommonLimit = FindConVar("z_common_limit");
	mapWeaponName = new StringMap();
	for (int i = 0; i < sizeof(WEAPON_NAMES_KEYs); i++)
		mapWeaponName.SetString(WEAPON_NAMES_KEYs[i], WEAPON_NAMES_VALUEs[i]);
	
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("defibrillator_used", Event_Defib_Used, EventHookMode_Pre);
	CreateTimer(PLAYERCOUNT_INTERVAL, Timer_UpdatePlayerCountHUD, _, TIMER_REPEAT);
	AutoExecConfig(true, "tuan_notify_core");
}

public void OnCvarChanged(ConVar cvar, const char[] oldValue, const char[] newValue) {
	g_bChatNotificationEnabled = g_hCvarChatNotification.BoolValue;
	g_bScreenHudNotificationEnabled = g_hCvarScreenHudNotification.BoolValue;
	g_bLegacyForwardMode = g_hCvarLegacyForwardMode.BoolValue;
	g_bKillFeedEnabled = g_hCvarKillFeed.BoolValue;

	if (!g_bScreenHudNotificationEnabled) {
		g_hud_info_left.Clear();
		g_hud_kill_right.Clear();
		for (int leftSlot = LEFT_FEED_BASE; leftSlot < LEFT_FEED_BASE + HUD_FEED_MAX; leftSlot++) {
			RemoveHUD(leftSlot);
		}
		for (int rightSlot = RIGHT_KILL_BASE; rightSlot < RIGHT_KILL_BASE + HUD_FEED_MAX; rightSlot++) {
			RemoveHUD(rightSlot);
		}
		delete g_hInfoHudDecreaseTimer;
		delete g_hKillHudDecreaseTimer;
	}

	if (!g_bKillFeedEnabled) {
		g_hud_kill_right.Clear();
		for (int slot = RIGHT_KILL_BASE; slot < RIGHT_KILL_BASE + HUD_FEED_MAX; slot++) {
			RemoveHUD(slot);
		}
		delete g_hKillHudDecreaseTimer;
	}
}

public any Native_PublishInfo(Handle plugin, int numParams) {
	char message[128];
	GetNativeString(1, message, sizeof(message));
	DisplayInfoHUD(message);
	return 1;
}

public any Native_PublishKill(Handle plugin, int numParams) {
	char message[128];
	GetNativeString(1, message, sizeof(message));
	DisplayKillHUD(message);
	return 1;
}

public any Native_IsChatNotificationEnabled(Handle plugin, int numParams) {
	return g_bChatNotificationEnabled ? 1 : 0;
}

public any Native_IsScreenHudNotificationEnabled(Handle plugin, int numParams) {
	return g_bScreenHudNotificationEnabled ? 1 : 0;
}

public any Native_IsKillFeedEnabled(Handle plugin, int numParams) {
	return g_bKillFeedEnabled ? 1 : 0;
}

void FirePublishedForward(const char[] channel, const char[] message, bool displayedOnHud) {
	Call_StartForward(g_hForwardPublished);
	Call_PushString(channel);
	Call_PushString(message);
	Call_PushCell(displayedOnHud ? 1 : 0);
	Call_Finish();
}

public void Tuan_OnClient_KillOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	bool isSelf = StrEqual(attacker_name, victim_name);
	if (StrEqual(weapon_name, "None")) {
		char attacker_name_fmt[32];
		char victim_name_fmt[32];
		FormatHudNameFromRaw(attacker_name, attacker_name_fmt, sizeof(attacker_name_fmt));
		FormatHudNameFromRaw(victim_name, victim_name_fmt, sizeof(victim_name_fmt));

		if (isSelf) {
			FormatEx(output, sizeof(output), "%s suicide", attacker_name_fmt);
			DisplayKillHUD(output);
		} else {
			FormatEx(output, sizeof(output), "%s killed %s", attacker_name_fmt, victim_name_fmt);
			DisplayKillHUD(output);
		}
	}
}

public void Tuan_OnClient_KilledByUnknown(char[] victim_name, char[] weapon_name) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char victim_name_fmt[32];
	FormatHudNameFromRaw(victim_name, victim_name_fmt, sizeof(victim_name_fmt));

	if (StrEqual(weapon_name, "Flame")) {
		FormatEx(output, sizeof(output), "%s died by flame", victim_name_fmt);
	}
	else if (StrEqual(weapon_name, "Explosion")) {
		FormatEx(output, sizeof(output), "%s died by explosion", victim_name_fmt);
	}
	else if (StrEqual(weapon_name, "Falling")) {
		FormatEx(output, sizeof(output), "%s died by falling", victim_name_fmt);
	}
	else if (StrEqual(weapon_name, "Bleeding")) {
		FormatEx(output, sizeof(output), "%s died by bleeding", victim_name_fmt);
	}
	DisplayKillHUD(output);
}

public void Tuan_OnClient_IncapOther(char[] attacker_name, char[] victim_name, char[] weapon_name) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	bool isSelf = StrEqual(attacker_name, victim_name);
	if (StrEqual(weapon_name, "None")) {
		char attacker_name_fmt[32];
		char victim_name_fmt[32];
		FormatHudNameFromRaw(attacker_name, attacker_name_fmt, sizeof(attacker_name_fmt));
		FormatHudNameFromRaw(victim_name, victim_name_fmt, sizeof(victim_name_fmt));

		if (isSelf) {
			FormatEx(output, sizeof(output), "%s self-incapacitated", attacker_name_fmt);
		} else {
			FormatEx(output, sizeof(output), "%s incapacitated %s", attacker_name_fmt, victim_name_fmt);
		}
		DisplayInfoHUD(output);
	}
}

public void Tuan_OnClient_IncappedByUnknown(char[] victim_name, char[] weapon_name) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char victim_name_fmt[32];
	FormatHudNameFromRaw(victim_name, victim_name_fmt, sizeof(victim_name_fmt));

	if (StrEqual(weapon_name, "Flame")) {
		FormatEx(output, sizeof(output), "%s incapacitated by flame", victim_name_fmt);
	}
	else if (StrEqual(weapon_name, "Explosion")) {
		FormatEx(output, sizeof(output), "%s incapacitated by explosion`", victim_name_fmt);
	}
	else if (StrEqual(weapon_name, "Falling")) {
		FormatEx(output, sizeof(output), "%s incapacitated by falling", victim_name_fmt);
	}
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_UsedThrowable(int client, int throwable_type) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char client_name_fmt[32];
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));

	switch (throwable_type) {
		case 0: {
			FormatEx(output, sizeof(output), "%s thrown molotov", client_name_fmt);
			DisplayInfoHUD(output);
		}
		case 1: {
			FormatEx(output, sizeof(output), "%s thrown pipebomb", client_name_fmt);
			DisplayInfoHUD(output);
		}
		case 2: {
			FormatEx(output, sizeof(output), "%s thrown vomitjar", client_name_fmt);
			DisplayInfoHUD(output);
		}
	}
}

public void Tuan_OnClient_HealedOther(int client, int victim) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char client_name_fmt[32];
	char victim_name_fmt[32];
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
	FormatHudNameFromClient(victim, victim_name_fmt, sizeof(victim_name_fmt));

	if (client == victim) {
		FormatEx(output, sizeof(output), "%s healed himself and no longer at last life.", client_name_fmt);
	} else {
		FormatEx(output, sizeof(output), "%s was healed by %s and no longer at last life.", victim_name_fmt, client_name_fmt);
	}
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_GoBnW(int client) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char client_name_fmt[32];
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
	FormatEx(output, sizeof(output), "%s is at last life", client_name_fmt);
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_RevivedOther(int client, int target) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	if (client == target) {
		return;
	}

	char client_name_fmt[32];
	char target_name_fmt[32];
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
	FormatHudNameFromClient(target, target_name_fmt, sizeof(target_name_fmt));

	FormatEx(output, sizeof(output), "%s helped %s to get up", client_name_fmt, target_name_fmt);
	DisplayInfoHUD(output);
}

public void Tuan_OnClient_SelfRevived(int client) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char client_name_fmt[32];
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
	FormatEx(output, sizeof(output), "%s self revived", client_name_fmt);
	DisplayInfoHUD(output);
}

public void OnMapStart() {
	GameRules_SetProp("m_bChallengeModeActive", true, _, _, true);
	g_fMapStartTime = GetGameTime();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	EnsureScriptedHudEnabled();

	for (int slot = LEFT_FEED_BASE; slot < LEFT_FEED_BASE + HUD_FEED_MAX; slot++)
		RemoveHUD(slot);
	for (int slot = RIGHT_KILL_BASE; slot < RIGHT_KILL_BASE + HUD_FEED_MAX; slot++)
		RemoveHUD(slot);
	RemoveHUD(PLAYERCOUNT_SLOT);
	RemoveHUD(TOTALSURVIVORS_SLOT);

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
	RemoveHUD(TOTALSURVIVORS_SLOT);
}

void EnsureScriptedHudEnabled() {
	int gameRules = FindEntityByClassname(-1, "terror_gamerules");
	if (gameRules == -1) {
		return;
	}

	GameRules_SetProp("m_bChallengeModeActive", true, _, _, true);
}


// HUD-------------------------------

void HUDSetLayout(int slot, int flags, const char[] dataval, any ...) {
	static char str[128];
	VFormat(str, sizeof str, dataval, 4);

	GameRules_SetProp("m_iScriptedHUDFlags", flags, _, slot, true);
	GameRules_SetPropString("m_szScriptedHUDStringSet", str, true, slot);
}

void GetShortHudNameFromRaw(const char[] name, char[] buffer, int maxlen) {
	if (strlen(name) > HUD_NAME_VISIBLE) {
		char short_name[HUD_NAME_VISIBLE + 1];
		strcopy(short_name, sizeof(short_name), name);
		short_name[HUD_NAME_VISIBLE] = '\0';
		FormatEx(buffer, maxlen, "%s...", short_name);
	} else {
		strcopy(buffer, maxlen, name);
	}
}

void GetShortHudClientName(int client, char[] buffer, int maxlen) {
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	GetShortHudNameFromRaw(name, buffer, maxlen);
}

bool IsInfectedHudLabel(const char[] name) {
	if (StrEqual(name, "Smoker", false)
		|| StrEqual(name, "Boomer", false)
		|| StrEqual(name, "Hunter", false)
		|| StrEqual(name, "Spitter", false)
		|| StrEqual(name, "Jockey", false)
		|| StrEqual(name, "Charger", false)
		|| StrEqual(name, "Tank", false)
		|| StrEqual(name, "Witch", false)) {
		return true;
	}

	if (StrContains(name, "infected", false) != -1) {
		return true;
	}

	return false;
}

void FormatHudNameFromRaw(const char[] name, char[] buffer, int maxlen) {
	char short_name[64];
	GetShortHudNameFromRaw(name, short_name, sizeof(short_name));

	if (IsInfectedHudLabel(name)) {
		strcopy(buffer, maxlen, short_name);
		return;
	}

	FormatEx(buffer, maxlen, "[%s]", short_name);
}

void FormatHudNameFromClient(int client, char[] buffer, int maxlen) {
	char short_name[64];
	GetShortHudClientName(client, short_name, sizeof(short_name));
	FormatEx(buffer, maxlen, "[%s]", short_name);
}

void GetGearTransferWeaponNameById(int weaponid, char[] buffer, int maxlen) {
	switch (weaponid) {
		case 23: strcopy(buffer, maxlen, "adrenaline");
		case 15: strcopy(buffer, maxlen, "pain pills");
		default: FormatEx(buffer, maxlen, "weapon #%d", weaponid);
	}
}

void FormatGearTransferGiveMessage(int client, int target, const char[] weapon_name, char[] buffer, int maxlen) {
	char giver_name[32];
	char receiver_name[32];
	FormatHudNameFromClient(client, giver_name, sizeof(giver_name));
	FormatHudNameFromClient(target, receiver_name, sizeof(receiver_name));
	FormatEx(buffer, maxlen, "%s give %s to %s", giver_name, weapon_name, receiver_name);
}

public void GearTransfer_OnWeaponGive(int client, int target, int item) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	if (!IsClient(client) || !IsClient(target)) {
		return;
	}

	L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
	char weapon_name[64];
	L4D2_GetWeaponNameByWeaponId(weaponId, weapon_name, sizeof(weapon_name));
	mapWeaponName.GetString(weapon_name, weapon_name, sizeof(weapon_name));
	FormatGearTransferGiveMessage(client, target, weapon_name, output, sizeof(output));
	DisplayInfoHUD(output);
}

public void GearTransfer_OnWeaponGivenEvent(int client, int target, int weaponid) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	if (!IsClient(client) || !IsClient(target)) {
		return;
	}

	char weapon_name[64];
	GetGearTransferWeaponNameById(weaponid, weapon_name, sizeof(weapon_name));
	FormatGearTransferGiveMessage(client, target, weapon_name, output, sizeof(output));
	DisplayInfoHUD(output);
}

public void GearTransfer_OnWeaponGrab(int client, int target, int item) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	if (IsClient(target)) {
		L4D2WeaponId weaponId = L4D2_GetWeaponId(item);
		char weapon_name[64];
		char client_name_fmt[32];
		char target_name_fmt[32];
		L4D2_GetWeaponNameByWeaponId(weaponId, weapon_name, sizeof(weapon_name));
		mapWeaponName.GetString(weapon_name, weapon_name, sizeof(weapon_name));
		FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
		FormatHudNameFromClient(target, target_name_fmt, sizeof(target_name_fmt));
		FormatEx(output, sizeof(output), "%s grabbed %s from %s", client_name_fmt, weapon_name, target_name_fmt);
		DisplayInfoHUD(output);
	}
}

public void GearTransfer_OnWeaponSwap(int client, int target, int itemGiven, int itemTaken) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	L4D2WeaponId givenWeaponId = L4D2_GetWeaponId(itemGiven);
	L4D2WeaponId takenWeaponId = L4D2_GetWeaponId(itemTaken);
	char given_weapon_name[64];
	char taken_weapon_name[64];
	char client_name_fmt[32];
	char target_name_fmt[32];
	L4D2_GetWeaponNameByWeaponId(givenWeaponId, given_weapon_name, sizeof(given_weapon_name));
	L4D2_GetWeaponNameByWeaponId(takenWeaponId, taken_weapon_name, sizeof(taken_weapon_name));
	mapWeaponName.GetString(given_weapon_name, given_weapon_name, sizeof(given_weapon_name));
	mapWeaponName.GetString(taken_weapon_name, taken_weapon_name, sizeof(taken_weapon_name));
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
	FormatHudNameFromClient(target, target_name_fmt, sizeof(target_name_fmt));
	FormatEx(output, sizeof(output), "%s swap %s for %s with %s", client_name_fmt, given_weapon_name, taken_weapon_name, target_name_fmt);
	DisplayInfoHUD(output);
}

//Function-------------------------------

void DisplayInfoHUD(const char[] info) {
	EnsureScriptedHudEnabled();

	if (info[0] == '\0') {
		return;
	}

	char hudInfo[128];
	BuildHudSafeMessage(info, hudInfo, sizeof(hudInfo));

	if (g_bChatNotificationEnabled) {
		CPrintToChatAll("%s", info);
	}

	bool displayedOnHud = false;
	if (!g_bScreenHudNotificationEnabled) {
		FirePublishedForward(TUAN_NOTIFY_CHANNEL_INFO, info, displayedOnHud);
		return;
	}

	HUD feed;
	g_hud_info_left.PushString(hudInfo);
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
	displayedOnHud = true;
	FirePublishedForward(TUAN_NOTIFY_CHANNEL_INFO, info, displayedOnHud);
}

void DisplayKillHUD(const char[] info) {
	EnsureScriptedHudEnabled();

	if (info[0] == '\0') {
		return;
	}

	char hudInfo[128];
	BuildHudSafeMessage(info, hudInfo, sizeof(hudInfo));

	if (g_bChatNotificationEnabled) {
		CPrintToChatAll("%s", info);
	}

	bool displayedOnHud = false;
	if (!g_bScreenHudNotificationEnabled || !g_bKillFeedEnabled) {
		FirePublishedForward(TUAN_NOTIFY_CHANNEL_KILL, info, displayedOnHud);
		return;
	}

	HUD feed;
	g_hud_kill_right.PushString(hudInfo);
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
	displayedOnHud = true;
	FirePublishedForward(TUAN_NOTIFY_CHANNEL_KILL, info, displayedOnHud);
}

void Event_Defib_Used(Event event, const char[] name, bool dontBroadCast) {
	int client = event.GetInt("userid");
	int subject = event.GetInt("subject");
	client = GetClientOfUserId(client);
	subject = GetClientOfUserId(subject);
	if (client > 0 && subject > 0) {
		char client_name_fmt[32];
		char subject_name_fmt[32];
		FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));
		FormatHudNameFromClient(subject, subject_name_fmt, sizeof(subject_name_fmt));
		FormatEx(output, sizeof(output), "%s brought %s back from dead", client_name_fmt, subject_name_fmt);
		DisplayInfoHUD(output);
	}
}
public void Tuan_OnClient_ExplodeObject(int client, int object_type) {
	if (!g_bLegacyForwardMode) {
		return;
	}

	char client_name_fmt[32];
	FormatHudNameFromClient(client, client_name_fmt, sizeof(client_name_fmt));

	switch (object_type) {
		case TYPE_GASCAN:
        {
			FormatEx(output, sizeof(output), "%s exploded a gascan", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_FUEL_BARREL:
        {
			FormatEx(output, sizeof(output), "%s exploded a fuel barrel", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_PROPANECANISTER:
        {
			FormatEx(output, sizeof(output), "%s exploded a propane canister", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_OXYGENTANK:
        {
			FormatEx(output, sizeof(output), "%s exploded an oxygen tank", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_BARRICADE_GASCAN:
        {
			FormatEx(output, sizeof(output), "%s exploded a barricade gascan", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_GAS_PUMP:
        {
			FormatEx(output, sizeof(output), "%s exploded a gas pump", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_FIREWORKS_CRATE:
        {
			FormatEx(output, sizeof(output), "%s exploded a fireworks crate", client_name_fmt);
			DisplayInfoHUD(output);
        }

        case TYPE_OIL_DRUM_EXPLOSIVE:
        {
			FormatEx(output, sizeof(output), "%s exploded an oil drum", client_name_fmt);
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
	int aliveSurvivorCount = 0;
	int humanSurvivorCount = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClient(i)) {
			continue;
		}

		if (GetClientTeam(i) == TEAM_SURVIVOR && IsPlayerAlive(i)) {
			aliveSurvivorCount++;
		}

		if (GetClientTeam(i) == TEAM_SURVIVOR && !IsFakeClient(i)) {
			humanSurvivorCount++;
		}
	}

	// Prefer l4dinfectedbots exported runtime status for 1:1 sync with its announce values.
	if (g_hCvarInfBotsCurrentAliveSurvivor != null) {
		aliveSurvivorCount = g_hCvarInfBotsCurrentAliveSurvivor.IntValue;
	}

	int maxSpecials = 0;
	if (g_hCvarInfBotsCurrentSILimit != null) {
		maxSpecials = g_hCvarInfBotsCurrentSILimit.IntValue;
	} else if (g_hCvarMaxSpecials != null) {
		maxSpecials = g_hCvarMaxSpecials.IntValue;
	}

	int tankHealth = 0;
	if (g_hCvarInfBotsCurrentTankHP != null) {
		tankHealth = g_hCvarInfBotsCurrentTankHP.IntValue;
	} else if (g_hCvarTankHealth != null) {
		tankHealth = g_hCvarTankHealth.IntValue;
	}

	int commonLimit = 0;
	if (g_hCvarZCommonLimit != null) {
		commonLimit = g_hCvarZCommonLimit.IntValue;
	}

	// Left HUD: dynamic info
	FormatEx(output, sizeof(output), "Alive Survivor: %d | SI: %d | Tank HP: %d | CI: %d", aliveSurvivorCount, maxSpecials, tankHealth, commonLimit);
	HUDSetLayout(PLAYERCOUNT_SLOT, g_iHUDFlags_PlayerCount, output);
	HUDPlace(PLAYERCOUNT_SLOT, PLAYERCOUNT_X, PLAYERCOUNT_Y, PLAYERCOUNT_W, PLAYERCOUNT_H);

	char chapterName[64];
	GetCurrentMap(chapterName, sizeof(chapterName));

	int maxPlayers = 8;
	if (g_hCvarSvMaxPlayers != null && g_hCvarSvMaxPlayers.IntValue > 0) {
		maxPlayers = g_hCvarSvMaxPlayers.IntValue;
	}

	int openSlots = maxPlayers - humanSurvivorCount;
	if (openSlots < 0) {
		openSlots = 0;
	}

	char mapTime[16];
	FormatElapsedMapTime(mapTime, sizeof(mapTime));

	// Right HUD: chapter, open slots, map time
	FormatEx(output, sizeof(output), "Chapter: %s\nOpen slots: %d\nMap time: %s", chapterName, openSlots, mapTime);
	HUDSetLayout(TOTALSURVIVORS_SLOT, g_iHUDFlags_TotalSurvivors, output);
	HUDPlace(TOTALSURVIVORS_SLOT, TOTALSURVIVORS_X, TOTALSURVIVORS_Y, TOTALSURVIVORS_W, TOTALSURVIVORS_H);
}

void BuildHudSafeMessage(const char[] input, char[] outputMessage, int maxlen)
{
	strcopy(outputMessage, maxlen, input);
	StripColorTags(outputMessage, maxlen);
	ReplaceString(outputMessage, maxlen, "[", "", false);
	ReplaceString(outputMessage, maxlen, "]", "", false);
	TrimString(outputMessage);
}

void StripColorTags(char[] text, int maxlen)
{
	static const char tags[][] = {
		"{default}",
		"{green}",
		"{blue}",
		"{red}",
		"{olive}",
		"{lightblue}",
		"{teamcolor}"
	};

	for (int i = 0; i < sizeof(tags); i++) {
		ReplaceString(text, maxlen, tags[i], "", false);
	}
}

void FormatElapsedMapTime(char[] buffer, int maxlen)
{
	int elapsed = RoundToFloor(GetGameTime() - g_fMapStartTime);
	if (elapsed < 0) {
		elapsed = 0;
	}

	int hours = elapsed / 3600;
	int minutes = (elapsed % 3600) / 60;
	int seconds = elapsed % 60;
	FormatEx(buffer, maxlen, "%02d:%02d:%02d", hours, minutes, seconds);
}
