/**
// ====================================================================================================
Change Log:
1.0.5 (14-02-2024)
	- Added new feature for survivors customizing their marker's color (and saving cookies).
1.0.4 (04-02-2024)
	- Fixed odly behavior problem for sprite when parent moving
	- Add feature showing message about item name and translations file
	- TODO:
		+ Feature letting survivors customized their marker's color (and saving cookies).
1.0.3 (04-02-2024)
	- Added Cvars
	- Sprite now static staying at their spawn place instead of moving with their parent to prevent some odd behavior
	- TODO:
		+ Feature letting survivors customized their marker's color
		+ Attemp on feature letting other survivors to turn off marker on their side.
1.0.2 (03-02-2024)
    - Removed instructor hint
	- Now using sprite and TE_SetupBeamPoints for markers
	- TODO:
		+ Adding cvar
		+ Feature letting other survivors to turn off marker on their side (need more test)
1.0.1 (02-02-2024)
    - Rewrite entire plugin, use enum struct to store marker's information instead of arrays
	- Added feature unmark item
	- Plugin not required L4DHookDirect anymore
1.0.0 (31-01-2024)
    - Initial release.
		+ Thanks Mart for his https://forums.alliedmods.net/showthread.php?t=331347 borrowed a lot idea for sprites and about organizing the project
		+ Thanks BHaType for his https://forums.alliedmods.net/showpost.php?p=2753773&postcount=2 learnt how to use SDKCall. Which also gave me idea about using enum struct
		+ Thanks Harry for his https://github.com/fbef0102/L4D2-Plugins/tree/master/l4d2_item_hint learnt a lot about entites from reading this plugin

// ====================================================================================================
*/

// ====================================================================================================
// Filenames
// ====================================================================================================

#define CONFIG_FILENAME  "Tuan_l4d2_item_marker"
#define TRANSLATION_FILENAME "l4d2_item_marker.tuan.phrases"
#define CONFIG_FILE "configs/item_markers.cfg"

// ====================================================================================================
// Plugin Info - define
// ====================================================================================================

#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <colors>
#include <clientprefs>
#define PLUGIN_VERSION "1.0.5"
#define GAMEDATA	 "Tuan_l4d2_item_marker"
#define MAXENTITIES 2048
#define DIRECTION_OUT 1
#define DIRECTION_IN 2
#define PLUGIN_DESCRIPTION "Allow survivor to mark an item"

// ====================================================================================================
// Cvars
// ====================================================================================================

ConVar g_hCvar_Alpha;
ConVar g_hCvar_ModelBeam;
ConVar g_hCvar_ModelSprite;
ConVar g_hCvar_MarkDuration;
ConVar g_hCvar_BeamStartRadius;
ConVar g_hCvar_BeamEndRadius;
ConVar g_hCvar_BeamDuration;
ConVar g_hCvar_SpriteZAxis;
ConVar g_hCvar_SpriteSpeed;
ConVar g_hCvar_SpriteMoveRange;
ConVar g_hCvar_UseCooldown;
ConVar g_hCvar_ReadySound;
ConVar g_hCvar_UseSound;

// ====================================================================================================
// Global Varriables
// ====================================================================================================
int g_iCvar_Alpha;
char g_sCvar_ModelSprite[64];
char g_sCvar_ModelBeam[64];
float g_fCvar_MarkDuration;
float g_fCvar_BeamStartRadius;
float g_fCvar_BeamEndRadius;
float g_fCvar_BeamDuration;
int g_iCvar_ModelBeamIndex;
float g_fCvar_SpriteZAxis;
float g_fCvar_SpriteZSpeed;
float g_fCvar_SpriteMoveRange;
float g_fCvar_UseCooldown;
char g_sCvar_ReadySound[64];
char g_sCvar_UseSound[64];

StringMap g_smModelToName;
Handle g_hSDK_UseEntity;
Marker g_eMarker[MAXENTITIES + 1];
ColorList gCColors;
Handle g_hMarkerTimer[MAXENTITIES + 1] = {null}; // This timer will remove enties of markers in case they cannot remove themself for some reason
float gc_fLastTimeUse[MAXPLAYERS];
MarkerColor gc_eMarkerColor[MAXPLAYERS];
bool bLate;
Cookie gSettingsCookie;

public Plugin myinfo = 
{
	name 			= "[L4D2] Item marker",
	author 			= "Tuan",
	description 	= PLUGIN_DESCRIPTION,
	version 		=  PLUGIN_VERSION,
	url 			= ""
}

enum struct Marker
{
	bool created;
	int client;
	int iTargetRef;
	int iHintRef;
	int iGlowRef;
	int iSpriteRef;
	int iBeamDirection;
	int iSpriteDirection;
	char sItemName[64];
	Handle hGlowTimer;
	Handle hBeamTimer;
	Handle hSpriteTimer;
	
	void init(int client, int iTarget, int iGlow, int iSprite, Handle hBeamTimer, Handle hSpriteTimer, char sItemName[64]) {
		this.created = true;
		this.client = client;
		this.iTargetRef = EntIndexToEntRef(iTarget);
		this.iGlowRef = EntIndexToEntRef(iGlow);
		this.iSpriteRef = EntIndexToEntRef(iSprite);
		this.hBeamTimer = hBeamTimer;
		this.hSpriteTimer = hSpriteTimer;
		this.sItemName = sItemName;
	}
	
	void clear() {
		this.created = false;
		this.client = 0;
		this.iTargetRef = 0;
		this.iGlowRef = 0;
		this.iSpriteRef = 0;
		this.iBeamDirection = 0;
		this.iSpriteDirection = 0;
		this.hGlowTimer = null;
		this.hBeamTimer = null;
		this.hSpriteTimer = null;
	}
}

enum struct MarkerColor
{
	int id;
	int array[3];
	char color[16];
	char color_name[64];
	
