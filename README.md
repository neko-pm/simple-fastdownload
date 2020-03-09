# simple-fastdownload

Provides fastdownload support for srcds without the need for webhosting. By default, it will automatically change the value of `sv_downloadurl` and serve files that are either in the downloadables stringtable or the mapcycle.

From here you can either leave it as is or begin to add bzip2 compressed versions of the files. These can either be in the same location as their non-compressed versions, or separately within the folder specified by `sv_downloadurl_bz2folder`.

### Requirements
* [Conplex & Webcon](https://forums.alliedmods.net/showthread.php?t=270962)

### ConVars
ConVar | Default Value | Description 
------ | ------- | --------- 
sv_downloadurl_urlpath | "fastdl" | path for fastdownload url eg: `fastdl`
sv_downloadurl_autoupdate | 1 | should sv_downloadurl be set automatically
sv_downloadurl_hostname | "" | either an empty string, or hostname to use in downloadurl with no trailing slash eg: `fastdownload.example.com`
sv_downloadurl_bz2folder | "" | either an empty string, or base folder for .bz2 files in game root folder eg: `bz2`
sv_downloadurl_add_mapcycle | 1 | should all maps in the mapcycle be added to the download whitelist, *recommended value: 1*
sv_downloadurl_add_downloadables | 1 | should all files in the downloads table be added to the download whitelist, *recommended value: 1*

### Commands
Command | Description
------ | ------
sm_fastdownload_list_files | prints a list of all files that are currently in the download whitelist, *note: for server console only*
