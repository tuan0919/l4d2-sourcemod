/**
// ====================================================================================================
Change Log:
1.0.0 (15-02-2024)
    - Initial release.
// ====================================================================================================
*/

// ====================================================================================================
// Filenames
// ====================================================================================================

#define FILE_DATA "configs/night_vision.cfg"
#define FILE_TRANS "l4d2_night_vision.tuan.phrases"

// ====================================================================================================
// Plugin Info - define
// ====================================================================================================

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <colors>
#define PLUGIN_VERSION "1.0.0"
#define PLUGIN_DESCRIPTION "Night Vision for survivors"
#define IMPULS_FLASHLIGHT 100 //Flashlight

public Plugin myinfo = 
{
	name 			= "[L4D2] Night Vision",
	author 			= "Tuan",
	description 	= PLUGIN_DESCRIPTION,
	version 		=  PLUGIN_VERSION,
	url 			= "https://steamcommunity.com/id/Strikeraot/"
}

// ====================================================================================================
// Cvars
// ====================================================================================================


	// Currently None
	
	
// ====================================================================================================
// Structs, Methodmaps
// ====================================================================================================

enum struct Correction
{
	int id;
	char display_name[128];
	char raw_file[PLATFORM_MAX_PATH];
}

methodmap CorrectionList < ArrayList
{
	//constructor
	public CorrectionList(int size) {
		return view_as<CorrectionList>(new ArrayList(size));
	}
	
	public void GetDisplayName(int ccid, char[] displayName, int size)
	{
		int idx = this.FindValue(ccid);
		
		if(idx == -1)
			strcopy(displayName, size, "None");
		else
		{
			Correction cor;
			this.GetArray(idx, cor);
			strcopy(displayName, size, cor.display_name);
		}
	}
	
	public void GetRawFile(int ccid, char[] raw_file, int size)
	{
		int idx = this.FindValue(ccid);
		
		if(idx == -1)
			ThrowError("Can't find id \"%i\" in CorrectionList!", ccid);
		else
		{
			Correction cor;
			this.GetArray(idx, cor);
			strcopy(raw_file, size, cor.raw_file);
		}
	}
}

enum struct CorrectionSetting
{
	int intensity;
	int ccid;
	
	void Empty()
	{
		this.intensity = 1;
		this.ccid = 0;
	}
}

// ====================================================================================================
// Global Varriables
// ====================================================================================================
CorrectionList g_mCorrections;
CorrectionSetting gc_eSettings[MAXPLAYERS];
bool g_bLate;
Cookie g_hCookie;
int g_iEntRef[MAXPLAYERS] = {INVALID_ENT_REFERENCE, ...};
float g_fLastPress[MAXPLAYERS];
bool g_bEnabled[MAXPLAYERS];

// ====================================================================================================
// Settings Stuff
// ====================================================================================================
public void OnPluginStart() 
{
	g_hCookie = new Cookie("nv_cookie", "Settings for night vision.", CookieAccess_Private);
	g_mCorrections = new CorrectionList(sizeof(Correction));
	LoadPluginTranslations();
	LoadPluginConfigs();
	// Late loading o_o, bruh i hate solving these cases
	if (g_bLate) {
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i) || !AreClientCookiesCached(i))
				continue;
			OnClientCookiesCached(i);
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();

	if (test != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	g_bLate = late;
	return APLRes_Success;
}

void LoadPluginTranslations()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/%s.txt", FILE_TRANS);
	if (FileExists(sPath))
        LoadTranslations(FILE_TRANS);
	else
        SetFailState("Missing required translation file on \"translations/%s.txt\", please re-download.", FILE_TRANS);
}

public void OnConfigsExecuted()
{
	LoadPluginConfigs();
}

