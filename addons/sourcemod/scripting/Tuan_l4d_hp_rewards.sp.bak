#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#pragma semicolon 1
#define PLUGIN_VERSION "2.12"
bool bSI;
bool bTank;
bool IsL4D2;
bool On = false;
Handle hHRFirst;
Handle hHRSecond;
Handle hHRThird;
Handle hHRMax;
Handle hHRTank;
Handle hHRWitch;
Handle hHRSI;
int iFirst;
int iSecond;
int iThird;
int iMax;
int zClassTank;
float g_fDecayDecay;


enum {
	ZOMBIECLASS_SMOKER = 1,
	ZOMBIECLASS_BOOMER = 2,
	ZOMBIECLASS_HUNTER = 3,
	ZOMBIECLASS_SPITTER = 4,
	ZOMBIECLASS_JOCKEY = 5,
	ZOMBIECLASS_CHARGER = 6,
	ZOMBIECLASS_TANK = 8,
};

char g_ZombiesIcons[9][32] = {
	"Unknown",
	"Stat_vs_Most_Smoker_Pulls",
	"Stat_vs_Most_Vomit_Hit",
	"Stat_vs_Most_Hunter_Pounces",
	"Stat_vs_Most_Spit_Dmg",
	"Stat_vs_Most_Jockey_Rides",
	"Stat_vs_Most_Damage_As_Charger",
	"Unknown",
	"Stat_vs_Most_Damage_As_Tank"
};