	void Empty() {
		this.id = 0;
		this.array = {0, 0, 0};
	}
}

methodmap ColorList < ArrayList
{
	public ColorList(int size)
	{
		return view_as<ColorList>(new ArrayList(size));
	}

	public void GetDisplayName(int id, char[] displayName, int size)
	{
		int idx = this.FindValue(id);
		
		if(idx == -1)
			strcopy(displayName, size, "None");
		else
		{
			MarkerColor markerColor;
			this.GetArray(idx, markerColor);
			strcopy(displayName, size, markerColor.color_name);
		}
	}
	
	public char[] GetColorStr(int id)
	{
		char buff[64];
		int idx = this.FindValue(id);
		
		if(idx == -1) {
			Format(buff, sizeof(buff), "255 255 255");
			return buff;
		}
		else
		{
			MarkerColor markerColor;
			this.GetArray(idx, markerColor);
			strcopy(buff, sizeof(buff), markerColor.color);
			return buff;
		}
	}
	
	public int[] GetColor(int id)
	{
		int color[4];
		int idx = this.FindValue(id);
		if(idx == -1)
			return color;
		else
		{
			MarkerColor markerColor;
			this.GetArray(idx, markerColor);
			color[0] = markerColor.array[0];
			color[1] = markerColor.array[1];
			color[2] = markerColor.array[2];
			color[3] = g_iCvar_Alpha;
			return color;
		}
	}
}

