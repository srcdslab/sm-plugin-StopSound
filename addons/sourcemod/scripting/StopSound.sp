#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <multicolors>

#define WEAPON_VOLUME_NORMAL 100

// Steps cycled through by the settings menu (0 = weapon sounds disabled).
int g_iWeaponVolumeSteps[] = { 100, 75, 50, 25, 10, 0 };

// CS:S shoot sounds indexed by CSWeaponID (game/shared/cstrike/cs_weapon_parse.h).
char g_sWeaponShootSounds[][] =
{
	"",							// WEAPON_NONE
	"Weapon_P228.Single",
	"Weapon_Glock.Single",
	"Weapon_Scout.Single",
	"",							// WEAPON_HEGRENADE
	"Weapon_XM1014.Single",
	"",							// WEAPON_C4
	"Weapon_MAC10.Single",
	"Weapon_AUG.Single",
	"",							// WEAPON_SMOKEGRENADE
	"Weapon_ELITE.Single",
	"Weapon_FiveSeven.Single",
	"Weapon_UMP45.Single",
	"Weapon_SG550.Single",
	"Weapon_Galil.Single",
	"Weapon_FAMAS.Single",
	"Weapon_USP.Single",
	"Weapon_AWP.Single",
	"Weapon_MP5Navy.Single",
	"Weapon_M249.Single",
	"Weapon_M3.Single",
	"Weapon_M4A1.Single",
	"Weapon_TMP.Single",
	"Weapon_G3SG1.Single",
	"",							// WEAPON_FLASHBANG
	"Weapon_DEagle.Single",
	"Weapon_SG552.Single",
	"Weapon_AK47.Single",
	"",							// WEAPON_KNIFE
	"Weapon_P90.Single"
};

#define CSS_WEAPON_USP 16
#define CSS_WEAPON_M4A1 21
#define CSS_SECONDARY_MODE 1

// Weapon sounds volume in percent: 100 = normal, 0 = disabled.
int g_iWeaponVolume[MAXPLAYERS+1] = { WEAPON_VOLUME_NORMAL, ... };
bool g_bStopMapMusic[MAXPLAYERS+1] = { false, ... };

bool g_bStopWeaponSoundsHooked = false;
bool g_bEmittingScaledSound = false;
bool g_bStopMapMusicHooked = false;
bool g_bLate = false;

StringMap g_MapMusic;

Handle g_hCookieStopSound = null;

public Plugin myinfo =
{
	name = "Toggle Game Sounds",
	author = "GoD-Tony, edit by Obus + BotoX, Oleg Tsvetkov",
	description = "Allows clients to stop hearing weapon sounds and map music",
	version = "3.3.0",
	url = "http://www.sourcemod.net/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (GetEngineVersion() != Engine_CSS)
	{
		strcopy(error, err_max, "This plugin supports only CS:S!");
		return APLRes_Failure;
	}

	g_bLate = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// Load translations
	LoadTranslations("plugin.stopsound.phrases");
	LoadTranslations("common.phrases"); // For On/Off buttons in Cookies Menu

	g_MapMusic = new StringMap();

	// Detect game and hook appropriate tempent.
	AddTempEntHook("Shotgun Shot", Hook_ShotgunShot);

	// Ambient sounds
	AddAmbientSoundHook(Hook_AmbientSound);

	// Map music will be caught here
	HookEvent("round_end", Event_RoundEnd);
	HookEvent("player_spawn", Event_PlayerSpawn);

	RegConsoleCmd("sm_stopsound", Command_StopSound, "Toggle hearing weapon sounds");
	RegConsoleCmd("sm_sound", Command_StopSound, "Toggle hearing weapon sounds");
	RegConsoleCmd("sm_stopmusic", Command_StopMusic, "Toggle hearing map music");
	RegConsoleCmd("sm_music", Command_StopMusic, "Toggle hearing map music");
	RegConsoleCmd("sm_weaponvolume", Command_WeaponVolume, "Set weapon sounds volume (0-100)");
	RegConsoleCmd("sm_wvol", Command_WeaponVolume, "Set weapon sounds volume (0-100)");

	// Single cookie for both settings
	g_hCookieStopSound = RegClientCookie("sound_settings", "Sound settings (weapon sounds : map music : weapon volume)", CookieAccess_Protected);

	SetCookieMenuItem(CookieMenuHandler_StopSounds, 0, "Stop sounds");

	// Suppress reload sound effects
	UserMsg ReloadEffect = GetUserMessageId("ReloadEffect");

	// Game-specific setup
	// Weapon sounds will be caught here.
	AddNormalSoundHook(Hook_NormalSound_CSS);

	if (ReloadEffect != INVALID_MESSAGE_ID)
	{
		HookUserMessage(ReloadEffect, Hook_ReloadEffect_CSS, true);
	}

	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i) || !AreClientCookiesCached(i))
				continue;

			OnClientCookiesCached(i);
		}
	}
}