void LoadPluginConfigs()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), FILE_DATA);
	
	if(!FileExists(path))
		SetFailState("Can't find file \"%s\".", path);
	
	KeyValues kv = new KeyValues("NightVision");
	kv.ImportFromFile(path);
	
	kv.GotoFirstSubKey();
	// Reset ArrayList
	g_mCorrections.Clear();
	
	char buff[32];
	Correction correction;
	do
	{
		kv.GetSectionName(buff, sizeof(buff));
		
		correction.id = kv.GetNum("id", -1);
		if(correction.id == -1)
		{
			LogMessage("Invalid or missing id for \"%s\" section in night_vision.cfg, skipping...", buff);
			continue;
		}
		
		kv.GetString("display_name", correction.display_name, sizeof(Correction::display_name));
		if(correction.display_name[0] == '\0')
		{
			LogMessage("Invalid or missing display_name for \"%s\" section in night_vision.cfg, skipping...", buff);
			continue;
		}
		
		kv.GetString("raw_file", correction.raw_file, sizeof(correction.raw_file));
		if(correction.raw_file[0] == '\0' || !FileExists(correction.raw_file, true))
		{
			LogMessage("Invalid or missing raw_file for \"%s\" section in night_vision.cfg, skipping...", buff);
			continue;
		}		
		g_mCorrections.PushArray(correction);
		
	} while(kv.GotoNextKey());
	
	if(g_mCorrections.Length == 0)
		SetFailState("Invalid or empty \"%s\" found, please add some entries to it before you can use that plugin!", path);
	
	delete kv;
}

public void OnClientCookiesCached(int client)
{
	if(g_mCorrections.Length == 0 || IsFakeClient(client))
		return;
	
	char buff[32];
	g_hCookie.Get(client, buff, sizeof(buff));
	
	// if client's cookie is available, clear a slot for him
	if(buff[0] == '\0')
		gc_eSettings[client].Empty();
	else
	{
		char pts[2][16];
		ExplodeString(buff, ";", pts, sizeof(pts), sizeof(pts[]));
		//Get client's own setting here
		gc_eSettings[client].intensity = StringToInt(pts[0]);
		gc_eSettings[client].ccid = StringToInt(pts[1]);
		// if his setting is invalid for some reason, we set correction's id as the first correction in list
		if(g_mCorrections.FindValue(gc_eSettings[client].ccid) == -1)
			gc_eSettings[client].ccid = g_mCorrections.Get(0);
	}
}

void SaveSettings(int client)
{
	char buff[32];
	// Saving as this format: "intensity;id"
	Format(buff, sizeof(buff), "%i;%i", gc_eSettings[client].intensity, gc_eSettings[client].ccid);
	g_hCookie.Set(client, buff);
}

public void OnClientDisconnect(int client)
{
	// Clear this player's slot
	if(IsFakeClient(client))
		return;
	DeletePlayerCC(client);
	g_fLastPress[client] = 0.0;
	g_bEnabled[client] = false;
	gc_eSettings[client].Empty();
}
// ====================================================================================================
// Main Plugin Code start here...
// ====================================================================================================
public Action OnPlayerRunCmd(int client, int &buttons, int &impuls, float vel[3], float angles[3], int &weapon)
{
	if (impuls == IMPULS_FLASHLIGHT)
	{
		if (0 < client < MaxClients && IsPlayerAlive(client)) {
			float fCurrent = GetEngineTime();
			if (fCurrent - g_fLastPress[client] <= 0.3) {
				// Show menu
				OpenNightVisionSettingsMenu(client);
			}
			g_fLastPress[client] = fCurrent;
		}
	}
	return Plugin_Continue;
}

