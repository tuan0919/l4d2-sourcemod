#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>
#define PLUGIN_VERSION "1.3"
#define GAMEDATA			"Tuan_l4d2_pipebomb_change_timer"
ConVar pipebomb_duration;
Handle g_hSDK_CBaseGrenade_Detonate;
enum struct Context
{
	ArrayList projectiles;
	bool init;
	float time;
	void constructor()
	{
		if (this.init) return;
		this.init = true;
		this.projectiles = new ArrayList();
		this.time = GetExplodeTime(); //mặc định
	}
	
	void toggleMode()
	{
		this.time = this.time == GetExplodeTime() ? 1.0 : GetExplodeTime();
	}
}
Context g_clientPrj[MAXPLAYERS + 1];
bool g_InReload[MAXPLAYERS + 1];
bool g_ShowHelp[MAXPLAYERS + 1];
#define TRANSLATION_FILENAME 	"Tuan_l4d2_pipebomb_change_timer.phrases"

public Plugin myinfo = 
{
	name 			= "[L4D2] Pipebomb changing timer",
	author 			= "Tuan",
	description 	= "Allows survivors to change their pipebomb timer on its explosion",
	version 		=  PLUGIN_VERSION,
	url 			= ""
}

public void OnPluginStart()
{
	// GameData
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\"\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);
	StartPrepSDKCall(SDKCall_Entity);
	if( PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseGrenade::Detonate") == false )
	{
		LogError("Failed to find signature: \"CBaseGrenade::Detonate\"");
	} 
	else {
		g_hSDK_CBaseGrenade_Detonate = EndPrepSDKCall();
		if( g_hSDK_CBaseGrenade_Detonate == null )
			LogError("Failed to create SDKCall: \"CBaseGrenade::Detonate\"");
	}
	delete hGameData;
	LoadTrans();
	pipebomb_duration = FindConVar("pipe_bomb_timer_duration");
	for (int i = 1; i <= MaxClients; i++)
	{
		g_clientPrj[i].constructor();
	}
}

void LoadTrans()
{
	char path[256];
	BuildPath(Path_SM, path, sizeof(path), "translations/%s.txt", TRANSLATION_FILENAME);
	if (FileExists(path)) {
		LoadTranslations(TRANSLATION_FILENAME);
	}
}

public void OnPlayerRunCmdPost(int client, int buttons)
{
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if ( weapon == -1 )
		return;
	char className[64];
	char message[255];
	GetEntityClassname(weapon, className, sizeof className);
	if (strcmp(className, "weapon_pipe_bomb") != 0) return;
	if (buttons & IN_ATTACK)
	{
		if (!g_ShowHelp[client])
		{
			Format(message, sizeof(message), "%t", "Helper Message");
			CPrintToChat(client, message);
			g_ShowHelp[client] = true;
			g_clientPrj[client].time = GetExplodeTime(); //Đặt lại thời gian nổ mặc định cho Pipebomb này
		}
		if (!g_InReload[client] && (buttons & IN_RELOAD))
		{
			g_clientPrj[client].toggleMode();
			g_InReload[client] = true;
			Format(message, sizeof(message), "%t", "Change Message", RoundFloat(g_clientPrj[client].time));
			CPrintToChat(client, message);
		}
		else if (g_InReload[client] && !(buttons & IN_RELOAD))
			g_InReload[client] = false;
	}
	else
	{
		g_ShowHelp[client] = false;
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (strcmp(classname, "pipe_bomb_projectile") != 0) return;
	SDKHook(entity, SDKHook_SpawnPost, OnSpawnPost);
}

public void OnSpawnPost( int entity )
{
	RequestFrame(NextFrame, EntIndexToEntRef(entity));
}

public void NextFrame(int entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity <= MaxClients || !IsValidEntity(entity)) return;
	int client = GetEntPropEnt(entity, Prop_Data, "m_hThrower");
	if (1 <= client <= MaxClients && IsClientConnected(client) && GetClientTeam(client) == 2)
	{
		g_clientPrj[client].projectiles.Push(entityRef);
		CreateTimer(g_clientPrj[client].time, Explode_Timer_Handle, client);
	}
	SDKHook(entity, SDKHook_Touch, OnTounch);
}

public void OnTounch(int entity, int other) {
	SDKCall(g_hSDK_CBaseGrenade_Detonate, entity);
}

Action Explode_Timer_Handle(Handle timer, int client)
{
	if (!IsClientConnected(client) || !g_clientPrj[client].projectiles.Length) return Plugin_Continue;
	int entity = EntRefToEntIndex(g_clientPrj[client].projectiles.Get(0));
	g_clientPrj[client].projectiles.Erase(0);
	if (!IsValidEntity(entity) || entity <= MaxClients) return Plugin_Continue;
	SDKCall(g_hSDK_CBaseGrenade_Detonate, entity);
	return Plugin_Continue;
}

public void OnMapEnd() 
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_clientPrj[i].projectiles.Clear();
	}
}

public void OnClientPutInServer(int client)
{
	if (!g_clientPrj[client].init){
		g_clientPrj[client].constructor();
	}
}

float GetExplodeTime()
{
	return pipebomb_duration.FloatValue;
}