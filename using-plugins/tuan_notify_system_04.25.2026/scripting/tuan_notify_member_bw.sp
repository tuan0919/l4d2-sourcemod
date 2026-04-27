/***************************************************************************************** 
* Black and White Notifier (L4D/L4D2)
* Author(s): DarkNoghri, madcap (recoded by: retsam), Merudo, Tuan
* Date: 27/04/2026
* File: tuan_notify_member_bw.sp
* Description: Notify people when player is black and white or dead
******************************************************************************************
* 2.2 - Sync BW state khi player self-revive bằng Tuan_l4d_incapped_weapons
* 2.1 - Hook LevelStartHeal_OnHealed để reset BW state khi plugin heal đầu map
* 2.0 - Rewrite this plugin by Tuan
* 1.7r2 - Cancel B/W glow if healed from non-medkit source.
* 1.7r  - Initial recode.
*/

#include <sourcemod>
#include <colors>
#include <level_start_heal>
#include <Tuan_custom_forwards>
#pragma semicolon 1;
#pragma newdecls required;

#define PLUGIN_VERSION "2.2"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

bool g_bPlayerBW[MAXPLAYERS+1] = { false, ... };
GlobalForward g_OnClientHealedBnW;
GlobalForward g_OnClientGoBnW;
GlobalForward g_OnClientRevivedOther;
ConVar g_hBWEnable;
ConVar g_hBWNotifyHealedOther;
ConVar g_hBWNotifyGoBnW;
ConVar g_hBWNotifyRevivedOther;
bool g_bBWEnable;
bool g_bBWNotifyHealedOther;
bool g_bBWNotifyGoBnW;
bool g_bBWNotifyRevivedOther;
bool g_bLeft4Dead2;

public Plugin myinfo = 
{
	name = "[L4D] Black and White Notifier",
	author = "DarkNoghri, madcap, Merudo, forked by Tuan",
	description = "Notify people when player is black and white or dead.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showpost.php?p=1438810&postcount=68"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	g_bLeft4Dead2 = (engine == Engine_Left4Dead2);
	MarkNativeAsOptional("LevelStartHeal_OnHealed");
	return APLRes_Success;
}