public void OnPluginEnd()
{
	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			OnClientDisconnect(client);
		}
	}

	// Remove tempent hook
	RemoveTempEntHook("Shotgun Shot", Hook_ShotgunShot);

	// Remove ambient sound hook
	RemoveAmbientSoundHook(Hook_AmbientSound);

	// Find ReloadEffect
	UserMsg ReloadEffect = GetUserMessageId("ReloadEffect");

	// Remove game-specific
	RemoveNormalSoundHook(Hook_NormalSound_CSS);

	if (ReloadEffect != INVALID_MESSAGE_ID)
		UnhookUserMessage(ReloadEffect, Hook_ReloadEffect_CSS, true);
}

public void OnMapStart()
{
	g_MapMusic.Clear();

	for (int i = 0; i < sizeof(g_sWeaponShootSounds); i++)
	{
		if (g_sWeaponShootSounds[i][0])
			PrecacheScriptSound(g_sWeaponShootSounds[i]);
	}

	PrecacheScriptSound("Weapon_USP.SilencedShot");
	PrecacheScriptSound("Weapon_M4A1.Silenced");
}

public void OnMapEnd()
{
	if (g_MapMusic != null)
		delete g_MapMusic;

	g_MapMusic = new StringMap();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_MapMusic.Clear();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if (!IsClientInGame(client) || GetClientTeam(client) <= CS_TEAM_SPECTATOR)
		return;

	if (g_iWeaponVolume[client] == 0)
		CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds disabled");
	else if (g_iWeaponVolume[client] < WEAPON_VOLUME_NORMAL)
		CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds volume", g_iWeaponVolume[client]);

	if (g_bStopMapMusic[client])
		CPrintToChat(client, "%t %t", "Chat Prefix", "Map music disabled");
}

public Action Command_StopSound(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	SetWeaponVolume(client, g_iWeaponVolume[client] == 0 ? WEAPON_VOLUME_NORMAL : 0);
	return Plugin_Handled;
}

public Action Command_WeaponVolume(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	if (args < 1)
	{
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Weapon volume usage");
		ShowStopSoundsSettingsMenu(client);
		return Plugin_Handled;
	}

	char sArg[8];
	GetCmdArg(1, sArg, sizeof(sArg));

	int iVolume;
	if (StringToIntEx(sArg, iVolume) == 0 || iVolume < 0 || iVolume > WEAPON_VOLUME_NORMAL)
	{
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Weapon volume usage");
		return Plugin_Handled;
	}

	SetWeaponVolume(client, iVolume);
	return Plugin_Handled;
}

void SetWeaponVolume(int client, int iVolume)
{
	g_iWeaponVolume[client] = iVolume;
	CheckWeaponSoundsHooks();

	if (iVolume == 0)
	{
		CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds disabled");
	}
	else if (iVolume == WEAPON_VOLUME_NORMAL)
	{
		CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds enabled");
	}
	else
	{
		CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds volume", iVolume);
	}

	SaveClientSettings(client);
}