char g_ZombiesNames[9][32] = {
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

public Plugin myinfo =
{
	name = "[L4D & L4D2] HP Rewards",
	author = "cravenge",
	description = "Grants Full Health After Killing Tanks And Witches, Additional Health For Killing SI.",
	version = PLUGIN_VERSION,
	url = ""
}

public void OnPluginStart()
{
	char game[12];
	GetGameFolderName(game, sizeof(game));
	if(StrEqual(game, "left4dead2"))
	{
		IsL4D2 = true;
		zClassTank = 8;
	}

	else
	{
		IsL4D2 = false;
		zClassTank = 5;
	}
	
	CreateConVar("l4d_hp_rewards_version", PLUGIN_VERSION, "HP Rewards Version", FCVAR_SPONLY|FCVAR_DONTRECORD);
	hHRFirst = CreateConVar("l4d_hp_rewards_first", "2", "Rewarded HP For Killing Boomers And Spitters");
	hHRSecond = CreateConVar("l4d_hp_rewards_second", "3", "Rewarded HP For Killing Smokers And Jockeys");
	hHRThird = CreateConVar("l4d_hp_rewards_third", "5", "Rewarded HP For Killing Hunters And Chargers");
	hHRMax = CreateConVar("l4d_hp_rewards_max", "200", "Max HP Limit");
	hHRTank = CreateConVar("l4d_hp_rewards_tank", "1", "Enable/Disable Tank Rewards");
	hHRWitch = CreateConVar("l4d_hp_rewards_witch", "1", "Enable/Disable Witch Rewards");
	hHRSI = CreateConVar("l4d_hp_rewards_si", "1", "Enable/Disable Special Infected Rewards");
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_end", OnRewardsReset);
	HookEvent("finale_win", OnRewardsReset);
	HookEvent("mission_lost", OnRewardsReset);
	HookEvent("map_transition", OnRewardsReset);
	HookEvent("player_death", OnPlayerDeath);
	iSecond = GetConVarInt(hHRSecond);
	iThird = GetConVarInt(hHRThird);
	iMax = GetConVarInt(hHRMax);
	bTank = GetConVarBool(hHRTank);
	bSI = GetConVarBool(hHRSI);
	HookConVarChange(hHRFirst, HRConfigsChanged);
	HookConVarChange(hHRSecond, HRConfigsChanged);
	HookConVarChange(hHRThird, HRConfigsChanged);
	HookConVarChange(hHRMax, HRConfigsChanged);
	HookConVarChange(hHRTank, HRConfigsChanged);
	HookConVarChange(hHRWitch, HRConfigsChanged);
	HookConVarChange(hHRSI, HRConfigsChanged);
	AutoExecConfig(true, "l4d_hp_rewards");
	g_fDecayDecay = FindConVar("pain_pills_decay_rate").FloatValue;
}

public void HRConfigsChanged(Handle convar, const char[] oValue, const char[] nValue)
{
	iFirst = GetConVarInt(hHRFirst);
	iSecond = GetConVarInt(hHRSecond);
	iThird = GetConVarInt(hHRThird);
	iMax = GetConVarInt(hHRMax);
	bTank = GetConVarBool(hHRTank);
	bSI = GetConVarBool(hHRSI);
}

public void OnMapStart()
{
	On = true;
}

public void OnMapEnd()
{
	On = false;
}

public void OnRoundStart(Handle event, const char[] name, bool dontBroadcast)
{
	if(On)
	{
		return;
	}

	On = true;
}

void OnRewardsReset(Handle event, const char[] name, bool dontBroadcast)
{
	if(!On)
	{
		return;
	}

	On = false;
}

void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if(On)
	{
		bool headshot = GetEventBool(event, "HeadShot");
		int client = GetClientOfUserId(GetEventInt(event, "userid"));
		if(client <= 0 || client > MaxClients || !IsClientInGame(client) || GetClientTeam(client) != 3)
		{
			return;
		}

		if(bTank)
		{
			int tClass = GetEntProp(client, Prop_Send, "m_zombieClass");
			char selfText[255];
			char iHintIcon[255];
			if(tClass == zClassTank)
			{
				for (int attacker=1; attacker<=MaxClients; attacker++)
				{
					if(IsClientInGame(attacker) && GetClientTeam(attacker) == 2 && IsPlayerAlive(attacker) && !IsPlayerIncapped(attacker))
					{
						int added = GiveBonus(attacker, 20);
						Format(selfText, sizeof(selfText), "Tank died, bonus %i [HP] for you", added);

						Format(iHintIcon, sizeof(iHintIcon), g_ZombiesIcons[tClass]);
						DisplayInstructorHint(attacker, selfText, iHintIcon);
					}
				}
			}
		}
		
		if(bSI)
		{
			int shooter = GetClientOfUserId(GetEventInt(event, "attacker"));
			if(shooter <= 0 || shooter > MaxClients || !IsClientInGame(shooter) || GetClientTeam(shooter) != 2 || !IsPlayerAlive(shooter))
			{
				return;
			}

			int aHealth;
			int cClass = GetEntProp(client, Prop_Send, "m_zombieClass");
			
			if(cClass == ZOMBIECLASS_BOOMER || (IsL4D2 && cClass == ZOMBIECLASS_SPITTER)) {
				aHealth = iFirst;
			}

			else if(cClass == ZOMBIECLASS_JOCKEY || (IsL4D2 && cClass == ZOMBIECLASS_SMOKER)) {
				aHealth = iSecond;
			}
			
			else if(cClass == ZOMBIECLASS_HUNTER || (IsL4D2 && cClass == ZOMBIECLASS_CHARGER)) {
				aHealth = iThird;
			}
			
			char selfText[255];
			char iHintIcon[255];
			if (headshot) aHealth = 2 * aHealth;
			int added = GiveBonus(shooter, aHealth);
			if(cClass != zClassTank)
			{
				Format(selfText, sizeof(selfText), "%s %s bonus %i [HP] %s", (headshot ? "Headshot" : "Killed"), g_ZombiesNames[cClass], 
					added, (IsPlayerIncapped(shooter) ? "while incapacitated": ""));

				Format(iHintIcon, sizeof(iHintIcon), g_ZombiesIcons[cClass]);
				DisplayInstructorHint(shooter, selfText, iHintIcon);
			}
		}
	}
}

public bool IsPlayerIncapped(int client)
{
	if(GetEntProp(client, Prop_Send, "m_isIncapacitated", 1))
	{
		return true;
	}

	else
	{
		return false;
	}
}