// ====================================================================================================
// Plugin start
// ====================================================================================================

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion test = GetEngineVersion();

	if (test != Engine_Left4Dead2)
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_ping", SM_PingMenu, "Open settings menu for markers.");
	CreateConVar("l4d2_item_marker_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY | FCVAR_DONTRECORD | FCVAR_SPONLY);
 	g_hCvar_Alpha = CreateConVar("l4d2_item_marker_alpha", "255", "Marker's alpha transparency.\nNote: Some models don't allow to change the alpha.\n0 = Invisible, 255 = Fully Visible", FCVAR_NOTIFY, true, 0.0, true, 255.0);
	g_hCvar_ModelBeam = CreateConVar("l4d2_item_marker_beam_model", "vgui/white_additive.vmt", "Model name of beam, some model name is \"wall-through\", this is depends on which *.vmt file you choose", FCVAR_NOTIFY);
	g_hCvar_ModelSprite = CreateConVar("l4d2_item_marker_sprite_model", "vgui/icon_arrow_down.vmt", "Model name of sprite, some model name is \"wall-through\", this is depends on which *.vmt file you choose", FCVAR_NOTIFY);
	g_hCvar_MarkDuration = CreateConVar("l4d2_item_marker_duration", "15.0", "Duration of the marker (in seconds)", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_BeamStartRadius = CreateConVar("l4d2_item_marker_beam_start_radius", "75.0", "The start radius of the beam", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_BeamEndRadius = CreateConVar("l4d2_item_marker_beam_end_radius", "100.0", "The end radius of the beam", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_BeamDuration = CreateConVar("l4d2_item_marker_beam_duration", "0.5", "This value determine how long the beam will reach its max radius from min radius (in seconds)", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_SpriteZAxis = CreateConVar("l4d2_item_marker_sprite_z_axis", "20.0", "Additional Z axis to the sprite.", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_SpriteSpeed = CreateConVar("l4d2_item_marker_sprite_speed", "1.0", "How fast the sprite will move. (determine which value use for changing sprite's z axis)", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_SpriteMoveRange = CreateConVar("l4d2_item_marker_sprite_move_range", "6.0", "The moving range for the sprite", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_UseCooldown = CreateConVar("l4d2_item_marker_use_cooldown", "5.0", "Cooldown to use markers", FCVAR_NOTIFY, true, 0.0);
	g_hCvar_ReadySound = CreateConVar("l4d2_item_marker_ready_sound", "ui/alert_clink.wav", "Sound when a marker ready to use", FCVAR_NOTIFY);
	g_hCvar_UseSound = CreateConVar("l4d2_item_marker_use_sound", "buttons/blip1.wav", "Sound when use marker", FCVAR_NOTIFY);
	
	//Hook Cvar change
	g_hCvar_Alpha.AddChangeHook(Event_ConVarChanged);
	g_hCvar_ModelBeam.AddChangeHook(Event_ConVarChanged);
	g_hCvar_ModelSprite.AddChangeHook(Event_ConVarChanged);
	g_hCvar_MarkDuration.AddChangeHook(Event_ConVarChanged);
	g_hCvar_BeamStartRadius.AddChangeHook(Event_ConVarChanged);
	g_hCvar_BeamEndRadius.AddChangeHook(Event_ConVarChanged);
	g_hCvar_BeamDuration.AddChangeHook(Event_ConVarChanged);
	g_hCvar_SpriteZAxis.AddChangeHook(Event_ConVarChanged);
	g_hCvar_SpriteSpeed.AddChangeHook(Event_ConVarChanged);
	g_hCvar_SpriteMoveRange.AddChangeHook(Event_ConVarChanged);
	g_hCvar_UseCooldown.AddChangeHook(Event_ConVarChanged);
	g_hCvar_ReadySound.AddChangeHook(Event_ConVarChanged);
	g_hCvar_UseSound.AddChangeHook(Event_ConVarChanged);
	
	// Load plugin configs from .cfg
    AutoExecConfig(true, CONFIG_FILENAME);
	
	// Chuẩn bị gamedata, vì cần sử dụng SDKCall CTerrorPlayer::FindUseEntity(float,float,float,bool *,bool)
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), "gamedata/%s.txt", GAMEDATA);
	if( FileExists(sPath) == false ) SetFailState("\n==========\nMissing required file: \"%s\"\n==========", sPath);

	Handle hGameData = LoadGameConfigFile(GAMEDATA);
	if( hGameData == null ) SetFailState("Failed to load \"%s.txt\" gamedata.", GAMEDATA);
	StartPrepSDKCall(SDKCall_Player);
	if( PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CTerrorPlayer::FindUseEntity") == false )
	{
		SetFailState("Failed to find signature: \"CTerrorPlayer::FindUseEntity\"");
	} 
	else {
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
		PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
		PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
		g_hSDK_UseEntity = EndPrepSDKCall();
		if( g_hSDK_UseEntity == null )
			SetFailState("Failed to create SDKCall: \"CTerrorPlayer::FindUseEntity\"");
	}
	delete hGameData;
	
	// Start Plugin
	CreateStringMap();
	AddCommandListener(Vocalize_Listener, "vocalize");
	if (bLate) {
		LateLoad();
	}
	
	gCColors = new ColorList(sizeof(MarkerColor));
	LoadPluginTranslations();
	ParseConfigFile();
	gSettingsCookie = new Cookie("item_marker_settings", "Settings for item marker.", CookieAccess_Private);
}

public void OnClientCookiesCached(int client)
{
	if(gCColors.Length == 0 || IsFakeClient(client))
		return;
	
	char buff[32];
	gSettingsCookie.Get(client, buff, sizeof(buff));
	
	if(buff[0] == '\0')
		gc_eMarkerColor[client].Empty();
	else
	{
		gc_eMarkerColor[client].id = StringToInt(buff);
		if(gCColors.FindValue(gc_eMarkerColor[client].id) == -1)
			gc_eMarkerColor[client].id = gCColors.Get(0);
	}
}

void LoadPluginTranslations()
{
    char path[256];
	BuildPath(Path_SM, path, sizeof(path), "translations/%s.txt", TRANSLATION_FILENAME);
    if (FileExists(path))
        LoadTranslations(TRANSLATION_FILENAME);
    else
        SetFailState("Missing required translation file on \"translations/%s.txt\", please re-download.", TRANSLATION_FILENAME);
}

void ParseConfigFile()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), CONFIG_FILE);
	if(!FileExists(path))
		SetFailState("Can't find file \"%s\".", path);
	gCColors.Clear();
	KeyValues kv = new KeyValues("Markers");
	kv.ImportFromFile(path);
	
	kv.GotoFirstSubKey();
	char buff[32];
	MarkerColor mColor;
	do
	{
		int color[3];
		kv.GetSectionName(buff, sizeof(buff));
		
		mColor.id = kv.GetNum("id", -1);
		if (mColor.id == -1) {
			LogMessage("Invalid or missing id for \"%s\" section in item_markers.cfg, skipping...", buff);
			continue;
		}
		kv.GetString("color", mColor.color, sizeof(MarkerColor::color));
		GetArrayColor(mColor.color, color);
		mColor.array = color;
		kv.GetString("display_name", mColor.color_name, sizeof(MarkerColor::color_name));
		if(mColor.color_name[0] == '\0')
		{
			LogMessage("Invalid or missing display_name for \"%s\" section in item_markers.cfg, skipping...", buff);
			continue;
		}
		gCColors.PushArray(mColor);
	} while(kv.GotoNextKey());
	if(gCColors.Length == 0)
		SetFailState("Invalid or empty \"%s\" found, please add some entries to it before you can use that plugin!", path);
	
	delete kv;
}

void SaveSettings(int client)
{
	char buff[32];
	Format(buff, sizeof(buff), "%i", gc_eMarkerColor[client].id);
	gSettingsCookie.Set(client, buff);
}

void LateLoad()
{
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) OnClientPutInServer(i);
	}
}

public Action SM_PingMenu(int client, int args)
{
	if(client == 0)
		return Plugin_Handled;
	
	OpenSettingsMenu(client);
	
	return Plugin_Handled;
}

void OpenSettingsMenu(int client)
{
	Menu menu = new Menu(PingSettings_Menu, MENU_ACTIONS_DEFAULT | MenuAction_DisplayItem);
	
	menu.SetTitle("%T:\n ", "Marker Setting Menu - Title", client);
	menu.AddItem("current", "", ITEMDRAW_DISABLED);
	char buff[256];
	Format(buff, sizeof(buff), "Change my marker color", client);
	menu.AddItem("change", buff);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PingSettings_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_DisplayItem:
		{
			char buff[16];
			menu.GetItem(param2, buff, sizeof(buff));
			if(StrEqual(buff, "current"))
			{
				char displ[128];
				gCColors.GetDisplayName(gc_eMarkerColor[param1].id, displ, sizeof(displ));
				Format(displ, sizeof(displ), "%T\n", "Color List Menu - Current", param1, displ);
				return RedrawMenuItem(displ);
			}
		}
		case MenuAction_Select:
		{
			char buff[128];
			menu.GetItem(param2, buff, sizeof(buff));
			if (StrEqual(buff, "change"))
			{
				Menu ccmenu = new Menu(CCColors_Menu, MENU_ACTIONS_DEFAULT | MenuAction_Display);
				gCColors.GetDisplayName(gc_eMarkerColor[param1].id, buff, sizeof(buff));
				ccmenu.SetTitle("%T\n%T\n", "Color List Menu - Title", param1, "Color List Menu - Current", param1, buff);
				
				MarkerColor mColor;
				for (int i = 0; i < gCColors.Length; i++) {
					gCColors.GetArray(i, mColor);
					IntToString(mColor.id, buff, sizeof(buff));
					ccmenu.AddItem(buff, mColor.color_name);
				}
				ccmenu.ExitBackButton = true;
				
				ccmenu.Display(param1, MENU_TIME_FOREVER);
				delete menu;
			}
		}
		case MenuAction_End:
		{
			if (param1 != MenuEnd_Selected)
				delete menu;
		}
	}
	
	return 0;
}