public Action Command_StopMusic(int client, int args)
{
	if (client == 0)
	{
		ReplyToCommand(client, "[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	g_bStopMapMusic[client] = !g_bStopMapMusic[client];
	CheckMapMusicHooks();

	if (g_bStopMapMusic[client])
	{
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Map music disabled");
		StopMapMusic(client);
	}
	else
	{
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Map music enabled");
	}

	SaveClientSettings(client);
	return Plugin_Handled;
}

void SaveClientSettings(int client)
{
	// First two digits keep the legacy format (weapon sounds stopped, map music stopped).
	char sBuffer[8];
	Format(sBuffer, sizeof(sBuffer), "%d%d%d", g_iWeaponVolume[client] == 0 ? 1 : 0, g_bStopMapMusic[client] ? 1 : 0, g_iWeaponVolume[client]);
	SetClientCookie(client, g_hCookieStopSound, sBuffer);
}

public void OnClientCookiesCached(int client)
{
	char sBuffer[8];
	GetClientCookie(client, g_hCookieStopSound, sBuffer, sizeof(sBuffer));

	// Parse the cookie format: %d%d[%d] (weapon sounds, map music[, weapon volume])
	if (sBuffer[0] != '\0' && strlen(sBuffer) >= 2)
	{
		g_iWeaponVolume[client] = (sBuffer[0] == '1') ? 0 : WEAPON_VOLUME_NORMAL;
		g_bStopMapMusic[client] = (sBuffer[1] == '1');

		int iVolume;
		if (sBuffer[0] != '1' && StringToIntEx(sBuffer[2], iVolume) > 0 && iVolume >= 0 && iVolume <= WEAPON_VOLUME_NORMAL)
			g_iWeaponVolume[client] = iVolume;
	}
	else
	{
		// Default values if cookie is empty or invalid
		g_iWeaponVolume[client] = WEAPON_VOLUME_NORMAL;
		g_bStopMapMusic[client] = false;
	}

	// Update hook states
	if (g_iWeaponVolume[client] < WEAPON_VOLUME_NORMAL)
		g_bStopWeaponSoundsHooked = true;
	if (g_bStopMapMusic[client])
		g_bStopMapMusicHooked = true;
}

public void OnClientDisconnect(int client)
{
	g_iWeaponVolume[client] = WEAPON_VOLUME_NORMAL;
	g_bStopMapMusic[client] = false;

	CheckWeaponSoundsHooks();
	CheckMapMusicHooks();
}

void CheckWeaponSoundsHooks()
{
	bool bShouldHook = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iWeaponVolume[i] < WEAPON_VOLUME_NORMAL)
		{
			bShouldHook = true;
			break;
		}
	}

	// Fake (un)hook because toggling actual hooks will cause server instability.
	g_bStopWeaponSoundsHooked = bShouldHook;
}

void CheckMapMusicHooks()
{
	bool bShouldHook = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bStopMapMusic[i])
		{
			bShouldHook = true;
			break;
		}
	}

	// Fake (un)hook because toggling actual hooks will cause server instability.
	g_bStopMapMusicHooked = bShouldHook;
}

void StopMapMusic(int client)
{
	int entity = INVALID_ENT_REFERENCE;

	char sEntity[16];
	char sSample[PLATFORM_MAX_PATH];

	StringMapSnapshot MapMusicSnap = g_MapMusic.Snapshot();
	for (int i = 0; i < MapMusicSnap.Length; i++)
	{
		MapMusicSnap.GetKey(i, sEntity, sizeof(sEntity));

		if ((entity = EntRefToEntIndex(StringToInt(sEntity))) == INVALID_ENT_REFERENCE)
		{
			g_MapMusic.Remove(sEntity);
			continue;
		}

		g_MapMusic.GetString(sEntity, sSample, sizeof(sSample));

		EmitSoundToClient(client, sSample, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOPLOOPING, SNDVOL_NORMAL, SNDPITCH_NORMAL);
	}
	delete MapMusicSnap;
}

public void CookieMenuHandler_StopSounds(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	if (action == CookieMenuAction_DisplayOption)
	{
		Format(buffer, maxlen, "%T", "Cookie Menu Stop Sounds", client);
	}
	else if (action == CookieMenuAction_SelectOption)
	{
		ShowStopSoundsSettingsMenu(client);
	}
}

void ShowStopSoundsSettingsMenu(int client)
{
	Menu menu = new Menu(MenuHandler_StopSoundsSettings);

	menu.SetTitle("%T", "Cookie Menu Stop Sounds Title", client);

	char sBuffer[128];

	if (g_iWeaponVolume[client] == 0)
		Format(sBuffer, sizeof(sBuffer), "%T%T", "Weapon Sounds", client, "Disabled", client);
	else if (g_iWeaponVolume[client] == WEAPON_VOLUME_NORMAL)
		Format(sBuffer, sizeof(sBuffer), "%T%T", "Weapon Sounds", client, "Enabled", client);
	else
		Format(sBuffer, sizeof(sBuffer), "%T%T", "Weapon Sounds", client, "Volume Value", client, g_iWeaponVolume[client]);
	menu.AddItem("0", sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T%T", "Map Sounds", client, g_bStopMapMusic[client] ? "Disabled" : "Enabled", client);
	menu.AddItem("1", sBuffer);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StopSoundsSettings(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Cancel)
	{
		ShowCookieMenu(client);
	}
	else if (action == MenuAction_Select)
	{
		if (selection == 0)
		{
			SetWeaponVolume(client, GetNextWeaponVolumeStep(g_iWeaponVolume[client]));
			ShowStopSoundsSettingsMenu(client);
			return 0;
		}
		else if (selection == 1)
		{
			g_bStopMapMusic[client] = !g_bStopMapMusic[client];
			CheckMapMusicHooks();

			if (g_bStopMapMusic[client])
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "Map music disabled");
				StopMapMusic(client);
			}
			else
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "Map music enabled");
			}

		}

		SaveClientSettings(client);
		ShowStopSoundsSettingsMenu(client);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
	return 0;
}

