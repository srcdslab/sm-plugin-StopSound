#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <clientprefs>
#include <multicolors>

#define PLUGIN_VERSION "3.1.0"

bool g_bStopWeaponSounds[MAXPLAYERS+1] = { false, ... };
bool g_bStopMapMusic[MAXPLAYERS+1] = { false, ... };

bool g_bStopWeaponSoundsHooked = false;
bool g_bStopMapMusicHooked = false;

StringMap g_MapMusic;

Handle g_hCookieStopSound = null;
Handle g_hCookieStopMapMusic = null;

public Plugin myinfo =
{
	name = "Toggle Game Sounds",
	author = "GoD-Tony, edit by Obus + BotoX, Oleg Tsvetkov",
	description = "Allows clients to stop hearing weapon sounds and map music",
	version = PLUGIN_VERSION,
	url = "http://www.sourcemod.net/"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(GetEngineVersion() != Engine_CSGO && GetEngineVersion() != Engine_CSS)
	{
		strcopy(error, err_max, "This plugin supports only CS:GO and CS:S!");
		return APLRes_Failure;
	}

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

	CreateConVar("sm_stopsound_version", PLUGIN_VERSION, "Toggle Weapon Sounds", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_REPLICATED);
	RegConsoleCmd("sm_stopsound", Command_StopSound, "Toggle hearing weapon sounds");
	RegConsoleCmd("sm_sound", Command_StopSound, "Toggle hearing weapon sounds");
	RegConsoleCmd("sm_stopmusic", Command_StopMusic, "Toggle hearing map music");
	RegConsoleCmd("sm_music", Command_StopMusic, "Toggle hearing map music");

	// Cookies
	g_hCookieStopSound = RegClientCookie("weaponsound_blocked", "Are weapon sounds enabled", CookieAccess_Protected);
	g_hCookieStopMapMusic = RegClientCookie("mapmusic_blocked", "Are map music enabled", CookieAccess_Protected);

	SetCookieMenuItem(CookieMenuHandler_StopSounds, 0, "Stop sounds");

	// Suppress reload sound effects
	UserMsg ReloadEffect = GetUserMessageId("ReloadEffect");

	// Game-specific setup
	if(GetEngineVersion() == Engine_CSGO)
	{
		// Weapon sounds will be caught here.
		AddNormalSoundHook(Hook_NormalSound_CSGO);

		if(ReloadEffect != INVALID_MESSAGE_ID)
		{
			HookUserMessage(ReloadEffect, Hook_ReloadEffect_CSGO, true);
		}
	}
	else // CS:S
	{
		// Weapon sounds will be caught here.
		AddNormalSoundHook(Hook_NormalSound_CSS);

		if(ReloadEffect != INVALID_MESSAGE_ID)
		{
			HookUserMessage(ReloadEffect, Hook_ReloadEffect_CSS, true);
		}
	}

	// Late load
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client) && AreClientCookiesCached(client))
		{
			OnClientCookiesCached(client);
		}
	}
}

public void OnPluginEnd()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
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
	if(GetEngineVersion() == Engine_CSGO)
	{
		RemoveNormalSoundHook(Hook_NormalSound_CSGO);

		if(ReloadEffect != INVALID_MESSAGE_ID)
			UnhookUserMessage(ReloadEffect, Hook_ReloadEffect_CSGO, true);
	}
	else
	{
		RemoveNormalSoundHook(Hook_NormalSound_CSS);

		if(ReloadEffect != INVALID_MESSAGE_ID)
			UnhookUserMessage(ReloadEffect, Hook_ReloadEffect_CSS, true);
	}
}

public void OnMapStart()
{
	g_MapMusic.Clear();
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_MapMusic.Clear();
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsClientInGame(client) || GetClientTeam(client) <= CS_TEAM_SPECTATOR)
		return;

	if(g_bStopWeaponSounds[client])
		CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds disabled");

	if(g_bStopMapMusic[client])
		CPrintToChat(client, "%t %t", "Chat Prefix", "Map music disabled");
}

public Action Command_StopSound(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	g_bStopWeaponSounds[client] = !g_bStopWeaponSounds[client];
	CheckWeaponSoundsHooks();

	if(g_bStopWeaponSounds[client])
	{
		SetClientCookie(client, g_hCookieStopSound, "1");
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Weapon sounds disabled");
	}
	else
	{
		SetClientCookie(client, g_hCookieStopSound, "");
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Weapon sounds enabled");
	}

	return Plugin_Handled;
}

public Action Command_StopMusic(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "[SM] Cannot use command from server console.");
		return Plugin_Handled;
	}

	g_bStopMapMusic[client] = !g_bStopMapMusic[client];
	CheckMapMusicHooks();

	if(g_bStopMapMusic[client])
	{
		SetClientCookie(client, g_hCookieStopMapMusic, "1");
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Map music disabled");
		StopMapMusic(client);
	}
	else
	{
		SetClientCookie(client, g_hCookieStopMapMusic, "");
		CReplyToCommand(client, "%t %t", "Chat Prefix", "Map music enabled");
	}

	return Plugin_Handled;
}

