#include <sourcemod>

#pragma semicolon 1
#pragma newdecls required

Database g_hDatabase = null;

bool isVisible[MAXPLAYERS + 1] =  { true, ... };
int connTime[MAXPLAYERS + 1];
char nextReset[64];

Handle reset = INVALID_HANDLE;
ConVar gcv_Vip, gcv_VipFlag, gcv_Reset, gcv_Minimum;

public Plugin myinfo =  {
	name = "[ANY] Advanced Admin List", 
	author = "StrikeR", 
	description = "", 
	version = "1.0", 
	url = "https://steamcommunity.com/id/kenmaskimmeod/"
}

//-----[ Events ]-----//

public void OnPluginStart()
{
	CreateConVar("adminlist_version", "1.0", "The current plugin version - do not edit!", FCVAR_SPONLY | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	gcv_Vip = CreateConVar("sm_admins_vip", "0", "Should VIPs appear in the admin list? 1 - yes, 0 - no.", _, true, 0.0, true, 1.0);
	gcv_VipFlag = CreateConVar("sm_admins_vipflag", "o", "VIP Flag in letters, as written in admin_levels.cfg");
	gcv_Reset = CreateConVar("sm_admins_resetime", "604800", "Time in seconds to reset admins' activity.", _, true, 0.0);
	gcv_Minimum = CreateConVar("sm_admins_minimum", "420", "Minimum time in minutes for admins to be active on the server.", _, true, 0.0);
	gcv_Reset.AddChangeHook(OnConvarChange);
	
	RegConsoleCmd("sm_admins", Command_Admins, "Show online admins.");
	RegAdminCmd("sm_nextreset", Command_NextReset, ADMFLAG_KICK);
	RegAdminCmd("sm_hours", Command_Hours, ADMFLAG_KICK);
	RegAdminCmd("sm_adminstime", Command_AdminsTime, ADMFLAG_ROOT);
	
	if (SQL_CheckConfig("AdminList"))
		Database.Connect(SQLCallback_Connect, "AdminList");
	else
		SetFailState("[SM] Could not find `AdminList` at databases.cfg");
	
	//if (reset == INVALID_HANDLE)
	//{
	reset = CreateTimer(float(gcv_Reset.IntValue), Timer_Reset, _, TIMER_REPEAT);
	char sTime[64];
	FormatTime(sTime, sizeof(sTime), "%A %d/%m/%G %T", GetTime() + gcv_Reset.IntValue);
	strcopy(nextReset, sizeof(nextReset), sTime);
	PrintToServer("-------------------------------------------\n-------------------------------------------");
	PrintToServer("[Admins] Reset starts at: %s.", sTime);
	PrintToServer("-------------------------------------------\n-------------------------------------------");
	//}
}

public void OnConvarChange(ConVar convar, char[] oldValue, char[] newValue)
{
	if (reset != INVALID_HANDLE)
		KillTimer(reset);
	
	reset = CreateTimer(float(gcv_Reset.IntValue), Timer_Reset, _, TIMER_REPEAT);
	char sTime[64];
	FormatTime(sTime, sizeof(sTime), "%A %d/%m/%G %T", GetTime() + gcv_Reset.IntValue);
	strcopy(nextReset, sizeof(nextReset), sTime);
	PrintToServer("-------------------------------------------\n-------------------------------------------");
	PrintToServer("[Admins] Reset starts at: %s.", sTime);
	PrintToServer("-------------------------------------------\n-------------------------------------------");
}

public void OnClientPostAdminCheck(int client)
{
	if (IsValidClient(client))
	{
		connTime[client] = GetTime();
		
		char auth[32], strQuery[128];
		GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
		FormatEx(strQuery, sizeof(strQuery), "SELECT * FROM admins WHERE steamid = '%s';", auth);
		g_hDatabase.Query(SQLCallback_LoadUser, strQuery, GetClientUserId(client));
	}
}

public void OnClientDisconnect(int client)
{
	if (IsAdmin(client))
	{
		char strQuery[512], auth[32], sTime[64];
		GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
		FormatEx(strQuery, sizeof(strQuery), "SELECT * FROM admins WHERE steamid = '%s';", auth);
		DBResultSet results = SQL_Query(g_hDatabase, strQuery);
		int updatedValue = results.FetchInt(3) + (GetTime() - connTime[client]) / 60;
		FormatTime(sTime, sizeof(sTime), "%A %d/%m/%G %T", GetTime());
		FormatEx(strQuery, sizeof(strQuery), "UPDATE admins SET name = '%N', minutes = %i, lastLogin = '%s' WHERE steamid = '%s';", client, updatedValue, sTime, auth);
		SQL_FastQuery(g_hDatabase, strQuery);
	}
}

//-----[ Commands ]-----//

public Action Command_Hours(int client, int args)
{
	if (!client)
	{
		PrintToServer("This command is in-game only.");
		return Plugin_Handled;
	}
	
	char auth[32], strQuery[128];
	GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
	FormatEx(strQuery, sizeof(strQuery), "SELECT minutes FROM admins WHERE steamid = '%s';", auth);
	g_hDatabase.Query(SQLCallback_LoadHours, strQuery, GetClientUserId(client));
	return Plugin_Handled;
}

public Action Command_NextReset(int client, int args)
{
	if (!client)
	{
		PrintToServer("This command is in-game only.");
		return Plugin_Handled;
	}
	
	PrintToChat(client, "\x04[\x01Admins\x04]\x01 Next activity reset: \x03%s\x01.", nextReset);
	return Plugin_Handled;
}

public Action Command_Admins(int client, int args)
{
	if (!client)
	{
		PrintToServer("This command is in-game only.");
		return Plugin_Handled;
	}
	
	if (!args)
	{
		Menu menu = new Menu(Handler_DoNothing);
		menu.SetTitle("Admins online:");
		
		if (gcv_Vip.BoolValue)
		{
			menu = new Menu(Handler_Admins);
			menu.SetTitle("Admins online:");
			menu.AddItem("vip", "VIPs Online");
			menu.AddItem("X", "----------", 8);
		}
		
		if (IsAdmin(client))
			ShowToAdmin(menu);
		else
			ShowToPlayer(menu);
		
		menu.Display(client, 30);
	}
	else if (IsAdmin(client))
	{
		Menu menu = new Menu(Handler_DoNothing);
		char val[2];
		GetCmdArg(1, val, sizeof(val));
		menu.SetTitle("Visiblity:");
		
		if (val[0] == '1')
		{
			menu.AddItem("X", "You are now visible.");
			isVisible[client] = true;
		}
		else
		{
			menu.AddItem("X", "You are now invisible.");
			isVisible[client] = false;
		}
		
		char auth[32], strQuery[128];
		GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
		FormatEx(strQuery, sizeof(strQuery), "UPDATE admins SET visible = '%s' WHERE steamid = '%s';", val[0], auth);
		SQL_FastQuery(g_hDatabase, strQuery);
		menu.Display(client, 20);
	}
	
	return Plugin_Handled;
}

public Action Command_AdminsTime(int client, int args)
{
	if (!client)
	{
		PrintToServer("This command is in-game only.");
		return Plugin_Handled;
	}
	
	PrintToChat(client, "[SM] See console for output.");
	g_hDatabase.Query(SQLCallback_AdminsList, "SELECT * FROM admins", GetClientUserId(client));
	return Plugin_Handled;
}

public int Handler_Admins(Menu menu, MenuAction action, int client, int Position)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (!Position)
			{
				Menu menu2 = new Menu(Handler_VIP);
				menu2.SetTitle("VIPs Online:");
				
				bool bFounded;
				char Name[MAX_NAME_LENGTH], flag[2];
				gcv_VipFlag.GetString(flag, sizeof(flag));
				int vipflag = GetVIPFlag(flag[0]);
				
				for (int i = 1; i <= MaxClients; i++)
				{
					if (IsClientInGame(i))
					{
						if (CheckCommandAccess(i, "", vipflag, true))
						{
							GetClientName(i, Name, sizeof(Name));
							menu2.AddItem("X", Name);
							
							if (!bFounded)
								bFounded = true;
						}
					}
				}
				
				if (!bFounded)
				{
					menu2.AddItem("no_online", "No VIPs are currently online");
				}
				
				menu2.ExitBackButton = true;
				menu2.Display(client, MENU_TIME_FOREVER);
			}
		}
		
		case MenuAction_End:
		{
			delete menu;
		}
	}
}