public Action Hook_NormalSound_CSS(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if (!g_bStopWeaponSoundsHooked || g_bEmittingScaledSound)
		return Plugin_Continue;

	// Ignore non-weapon sounds.
	if (channel != SNDCHAN_WEAPON &&
		!(channel == SNDCHAN_AUTO && strncmp(sample, "physics/flesh", 13) == 0) &&
		!(channel == SNDCHAN_VOICE && StrContains(sample, "player/headshot", true) != -1))
	{
		return Plugin_Continue;
	}

	int[] scaledClients = new int[numClients];
	int scaledTotal = 0;

	int j = 0;
	for (int i = 0; i < numClients; i++)
	{
		int client = clients[i];
		if (!IsClientInGame(client) || g_iWeaponVolume[client] == 0)
			continue;

		if (g_iWeaponVolume[client] < WEAPON_VOLUME_NORMAL)
		{
			// Re-emitted below with a reduced volume.
			scaledClients[scaledTotal++] = client;
			continue;
		}

		// Keep client.
		clients[j] = clients[i];
		j++;
	}

	if (j == numClients)
		return Plugin_Continue;

	if (scaledTotal > 0)
		EmitScaledSound(scaledClients, scaledTotal, sample, entity, channel, level, flags, volume, pitch, NULL_VECTOR);

	numClients = j;

	return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
}

public Action Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if (!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	// Check which clients need to be excluded.
	int[] newClients = new int[numClients];
	int newTotal = 0;
	int[] scaledClients = new int[numClients];
	int scaledTotal = 0;

	for (int i = 0; i < numClients; i++)
	{
		int client = Players[i];
		if (client <= 0 || client > MaxClients || !IsClientInGame(client) || g_iWeaponVolume[client] == 0)
			continue;

		// The client plays the shoot sound itself when it receives this tempent,
		// so clients with a reduced volume get the sound emitted by the server instead.
		if (g_iWeaponVolume[client] < WEAPON_VOLUME_NORMAL)
			scaledClients[scaledTotal++] = client;
		else
			newClients[newTotal++] = client;
	}

	if (newTotal == numClients)
	{
		// No clients were excluded.
		return Plugin_Continue;
	}

	if (scaledTotal > 0)
		EmitScaledShootSound(scaledClients, scaledTotal);

	if (newTotal == 0)
	{
		// All clients were excluded and there is no need to broadcast.
		return Plugin_Stop;
	}

	// Re-broadcast to clients that still need it.
	float vTemp[3];
	TE_Start("Shotgun Shot");
	TE_ReadVector("m_vecOrigin", vTemp);
	TE_WriteVector("m_vecOrigin", vTemp);
	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
	TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
	TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	TE_Send(newClients, newTotal, delay);

	return Plugin_Stop;
}