public int CCColors_Menu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action) {
		case MenuAction_Display:
		{
			char buff[128];
			gCColors.GetDisplayName(gc_eMarkerColor[param1].id, buff, sizeof(buff));
			menu.SetTitle("%T\n%T\n ", "Color List Menu - Title", param1, "Color List Menu - Current", param1, buff);
		}
		case MenuAction_Select:
		{
			char buff[PLATFORM_MAX_PATH];
			menu.GetItem(param2, buff, sizeof(buff));
			gc_eMarkerColor[param1].id = StringToInt(buff);
			if(gCColors.FindValue(gc_eMarkerColor[param1].id) == -1)
				ThrowError("Invalid id \"%i\" found in gCColors!", gc_eMarkerColor[param1].id);
			delete menu;
			OpenSettingsMenu(param1);
		}
		case MenuAction_Cancel:
		{
			SaveSettings(param1);
			if(param2 == MenuCancel_ExitBack)
				OpenSettingsMenu(param1);
		}
		case MenuAction_End:
		{
			if (param1 != MenuEnd_Selected)
				delete menu;
		}
	}
	return 0;
}

// ====================================================================================================
// Cvar section
// ====================================================================================================

void Event_ConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    GetCvars();
}

void GetCvars()
{
	g_iCvar_Alpha = g_hCvar_Alpha.IntValue;
	g_hCvar_ModelBeam.GetString(g_sCvar_ModelBeam, sizeof(g_sCvar_ModelBeam));
	TrimString(g_sCvar_ModelBeam);
		g_iCvar_ModelBeamIndex = PrecacheModel(g_sCvar_ModelBeam, true);
	g_hCvar_ModelSprite.GetString(g_sCvar_ModelSprite, sizeof(g_sCvar_ModelSprite));
	TrimString(g_sCvar_ModelSprite);
		PrecacheModel(g_sCvar_ModelSprite, true);
	g_fCvar_MarkDuration = g_hCvar_MarkDuration.FloatValue;
	g_fCvar_BeamStartRadius = g_hCvar_BeamStartRadius.FloatValue;
	g_fCvar_BeamEndRadius = g_hCvar_BeamEndRadius.FloatValue;
	g_fCvar_BeamDuration = g_hCvar_BeamDuration.FloatValue;
	g_fCvar_SpriteZAxis = g_hCvar_SpriteZAxis.FloatValue;
	g_fCvar_SpriteZSpeed = g_hCvar_SpriteSpeed.FloatValue;
	g_fCvar_SpriteMoveRange = g_hCvar_SpriteMoveRange.FloatValue;
	g_fCvar_UseCooldown = g_hCvar_UseCooldown.FloatValue;
	g_hCvar_UseSound.GetString(g_sCvar_UseSound, sizeof(g_sCvar_UseSound));
		PrecacheSound(g_sCvar_UseSound, true);
	g_hCvar_ReadySound.GetString(g_sCvar_ReadySound, sizeof(g_sCvar_ReadySound));
		PrecacheSound(g_sCvar_ReadySound, true);
}

public void OnConfigsExecuted()
{
    GetCvars();
    LateLoad();
}

public void OnClientDisconnect(int client)
{
    gc_fLastTimeUse[client] = 0.0;
}

