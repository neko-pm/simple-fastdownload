#include <sourcemod>
#include <sdktools>
#include <webcon>

#undef REQUIRE_EXTENSIONS
#define _system2_legacy_included
#include <system2>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "simple-fastdownload",
	author = "domino_",
	description = "fastdownload support without webhosting",
	version = "2.0.0",
	url = "https://github.com/neko-pm/simple-fastdownload"
};

//------------------------------------------------------
// Vars
//------------------------------------------------------

StringMap downloadable_files;
ArrayList paths;
bool files_added;

char urlpath[PLATFORM_MAX_PATH];
char downloadurl_backup[PLATFORM_MAX_PATH];

char logpath[PLATFORM_MAX_PATH];
bool log_access;
bool log_general;

WebResponse response_filenotfound;

ConVar sv_downloadurl;
ConVar sv_downloadurl_autoupdate;
ConVar sv_downloadurl_hostname;
ConVar sv_downloadurl_add_mapcycle;
ConVar sv_downloadurl_add_downloadables;
ConVar sv_downloadurl_autoreload;
ConVar sv_downloadurl_compress;
ConVar sv_downloadurl_compress_max_concurrent;
ConVar sv_downloadurl_log_access;
ConVar sv_downloadurl_log_general;

//------------------------------------------------------
// Forwards
//------------------------------------------------------

