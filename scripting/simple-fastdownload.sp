#include <sourcemod>
#include <sdktools>
#include <webcon>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "simple-fastdownload",
	author = "domino_",
	description = "fastdownload support without webhosting",
	version = "1.2.0",
	url = "https://github.com/neko-pm/simple-fastdownload"
};

char urlpath[PLATFORM_MAX_PATH];
StringMap downloadable_files;
WebResponse response_filenotfound;
ConVar sv_downloadurl;
char downloadurl_backup[PLATFORM_MAX_PATH];
ConVar sv_downloadurl_autoupdate;
ConVar sv_fastdownload_log;
ConVar sv_downloadurl_hostname;
char bz2folder[PLATFORM_MAX_PATH];
ConVar sv_downloadurl_add_mapcycle;
ConVar sv_downloadurl_add_downloadables;
char logpath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	ConVar sv_downloadurl_urlpath = CreateConVar("sv_downloadurl_urlpath", "fastdl", "path for fastdownload url eg: fastdl");
	sv_downloadurl_urlpath.GetString(urlpath, sizeof(urlpath));
	
	if(!Web_RegisterRequestHandler(urlpath, OnWebRequest, urlpath, "https://github.com/neko-pm/simple-fastdownload"))
	{
		SetFailState("Failed to register request handler.");
	}
	
	downloadable_files = new StringMap();
	
	response_filenotfound = new WebStringResponse("Not Found");
	response_filenotfound.AddHeader(WebHeader_ContentType, "text/plain; charset=UTF-8");
	
	sv_downloadurl = FindConVar("sv_downloadurl");
	sv_downloadurl.GetString(downloadurl_backup, sizeof(downloadurl_backup));
	sv_downloadurl.AddChangeHook(OnDownloadUrlChanged);
	
	sv_downloadurl_autoupdate = CreateConVar("sv_downloadurl_autoupdate", "1", "should sv_downloadurl be set automatically");
	sv_downloadurl_autoupdate.AddChangeHook(OnAutoUpdateChanged);
	sv_fastdownload_log = CreateConVar("sv_fastdownload_log", "0", "should simple-fastdownload log downloads from users into the console");
	
	sv_downloadurl_hostname = CreateConVar("sv_downloadurl_hostname", "", "either an empty string, or hostname to use in downloadurl with no trailing slash eg: fastdownload.example.com");
	if(sv_downloadurl_autoupdate.BoolValue)
	{
		sv_downloadurl_hostname.AddChangeHook(OnHostnameChanged);
		
		char hostname[PLATFORM_MAX_PATH];
		sv_downloadurl_hostname.GetString(hostname, sizeof(hostname));
		
		SetFastDownloadUrl(hostname);
	}
	
	ConVar sv_downloadurl_bz2folder = CreateConVar("sv_downloadurl_bz2folder", "", "either an empty string, or base folder for .bz2 files in game root folder eg: bz2");
	sv_downloadurl_bz2folder.GetString(bz2folder, sizeof(bz2folder));
	sv_downloadurl_bz2folder.AddChangeHook(OnBz2FolderChanged);
	
	sv_downloadurl_add_mapcycle = CreateConVar("sv_downloadurl_add_mapcycle", "1", "should all maps in the mapcycle be added to the download whitelist, recommended value: 1");
	
	sv_downloadurl_add_downloadables = CreateConVar("sv_downloadurl_add_downloadables", "1", "should all files in the downloads table be added to the download whitelist, recommended value: 1");
	
	AutoExecConfig();
	
	char date[PLATFORM_MAX_PATH];
	FormatTime(date, sizeof(date), "%Y-%m-%d");
	BuildPath(Path_SM, logpath, sizeof(logpath), "logs/fastdownload_access.%s.log", date);
	
	RegAdminCmd("sm_fastdownload_list_files", FastDownloadListFiles, ADMFLAG_ROOT, "prints a list of all files that are currently in the download whitelist, note: for server console only");
}

public void OnPluginEnd()
{
	sv_downloadurl.RemoveChangeHook(OnDownloadUrlChanged);
	sv_downloadurl.SetString(downloadurl_backup, true, false);
}

public Action FastDownloadListFiles(int client, int args)
{
	if(client == 0)
	{
		StringMapSnapshot snapshot = downloadable_files.Snapshot();
		int length = snapshot.Length;
		
		ArrayList array = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		
		for(int index = 0; index < length; index++)
		{
			int size = snapshot.KeyBufferSize(index);
			char[] filepath = new char[size];
			snapshot.GetKey(index, filepath, size);
			
			array.PushString(filepath);
		}
		
		delete snapshot;
		
		array.Sort(Sort_Ascending, Sort_String);
		
		PrintToServer("downloadable files:");
		for(int index = 0; index < length; index++)
		{
			char filepath[PLATFORM_MAX_PATH];
			array.GetString(index, filepath, sizeof(filepath));
			PrintToServer("  %s", filepath);
		}
		
		delete array;
	}
	else
	{
		ReplyToCommand(client, "this command is for use in the server console only.");
	}
	
	return Plugin_Handled;
}

public void OnDownloadUrlChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(sv_downloadurl_autoupdate.BoolValue)
	{
		char hostname[PLATFORM_MAX_PATH];
		sv_downloadurl_hostname.GetString(hostname, sizeof(hostname));
		
		SetFastDownloadUrl(hostname);
	}
}