void OpenNightVisionSettingsMenu(int client)
{
	Menu menu = new Menu(NightVisionSettings_Menu, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	
	menu.SetTitle("%T\n ", "Settings Menu - Title", client);
	
	char buff[256];
	Format(buff, sizeof(buff), "%T\n", "Settings Menu - Toggle", client);
	menu.AddItem("toggle", buff);
	Format(buff, sizeof(buff), "%T\n  ", "Settings Menu - Select", client);
	menu.AddItem("select", buff);
	Format(buff, sizeof(buff), "%T\n ", "Settings Menu - Current", client, gc_eSettings[client].intensity);
	menu.AddItem("ccint", buff, ITEMDRAW_DISABLED);
	
	Format(buff, sizeof(buff), "%T", "Settings Menu - Intensity_Decrease", client);
	menu.AddItem("ccint_dec", buff);
	Format(buff, sizeof(buff), "%T", "Settings Menu - Intensity_Increase", client);
	menu.AddItem("ccint_inc", buff);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

public int NightVisionSettings_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DisplayItem:
		{
			char buff[16];
			menu.GetItem(param2, buff, sizeof(buff));
			
			if(StrEqual(buff, "ccint"))
			{
				char displ[256];
				char bar[][] = {
					"□□□□□□□□□□",
					"■□□□□□□□□□",
					"■■□□□□□□□□",
					"■■■□□□□□□□",
					"■■■■□□□□□□",
					"■■■■■□□□□□",
					"■■■■■■□□□□",
					"■■■■■■■□□□",
					"■■■■■■■■□□",
					"■■■■■■■■■□",
					"■■■■■■■■■■",
				};
				char name[64];
				g_mCorrections.GetDisplayName(gc_eSettings[param1].ccid, name, sizeof(name));
				Format(displ, sizeof(displ), "%T\n - Correction: %s %s\n - Intensity: %s\n ", "Settings Menu - Current", param1, 
					name, 
					g_bEnabled[param1] ? "[●]" : "[○]",
					bar[gc_eSettings[param1].intensity]);
				return RedrawMenuItem(displ);
			}
		}
		
		case MenuAction_Select:
		{
			char buff[128];
			menu.GetItem(param2, buff, sizeof(buff));
			
			if(StrEqual(buff, "select"))
			{
				Menu ccmenu = new Menu(CorrectionList_Menu, MENU_ACTIONS_DEFAULT | MenuAction_Display);
				
				g_mCorrections.GetDisplayName(gc_eSettings[param1].ccid, buff, sizeof(buff));
				ccmenu.SetTitle("%T\n%T\n ", "Color Corrections Menu - Title", param1, "Color Corrections Menu - Current", param1, buff);
				
				Correction correction;
				for(int i = 0; i < g_mCorrections.Length; i++)
				{
					g_mCorrections.GetArray(i, correction);
					IntToString(correction.id, buff, sizeof(buff));
					ccmenu.AddItem(buff, correction.display_name);
				}
				
				ccmenu.ExitBackButton = true;
				
				ccmenu.Display(param1, MENU_TIME_FOREVER);
				delete menu;
			}
			if (StrEqual(buff, "toggle"))
			{
				Toggle(param1);
				menu.Display(param1, MENU_TIME_FOREVER);
			}
			else if (StrEqual(buff, "ccint_inc") || StrEqual(buff, "ccint_dec"))
			{
				if(StrEqual(buff, "ccint_inc"))
					gc_eSettings[param1].intensity = Change(gc_eSettings[param1].intensity + 1, 0, 10);
				else if(StrEqual(buff, "ccint_dec"))
					gc_eSettings[param1].intensity = Change(gc_eSettings[param1].intensity - 1, 0, 10);
				
				UpdateInsentityChanges(param1);
				
				menu.Display(param1, MENU_TIME_FOREVER);
			}
		}
		
		case MenuAction_Cancel:
		{
			SaveSettings(param1);
		}
		
		case MenuAction_End:
		{
			if (param2 != MenuEnd_Selected)
				delete menu;
		}
	}
	return 0;
}

public int CorrectionList_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_Display:
		{
			char buff[128];
			g_mCorrections.GetDisplayName(gc_eSettings[param1].ccid, buff, sizeof(buff));
			menu.SetTitle("%T\n%T\n ", "Color Corrections Menu - Title", param1, "Color Corrections Menu - Current", param1, buff);
		}
		
		case MenuAction_Select:
		{
			char buff[PLATFORM_MAX_PATH];
			menu.GetItem(param2, buff, sizeof(buff));
			
			gc_eSettings[param1].ccid = StringToInt(buff);
			if(g_mCorrections.FindValue(gc_eSettings[param1].ccid) == -1)
				ThrowError("Invalid id \"%i\" found in g_mCorrections!", gc_eSettings[param1].ccid);
			
			if (g_bEnabled[param1]) {
				DeletePlayerCC(param1);
				g_mCorrections.GetRawFile(gc_eSettings[param1].ccid, buff, sizeof(buff));
				if(!CreatePlayerCC(param1, buff))
				{
					LogError("Can't create \"color_correction\" entity for %i (%N)", param1, param1);
					return 0;
				}
			}
			menu.Display(param1, MENU_TIME_FOREVER);
		}
		
		case MenuAction_Cancel:
		{
			SaveSettings(param1);
			if(param2 == MenuCancel_ExitBack)
				OpenNightVisionSettingsMenu(param1);
		}
		
		case MenuAction_End:
		{
			if (param2 != MenuEnd_Selected)
				delete menu;
		}
	}
	
	return 0;
}


