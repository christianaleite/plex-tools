#!/bin/bash

#######################################
# Get the GUID of the media that has been watched by a specific account and save result to a temporary file
#
# Globals:
#   WORK_DIRECTORY
#	PLEX_DATABASE
#   PLEX_SERVER_NAME
# Arguments:
#   Plex Account Name
# Returns:
#   None
#######################################
function get_watched {

	sqlite3 -list "$PLEX_DATABASE" "select distinct(item.guid) from accounts account, metadata_items item, metadata_item_settings setting where account.name='$1' and item.metadata_type in (1,4) and (item.guid like 'com.plexapp.agents.imdb%' or item.guid like 'com.plexapp.agents.thetvdb%') and setting.account_id=account.id and setting.guid=item.guid and setting.view_count>0;" > $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-watched
	echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-watched"

}

#######################################
# Get the GUID of the media that has not been watched by a specific account and save result to a temporary file
#
# Globals:
#   WORK_DIRECTORY
#	PLEX_DATABASE
#   PLEX_SERVER_NAME
# Arguments:
#   Plex Account Name
# Returns:
#   None
#######################################
function get_unwatched {

	sqlite3 -list "$PLEX_DATABASE" "select distinct(item.guid) from metadata_items item where item.metadata_type in (1,4) and (item.guid like 'com.plexapp.agents.imdb%' or item.guid like 'com.plexapp.agents.thetvdb%') and item.guid not in (select setting.guid from accounts account, metadata_item_settings setting where account.name='$1' and setting.account_id=account.id and setting.view_count>0);" > $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-unwatched
	echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-unwatched"

}

