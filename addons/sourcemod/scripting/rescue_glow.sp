#define PLUGIN_VERSION	"2.6"
#define PLUGIN_NAME		"Rescue Glow"
#define PLUGIN_PREFIX	"rescue_glow"

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <little_froy_utils>

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = "little_froy",
	description = "game play",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=348762"
};

ConVar C_color;
int O_color[3];
ConVar C_flash;
bool O_flash;

GlobalForward Forward_OnAdded;
GlobalForward Forward_OnRemoved;
bool Late_load;

bool Added[MAXPLAYERS+1];

void set_glow(int entity, int type = 0, const int color[3] = {0, 0, 0}, int range = 0, int range_min = 0, bool flash = false)
{
    SetEntProp(entity, Prop_Send, "m_iGlowType", type);
    SetEntProp(entity, Prop_Send, "m_glowColorOverride", color[0] + color[1] * 256 + color[2] * 65536);
    SetEntProp(entity, Prop_Send, "m_nGlowRange", range);
    SetEntProp(entity, Prop_Send, "m_nGlowRangeMin", range_min);
    SetEntProp(entity, Prop_Send, "m_bFlashing", flash ? 1 : 0);
}

void add_glow(int client)
{
    if(!Added[client])
    {
        Added[client] = true;
        set_glow(client, 3, O_color, .flash = O_flash);
        Call_StartForward(Forward_OnAdded);
        Call_PushCell(client);
        Call_Finish();
    }
}

void remove_glow(int client)
{
    if(Added[client])
    {
        Added[client] = false;
        set_glow(client);
        Call_StartForward(Forward_OnRemoved);
        Call_PushCell(client);
        Call_Finish();
    }
}

void reset_all()
{
    for(int client = 1; client <= MAXPLAYERS; client++)
    {
        if(client <= MaxClients)
        {
            remove_glow(client);
        }
        else
        {
            Added[client] = false;
        }
    }
}

void on_post_think_post(int client)
{
    if(GetClientTeam(client) == 2 && !IsPlayerAlive(client))
    {
        int resuce = -1;
        while((resuce = FindEntityByClassname(resuce, "info_survivor_rescue")) != -1)
        {
            if(resuce > 0 && GetEntPropEnt(resuce, Prop_Send, "m_survivor") == client)
            {
                add_glow(client);
                return;
            }
        }
        remove_glow(client);
    }
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_PostThinkPost, on_post_think_post);
}

public void OnClientDisconnect_Post(int client)
{
    Added[client] = false;
}

void event_player_spawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client != 0)
	{
		remove_glow(client);
	}
}

void event_player_team(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client != 0)
	{
		remove_glow(client);
	}
}

void event_player_death(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(client != 0)
	{
		remove_glow(client);
	}
}

void event_round_start(Event event, const char[] name, bool dontBroadcast)
{
    reset_all();
}

void get_all_cvars()
{
    char buffer[64];
    C_color.GetString(buffer, sizeof(buffer));
    explode_string_to_cell_array(buffer, " ", O_color, sizeof(O_color), 32, StringExplodeType_Int);
    O_flash = C_flash.BoolValue;
}

void get_single_cvar(ConVar convar)
{
    if(convar == C_color)
    {
        char buffer[64];
        C_color.GetString(buffer, sizeof(buffer));
        explode_string_to_cell_array(buffer, " ", O_color, sizeof(O_color), 32, StringExplodeType_Int);
    }
    else if(convar == C_flash)
    {
        O_flash = C_flash.BoolValue;
    }
}

void convar_changed(ConVar convar, const char[] oldValue, const char[] newValue)
{
	get_single_cvar(convar);
}

any native_RescueGlow_HasGlow(Handle plugin, int numParams)
{
    return Added[GetNativeCell(1)];
}

public APLRes AskPluginLoad2(Handle plugin, bool late, char[] error, int err_max)
{
    if(GetEngineVersion() != Engine_Left4Dead2)
    {
        strcopy(error, err_max, "this plugin only runs in \"Left 4 Dead 2\"");
        return APLRes_SilentFailure;
    }
    Late_load = late;
    Forward_OnAdded = new GlobalForward("RescueGlow_OnAdded", ET_Ignore, Param_Cell);
    Forward_OnRemoved = new GlobalForward("RescueGlow_OnRemoved", ET_Ignore, Param_Cell);
    CreateNative("RescueGlow_HasGlow", native_RescueGlow_HasGlow);
    RegPluginLibrary(PLUGIN_PREFIX);
    return APLRes_Success;
}

public void OnPluginStart()
{
    HookEvent("player_spawn", event_player_spawn);
	HookEvent("player_team", event_player_team);
    HookEvent("player_death", event_player_death);
    HookEvent("round_start", event_round_start);

    C_color = CreateConVar(PLUGIN_PREFIX ... "_color", "255 102 0", "color of glow, split up with space");
    C_color.AddChangeHook(convar_changed);
    C_flash = CreateConVar(PLUGIN_PREFIX ... "_flash", "1", "1 = enable, 0 = disable. will the glow flash?");
    C_flash.AddChangeHook(convar_changed);
    CreateConVar(PLUGIN_PREFIX ... "_version", PLUGIN_VERSION, "version of " ... PLUGIN_NAME, FCVAR_NOTIFY | FCVAR_DONTRECORD);
    //AutoExecConfig(true, PLUGIN_PREFIX);
    get_all_cvars();

    if(Late_load)
    {
        for(int client = 1; client <= MaxClients; client++)
        {
            if(IsClientInGame(client))
            {
                OnClientPutInServer(client);
            }
        }
    }
}

public void OnPluginEnd()
{
    reset_all();
}