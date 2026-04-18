#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.0.0"

#define TEAM_SURVIVOR 2
#define TEAM_INFECTED 3

#define ZC_BOOMER 2

#define ELITE_SUBTYPE_BOOMER_FLASHBANG 27

#define FLASH_TRACE_TOLERANCE 25.0

#define FFADE_IN 0x0001
#define FFADE_PURGE 0x0010

native bool EliteSI_IsElite(int client);
native int EliteSI_GetSubtype(int client);

ConVar g_cvEnable;
ConVar g_cvSightAngle;
ConVar g_cvCloseRange;
ConVar g_cvMediumRange;
ConVar g_cvFarRange;
ConVar g_cvCloseDuration;
ConVar g_cvMediumDuration;
ConVar g_cvFarDuration;
ConVar g_cvDistantDuration;
ConVar g_cvBlockedDuration;
ConVar g_cvColor;
ConVar g_cvAlpha;

bool g_bHasEliteApi;

public Plugin myinfo =
{
	name = "[L4D2] Elite SI Boomer Flashbang",
	author = "OpenCode",
	description = "Flashbang subtype module for elite Boomer bots.",
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
	g_cvEnable = CreateConVar("l4d2_elite_si_boomer_flashbang_enable", "1", "0=Off, 1=On.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvSightAngle = CreateConVar("l4d2_elite_si_boomer_flashbang_sight_angle", "180.0", "Sight cone angle in degrees.", FCVAR_NOTIFY, true, 1.0, true, 360.0);
	g_cvCloseRange = CreateConVar("l4d2_elite_si_boomer_flashbang_close_range", "1000.0", "Close-range threshold for the strongest flash.", FCVAR_NOTIFY, true, 50.0, true, 5000.0);
	g_cvMediumRange = CreateConVar("l4d2_elite_si_boomer_flashbang_medium_range", "1500.0", "Medium-range threshold for flash strength.", FCVAR_NOTIFY, true, 50.0, true, 5000.0);
	g_cvFarRange = CreateConVar("l4d2_elite_si_boomer_flashbang_far_range", "2000.0", "Far-range threshold for flash strength.", FCVAR_NOTIFY, true, 50.0, true, 5000.0);
	g_cvCloseDuration = CreateConVar("l4d2_elite_si_boomer_flashbang_close_duration", "4000", "Fade duration in ms at close range.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
	g_cvMediumDuration = CreateConVar("l4d2_elite_si_boomer_flashbang_medium_duration", "2000", "Fade duration in ms at medium range.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
	g_cvFarDuration = CreateConVar("l4d2_elite_si_boomer_flashbang_far_duration", "1500", "Fade duration in ms at far range.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
	g_cvDistantDuration = CreateConVar("l4d2_elite_si_boomer_flashbang_distant_duration", "500", "Fade duration in ms beyond far range when still visible.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
	g_cvBlockedDuration = CreateConVar("l4d2_elite_si_boomer_flashbang_blocked_duration", "200", "Fade duration in ms when the blast is occluded or outside the sight cone.", FCVAR_NOTIFY, true, 0.0, true, 10000.0);
	g_cvColor = CreateConVar("l4d2_elite_si_boomer_flashbang_color", "127 235 212", "Fade color as R G B.", FCVAR_NOTIFY);
	g_cvAlpha = CreateConVar("l4d2_elite_si_boomer_flashbang_alpha", "255", "Fade alpha (0-255).", FCVAR_NOTIFY, true, 0.0, true, 255.0);

	CreateConVar("l4d2_elite_si_boomer_flashbang_version", PLUGIN_VERSION, "Plugin version.", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	AutoExecConfig(true, "l4d2_elite_si_boomer_flashbang");

	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

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

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_cvEnable.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!ShouldApplySubtype(client, false))
	{
		return;
	}

	float boomerPos[3];
	GetClientAbsOrigin(client, boomerPos);

	int color[3];
	GetFlashColor(color);
	int alpha = g_cvAlpha.IntValue;

	for (int survivor = 1; survivor <= MaxClients; survivor++)
	{
		if (!IsValidHumanSurvivor(survivor))
		{
			continue;
		}

		float eyePos[3];
		GetClientEyePosition(survivor, eyePos);
		float distance = GetVectorDistance(boomerPos, eyePos);
		int duration = GetFlashDuration(survivor, boomerPos, distance);
		if (duration <= 0)
		{
			continue;
		}

		PerformFade(survivor, duration, color, alpha);
	}
}

int GetFlashDuration(int survivor, const float boomerPos[3], float distance)
{
	if (!IsPointInSightRange(survivor, boomerPos, g_cvSightAngle.FloatValue) || !HasLineOfSight(survivor, boomerPos))
	{
		return g_cvBlockedDuration.IntValue;
	}

	if (distance > g_cvFarRange.FloatValue)
	{
		return g_cvDistantDuration.IntValue;
	}

	if (distance > g_cvMediumRange.FloatValue)
	{
		return g_cvFarDuration.IntValue;
	}

	if (distance > g_cvCloseRange.FloatValue)
	{
		return g_cvMediumDuration.IntValue;
	}

	return g_cvCloseDuration.IntValue;
}

bool IsPointInSightRange(int client, const float target[3], float angle)
{
	if (!IsValidHumanSurvivor(client))
	{
		return false;
	}

	float eyeAngles[3];
	float forwardVec[3];
	float viewerPos[3];
	float targetPos[3];
	float toTarget[3];

	GetClientEyeAngles(client, eyeAngles);
	eyeAngles[0] = 0.0;
	eyeAngles[2] = 0.0;
	GetAngleVectors(eyeAngles, forwardVec, NULL_VECTOR, NULL_VECTOR);
	NormalizeVector(forwardVec, forwardVec);

	GetClientAbsOrigin(client, viewerPos);
	targetPos[0] = target[0];
	targetPos[1] = target[1];
	targetPos[2] = target[2];
	viewerPos[2] = 0.0;
	targetPos[2] = 0.0;

	MakeVectorFromPoints(viewerPos, targetPos, toTarget);
	if (GetVectorLength(toTarget) < 0.001)
	{
		return true;
	}

	NormalizeVector(toTarget, toTarget);
	float dot = GetVectorDotProduct(toTarget, forwardVec);
	if (dot > 1.0)
	{
		dot = 1.0;
	}
	else if (dot < -1.0)
	{
		dot = -1.0;
	}

	return RadToDeg(ArcCosine(dot)) <= angle * 0.5;
}

bool HasLineOfSight(int client, const float targetPos[3])
{
	float start[3];
	float end[3];
	float hitPos[3];

	GetClientEyePosition(client, start);
	end[0] = targetPos[0];
	end[1] = targetPos[1];
	end[2] = targetPos[2] + 30.0;

	TR_TraceRayFilter(start, end, MASK_VISIBLE_AND_NPCS, RayType_EndPoint, TraceFilterFlash, client);
	TR_GetEndPosition(hitPos);

	return GetVectorDistance(hitPos, end) <= FLASH_TRACE_TOLERANCE;
}

public bool TraceFilterFlash(int entity, int mask, any data)
{
	if (entity > 0 && entity <= MaxClients)
	{
		return entity != data;
	}

	return true;
}

void PerformFade(int client, int duration, const int color[3], int alpha)
{
	Handle message = StartMessageOne("Fade", client);
	if (message == null)
	{
		return;
	}

	int hold = duration / 4;
	BfWriteShort(message, duration);
	BfWriteShort(message, hold);
	BfWriteShort(message, FFADE_PURGE | FFADE_IN);
	BfWriteByte(message, color[0]);
	BfWriteByte(message, color[1]);
	BfWriteByte(message, color[2]);
	BfWriteByte(message, alpha);
	EndMessage();
}

void GetFlashColor(int color[3])
{
	char value[32];
	char parts[3][8];
	g_cvColor.GetString(value, sizeof(value));

	color[0] = 127;
	color[1] = 235;
	color[2] = 212;

	if (ExplodeString(value, " ", parts, sizeof(parts), sizeof(parts[])) < 3)
	{
		return;
	}

	for (int i = 0; i < 3; i++)
	{
		int parsed = StringToInt(parts[i]);
		if (parsed < 0)
		{
			parsed = 0;
		}
		else if (parsed > 255)
		{
			parsed = 255;
		}

		color[i] = parsed;
	}
}

bool ShouldApplySubtype(int client, bool requireAlive)
{
	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		return false;
	}

	if (GetClientTeam(client) != TEAM_INFECTED || !IsFakeClient(client))
	{
		return false;
	}

	if (requireAlive && !IsPlayerAlive(client))
	{
		return false;
	}

	if (GetEntProp(client, Prop_Send, "m_zombieClass") != ZC_BOOMER)
	{
		return false;
	}

	if (!g_bHasEliteApi || !EliteSI_IsElite(client))
	{
		return false;
	}

	return EliteSI_GetSubtype(client) == ELITE_SUBTYPE_BOOMER_FLASHBANG;
}

bool IsValidHumanSurvivor(int client)
{
	return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && GetClientTeam(client) == TEAM_SURVIVOR && IsPlayerAlive(client);
}

void RefreshEliteState()
{
	g_bHasEliteApi = (GetFeatureStatus(FeatureType_Native, "EliteSI_IsElite") == FeatureStatus_Available)
		&& (GetFeatureStatus(FeatureType_Native, "EliteSI_GetSubtype") == FeatureStatus_Available);
}
