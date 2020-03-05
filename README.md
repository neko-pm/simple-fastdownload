# simple-fastdownload

Provides fastdownload support for srcds without the need for webhosting.

### Requirements
[Conplex & Webcon](https://forums.alliedmods.net/showthread.php?t=270962)

### ConVars
ConVar | Default Value | Description 
------ | ------- | --------- 
sv_downloadurl_urlpath | "fastdl" | path for fastdownload url eg: `fastdl`
sv_downloadurl_autoupdate | 1 | should sv_downloadurl be set automatically
sv_downloadurl_hostname | "" | either empty string, or hostname to use in downloadurl with no trailing slash eg: `fastdownload.example.com`
sv_downloadurl_bz2folder | "" | either empty string, or base folder for bz2 files with trailing slash eg: `bz2/`

### Commands
Command | Desciption
------ | ------
sm_fastdownload_list_files | prints a list of all files that are currently in the download whitelist, *note: for server console only*