public int Handler_DoNothing(Handle menu, MenuAction action, int param1, int param2) {  }

public int Handler_VIP(Handle menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		FakeClientCommand(param1, "say /admins");
	}
}

public Action Timer_Reset(Handle timer)
{
	SQL_FastQuery(g_hDatabase, "UPDATE admins SET minutes = '0';");
	char sTime[64];
	FormatTime(sTime, sizeof(sTime), "%A %d/%m/%G %T", GetTime() + gcv_Reset.IntValue);
	strcopy(nextReset, sizeof(nextReset), sTime);
	PrintToServer("-------------------------------------------\n-------------------------------------------");
	PrintToServer("[Admins] Next reset: %s.", sTime);
	PrintToServer("-------------------------------------------\n-------------------------------------------");
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && IsAdmin(i))
		{
			PrintToChat(i, "\x04[\x01Admins\x04]\x01 Activity has been reset, Next reset: \x03%s\x01.", sTime);
		}
	}
	
	return Plugin_Continue;
}

//-----[ Functions ]-----//

bool IsAdmin(int client)
{
	return CheckCommandAccess(client, "", ADMFLAG_KICK, true);
}

int GetVIPFlag(char flag)
{
	switch(flag)
	{
		case 'a':
		{
			return ADMFLAG_RESERVATION;
		}
		case 'b':
		{
			return ADMFLAG_GENERIC;
		}
		case 'o':
		{
			return ADMFLAG_CUSTOM1;
		}
		case 'p':
		{
			return ADMFLAG_CUSTOM2;
		}
		case 'q':
		{
			return ADMFLAG_CUSTOM3;
		}
		case 'r':
		{
			return ADMFLAG_CUSTOM4;
		}
		case 's':
		{
			return ADMFLAG_CUSTOM5;
		}
	}
	
	return ADMFLAG_CUSTOM6;
}