#######################################
# Create a master watched and unwatched list for a specific user based on the temporary files from all servers
#
# Globals:
#   WORK_DIRECTORY
#   PLEX_SERVER_NAME
# Arguments:
#   Plex Account Name
# Returns:
#   None
#######################################
function merge_server_stats {

	cat $WORK_DIRECTORY/*-$1-watched | sort | uniq -u > $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-watched-merged
	echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-merged-watched"

	cat $WORK_DIRECTORY/*-$1-unwatched | sort | uniq -u > $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-unwatched-merged
	echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-merged-unwatched"

}

#######################################
# Compare an account's local unwatched file with the merged watched file for the same account
# to find out which GUID's must be updated on the local server to match the state of the other plex servers
#
# Globals:
#   WORK_DIRECTORY
#   PLEX_SERVER_NAME
# Arguments:
#   Plex Account Name
# Returns:
#   None
#######################################
function compare_viewed_servers {

	# Find all the guid's that are present in both watched and unwatched temporary files as these are the media that needs to be marked as watched
	cat $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-unwatched $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-watched-merged | sort | uniq -d > $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-update
	echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$1-update"

}

#######################################
# Get the GUID of the media that has been watched by all the accounts on the server and save to a temporary file
# Must generate watched files for the accounts before using this function
#
# Globals:
#   WORK_DIRECTORY
#   PLEX_SERVER_NAME
# Arguments:
#   Plex Account Name
# Returns:
#   None
#######################################
function compare_viewed_accounts {

	# Determine the number of plex accounts by creating an array based on the value of the config file
	IFS=',' read -ra PLEX_ACCOUNTS_ARRAY_TEMP <<< "$PLEX_ACCOUNTS"
	
	# To find the GUID's of the watched media on all of the accounts we must merge the viewed files for the server and check the number
	# of ocurrences for each GUID. If the number of ocurrences is equal to the number of accounts then we found a GUID that is present on all of them
	cat $WORK_DIRECTORY/$PLEX_SERVER_NAME-*-watched | sort | uniq -c | grep "^ *${#PLEX_ACCOUNTS_ARRAY_TEMP[@]}" | cut -d " " -f 8 > $WORK_DIRECTORY/$PLEX_SERVER_NAME-watched-intersection
	echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-watched-intersection"

}

#######################################
# Print the complete file path for a specific GUID
#
# Globals:
#   PLEX_DATABASE
# Arguments:
#   GUID
# Returns:
#   None
#######################################
function get_file_location {

	# Find the id asigned by plex to a specific guid as it required to make a call to the plex api
	media_id=$(sqlite3 -list "$PLEX_DATABASE" "select parts.file from metadata_items metadata, media_items media, media_parts parts where metadata.guid='$1' and media.metadata_item_id=metadata.id and parts.media_item_id=media.id;")

	echo \"$media_id\"

}

#######################################
# Call the Plex Server API to set media as watched
#
# Globals:
#	PLEX_DATABASE
#   PLEX_SERVER_NAME
# Arguments:
#   GUID
# Returns:
#   None
#######################################
function update_watched {
	
	# Find the id asigned by plex to a specific guid as it is required to make the call to the plex api
	media_id=$(sqlite3 -list "$PLEX_DATABASE" "select id from metadata_items item where item.guid='$1';")
	echo "Updating Media Watched Status: $media_id"

	# Call the plex api to scrobble (mark as watched) a specific media file
	curl -s "$PLEX_BASE_URL/:/scrobble?identifier=com.plexapp.plugins.library&X-Plex-Token=$PLEX_TOKEN&key=$media_id"
}

#######################################
# Set script variables based on config file provided
#
# Globals:
#   None
# Arguments:
#   Config File
# Returns:
#   None
#######################################
function load_config {
	# Check if config file exists
	if [ ! -e $1 ]; then
		echo "Configuration file $1 not found."
		exit 1
	fi

	# Load config file values as variables
	source $1
}

#######################################
# Check Plex server token validity
#
# Globals:
#   PLEX_BASE_URL
#	PLEX_TOKEN
# Arguments:
#   None
# Returns:
#   Integer
#######################################
function verify_plex_token {
	token_valid=0

	# Make a request to the plex server using the access token and verify that the reponse does not incluide the word Unauthorized
	# as this would means the token is expired or invalid
	PLEX_TOKEN_TEST=$(curl "$PLEX_BASE_URL/library?X-Plex-Token=$PLEX_TOKEN" 2> /dev/null | grep 'Unauthorized')

	if [ -n "$PLEX_TOKEN_TEST" ]
	then
		token_valid=1
	fi

	return "$token_valid"
}


NOW=$(date +"%d-%b-%Y %T")


if [ $# -ge 2 ]; then
	load_config $1

	case $2 in
			list_user_accounts)
						# Lists the accounts found in the plex database
						sqlite3 -header "$PLEX_DATABASE" "select id, name from accounts;"
						;;
			list_library_sections)
						# Lists the library sections found in the plex database
						sqlite3 -header "$PLEX_DATABASE" "select id, name, section_type from library_sections";
						;;
			list_collections)
						# Lists the collections found in the plex database
						sqlite3 -header "$PLEX_DATABASE" "select id, tag from tags where tag_type=2;";
						;;
           	export_stats)
						# Creates files with the GUID of all the watched and unwatched media grouped by account

						# Creates and array of all the accounts found under PLEX_ACCOUNTS in the configuration file
						IFS=',' read -ra PLEX_ACCOUNTS_ARRAY <<< "$PLEX_ACCOUNTS"

						for (( x=0;x<${#PLEX_ACCOUNTS_ARRAY[@]};x++ ))
						do
							get_watched ${PLEX_ACCOUNTS_ARRAY[x]}
							get_unwatched ${PLEX_ACCOUNTS_ARRAY[x]}
						done
						;;
			update_stats)
						# Updates viewed status of media on the plex server

						# Verify Plex Token is Valid
						verify_plex_token
						token_valid=$?
						if [ "$token_valid" == 0 ]
						then
							
							# Creates and array of all the accounts found under PLEX_ACCOUNTS in the configuration file
							IFS=',' read -ra PLEX_ACCOUNTS_ARRAY <<< "$PLEX_ACCOUNTS"

							for (( x=0;x<${#PLEX_ACCOUNTS_ARRAY[@]};x++ ))
							do
								merge_server_stats ${PLEX_ACCOUNTS_ARRAY[x]}
								compare_viewed_servers ${PLEX_ACCOUNTS_ARRAY[x]}
		
								file="$WORK_DIRECTORY/$PLEX_SERVER_NAME-${PLEX_ACCOUNTS_ARRAY[x]}-update"

								while IFS= read line
								do
									update_watched $line
								done <"$file"
							done
						else
							echo "-----------------------------"
					        echo "WARNING: Plex Token Not Valid ($NOW)"
							echo "-----------------------------"
						fi
						
						;;
			sync_unwatched_files)
						# Search for the unwatched TV Shows in a collection, for the first plex account only, and copy them
						# to the destination directory
						
						# Creates and array of all the accounts found under PLEX_ACCOUNTS in the configuration file
						IFS=',' read -ra PLEX_ACCOUNTS_ARRAY <<< "$PLEX_ACCOUNTS"
						account=${PLEX_ACCOUNTS_ARRAY[x]}

						sqlite3 -list "$PLEX_DATABASE" "select part.file from metadata_items metadata, media_items media, media_parts part where metadata.parent_id in (select id from metadata_items where parent_id in (select id from metadata_items where tags_collection='$PLEX_COLLECTION')) and metadata.guid not in (select setting.guid from accounts account, metadata_item_settings setting where account.name='$account' and setting.account_id=account.id and setting.view_count>0) and media.metadata_item_id=metadata.id and part.media_item_id=media.id;" | sed -r s/.{3}$/*\/ | rev | cut -d "/" -f -4 | rev > $WORK_DIRECTORY/$PLEX_SERVER_NAME-${PLEX_ACCOUNTS_ARRAY[x]}-sync
						echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$account-sync"
						
						cd $SYNC_SOURCE_DIRECTORY

						find . | grep -f $WORK_DIRECTORY/$PLEX_SERVER_NAME-$account-sync | sed  's/ /\\ /g' > $WORK_DIRECTORY/$PLEX_SERVER_NAME-$account-sync-complete
						echo "Created Work File: $WORK_DIRECTORY/$PLEX_SERVER_NAME-$account-sync-complete"

						echo "Syncing files to destination directory ($SYNC_DEST_DIRECTORY)..."

						# Create hard link's in the destination directory of all the media that needs to be synced
						xargs -a $WORK_DIRECTORY/$PLEX_SERVER_NAME-$account-sync-complete cp -ulv --parents --target-directory=$SYNC_DEST_DIRECTORY

						;;
			server_watched_files)
						# Gets the media that has been watched by all the plex accounts in the configuration file
						compare_viewed_accounts

						file="$WORK_DIRECTORY/$PLEX_SERVER_NAME-watched-intersection"

						while IFS= read line
						do
							get_file_location $line
						done <"$file"

						;;
			plex_token)
						verify_plex_token
						token_valid=$?
						if [ "$token_valid" == 0 ]
						then
							echo "Token Valid: $PLEX_TOKEN"
						else
							echo "-----------------------------"
					        echo "WARNING: Plex Token Not Valid ($NOW)"
							echo "-----------------------------"
						fi
						;;
			*)
                       	echo "Invalid Option"
                       	exit 1
                       	;;
	esac


else
	echo "-----------------------------------------------------------------------------------"
    echo "Usage: [config file] [option]"
	echo "-----------------------------------------------------------------------------------"
	echo "list_user_accounts        Lists the accounts found in the plex database"
	echo "list_library_sections     Lists the library sections found in the plex database"
	echo "list_collections          Lists the collections found in the plex database"
	echo "export_stats              Creates files with the GUID of all the watched and unwatched media grouped by account"
	echo "update_stats              Updates viewed status of media on the plex server"
	echo "sync_unwatched_files      Search for the unwatched TV Shows in a collection, for the first plex account only, and copy them to the destination directory"
	echo "server_watched_files      Gets the media that has been watched by all the plex accounts in the configuration file"
    echo "plex_token                Verify and print plex token"
	echo "-----------------------------------------------------------------------------------"
fi

exit 0	