public Action Hook_ReloadEffect_CSS(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	int client = msg.ReadShort();

	// Check which clients need to be excluded.
	int[] newClients = new int[playersNum];
	int newTotal = 0;

	for (int i = 0; i < playersNum; i++)
	{
		int client_ = players[i];
		if (client_ > 0 && client_ <= MaxClients && IsClientInGame(client_) && g_iWeaponVolume[client_] != 0)
		{
			newClients[newTotal++] = client_;
		}
	}

	if (newTotal == playersNum)
	{
		// No clients were excluded.
		return Plugin_Continue;
	}
	else if (newTotal == 0)
	{
		// All clients were excluded and there is no need to broadcast.
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(newTotal);

	for (int i = 0; i < newTotal; i++)
	{
		pack.WriteCell(newClients[i]);
	}

	RequestFrame(OnReloadEffect, pack);

	return Plugin_Handled;
}

public void OnReloadEffect(DataPack pack)
{
	pack.Reset();
	int client = pack.ReadCell();

	if (client <= 0 || client > MaxClients || !IsClientInGame(client))
	{
		delete pack;
		return;
	}

	int newTotal = pack.ReadCell();

	int[] players = new int[newTotal];
	int playersNum = 0;

	for (int i = 0; i < newTotal; i++)
	{
		int client_ = pack.ReadCell();
		// In case of invalid client, skip it.
		if (client_ > 0 && client_ <= MaxClients && IsClientInGame(client_))
		{
			players[playersNum++] = client_;
		}
	}

	CloseHandle(pack);

	// All clients were excluded and there is no need to broadcast.
	if (playersNum == 0)
		return;

	Handle ReloadEffect = StartMessage("ReloadEffect", players, playersNum, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
	if (GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(ReloadEffect, "entidx", client);
	}
	else
	{
		BfWriteShort(ReloadEffect, client);
	}

	EndMessage();
}

public Action Hook_AmbientSound(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay)
{
	// Are we playing music?
	if (!strncmp(sample, "music", 5, false) && !strncmp(sample, "#", 1, false))
		return Plugin_Continue;

	char sEntity[16];
	IntToString(EntIndexToEntRef(entity), sEntity, sizeof(sEntity));

	g_MapMusic.SetString(sEntity, sample, true);

	if (!g_bStopMapMusicHooked)
		return Plugin_Continue;

	switch(flags)
	{
		case(SND_NOFLAGS):
		{
			// Starting sound..
			for (int client = 1; client <= MaxClients; client++)
			{
				if (!IsClientInGame(client) || g_bStopMapMusic[client])
					continue;

				// Stop the old sound..
				EmitSoundToClient(client, sample, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOPLOOPING, SNDVOL_NORMAL, SNDPITCH_NORMAL);

				// Pass through the new sound..
				EmitSoundToClient(client, sample, entity, SNDCHAN_STATIC, level, flags, volume, pitch);
			}
		}
		default:
		{
			// Nothing special going on.. Pass it through..
			for (int client = 1; client <= MaxClients; client++)
			{
				if (!IsClientInGame(client) || g_bStopMapMusic[client])
					continue;

				EmitSoundToClient(client, sample, entity, SNDCHAN_STATIC, level, flags, volume, pitch);
			}
		}
	}

	// Block the default sound..
	return Plugin_Handled;
}

int GetNextWeaponVolumeStep(int iVolume)
{
	for (int i = 0; i < sizeof(g_iWeaponVolumeSteps); i++)
	{
		if (iVolume > g_iWeaponVolumeSteps[i])
			return g_iWeaponVolumeSteps[i];
	}

	return WEAPON_VOLUME_NORMAL;
}

// Must be called from the "Shotgun Shot" tempent hook, it reads the tempent being sent.
void EmitScaledShootSound(const int[] clients, int numClients)
{
	int iWeaponID = TE_ReadNum("m_iWeaponID");
	if (iWeaponID < 0 || iWeaponID >= sizeof(g_sWeaponShootSounds) || !g_sWeaponShootSounds[iWeaponID][0])
		return;

	char sGameSound[32];
	strcopy(sGameSound, sizeof(sGameSound), g_sWeaponShootSounds[iWeaponID]);

	if (TE_ReadNum("m_iMode") == CSS_SECONDARY_MODE)
	{
		if (iWeaponID == CSS_WEAPON_USP)
			strcopy(sGameSound, sizeof(sGameSound), "Weapon_USP.SilencedShot");
		else if (iWeaponID == CSS_WEAPON_M4A1)
			strcopy(sGameSound, sizeof(sGameSound), "Weapon_M4A1.Silenced");
	}

	// m_iPlayer is the entity index minus one.
	int iShooter = TE_ReadNum("m_iPlayer") + 1;

	float vOrigin[3];
	TE_ReadVector("m_vecOrigin", vOrigin);

	int iChannel, iLevel, iPitch;
	float fVolume;
	char sSample[PLATFORM_MAX_PATH];
	if (!GetGameSoundParams(sGameSound, iChannel, iLevel, fVolume, iPitch, sSample, sizeof(sSample), iShooter))
		return;

	EmitScaledSound(clients, numClients, sSample, iShooter, iChannel, iLevel, SND_NOFLAGS, fVolume, iPitch, vOrigin);
}

// Emits a sound to each client with its own weapon volume, grouping clients sharing the same volume.
void EmitScaledSound(const int[] clients, int numClients, const char[] sample, int entity, int channel, int level, int flags, float volume, int pitch, const float origin[3])
{
	int[] group = new int[numClients];
	bool[] done = new bool[numClients];

	// Our own emits must not be caught again by the normal sound hook.
	g_bEmittingScaledSound = true;

	for (int i = 0; i < numClients; i++)
	{
		if (done[i])
			continue;

		int iVolume = g_iWeaponVolume[clients[i]];
		int groupTotal = 0;

		for (int j = i; j < numClients; j++)
		{
			if (!done[j] && g_iWeaponVolume[clients[j]] == iVolume)
			{
				group[groupTotal++] = clients[j];
				done[j] = true;
			}
		}

		EmitSound(group, groupTotal, sample, entity, channel, level, flags, volume * float(iVolume) / 100.0, pitch, -1, origin);
	}

	g_bEmittingScaledSound = false;
}