bool IsValidClient(int client)
{
	return IsClientInGame(client) && !IsFakeClient(client);
}

void ShowToPlayer(Menu &menu)
{
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && IsAdmin(i))
		{
			if (isVisible[i])
			{
				count++;
				if (CheckCommandAccess(i, "", ADMFLAG_ROOT))
				{
					char name[MAX_NAME_LENGTH + 10];
					Format(name, MAX_NAME_LENGTH + 10, "%N *ROOT*", i);
					menu.AddItem("X", name);
				}
				else
				{
					char name[MAX_NAME_LENGTH];
					Format(name, MAX_NAME_LENGTH, "%N", i);
					menu.AddItem("X", name);
				}
			}
		}
	}
	
	if (!count)
	{
		menu.AddItem("X", "No admins are currently online.");
	}
}

void ShowToAdmin(Menu &menu)
{
	char name[MAX_NAME_LENGTH + 20];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && IsAdmin(i))
		{
			if (isVisible[i])
			{
				if (CheckCommandAccess(i, "", ADMFLAG_ROOT))
				{
					Format(name, MAX_NAME_LENGTH + 10, "%N *ROOT*", i);
					menu.AddItem(name, name);
				}
				else
				{
					Format(name, MAX_NAME_LENGTH, "%N", i);
					menu.AddItem(name, name);
				}
			}
			else
			{
				Format(name, MAX_NAME_LENGTH + 20, "[INVISIBLE] %N", i);
				menu.AddItem(name, name);
			}
		}
	}
}