public void Toggle(int client)
{
	//PrintToChatAll("In Toggle for id: %i, %N", client, client);
	if(client == 0) return;
	g_bEnabled[client] = !g_bEnabled[client];
	DeletePlayerCC(client);
	// player's correction has been enabled before disabling
	if (!g_bEnabled[client])  {
		//PrintToChatAll("Disabled");
	}
	else
	{
		char buff[PLATFORM_MAX_PATH];
		
		g_mCorrections.GetRawFile(gc_eSettings[client].ccid, buff, sizeof(buff));
		if(!CreatePlayerCC(client, buff)) {
			LogError("Can't create \"color_correction\" entity for %i (%N)", client, client);
			g_bEnabled[client] = false;
		}
		else {
			//PrintToChatAll("Enabled");
		}
	}
}

// ====================================================================================================
// Entity Stuff
// ====================================================================================================
void DeletePlayerCC(int client)
{
	int ent = EntRefToEntIndex(g_iEntRef[client]);
	if(ent != -1 && IsValidEntity(ent)) 
		RemoveEntity(ent);
	g_iEntRef[client] = INVALID_ENT_REFERENCE;
}

bool CreatePlayerCC(int client, const char[] raw_file)
{
	int ent = CreateEntityByName("color_correction");
	DispatchKeyValue(ent, "StartDisabled", "0");
	DispatchKeyValue(ent, "maxweight", "1.0");
	DispatchKeyValue(ent, "maxfalloff", "-1.0");
	DispatchKeyValue(ent, "minfalloff", "0.0");
	DispatchKeyValue(ent, "filename", raw_file);
	
	DispatchSpawn(ent);
	ActivateEntity(ent);
	
	SetEntPropFloat(ent, Prop_Send, "m_flCurWeight", 0.1 * gc_eSettings[client].intensity);
	SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_ALWAYS);
	if (!CheckIfEntityMax(EntIndexToEntRef(ent))) return false;
	SDKHook(ent, SDKHook_SetTransmit, OnHook_Transmit);
	g_iEntRef[client] = EntIndexToEntRef(ent);
	
	return true;
}

void UpdateInsentityChanges(int client)
{
	if(g_iEntRef[client] != INVALID_ENT_REFERENCE)
	{
		int ent = EntRefToEntIndex(g_iEntRef[client]);
		
		if(ent != -1)
			SetEdictFlags(ent, GetEdictFlags(ent) & ~FL_EDICT_ALWAYS & ~FL_EDICT_DONTSEND);
	}
}

public Action OnHook_Transmit(int entity, int client)
{
	SetEdictFlags(entity, GetEdictFlags(entity) & ~FL_EDICT_ALWAYS);
	
	// only show to client his correction
	if (EntRefToEntIndex(g_iEntRef[client]) != entity)
		return Plugin_Handled;
	else
	{
		SetEdictFlags(entity, GetEdictFlags(entity) | FL_EDICT_DONTSEND);
		SetEntPropFloat(entity, Prop_Send, "m_flCurWeight", 0.1 * gc_eSettings[client].intensity);
		return Plugin_Continue;
	}
}

// ====================================================================================================
// Stocks
// ====================================================================================================
bool CheckIfEntityMax(int entity)
{
	entity = EntRefToEntIndex(entity);
	if(entity == -1) return false;

	if(	entity > 2000)
	{
		AcceptEntityInput(entity, "Kill");
		return false;
	}
	return true;
}

int Change(int val, int min, int max)
{
	return (val < min) ? min : (max < val) ? max : val;
}