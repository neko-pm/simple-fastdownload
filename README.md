# simple-fastdownload

Provides fastdownload support for srcds without the need for webhosting. By default, it will automatically change the value of `sv_downloadurl` and serve files that are either in the downloadables stringtable or the mapcycle.

By default, if `System2` extension is installed, this will also automatically compress missing .bz2 archives to speed up the downloads further. The compressed files are placed in same folder as the source file.

Files are preprocessed (added to whitelist and compressed) on every mapchange. If you don't change downloads at runtime, you can save some time by setting `sv_downloadurl_autoreload` to 0.

Files inside the custom folder are fully supported.

Configuration file is automatically created at cfg\sourcemod\plugin.simple-fastdownload.cfg.

### Dependencies
* [Conplex & Webcon](https://forums.alliedmods.net/showthread.php?t=270962)
* [(Optional) System2](https://forums.alliedmods.net/showthread.php?t=146019)

### ConVars
ConVar | Default Value | Description 
------ | ------- | --------- 
sv_downloadurl_urlpath | "fastdl" | path for fastdownload url eg: `fastdl`
sv_downloadurl_autoupdate | 1 | should sv_downloadurl be set automatically
sv_downloadurl_hostname | "" | either an empty string, or hostname to use in downloadurl with no trailing slash eg: `fastdownload.example.com`
sv_downloadurl_add_mapcycle | 1 | should all maps in the mapcycle be added to the download whitelist, *recommended value: 1*
sv_downloadurl_add_downloadables | 1 | should all files in the downloads table be added to the download whitelist, *recommended value: 1*
sv_downloadurl_autoreload | 1 | should reload (and compress) files in the download whitelist on each mapchange
sv_downloadurl_compress | 1 | should files in the download whitelist get automatically compressed as bz2 archives; requires System2 extension
sv_downloadurl_compress_max_concurrent | 2 | maximum concurrently compressed files; increasing this value should speed up processing at the cost of higher resource usage (primarily CPU)
sv_downloadurl_log_access | 1 | should all fastDL requests get logged
sv_downloadurl_log_general | 1 | should general info get logged via Sourcemod logging

### Commands
Command | Description
------ | ------
sm_fastdownload_list_files | prints a list of all files that are currently in the download whitelist, *note: for server console only*