//-----[ SQL ]-----//

public void SQLCallback_Connect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		SetFailState(error);
	}
	
	g_hDatabase = db;
	SQL_FastQuery(g_hDatabase, "CREATE TABLE IF NOT EXISTS admins (id INTEGER PRIMARY KEY AUTOINCREMENT, steamid varchar(32) UNIQUE, name varchar(32), minutes INT, lastLogin varchar(32), visible BOOL)");
}

public void SQLCallback_LoadUser(Database db, DBResultSet results, const char[] strError, int Data)
{
	int client = GetClientOfUserId(Data);
	if (!client)
	{
		return;
	}
	if (strcmp(strError, "") != 0)
	{
		LogError("[Admins] SQL Error ON SQLCallback_LoadUser: %s", strError);
		return;
	}
	if (results.FetchRow() && results.RowCount)
	{
		if (!IsAdmin(client)) // no longer an admin
		{
			char strQuery[128], auth[32];
			GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
			FormatEx(strQuery, sizeof(strQuery), "DELETE FROM admins WHERE steamid = '%s';", auth);
			SQL_FastQuery(g_hDatabase, strQuery);
		}
		else // still admin
		{
			int updatedValue = results.FetchInt(3);
			PrintToChat(client, "[SM] Your activity: %02d:%02d (Minimum %i minutes).", updatedValue / 60, updatedValue % 60, gcv_Minimum.IntValue);
			isVisible[client] = (results.FetchInt(5) == 1);
		}
	}
	else if (!results.RowCount && IsAdmin(client)) // admin joins for the first time after the plugin was installed
	{
		char auth[32], strQuery[256];
		GetClientAuthId(client, AuthId_Steam3, auth, sizeof(auth));
		FormatEx(strQuery, sizeof(strQuery), "INSERT INTO admins (steamid, name, minutes, lastLogin, visible) VALUES ('%s', '%N', '0', '0', '1');", auth, client);
		SQL_FastQuery(g_hDatabase, strQuery);
		
		PrintToChat(client, "[SM] Ahoy there admin! Your activity is being logged starting from now.");
	}
}

public void SQLCallback_AdminsList(Database db, DBResultSet results, const char[] strError, int Data)
{
	int client = GetClientOfUserId(Data);
	
	if (strcmp(strError, "") != 0)
	{
		LogError("[Admins] SQL Error ON SQLCallback_AdminList: %s", strError);
		return;
	}
	
	char name[MAX_NAME_LENGTH], lastSeen[64];
	PrintToConsole(client, "Admins' activity:\n---------------------------------------------------------\n---------------------------------------------------------");
	
	while (results.FetchRow())
	{
		results.FetchString(2, name, sizeof(name));
		results.FetchString(4, lastSeen, sizeof(lastSeen));
		PrintToConsole(client, "%s - %i minutes (lastseen: %s)", name, results.FetchInt(3), lastSeen);
	}
	
	PrintToConsole(client, "---------------------------------------------------------\n---------------------------------------------------------");
}

public void SQLCallback_LoadHours(Database db, DBResultSet results, const char[] strError, int Data)
{
	int client = GetClientOfUserId(Data);
	
	if (strcmp(strError, "") != 0)
	{
		LogError("[Admins] SQL Error ON SQLCallback_LoadHours: %s", strError);
		return;
	}
	
	results.FetchRow();
	int dbTime = results.FetchInt(0);
	PrintToChat(client, "[SM] Your activity: %02d:%02d (+%i minutes when disconnecting).", dbTime / 60, dbTime % 60, RoundToFloor(GetClientTime(client) / 60));
} 