public void OnPluginStart()
{
	HookEvent("revive_success", Event_ReviveSuccess_Pre, EventHookMode_Pre);
	HookEvent("revive_success", Event_ReviveSuccess_Post);
	HookEvent("heal_success", Event_HealSuccess_Post);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
	g_OnClientHealedBnW = CreateGlobalForward("Tuan_OnClient_HealedOther", ET_Event, Param_Cell, Param_Cell);
	g_OnClientGoBnW = CreateGlobalForward("Tuan_OnClient_GoBnW", ET_Event, Param_Cell);
	g_OnClientRevivedOther = CreateGlobalForward("Tuan_OnClient_RevivedOther", ET_Event, Param_Cell, Param_Cell);
	g_hBWEnable = CreateConVar("tuan_notifier_bw_enable", "1", "Enable black&white notifier forwards.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hBWNotifyHealedOther = CreateConVar("tuan_notifier_bw_notify_healed_other", "1", "Notify Tuan_OnClient_HealedOther.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hBWNotifyGoBnW = CreateConVar("tuan_notifier_bw_notify_go_bnw", "1", "Notify Tuan_OnClient_GoBnW.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hBWNotifyRevivedOther = CreateConVar("tuan_notifier_bw_notify_revived_other", "1", "Notify Tuan_OnClient_RevivedOther.\n0=OFF, 1=ON.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_hBWEnable.AddChangeHook(BW_OnConVarChanged);
	g_hBWNotifyHealedOther.AddChangeHook(BW_OnConVarChanged);
	g_hBWNotifyGoBnW.AddChangeHook(BW_OnConVarChanged);
	g_hBWNotifyRevivedOther.AddChangeHook(BW_OnConVarChanged);
	BW_GetCvars();
	AutoExecConfig(true, "tuan_notifier_unified_blackwhite");
}

public void OnMapStart() {
	BW_ResetAllStates();
}

public void OnClientPutInServer(int client) {
	BW_ResetClientState(client);
}

public void OnClientDisconnect(int client) {
	BW_ResetClientState(client);
}

/**
 * Hook từ level_start_heal: reset BW state sau khi survivor được heal đầu map.
 * Tránh thông báo nhầm "is at last life" sau khi plugin đã clear BW state.
 */
public void LevelStartHeal_OnHealed(int client)
{
	BW_ResetClientState(client);
}

void BW_ResetClientState(int client) {
	if (client >= 1 && client <= MaxClients) {
		g_bPlayerBW[client] = false;
	}
}

void BW_ResetAllStates() {
	for (int i = 1; i <= MaxClients; i++) {
		g_bPlayerBW[i] = false;
	}
}

bool BW_IsClientCurrentlyBnW(int client) {
	if (client < 1 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client)) {
		return false;
	}

	if (g_bLeft4Dead2 && GetEntProp(client, Prop_Send, "m_bIsOnThirdStrike") != 0) {
		return true;
	}

	ConVar maxIncapCvar = FindConVar("survivor_max_incapacitated_count");
	int maxIncap = maxIncapCvar != null ? maxIncapCvar.IntValue : 2;
	return GetEntProp(client, Prop_Send, "m_currentReviveCount") >= maxIncap;
}

void BW_GetCvars() {
	g_bBWEnable = g_hBWEnable.BoolValue;
	g_bBWNotifyHealedOther = g_hBWNotifyHealedOther.BoolValue;
	g_bBWNotifyGoBnW = g_hBWNotifyGoBnW.BoolValue;
	g_bBWNotifyRevivedOther = g_hBWNotifyRevivedOther.BoolValue;
}

void BW_OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	BW_GetCvars();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
	BW_ResetAllStates();
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	BW_ResetClientState(client);
}

public void Tuan_OnClient_SelfRevived(int client) {
	if (client < 1 || client > MaxClients) {
		return;
	}

	bool isBnW = BW_IsClientCurrentlyBnW(client);

	if (isBnW && !g_bPlayerBW[client]) {
		g_bPlayerBW[client] = true;
		FireClientGoBnW(client);
		return;
	}

	g_bPlayerBW[client] = isBnW;
}

void FireClientHealedOtherEvent(int client, int victim) {
	if (!g_bBWEnable || !g_bBWNotifyHealedOther) return;
	Call_StartForward(g_OnClientHealedBnW);
	Call_PushCell(client);
	Call_PushCell(victim);
	Call_Finish();
}

void FireClientGoBnW(int client) {
	if (!g_bBWEnable || !g_bBWNotifyGoBnW) return;
	Call_StartForward(g_OnClientGoBnW);
	Call_PushCell(client);
	Call_Finish();
}

void FireClientRevivedOther(int client, int target) {
	if (!g_bBWEnable || !g_bBWNotifyRevivedOther) return;
	Call_StartForward(g_OnClientRevivedOther);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_Finish();
}

void Event_ReviveSuccess_Pre(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
}

public void Event_ReviveSuccess_Post(Handle event, const char[] name, bool dontBroadcast)
{
	int target = GetClientOfUserId(GetEventInt(event, "subject"));
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (GetEventBool(event, "lastlife"))
	{
		if (target < 1) return;
		g_bPlayerBW[target] = true;
		FireClientGoBnW(target);
	} else {
		FireClientRevivedOther(client, target);
	}
}

public void Event_HealSuccess_Post(Handle event, const char[] name, bool dontBroadcast)
{
	int healee = GetClientOfUserId(GetEventInt(event, "subject"));
	int healer = GetClientOfUserId(GetEventInt(event, "userid"));

	if (healee < 1)
		return;

	if (g_bPlayerBW[healee])
	{
		g_bPlayerBW[healee] = false;
		FireClientHealedOtherEvent(healer, healee);
	}
}