public void OnPluginEnd()
{
    int entity;
    char targetname[17];

    entity = INVALID_ENT_REFERENCE;
    while ((entity = FindEntityByClassname(entity, "info_target")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
        if (StrEqual(targetname, "l4d2_item_marker"))
            AcceptEntityInput(entity, "Kill");
    }

    entity = INVALID_ENT_REFERENCE;
    while ((entity = FindEntityByClassname(entity, "env_sprite")) != INVALID_ENT_REFERENCE)
    {
        GetEntPropString(entity, Prop_Data, "m_iName", targetname, sizeof(targetname));
        if (StrEqual(targetname, "l4d2_item_marker"))
            AcceptEntityInput(entity, "Kill");
    }
}

// ====================================================================================================
// StringMap section
// ====================================================================================================

void CreateStringMap()
{
	g_smModelToName = new StringMap();
	// Case-sensitive
	g_smModelToName.SetString("models/w_models/weapons/w_eq_medkit.mdl", "First aid kit");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_defibrillator.mdl", "Defibrillator");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_painpills.mdl", "Pain pills");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_adrenaline.mdl", "Adrenaline");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_bile_flask.mdl", "Bile Bomb");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_molotov.mdl", "Molotov");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_pipebomb.mdl", "Pipe bomb");
	g_smModelToName.SetString("models/w_models/weapons/w_laser_sights.mdl", "Laser Sight");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_incendiary_ammopack.mdl", "Incendiary UpgradePack");
	g_smModelToName.SetString("models/w_models/weapons/w_eq_explosive_ammopack.mdl", "Explosive UpgradePack");
	g_smModelToName.SetString("models/props/terror/ammo_stack.mdl", "Ammo");
	g_smModelToName.SetString("models/props_unique/spawn_apartment/coffeeammo.mdl", "Ammo");
	g_smModelToName.SetString("models/props/de_prodigy/ammo_can_02.mdl", "Ammo");
	g_smModelToName.SetString("models/weapons/melee/w_chainsaw.mdl", "Chainsaw");
	g_smModelToName.SetString("models/w_models/weapons/w_pistol_b.mdl", "Pistol");
	g_smModelToName.SetString("models/w_models/weapons/w_pistol_a.mdl", "Pistol");
	g_smModelToName.SetString("models/w_models/weapons/w_desert_eagle.mdl", "Magnum");
	g_smModelToName.SetString("models/w_models/weapons/w_shotgun.mdl", "Pump Shotgun");
	g_smModelToName.SetString("models/w_models/weapons/w_pumpshotgun_a.mdl", "Shotgun Chrome");
	g_smModelToName.SetString("models/w_models/weapons/w_smg_uzi.mdl", "Uzi");
	g_smModelToName.SetString("models/w_models/weapons/w_smg_a.mdl", "Silenced Smg");
	g_smModelToName.SetString("models/w_models/weapons/w_smg_mp5.mdl", "MP5");
	g_smModelToName.SetString("models/w_models/weapons/w_rifle_m16a2.mdl", "Rifle");
	g_smModelToName.SetString("models/w_models/weapons/w_rifle_sg552.mdl", "SG552");
	g_smModelToName.SetString("models/w_models/weapons/w_rifle_ak47.mdl", "AK47");
	g_smModelToName.SetString("models/w_models/weapons/w_desert_rifle.mdl", "Desert Rifle");
	g_smModelToName.SetString("models/w_models/weapons/w_shotgun_spas.mdl", "Shotgun Spas");
	g_smModelToName.SetString("models/w_models/weapons/w_autoshot_m4super.mdl", "Auto Shotgun");
	g_smModelToName.SetString("models/w_models/weapons/w_sniper_mini14.mdl", "Hunting Rifle");
	g_smModelToName.SetString("models/w_models/weapons/w_sniper_military.mdl", "Military Sniper");
	g_smModelToName.SetString("models/w_models/weapons/w_sniper_scout.mdl", "Scout");
	g_smModelToName.SetString("models/w_models/weapons/w_sniper_awp.mdl", "AWP");
	g_smModelToName.SetString("models/w_models/weapons/w_grenade_launcher.mdl", "Grenade Launcher");
	g_smModelToName.SetString("models/w_models/weapons/w_m60.mdl", "M60");
	g_smModelToName.SetString("models/props_junk/gascan001a.mdl", "Gas Can");
	g_smModelToName.SetString("models/props_junk/explosive_box001.mdl", "Firework");
	g_smModelToName.SetString("models/props_junk/propanecanister001a.mdl", "Propane Tank");
	g_smModelToName.SetString("models/props_equipment/oxygentank01.mdl", "Oxygen Tank");
	g_smModelToName.SetString("models/props_junk/gnome.mdl", "Gnome");
	g_smModelToName.SetString("models/w_models/weapons/w_cola.mdl", "Cola");
	g_smModelToName.SetString("models/w_models/weapons/50cal.mdl", ".50 Cal Machine Gun");
	g_smModelToName.SetString("models/w_models/weapons/w_minigun.mdl", "Minigun here");
	g_smModelToName.SetString("models/props/terror/exploding_ammo.mdl", "Explosive Ammo");
	g_smModelToName.SetString("models/props/terror/incendiary_ammo.mdl", "Incendiary Ammo");
	g_smModelToName.SetString("models/w_models/weapons/w_knife_t.mdl", "Knife");
	g_smModelToName.SetString("models/weapons/melee/w_bat.mdl", "Baseball Bat");
	g_smModelToName.SetString("models/weapons/melee/w_cricket_bat.mdl", "Cricket Bat");
	g_smModelToName.SetString("models/weapons/melee/w_crowbar.mdl", "Crowbar");
	g_smModelToName.SetString("models/weapons/melee/w_electric_guitar.mdl", "Electric Guitar");
	g_smModelToName.SetString("models/weapons/melee/w_fireaxe.mdl", "Fireaxe");
	g_smModelToName.SetString("models/weapons/melee/w_frying_pan.mdl", "Frying Pan");
	g_smModelToName.SetString("models/weapons/melee/w_katana.mdl", "Katana");
	g_smModelToName.SetString("models/weapons/melee/w_machete.mdl", "Machete");
	g_smModelToName.SetString("models/weapons/melee/w_tonfa.mdl", "Nightstick");
	g_smModelToName.SetString("models/weapons/melee/w_golfclub.mdl", "Golf Club");
	g_smModelToName.SetString("models/weapons/melee/w_pitchfork.mdl", "Pitckfork");
	g_smModelToName.SetString("models/weapons/melee/w_shovel.mdl", "Shovel");
}

public Action Vocalize_Listener(int client, const char[] command, int argc)
{
	if (IsValidSur(client))
	{
		static char sCmdString[32];
		if (GetCmdArgString(sCmdString, sizeof(sCmdString)) > 1)
		{
			if (strncmp(sCmdString, "smartlook #", 11, false) == 0)
			{
				PlayerMarkHint(client);
			}
		}
	}

	return Plugin_Continue;
}

