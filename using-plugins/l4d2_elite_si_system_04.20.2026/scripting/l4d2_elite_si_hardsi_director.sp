#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>

#define PLUGIN_VERSION "1.0.1"

ConVar g_cvEnable;
ConVar g_cvAssaultInterval;

Handle g_hAssaultTimer;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Abnormal Director",
	author = "OpenCode",
	description = "Global aggressive director support for Abnormal Behavior modules.",
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

	return APLRes_Success;
}

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("l4d2_elite_si_hardsi_director_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvAssaultInterval = CreateConVar("l4d2_elite_si_hardsi_director_assault_interval", "2.0", "Frequency in seconds for nb_assault. 0=Off.", FCVAR_NOTIFY, true, 0.0, true, 30.0);

	CreateConVar("l4d2_elite_si_hardsi_director_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_hardsi_director");

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
}

public void OnMapEnd()
{
	StopAssaultTimer();
}

public void OnConfigsExecuted()
{
	if (!g_cvEnable.BoolValue)
	{
		StopAssaultTimer();
		return;
	}

	if (L4D_HasAnySurvivorLeftSafeArea())
	{
		StartAssaultTimer();
	}
}

public void L4D_OnFirstSurvivorLeftSafeArea_Post(int client)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	StartAssaultTimer();
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	StopAssaultTimer();
	return Plugin_Continue;
}

public Action Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	StopAssaultTimer();
	return Plugin_Continue;
}

void StartAssaultTimer()
{
	StopAssaultTimer();

	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	float interval = g_cvAssaultInterval.FloatValue;
	if (interval <= 0.0)
	{
		return;
	}

	g_hAssaultTimer = CreateTimer(interval, Timer_Assault, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

void StopAssaultTimer()
{
	if (g_hAssaultTimer == null)
	{
		return;
	}

	KillTimer(g_hAssaultTimer);
	g_hAssaultTimer = null;
}

public Action Timer_Assault(Handle timer)
{
	if (timer != g_hAssaultTimer)
	{
		return Plugin_Stop;
	}

	if (!g_cvEnable.BoolValue || g_cvAssaultInterval.FloatValue <= 0.0)
	{
		StopAssaultTimer();
		return Plugin_Stop;
	}

	RunCheatCommand("nb_assault");
	return Plugin_Continue;
}

void RunCheatCommand(const char[] command)
{
	int flags = GetCommandFlags(command);
	SetCommandFlags(command, flags & ~FCVAR_CHEAT);
	ServerCommand("%s", command);
	ServerExecute();
	SetCommandFlags(command, flags);
}
