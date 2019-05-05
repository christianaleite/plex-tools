# plex-tools
 The purpose of this project is to provide automation tools for common Plex server administration tasks. These are the tools I have been using for a while now to manage 2 Plex server instances. Some of the options are specific to my setup but they give a general idea on how Plex works and can help you to build your own. 

## Getting Started
 This project consists of bash script files where each function has been document in an effort to help you better understand how it all works.

### Prerequisites

 The programs used by the script’s are commonly found in any linux installation with the exception of sqlite3.

 The script uses a simple configuration file that contains basic information about your server. An example configuration file is provided in the examples directory. Since the script uses the Plex server database for some of its options you need to find where the database file is located.

### Installing

  Simply clone the project and set execution permission the script:

```
git clone https://github.com/christianaleite/plex-tools.git
cd plex-tools
chmod u+x plex-tools.sh
```

 Running the script without arguments will print it usage information to the console.

```
./plex-tools
```
 
 In order to use these function you need to provide a configuration file. The use of configuration files simplifies the creation of cron jobs when using 2 or more Plex servers.

## Deployment
 Before starting make sure to create a backup of your Plex server database. This script was designed to safely access the database to avoid data corruption but I still recommend you have a backup in case things don’t work as expected.

 The main task performed by this script is to synchronize the watched status between multiple Plex servers. It is a 2 step process that each server has to perform.

1. Export watched and unwatched media from each server and publish to all the others.

```
./plex-tools.sh [config file] export_stats
```

2. Create a master list of the media status and update the watched status of the media in the server.

```
./plex-tools.sh [config file] update_stats
```


 The time between tasks will depend on how you publish the files between servers. 

 Information is only read from the Plex server database and all updates are done using the Plex web api. Since user aren’t supposed to access the database directly any modification may result in corruption.

 The rest of the functions are described when the script is executed without options. You can always open the script with a text editor to see how everything works and also view the comments I left. 

 The script may not be elegant but it works.