// ====================================================================================================
// Main Function - When Player Start Mark Hint
// ====================================================================================================
void PlayerMarkHint(int client)
{
	static char sItemName[64], 
	sEntModelName[PLATFORM_MAX_PATH];
	static int iEntity;
	iEntity = GetUseEntity(client);
	bool bIsVaildItem = false;
	if (IsValidEntityIndex(iEntity) && IsValidEntity(iEntity) && !IsParentByClient(iEntity))
	{
		// nếu item đã được đánh dấu bởi một player
		if (g_eMarker[iEntity].created)
		{
			DoUnmarkItem(iEntity);
			return;
		}
		// Item này chưa đánh dấu
		if (HasEntProp(iEntity, Prop_Data, "m_ModelName"))
		{
			float vEndPos[3];
			GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vEndPos);
			if (GetEntPropString(iEntity, Prop_Data, "m_ModelName", sEntModelName, sizeof(sEntModelName)) > 1)
			{
				StringToLowerCase(sEntModelName);
				if (g_smModelToName.GetString(sEntModelName, sItemName, sizeof(sItemName)))
				{
					bIsVaildItem = true;
				}
				else if (StrContains(sEntModelName, "/melee/") != -1) // entity không được liệt kê trong StringMap (custom weapon model)
				{
					FormatEx(sItemName, sizeof sItemName, "%s", "Melee!");
					bIsVaildItem = true;
				}
				else if (StrContains(sEntModelName, "/weapons/") != -1) // entity không được liệt kê trong StringMap (custom weapon model)
				{
					FormatEx(sItemName, sizeof sItemName, "%s", "Weapons!");
					bIsVaildItem = true;
				}
				else // entity không được liệt kê trong StringMap (các model khác)
				{
					bIsVaildItem = false;
				}
				if (bIsVaildItem)
				{
					if (gc_fLastTimeUse[client] != 0 && GetGameTime() - gc_fLastTimeUse[client] < g_fCvar_UseCooldown) {
						char temp[4];
						FormatEx(temp, sizeof(temp), "%.2f", g_fCvar_UseCooldown - (GetGameTime() - gc_fLastTimeUse[client]));
						CPrintToChat(client, "%t", "Player In Cooldown Message", temp);
						return;
					}
					else {
						gc_fLastTimeUse[client] = GetGameTime();
						EmitSoundToClient(client, g_sCvar_UseSound);
						DoMarkItem(client, iEntity, sEntModelName, sItemName, vEndPos);
						CreateTimer(g_fCvar_UseCooldown, TimerCooldownCallback, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}
		}
	}
}

void DoMarkItem(int client, int iEntity, const char[] sEntModelName, char sItemName[64], const float vOrigin[3])
{
	static char sTargetName[64];
	FormatEx(sTargetName, sizeof(sTargetName), "%s-%02i", "l4d2_item_marker", client);
	int iGlow = _create_EntityGlow_(iEntity, gCColors.GetColorStr(gc_eMarkerColor[client].id), sEntModelName);
	int iTarget = _create_InfoTarget_(iEntity, vOrigin, sTargetName, g_fCvar_MarkDuration);
	Handle hBeamTimer = _create_BeamTimer_(client, gCColors.GetColor(gc_eMarkerColor[client].id), g_iCvar_ModelBeamIndex, iEntity, vOrigin);
	int iSprite = _create_Sprite_(client, iTarget, vOrigin, gCColors.GetColorStr(gc_eMarkerColor[client].id), sTargetName, g_fCvar_MarkDuration, g_sCvar_ModelSprite);
	Handle hSpriteTimer = _create_SpriteTimer_(iSprite, iEntity);
	
	if (IsValidEntityIndex(iGlow) && IsValidEntityIndex(iTarget) && IsValidEntityIndex(iSprite))
	{
		g_eMarker[iEntity].init(client, iTarget, iGlow, iSprite, hBeamTimer, hSpriteTimer, sItemName);
		g_hMarkerTimer[iEntity] = CreateTimer(g_fCvar_MarkDuration, Timer_Remove, iEntity);
		CPrintToChatAll("%t", "Player Marked Item", client, g_eMarker[iEntity].sItemName);
	}
}

void DoUnmarkItem(int iEntity)
{
	removeMarker(iEntity);
	delete g_hMarkerTimer[iEntity];
}

public Action Timer_Remove(Handle timer, int iEntity)
{
	removeMarker(iEntity);
	g_hMarkerTimer[iEntity] = null;
	return Plugin_Continue;
}

void removeMarker(int iEntity)
{
	if (g_eMarker[iEntity].created)
	{
		delete g_eMarker[iEntity].hBeamTimer;
		delete g_eMarker[iEntity].hSpriteTimer;
		_remove_EntityGlow_(iEntity);
		_remove_Sprite_(iEntity);
		_remove_TargetInstructor_(iEntity);
		g_eMarker[iEntity].clear();
	}
}

// ====================================================================================================
// info target
// ====================================================================================================
int _create_InfoTarget_(int iEntity, const float vOrigin[3], const char[] sTargetName, float duration)
{
	float vEndPos[3];
	vEndPos = vOrigin;
	vEndPos[2] += g_fCvar_SpriteZAxis;
	int entity = CreateEntityByName("info_target");
	if (!CheckIfEntityMax(entity)) return false;
	
	DispatchKeyValue(entity, "targetname", sTargetName);
	DispatchKeyValue(entity, "spawnflags", "1"); //Only visible to survivors
	DispatchKeyValueVector(entity, "origin", vEndPos);
	DispatchSpawn(entity);
	SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
	
	// xóa info_target đã tồn tại trước đó cho item này (nếu có tồn tại)
	_remove_TargetInstructor_(iEntity);
	static char szBuffer[36];
	FormatEx(szBuffer, sizeof szBuffer, "OnUser1 !self:Kill::%f:-1", duration);
	SetVariantString(szBuffer);
	// #format: <output name> <target name>:<input name>:<parameter>:<delay>:<max times to fire>
	// fire input "AddOutput" để add thêm output "OnUser1"
	AcceptEntityInput(entity, "AddOutput");
	// fire input "FireUser1"
	AcceptEntityInput(entity, "FireUser1");
	return entity;
}

// ====================================================================================================
// beam
// ====================================================================================================
Handle _create_BeamTimer_(int client, int color[4], int iModelIndex, int iEntity, const float vOrigin[3])
{
	float vEndPos[3];
	vEndPos = vOrigin;
	DataPack pack = new DataPack();
	pack.WriteCell(EntIndexToEntRef(iEntity));
	pack.WriteCell(iModelIndex);
	pack.WriteCellArray(color, 4, true);
	int[] targets = new int[MaxClients];
	int targetsCount;
	g_eMarker[iEntity].iBeamDirection = DIRECTION_IN;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target))
			continue;
		if (IsFakeClient(target))
			continue;
		if (GetClientTeam(target) == 3)
			continue;
		targets[targetsCount++] = target;
	}
	TE_SetupBeamRingPoint(vEndPos, g_fCvar_BeamStartRadius, g_fCvar_BeamEndRadius, iModelIndex, 0, 0, 0, g_fCvar_BeamDuration, 2.0, 0.0, color, 0, 0);
    TE_Send(targets, targetsCount);
	return CreateTimer(g_fCvar_BeamDuration, TimerFieldCallback, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ====================================================================================================
// entity glow
// ====================================================================================================
int _create_EntityGlow_(int iEntity, char[] sColor, const char[] sEntModelName)
{
	// Spawn dynamic prop entity
	int entity = CreateEntityByName("prop_dynamic_override");
	if( !CheckIfEntityMax(entity) ) return -1;

	// Set new fake model
	DispatchKeyValue(entity, "model", sEntModelName);
	DispatchKeyValue(entity, "targetname", "tuan_marked_item");
	DispatchSpawn(entity);

	float vPos[3], vAng[3];
	GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", vPos);
	GetEntPropVector(iEntity, Prop_Send, "m_angRotation", vAng);
	TeleportEntity(entity, vPos, vAng, NULL_VECTOR);
	_remove_EntityGlow_(iEntity);

	// Set outline glow color
	SetEntProp(entity, Prop_Send, "m_CollisionGroup", 0);
	SetEntProp(entity, Prop_Send, "m_nSolidType", 0);
	SetEntProp(entity, Prop_Send, "m_nGlowRange", -1);
	SetEntProp(entity, Prop_Send, "m_iGlowType", 3);
	SetEntProp(entity, Prop_Send, "m_glowColorOverride", GetColor(sColor));
	AcceptEntityInput(entity, "StartGlowing");

	// Set model invisible
	SetEntityRenderMode(entity, RENDER_TRANSCOLOR);
	SetEntityRenderColor(entity, 0, 0, 0, 0);

	// Set model attach to item, and always synchronize
	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", iEntity);
	SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
	return entity;
}


// ====================================================================================================
// sprite
// ====================================================================================================
int _create_Sprite_(int client, int iTarget, const float vOrigin[3], const char[] sColor, const char[] sTargetName, float duration, const char[] sModelSprite)
{
	int entity = CreateEntityByName("env_sprite");
	char alpha[3];
	IntToString(g_iCvar_Alpha, alpha, sizeof(alpha));
	if (!CheckIfEntityMax(entity)) return false;
	float vEndPos[3];
	GetEntPropVector(iTarget, Prop_Data, "m_vecOrigin", vEndPos); 
	DispatchKeyValue(entity, "targetname", sTargetName);
	DispatchKeyValue(entity, "spawnflags", "1"); //Only visible to survivors
	TeleportEntity(entity, vEndPos, NULL_VECTOR, NULL_VECTOR);
	SDKHook(entity, SDKHook_SetTransmit, Hook_SetTransmit);
	DispatchKeyValue(entity, "model", sModelSprite);
	DispatchKeyValue(entity, "rendercolor", sColor);
	DispatchKeyValue(entity, "renderamt", alpha);
	DispatchKeyValue(entity, "scale", "0.5");
	DispatchKeyValue(entity, "fademindist", "-1");
	DispatchSpawn(entity);
	SetVariantString("!activator");
	AcceptEntityInput(entity, "SetParent", iTarget);
	SetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity", client);
	AcceptEntityInput(entity, "ShowSprite");
	static char szBuffer[36];
	FormatEx(szBuffer, sizeof szBuffer, "OnUser1 !self:Kill::%f:-1", duration);
	SetVariantString(szBuffer);
	// #format: <output name> <target name>:<input name>:<parameter>:<delay>:<max times to fire>
	// fire input "AddOutput" để add thêm output "OnUser1"
	AcceptEntityInput(entity, "AddOutput");
	// fire input "FireUser1"
	AcceptEntityInput(entity, "FireUser1");
	return entity;
}

Handle _create_SpriteTimer_(int iSprite, int iEntity)
{
	DataPack pack = new DataPack();
	g_eMarker[iEntity].iSpriteDirection = DIRECTION_IN;
	pack.WriteCell(EntIndexToEntRef(iSprite));
	pack.WriteCell(EntIndexToEntRef(iEntity));
	return CreateTimer(0.1, TimerSpriteCallback, pack, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// ====================================================================================================
// callbacks
// ====================================================================================================
Action TimerSpriteCallback(Handle timer, DataPack pack)
{
	pack.Reset();
	int iSprite = EntRefToEntIndex(pack.ReadCell());
	int iEntity = EntRefToEntIndex(pack.ReadCell());
	float vPos[3];
	if (!IsValidEntityIndex(iSprite)) {
		//PrintToChatAll("Cannot found Entity %d", iSprite);
		return Plugin_Stop;
	}
	// Update position for info_target
	int iTarget = GetEntPropEnt(iSprite, Prop_Data, "m_pParent");
	if (IsValidEntityIndex(iTarget)) {
		float vEndPos[3];
		GetEntPropVector(iEntity, Prop_Data, "m_vecOrigin", vEndPos);
		vEndPos[2] += g_fCvar_SpriteZAxis;
		TeleportEntity(iTarget, vEndPos, NULL_VECTOR, NULL_VECTOR);
	}
	GetEntPropVector(iSprite, Prop_Data, "m_vecOrigin", vPos);
	int direction = g_eMarker[iEntity].iSpriteDirection;
	switch (direction) {
		case DIRECTION_IN:
		{
			vPos[2] -= g_fCvar_SpriteZSpeed;
			if (vPos[2] <= - g_fCvar_SpriteMoveRange) g_eMarker[iEntity].iSpriteDirection = DIRECTION_OUT;
		}
		case DIRECTION_OUT:
		{
			vPos[2] += g_fCvar_SpriteZSpeed;
			if (vPos[2] >= g_fCvar_SpriteMoveRange) g_eMarker[iEntity].iSpriteDirection = DIRECTION_IN;
		}
	}
	TeleportEntity(iSprite, vPos, NULL_VECTOR, NULL_VECTOR);
    return Plugin_Continue;
}

Action TimerFieldCallback(Handle timer, DataPack pack)
{
	float vEndPos[3];
	int iEntity;
	int color[4];
	int[] targets = new int[MaxClients];
	int targetsCount;
	int iModelIndex;
	
	pack.Reset();
	iEntity = EntRefToEntIndex(pack.ReadCell());
	if (!IsValidEntityIndex(iEntity)) {
		return Plugin_Stop;
	}
	GetEntPropVector(iEntity, Prop_Data, "m_vecOrigin", vEndPos);
	iModelIndex = pack.ReadCell();
	pack.ReadCellArray(color, 4);
	int direction = g_eMarker[iEntity].iBeamDirection;
	for (int target = 1; target <= MaxClients; target++)
	{
		if (!IsClientInGame(target))
			continue;
		if (IsFakeClient(target))
			continue;
		if (GetClientTeam(target) == 3)
			continue;
		targets[targetsCount++] = target;
	}
	switch (direction)
	{
		case DIRECTION_IN:
		{
			TE_SetupBeamRingPoint(vEndPos, g_fCvar_BeamEndRadius, g_fCvar_BeamStartRadius, iModelIndex, 0, 0, 0, g_fCvar_BeamDuration, 2.0, 0.0, color, 0, 0);
			TE_Send(targets, targetsCount);
			g_eMarker[iEntity].iBeamDirection = DIRECTION_OUT;
		}
		case DIRECTION_OUT:
		{
			TE_SetupBeamRingPoint(vEndPos, g_fCvar_BeamStartRadius, g_fCvar_BeamEndRadius, iModelIndex, 0, 0, 0, g_fCvar_BeamDuration, 2.0, 0.0, color, 0, 0);
			TE_Send(targets, targetsCount);
			g_eMarker[iEntity].iBeamDirection = DIRECTION_IN;
		}
	}
}

Action TimerCooldownCallback(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);
    if (client == 0)
        return Plugin_Stop;
	CPrintToChat(client, "%t", "Player Ready To Use");
	EmitSoundToClient(client, g_sCvar_ReadySound);
    return Plugin_Stop;
}

void _remove_TargetInstructor_(int iEntity)
{
	if (g_eMarker[iEntity].created && IsValidEntRef(g_eMarker[iEntity].iTargetRef))
		RemoveEntity(g_eMarker[iEntity].iTargetRef);
}

void _remove_EntityGlow_(int iEntity)
{
	if (g_eMarker[iEntity].created && IsValidEntRef(g_eMarker[iEntity].iGlowRef))
		RemoveEntity(g_eMarker[iEntity].iGlowRef);
}

void _remove_Sprite_(int iEntity)
{
	if (g_eMarker[iEntity].created && IsValidEntRef(g_eMarker[iEntity].iSpriteRef))
		RemoveEntity(g_eMarker[iEntity].iSpriteRef);
}

public void OnEntityDestroyed(int entity)
{
	if (!IsValidEntityIndex(entity))
		return;
	DoUnmarkItem(entity);
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_WeaponEquipPost, OnWeaponEquipPost);
}

public void OnWeaponEquipPost(int client, int weapon)
{
	if (!IsValidEntity(weapon))
		return;
	if (g_eMarker[weapon].created) {
		DoUnmarkItem(weapon);
		CPrintToChatAll("%t", "Player Got Marked Item", client, g_eMarker[weapon].sItemName);
	}
}

bool IsValidEntRef(int entity)
{
	if (entity && EntRefToEntIndex(entity) != INVALID_ENT_REFERENCE)
		return true;
	return false;
}

bool IsValidSur(int client)
{
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && GetClientTeam(client) == 2 && IsPlayerAlive(client) && !IsFakeClient(client));
}