public void OnAutoUpdateChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar.BoolValue)
	{
		sv_downloadurl_hostname.AddChangeHook(OnHostnameChanged);
		
		char hostname[PLATFORM_MAX_PATH];
		sv_downloadurl_hostname.GetString(hostname, sizeof(hostname));
		
		SetFastDownloadUrl(hostname);
	}
	else
	{
		sv_downloadurl_hostname.RemoveChangeHook(OnHostnameChanged);
		
		sv_downloadurl.SetString(downloadurl_backup, true, false);
	}
}

public void OnHostnameChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	SetFastDownloadUrl(newValue);
}

public void OnBz2FolderChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	convar.GetString(bz2folder, sizeof(bz2folder));
}

public void SetFastDownloadUrl(const char[] hostname)
{
	char fastdownload_url[PLATFORM_MAX_PATH];
	
	if(hostname[0] == '\0')
	{
		int hostip = FindConVar("hostip").IntValue;
		FormatEx(fastdownload_url, sizeof(fastdownload_url), "http://%d.%d.%d.%d:%d/%s",
			(hostip >> 24) & 0xFF,
			(hostip >> 16) & 0xFF,
			(hostip >> 8 ) & 0xFF,
			hostip         & 0xFF,
			FindConVar("hostport").IntValue,
			urlpath
		);
	}
	else
	{
		FormatEx(fastdownload_url, sizeof(fastdownload_url), "http://%s:%d/%s",
			hostname,
			FindConVar("hostport").IntValue,
			urlpath
		);
	}
	
	sv_downloadurl.SetString(fastdownload_url, true, false);
}

public void OnMapStart()
{
	char current_map[PLATFORM_MAX_PATH];
	if(GetCurrentMap(current_map, sizeof(current_map)))
	{
		char filepath[PLATFORM_MAX_PATH];
		
		FormatEx(filepath, sizeof(filepath), "maps/%s.bsp", current_map);
		AddFileToFileList(filepath);
	}
	
	AddFilesToFileList();
}

public void OnMapEnd()
{
	char next_map[PLATFORM_MAX_PATH];
	if(GetNextMap(next_map, sizeof(next_map)))
	{
		char filepath[PLATFORM_MAX_PATH];
		
		FormatEx(filepath, sizeof(filepath), "maps/%s.bsp", next_map);
		AddFileToFileList(filepath);
	}
	
	AddFilesToFileList();
}

bool AddFileToFileList(const char[] filepath)
{
	if(downloadable_files.SetValue(filepath, false, false))
	{
		char filepath_bz2[PLATFORM_MAX_PATH];
		
		FormatEx(filepath_bz2, sizeof(filepath_bz2), "%s%s.bz2", bz2folder, filepath);
		downloadable_files.SetValue(filepath_bz2, true, false);
	}
}

void AddFilesToFileList()
{
	if(sv_downloadurl_add_mapcycle.BoolValue)
	{
		ArrayList maplist = view_as<ArrayList>(ReadMapList());
		
		if(maplist != INVALID_HANDLE)
		{
			int length = maplist.Length;
			
			if(length > 0)
			{
				for(int index = 0; index < length; index++)
				{
					char mapname[PLATFORM_MAX_PATH];
					maplist.GetString(index, mapname, sizeof(mapname));
					
					char filepath[PLATFORM_MAX_PATH];
		
					FormatEx(filepath, sizeof(filepath), "maps/%s.bsp", mapname);
					AddFileToFileList(filepath);
				}
			}
			
			delete maplist;
		}
	}
	
	if(sv_downloadurl_add_downloadables.BoolValue)
	{
		int downloadables = FindStringTable("downloadables");
		int size = GetStringTableNumStrings(downloadables);
		
		for(int index = 0; index < size; index++)
		{
			char filepath[PLATFORM_MAX_PATH];
			ReadStringTable(downloadables, index, filepath, sizeof(filepath));
			
			int length = GetStringTableDataLength(downloadables, index);
			
			if(length > 0)
				continue;
			
			AddFileToFileList(filepath);
		}
	}
}

public bool OnWebRequest(WebConnection connection, const char[] method, const char[] url)
{
	char address[WEB_CLIENT_ADDRESS_LENGTH];
	connection.GetClientAddress(address, sizeof(address));
	
	bool is_bz2;
	bool is_downloadable = downloadable_files.GetValue(url[1], is_bz2);
	
	char filepath[PLATFORM_MAX_PATH];
	if(is_downloadable)
	{
		if(is_bz2 && bz2folder[0] != '\0')
		{
			FormatEx(filepath, sizeof(filepath), "/%s%s", bz2folder, url);
		}
		else
		{
			strcopy(filepath, sizeof(filepath), url);
		}
		
		if(FileExists(filepath))
		{
			WebResponse response_file = new WebFileResponse(filepath);
			if(response_file != INVALID_HANDLE)
			{
				bool success = connection.QueueResponse(WebStatus_OK, response_file);
				delete response_file;
				
				if(sv_fastdownload_log.BoolValue)
				{
				LogToFileEx(logpath, "%i - %s - %s", (success ? 200 : 500), address, filepath);
				}
				
				return success;
			}
		}
	}
	
	if(sv_fastdownload_log.BoolValue)
	{
	LogToFileEx(logpath, "%i - %s - %s", (is_downloadable ? 404 : 403), address, (is_downloadable ? filepath : url));
	}
	
	return connection.QueueResponse(WebStatus_NotFound, response_filenotfound);
}