public void OnPluginStart()
{
	ConVar sv_downloadurl_urlpath = CreateConVar("sv_downloadurl_urlpath", "fastdl", "path for fastdownload url eg: fastdl");
	sv_downloadurl_urlpath.GetString(urlpath, sizeof(urlpath));
	
	if(!Web_RegisterRequestHandler(urlpath, OnWebRequest, urlpath, "https://github.com/neko-pm/simple-fastdownload"))
	{
		SetFailState("Failed to register request handler.");
	}
	
	downloadable_files = new StringMap();
	paths = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	Compressor.Init();
	
	response_filenotfound = new WebStringResponse("Not Found");
	response_filenotfound.AddHeader(WebHeader_ContentType, "text/plain; charset=UTF-8");
	
	sv_downloadurl = FindConVar("sv_downloadurl");
	sv_downloadurl.GetString(downloadurl_backup, sizeof(downloadurl_backup));
	sv_downloadurl.AddChangeHook(OnDownloadUrlChanged);
	
	sv_downloadurl_autoupdate = CreateConVar("sv_downloadurl_autoupdate", "1", "should sv_downloadurl be set automatically", _, true, 0.0, true, 1.0);
	sv_downloadurl_autoupdate.AddChangeHook(OnAutoUpdateChanged);

	sv_downloadurl_hostname = CreateConVar("sv_downloadurl_hostname", "", "either an empty string, or hostname to use in downloadurl with no trailing slash eg: fastdownload.example.com");
	if(sv_downloadurl_autoupdate.BoolValue)
	{
		sv_downloadurl_hostname.AddChangeHook(OnHostnameChanged);
		
		char hostname[PLATFORM_MAX_PATH];
		sv_downloadurl_hostname.GetString(hostname, sizeof(hostname));
		
		SetFastDownloadUrl(hostname);
	}
	
	sv_downloadurl_add_mapcycle = CreateConVar("sv_downloadurl_add_mapcycle", "1", "should all maps in the mapcycle be added to the download whitelist, recommended value: 1", _, true, 0.0, true, 1.0);
	sv_downloadurl_add_downloadables = CreateConVar("sv_downloadurl_add_downloadables", "1", "should all files in the downloads table be added to the download whitelist, recommended value: 1", _, true, 0.0, true, 1.0);
	sv_downloadurl_autoreload = CreateConVar("sv_downloadurl_autoreload", "1", "should reload (and compress) files in the download whitelist on each mapchange", _, true, 0.0, true, 1.0);
	
	sv_downloadurl_compress = CreateConVar("sv_downloadurl_compress", "1", "should files in the download whitelist get automatically compressed as bz2 archives; requires System2 extension", _, true, 0.0, true, 1.0);
	sv_downloadurl_compress_max_concurrent = CreateConVar("sv_downloadurl_compress_max_concurrent", "2", "maximum concurrently compressed files; increasing this value should speed up processing at the cost of higher resource usage (primarily CPU)", _, true, 1.0);
	sv_downloadurl_compress_max_concurrent.AddChangeHook(OnCompressMaxConcurrentChanged);
	Compressor.SetMaxConcurrent(sv_downloadurl_compress_max_concurrent.IntValue);

	sv_downloadurl_log_access = CreateConVar("sv_downloadurl_log_access", "1", "should all fastDL requests get logged", _, true, 0.0, true, 1.0);
	sv_downloadurl_log_access.AddChangeHook(OnLogAccessChanged);
	log_access = sv_downloadurl_log_access.BoolValue;

	sv_downloadurl_log_general = CreateConVar("sv_downloadurl_log_general", "1", "should general info get logged via Sourcemod logging", _, true, 0.0, true, 1.0);
	sv_downloadurl_log_general.AddChangeHook(OnLogGeneralChanged);
	log_general = sv_downloadurl_log_general.BoolValue;
	
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

public void OnConfigsExecuted()
{
	if (!files_added || sv_downloadurl_autoreload.BoolValue)
	{
		files_added = false;
		downloadable_files.Clear();
		paths.Clear();
		Compressor.ClearQueue();

		BuildPaths();
		CreateTimer(0.2, Timer_AddFilesFallback, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	char current_map[PLATFORM_MAX_PATH];
	if (GetCurrentMap(current_map, sizeof(current_map)))
	{
		char filepath[PLATFORM_MAX_PATH];

		FormatEx(filepath, sizeof(filepath), "maps/%s.bsp", current_map);
		AddFileToFileList(filepath);
	}
	
	if (files_added)
	{
		// reloads are off, resume compressing
		if (sv_downloadurl_compress.BoolValue && LibraryExists("system2"))
		{
			Compressor.Start();	
		}
	}
}

public void OnMapEnd()
{
	Compressor.Pause();
}

public void OnClientConnected(int client)
{
	if (!files_added && !IsFakeClient(client))
	{
		AddFilesToFileList();
		files_added = true;
	}
}

// fallback used to whitelist files when no clients are connected,
// but after plugins have had a chance to add their files to downloadables
public void Timer_AddFilesFallback(Handle timer)
{
	if (!files_added)
	{
		AddFilesToFileList();
		files_added = true;
	}
}

//------------------------------------------------------
// Commands | Convars
//------------------------------------------------------

public Action FastDownloadListFiles(int client, int args)
{
	if(client == 0)
	{
		StringMapSnapshot snapshot = downloadable_files.Snapshot();
		int length = snapshot.Length;
		
		ArrayList array = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
		
		char path[PLATFORM_MAX_PATH], filepath[PLATFORM_MAX_PATH];
		for(int index = 0, path_index; index < length; index++)
		{
			snapshot.GetKey(index, filepath, sizeof(filepath));
			downloadable_files.GetValue(filepath, path_index);
			if (paths.GetString(path_index, path, sizeof(path)))
			{
				Format(filepath, sizeof(filepath), "%s%s", path, filepath);
			}
			array.PushString(filepath);
		}
		
		delete snapshot;
		
		array.Sort(Sort_Ascending, Sort_String);
		
		PrintToServer("downloadable files:");
		for(int index = 0; index < length; index++)
		{
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

public void OnLogAccessChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	log_access = convar.BoolValue;
}

public void OnLogGeneralChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	log_general = convar.BoolValue;
}

public void OnCompressMaxConcurrentChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	Compressor.SetMaxConcurrent(convar.IntValue);
}

//------------------------------------------------------
// File whitelisting
//------------------------------------------------------

void BuildPaths()
{
	char path[PLATFORM_MAX_PATH];
	FileType type;
	DirectoryListing custom = OpenDirectory("custom");
	if (custom)
	{
		while (custom.GetNext(path, sizeof(path), type))
		{
			if (type == FileType_Directory && !StrEqual(path, ".") && !StrEqual(path, ".."))
			{
				Format(path, sizeof(path), "custom/%s/", path);
				paths.PushString(path);
			}
		}
		delete custom;
	}
	paths.PushString(""); // root is last
}

void AddFileToFileList(const char filepath[PLATFORM_MAX_PATH])
{
	int pathId;
	if (AddFileToFileListAllPaths(filepath, pathId))
	{
		char filepath_bz2[PLATFORM_MAX_PATH];
		FormatEx(filepath_bz2, sizeof(filepath_bz2), "%s.bz2", filepath);
		if (!AddFileToFileListAllPaths(filepath_bz2))
		{
			char path[PLATFORM_MAX_PATH];
			paths.GetString(pathId, path, sizeof(path));
			Compressor.AddToQueue(path, filepath);
		}
	}
}

bool AddFileToFileListAllPaths(const char[] filepath, int &pathId = -1)
{
	char path[PLATFORM_MAX_PATH];
	int paths_len = paths.Length;
	for (int i = 0; i < paths_len; i++)
	{
		paths.GetString(i, path, sizeof(path));
		Format(path, sizeof(path), "%s%s", path, filepath);
		if (FileExists(path))
		{
			pathId = i;
			return downloadable_files.SetValue(filepath, i, false);
		}
	}
	return false;
}

void AddFilesToFileList()
{
	float start = GetEngineTime();
	
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
			
			ReplaceString(filepath, sizeof(filepath), "\\", "/");
			AddFileToFileList(filepath);
		}
	}
	
	if (log_general) LogMessage("Whitelisting files took %.2fs.", GetEngineTime() - start);

	if (sv_downloadurl_compress.BoolValue && LibraryExists("system2"))
	{
		Compressor.Start(true);
	}
}

//------------------------------------------------------
// BZ2 Compressor
//------------------------------------------------------

enum struct CompressorQueueEntry
{
	char path[PLATFORM_MAX_PATH];
	char filepath[PLATFORM_MAX_PATH];
}

enum CompressorState
{
	COMPRESSOR_PAUSED,
	COMPRESSOR_RUNNING,
	COMPRESSOR_RESTARTING /* Wait for active processes to finish and resume */
}

ArrayStack compressor_queue;
int compressor_count;
int compressor_max_concurrent;
CompressorState compressor_state;

methodmap Compressor
{
	public static void Init()
	{
		compressor_queue = new ArrayStack(sizeof(CompressorQueueEntry));
	}

	public static void AddToQueue(const char path[PLATFORM_MAX_PATH], const char filepath[PLATFORM_MAX_PATH])
	{
		CompressorQueueEntry entry;
		entry.path = path;
		entry.filepath = filepath;
		compressor_queue.PushArray(entry);
	}

	public static void ClearQueue()
	{
		compressor_queue.Clear();
	}
	
	public static void Start(bool waitUntilOngoingFinish = false)
	{
		if (waitUntilOngoingFinish && compressor_count)
		{
			compressor_state = COMPRESSOR_RESTARTING;
		}
		else
		{
			compressor_state = COMPRESSOR_RUNNING;
			Compressor.CompressFiles();
		}
	}

	public static void Pause()
	{
		compressor_state = COMPRESSOR_PAUSED;
	}

	public static void SetMaxConcurrent(int max_concurrent)
	{
		compressor_max_concurrent = max_concurrent;
	}

	public static void CompressFiles()
	{
		while (!compressor_queue.Empty)
		{
			if (compressor_count >= compressor_max_concurrent)
				return;
			
			char filepath[PLATFORM_MAX_PATH], archive[PLATFORM_MAX_PATH];
			CompressorQueueEntry entry;
			compressor_queue.PopArray(entry);
			FormatEx(filepath, sizeof(filepath), "%s%s", entry.path, entry.filepath);
			FormatEx(archive, sizeof(archive), "%s.bz2", filepath);

			DataPack data = new DataPack();
			if (System2_Compress(CompressCallback, filepath, archive, ARCHIVE_BZIP2, LEVEL_9, data))
			{
				data.WriteString(entry.path);
				data.WriteString(archive);
				compressor_count++;
				if (log_general) LogMessage("Compressing archive: \"%s\"", archive);
			}
			else
			{
				delete data;
				LogError("Compressing archive failed - check System2 extension: \"%s\"", archive);
			}
		}
		if (!compressor_count)
		{
			if (log_general) LogMessage("All whitelisted downloads are compressed.");
		}
	}
}

void CompressCallback(bool success, const char[] command, System2ExecuteOutput output, DataPack data)
{
	if (!success || output.ExitStatus)
	{
		LogError("Compressing archive failed (%s)", command);
	}
	else
	{
		data.Reset();
		char path[PLATFORM_MAX_PATH];
		data.ReadString(path, sizeof(path));
		int pathId = FindStringInArray(paths, path);
		if (pathId != -1)
		{
			char archive[PLATFORM_MAX_PATH];
			data.ReadString(archive, sizeof(archive));
			downloadable_files.SetValue(archive, pathId, false);
		}
	}
	delete data;
	compressor_count--;
	
	if (compressor_state == COMPRESSOR_RUNNING)
	{
		Compressor.CompressFiles();
	}
	else if (compressor_state == COMPRESSOR_RESTARTING && !compressor_count)
	{
		compressor_state = COMPRESSOR_RUNNING;
		Compressor.CompressFiles();
	}
}

//------------------------------------------------------
// Request handler
//------------------------------------------------------

public bool OnWebRequest(WebConnection connection, const char[] method, const char[] url)
{
	char address[WEB_CLIENT_ADDRESS_LENGTH];
	connection.GetClientAddress(address, sizeof(address));
	
	int path_index;
 	bool is_downloadable = downloadable_files.GetValue(url[1], path_index);
	
	char filepath[PLATFORM_MAX_PATH];
	if (is_downloadable)
	{
		char path[PLATFORM_MAX_PATH];
		if (paths.GetString(path_index, path, sizeof(path)))
		{
			FormatEx(filepath, sizeof(filepath), "/%s%s", path, url);
		}
		else
		{
			strcopy(filepath, sizeof(filepath), url);
		}
		
		if (FileExists(filepath))
		{
			WebResponse response_file = new WebFileResponse(filepath);
			if (response_file != INVALID_HANDLE)
			{
				bool success = connection.QueueResponse(WebStatus_OK, response_file);
				delete response_file;

				if (log_access) LogToFileEx(logpath, "%i - %s - %s", (success ? 200 : 500), address, filepath);
				
				return success;
			}
		}
	}
	
	if (log_access) LogToFileEx(logpath, "%i - %s - %s", (is_downloadable ? 404 : 403), address, (is_downloadable ? filepath : url));
	
	return connection.QueueResponse(WebStatus_NotFound, response_filenotfound);
}

//------------------------------------------------------
// Utils
//------------------------------------------------------

void SetFastDownloadUrl(const char[] hostname)
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