public Action Hook_SetTransmit(int entity, int client)
{
	if( GetClientTeam(client) == 3)
		return Plugin_Handled;

	return Plugin_Continue;
}

bool IsParentByClient(int entity)
{
	if(HasEntProp(entity, Prop_Data, "m_pParent"))
	{
		int parent_entity = GetEntPropEnt(entity, Prop_Data, "m_pParent");
		//PrintToChatAll("%d m_pParent: %d", entity, parent_entity);
		if (1 <= parent_entity <= MaxClients && IsClientInGame(parent_entity))
		{
			return true;
		}
	}

	return false;
}

int GetColor(char[] sTemp)
{
	if (StrEqual(sTemp, ""))
		return 0;

	char sColors[3][4];
	int  color = ExplodeString(sTemp, " ", sColors, 3, 4);

	if (color != 3)
		return 0;

	color = StringToInt(sColors[0]);
	color += 256 * StringToInt(sColors[1]);
	color += 65536 * StringToInt(sColors[2]);

	return color;
}

void GetArrayColor(char[] sColor, int[] buffer)
{
    if (sColor[0] == 0)
        return;

    char sColors[3][4];
    int count = ExplodeString(sColor, " ", sColors, sizeof(sColors), sizeof(sColors[]));

    switch (count)
    {
        case 1:
        {
            buffer[0] = StringToInt(sColors[0]);
        }
        case 2:
        {
            buffer[0] = StringToInt(sColors[0]);
            buffer[1] = StringToInt(sColors[1]);
        }
        case 3:
        {
            buffer[0] = StringToInt(sColors[0]);
            buffer[1] = StringToInt(sColors[1]);
            buffer[2] = StringToInt(sColors[2]);
        }
    }
}

bool CheckIfEntityMax(int entity)
{
	if(entity == -1) return false;

	if(	entity > 2000)
	{
		AcceptEntityInput(entity, "Kill");
		return false;
	}
	return true;
}

bool IsValidEntityIndex(int entity)
{
	return (MaxClients + 1 <= entity <= GetMaxEntities());
}

void StringToLowerCase(char[] input)
{
    for (int i = 0; i < strlen(input); i++)
    {
        input[i] = CharToLower(input[i]);
    }
}

int GetUseEntity (int client, float use_radius = 96.0 /* default of player_use_radius */)
{
    return SDKCall(g_hSDK_UseEntity, client, use_radius, 0.0, 0.0, 0, 0);
}
