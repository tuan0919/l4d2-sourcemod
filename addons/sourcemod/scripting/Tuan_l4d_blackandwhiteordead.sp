/***************************************************************************************** 
* Black and White Notifier (L4D/L4D2)
* Author(s): DarkNoghri, madcap (recoded by: retsam), Merudo, Tuan
* Date: 21/01/2024
* File: Tuan_l4d_blackandwhiteordead.sp
* Description: Notify people when player is black and white or dead
******************************************************************************************
* 2.0 - Rewrite this plugin by Tuan
* 1.7r2 - Cancel B/W glow if healed from non-medkit source. Glow stays if player disconnect / goes idle
* 1.7r  - Initial recode.
*/

#include <sourcemod>
#include <colors>
#include <Tuan_custom_forwards>
#pragma semicolon 1;
#pragma newdecls required;

#define PLUGIN_VERSION "1.8"
#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3
bool g_bPlayerBW[MAXPLAYERS+1] = { false, ... };
GlobalForward g_OnClientHealedBnW;
GlobalForward g_OnClientGoBnW;
GlobalForward g_OnClientRevivedOther;
public Plugin myinfo = 
{
	name = "[L4D] Black and White Notifier",
	author = "DarkNoghri, madcap, Merudo, forked by Tuan",
	description = "Notify people when player is black and white or dead.",
	version = PLUGIN_VERSION,
	url = "http://forums.alliedmods.net/showpost.php?p=1438810&postcount=68"
}

public void OnPluginStart()
{
	HookEvent("revive_success", Event_ReviveSuccess_Pre, EventHookMode_Pre);
	HookEvent("revive_success", Event_ReviveSuccess_Post);
	HookEvent("heal_success", Event_HealSuccess_Post);
	g_OnClientHealedBnW = CreateGlobalForward("Tuan_OnClient_HealedOther", ET_Event, Param_Cell, Param_Cell);
	g_OnClientGoBnW = CreateGlobalForward("Tuan_OnClient_GoBnW", ET_Event, Param_Cell);
	g_OnClientRevivedOther = CreateGlobalForward("Tuan_OnClient_RevivedOther", ET_Event, Param_Cell, Param_Cell);
}

void FireClientHealedOtherEvent(int client, int victim) {
    Call_StartForward(g_OnClientHealedBnW);
    Call_PushCell(client);
	Call_PushCell(victim);
    Call_Finish();
}

void FireClientGoBnW(int client) {
    Call_StartForward(g_OnClientGoBnW);
    Call_PushCell(client);
    Call_Finish();
}

void FireClientRevivedOther(int client, int target) {
    Call_StartForward(g_OnClientRevivedOther);
    Call_PushCell(client);
	Call_PushCell(target);
    Call_Finish();
}

void Event_ReviveSuccess_Pre(Event event, const char[] name, bool dontBroadcast) {
	event.BroadcastDisabled = true;
}

// --------------------------------------
// On last revive
// --------------------------------------
public void Event_ReviveSuccess_Post(Handle event, const char[] name, bool dontBroadcast)
{
	int target = GetClientOfUserId(GetEventInt(event, "subject"));
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(GetEventBool(event, "lastlife"))
	{
		if(target < 1) return;
		g_bPlayerBW[target] = true;
		// fire event
		FireClientGoBnW(target);
	} else {
		FireClientRevivedOther(client, target);
	}
}

// --------------------------------------
// If healing and healee was B&W, show message
// --------------------------------------
public void Event_HealSuccess_Post(Handle event, const char[] name, bool dontBroadcast)
{

	int healee = GetClientOfUserId(GetEventInt(event, "subject"));
	int healer = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(healee < 1)
	return;
	
	if(g_bPlayerBW[healee])
	{
		g_bPlayerBW[healee] = false;
		FireClientHealedOtherEvent(healer, healee);
	}
}