public void OnClientCookiesCached(int client)
{
	char sBuffer[2];

	// Weapon Sounds cookie
	GetClientCookie(client, g_hCookieStopSound, sBuffer, sizeof(sBuffer));

	if(sBuffer[0] != '\0')
	{
		g_bStopWeaponSounds[client] = true;
		g_bStopWeaponSoundsHooked = true;
	}
	else
		g_bStopWeaponSounds[client] = false;

	// Map Music cookie
	GetClientCookie(client, g_hCookieStopMapMusic, sBuffer, sizeof(sBuffer));

	if(sBuffer[0] != '\0')
	{
		g_bStopMapMusic[client] = true;
		g_bStopMapMusicHooked = true;
	}
	else
		g_bStopMapMusic[client] = false;
}

public void OnClientDisconnect(int client)
{
	g_bStopWeaponSounds[client] = false;
	g_bStopMapMusic[client] = false;

	CheckWeaponSoundsHooks();
	CheckMapMusicHooks();
}

void CheckWeaponSoundsHooks()
{
	bool bShouldHook = false;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(g_bStopWeaponSounds[i])
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

	for(int i = 1; i <= MaxClients; i++)
	{
		if(g_bStopMapMusic[i])
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
	for(int i = 0; i < MapMusicSnap.Length; i++)
	{
		MapMusicSnap.GetKey(i, sEntity, sizeof(sEntity));

		if((entity = EntRefToEntIndex(StringToInt(sEntity))) == INVALID_ENT_REFERENCE)
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
	if(action == CookieMenuAction_DisplayOption)
	{
		Format(buffer, maxlen, "%T", "Cookie Menu Stop Sounds", client);
	}
	else if(action == CookieMenuAction_SelectOption)
	{
		ShowStopSoundsSettingsMenu(client);
	}
}

void ShowStopSoundsSettingsMenu(int client)
{
	Menu menu = new Menu(MenuHandler_StopSoundsSettings);

	menu.SetTitle("%T", "Cookie Menu Stop Sounds Title", client);

	char sBuffer[128];

	Format(sBuffer, sizeof(sBuffer), "%T%T", "Weapon Sounds", client, g_bStopWeaponSounds[client] ? "Disabled" : "Enabled", client);
	menu.AddItem("0", sBuffer);

	Format(sBuffer, sizeof(sBuffer), "%T%T", "Map Sounds", client, g_bStopMapMusic[client] ? "Disabled" : "Enabled", client);
	menu.AddItem("1", sBuffer);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_StopSoundsSettings(Menu menu, MenuAction action, int client, int selection)
{
	if(action == MenuAction_Cancel)
	{
		ShowCookieMenu(client);
	}
	else if(action == MenuAction_Select)
	{
		if(selection == 0)
		{
			g_bStopWeaponSounds[client] = !g_bStopWeaponSounds[client];
			CheckWeaponSoundsHooks();

			if(g_bStopWeaponSounds[client])
			{
				SetClientCookie(client, g_hCookieStopSound, "1");
				CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds disabled");
			}
			else
			{
				SetClientCookie(client, g_hCookieStopSound, "");
				CPrintToChat(client, "%t %t", "Chat Prefix", "Weapon sounds enabled");
			}

		}
		else if(selection == 1)
		{
			g_bStopMapMusic[client] = !g_bStopMapMusic[client];
			CheckMapMusicHooks();

			if(g_bStopMapMusic[client])
			{
				SetClientCookie(client, g_hCookieStopMapMusic, "1");
				CPrintToChat(client, "%t %t", "Chat Prefix", "Map music disabled");
				StopMapMusic(client);
			}
			else
			{
				SetClientCookie(client, g_hCookieStopMapMusic, "");
				CPrintToChat(client, "%t %t", "Chat Prefix", "Map music enabled");
			}
		}

		ShowStopSoundsSettingsMenu(client);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}
}

public Action Hook_NormalSound_CSS(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	// Ignore non-weapon sounds.
	if(channel != SNDCHAN_WEAPON &&
		!(channel == SNDCHAN_AUTO && strncmp(sample, "physics/flesh", 13) == 0) &&
		!(channel == SNDCHAN_VOICE && StrContains(sample, "player/headshot", true) != -1))
	{
		return Plugin_Continue;
	}

	int j = 0;
	for(int i = 0; i < numClients; i++)
	{
		int client = clients[i];
		if(!g_bStopWeaponSounds[client] && IsClientInGame(client))
		{
			// Keep client.
			clients[j] = clients[i];
			j++;
		}
	}

	numClients = j;

	return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
}

public Action Hook_NormalSound_CSGO(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH],
	  int &entity, int &channel, float &volume, int &level, int &pitch, int &flags,
	  char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	// Ignore non-weapon sounds.
	if(channel != SNDCHAN_WEAPON &&
		!(channel == SNDCHAN_AUTO && strncmp(sample, "physics/flesh", 13) == 0) &&
		!(channel == SNDCHAN_STATIC && StrContains(sample, "player/headshot", true) != -1))
	{
		return Plugin_Continue;
	}

	int j = 0;
	for(int i = 0; i < numClients; i++)
	{
		int client = clients[i];
		if(!g_bStopWeaponSounds[client] && IsClientInGame(client))
		{
			// Keep client.
			clients[j] = clients[i];
			j++;
		}
	}

	numClients = j;

	return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
}

public Action Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	// Check which clients need to be excluded.
	int[] newClients = new int[numClients];
	int newTotal = 0;

	for(int i = 0; i < numClients; i++)
	{
		if(!g_bStopWeaponSounds[Players[i]])
		{
			newClients[newTotal++] = Players[i];
		}
	}

	if(newTotal == numClients)
	{
		// No clients were excluded.
		return Plugin_Continue;
	}
	else if(newTotal == 0)
	{
		// All clients were excluded and there is no need to broadcast.
		return Plugin_Stop;
	}

	// Re-broadcast to clients that still need it.
	if(GetEngineVersion() == Engine_CSGO)
	{
		float vTemp[3];
		TE_Start("Shotgun Shot");
		TE_ReadVector("m_vecOrigin", vTemp);
		TE_WriteVector("m_vecOrigin", vTemp);
		TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
		TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
		TE_WriteNum("m_weapon", TE_ReadNum("m_weapon"));
		TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
		TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
		TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
		TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
		TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
		TE_Send(newClients, newTotal, delay);
	}
	else
	{
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
	}

	return Plugin_Stop;
}

public Action Hook_ReloadEffect_CSS(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	int client = msg.ReadShort();

	// Check which clients need to be excluded.
	int[] newClients = new int[playersNum];
	int newTotal = 0;

	for(int i = 0; i < playersNum; i++)
	{
		int client_ = players[i];
		if(IsClientInGame(client_) && !g_bStopWeaponSounds[client_])
		{
			newClients[newTotal++] = client_;
		}
	}

	if(newTotal == playersNum)
	{
		// No clients were excluded.
		return Plugin_Continue;
	}
	else if(newTotal == 0)
	{
		// All clients were excluded and there is no need to broadcast.
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(newTotal);

	for(int i = 0; i < newTotal; i++)
	{
		pack.WriteCell(newClients[i]);
	}

	RequestFrame(OnReloadEffect, pack);

	return Plugin_Handled;
}

public Action Hook_ReloadEffect_CSGO(UserMsg msg_id, Protobuf msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!g_bStopWeaponSoundsHooked)
		return Plugin_Continue;

	int client = PbReadInt(msg, "entidx");

	// Check which clients need to be excluded.
	int[] newClients = new int[playersNum];
	int newTotal = 0;

	for(int i = 0; i < playersNum; i++)
	{
		int client_ = players[i];
		if(IsClientInGame(client_) && !g_bStopWeaponSounds[client_])
		{
			newClients[newTotal++] = client_;
		}
	}

	if(newTotal == playersNum)
	{
		// No clients were excluded.
		return Plugin_Continue;
	}
	else if(newTotal == 0)
	{
		// All clients were excluded and there is no need to broadcast.
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(client);
	pack.WriteCell(newTotal);

	for(int i = 0; i < newTotal; i++)
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
	int newTotal = pack.ReadCell();

	int[] players = new int[newTotal];
	int playersNum = 0;

	for(int i = 0; i < newTotal; i++)
	{
		int client_ = pack.ReadCell();
		if(IsClientInGame(client_))
		{
			players[playersNum++] = client_;
		}
	}

	CloseHandle(pack);

	Handle ReloadEffect = StartMessage("ReloadEffect", players, playersNum, USERMSG_RELIABLE | USERMSG_BLOCKHOOKS);
	if(GetFeatureStatus(FeatureType_Native, "GetUserMessageType") == FeatureStatus_Available && GetUserMessageType() == UM_Protobuf)
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
	if(!strncmp(sample, "music", 5, false) && !strncmp(sample, "#", 1, false))
		return Plugin_Continue;

	char sEntity[16];
	IntToString(EntIndexToEntRef(entity), sEntity, sizeof(sEntity));

	g_MapMusic.SetString(sEntity, sample, true);

	if(!g_bStopMapMusicHooked)
		return Plugin_Continue;

	switch(flags)
	{
		case(SND_NOFLAGS):
		{
			// Starting sound..
			for(int client = 1; client <= MaxClients; client++)
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
			for(int client = 1; client <= MaxClients; client++)
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