int GiveBonus(int client, int aHealth) {
	int sHealth = GetClientHealth(client); // source health
	float tHealth = GetTempHealth(client) < 0 ? 0.0 : GetTempHealth(client); // get temp health
	// incapacitated ?
	if (IsPlayerIncapped(client)) {
		// 10 times multiplier
		aHealth = aHealth * 10;
		SetEntProp(client, Prop_Send, "m_iHealth", sHealth + aHealth, 1);
		return aHealth;
	}
	if ((sHealth + aHealth) >= iMax) {
		SetEntProp(client, Prop_Send, "m_iHealth", sHealth, 1);
		// re-calculate how much buffer health need to add for reaching iMax value
		int calcHealth = iMax - sHealth;
		SetTempHealth(client, float(calcHealth));
		return calcHealth;
	} else {
		SetEntProp(client, Prop_Send, "m_iHealth", sHealth, 1);
		SetTempHealth(client, tHealth + aHealth);
		return aHealth;
	}
}

stock void DisplayInstructorHint(int target, char text[255], char icon[255])
{
	int entity = CreateEntityByName("env_instructor_hint");
	if (entity <= 0)
		return;
	char sBuffer[32];
	FormatEx(sBuffer, sizeof(sBuffer), "hintRewardHPTo%d", target);
	// Target
	DispatchKeyValue(target, "targetname", sBuffer);
	DispatchKeyValue(entity, "hint_target", sBuffer);
	// Static
	DispatchKeyValue(entity, "hint_static", "false");
	// Timeout
	DispatchKeyValue(entity, "hint_timeout", "5.0");
	DestroyEntity(entity, 5.0);
	// Height
	FormatEx(sBuffer, sizeof(sBuffer), "%d", 0.1);
	DispatchKeyValue(entity, "hint_icon_offset", sBuffer);
	// Range
	DispatchKeyValue(entity, "hint_range", "0.1");
	// Show off screen
	DispatchKeyValue(entity, "hint_nooffscreen", "true");
	// Icons
	DispatchKeyValue(entity, "hint_icon_onscreen", icon);
	DispatchKeyValue(entity, "hint_icon_offscreen", icon);
	// Show text behind walls
	DispatchKeyValue(entity, "hint_forcecaption", "true");
	// Text color
	FormatEx(sBuffer, sizeof(sBuffer), "%d %d %d", 255, 255, 255);
	DispatchKeyValue(entity, "hint_allow_nodraw_target", "1");
	DispatchKeyValue(entity, "hint_instance_type", "0");
	DispatchKeyValue(entity, "hint_color", sBuffer);
	// Text
	ReplaceString(text, sizeof(text), "\n", " ");
	DispatchKeyValue(entity, "hint_caption", text);
	DispatchSpawn(entity);
	AcceptEntityInput(entity, "ShowHint", target);
}

stock void DestroyEntity(int entity, float time = 0.0)
{
	if (time == 0.0)
	{
		if (IsValidEntity(entity))
		{
			char edictname[32];
			GetEdictClassname(entity, edictname, 32);

			if (!StrEqual(edictname, "player"))
				AcceptEntityInput(entity, "kill");
		}
	}
	else
	{
		CreateTimer(time, DestroyEntityOnTimer, EntIndexToEntRef(entity), TIMER_FLAG_NO_MAPCHANGE);
	}
}

Action DestroyEntityOnTimer(Handle timer, any entityRef)
{
	int entity = EntRefToEntIndex(entityRef);
	if (entity != INVALID_ENT_REFERENCE)
	{
		DestroyEntity(entity);
	}
	return (Plugin_Stop);
}

float GetTempHealth(int client)
{
	float fHealth = GetEntPropFloat(client, Prop_Send, "m_healthBuffer");
	fHealth -= (GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * g_fDecayDecay;
	return fHealth < 0.0 ? 0.0 : fHealth;
}

void SetTempHealth(int client, float fHealth)
{
	SetEntPropFloat(client, Prop_Send, "m_healthBuffer", fHealth < 0.0 ? 0.0 : fHealth );
	SetEntPropFloat(client, Prop_Send, "m_healthBufferTime", GetGameTime());
}