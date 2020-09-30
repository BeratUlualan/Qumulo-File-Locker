#!/bin/bash

dbDirectory="/history/protector"
credentialsFile="credentials.json"
protectedFiles="protectedFiles.json"

for protectionPolicy in $(jq -r '.main_credentials|.[]|select(.protection_enablement=="yes")|.protection_policy' $dbDirectory'/'$credentialsFile)
do
		
	dbDirectory=$(jq -r --arg protectionPolicy "$protectionPolicy" '.main_credentials|.[]|select (.protection_policy==$protectionPolicy)|.db_directory'  $dbDirectory'/'$credentialsFile)
	protectedDirectory=$(jq -r --arg protectionPolicy "$protectionPolicy" '.main_credentials|.[]|select (.protection_policy==$protectionPolicy)|.protected_directory' $dbDirectory'/'$credentialsFile)	
	echo $protectedDirectory
	protectorSID=$(jq -r --arg protectionPolicy "$protectionPolicy" '.main_credentials|.[]|select (.protection_policy==$protectionPolicy)|.protection_user_sid'  $dbDirectory'/'$credentialsFile)
	currentTime=$(date)
		
	for fileID in $(qq fs_walk_tree --path $protectedDirectory|jq -r '.[]|.[]|.id')
	do
		fileType=$(qq fs_file_get_attr --id $fileID|jq -r .type)

		if [[ $fileType == "FS_FILE_TYPE_FILE" ]]
		then
			existingFileCheck=$(jq -r '.original_file_permissions|.[]|select(.file_id=="'$fileID'")|.file_id' $dbDirectory'/'$protectedFiles)
			
			if [[ -z $existingFileCheck ]]
			then
			
				modTime=$(qq fs_file_get_attr --id $fileID|jq -r '.modification_time')
				timeDiff=$(( $(date -d"$currentTime" +%s) - $(date -d"$modTime" +%s)))
				if [[ $timeDiff -ge 10 ]]
				then
						# md5Hash=$(echo -n $fileID | md5sum | cut -f1 -d' ')
						# originalAttrFile=$(echo -n $dbDirectory'/'$md5Hash.attr)
						# originalACLFile=$(echo -n $dbDirectory'/'$md5Hash.acl)
						# qq fs_file_get_attr --id $fileID > $originalAttrFile
						# qq fs_get_acl --id $fileID --json > $originalACLFile
						
					declare -a fileSIDs=$(qq fs_get_acl --id $fileID --json|jq -r '.aces|.[]|.trustee|.sid')
						
					file=$(qq fs_resolve_paths --id $fileID|jq -r '.[].path')
					echo $file

					for userSID in ${fileSIDs[@]}
					do
						qq fs_modify_acl --id $fileID modify_entry --old-trustee sid:$userSID --new-rights "Read, Read ACL, Read EA, Read attr, Read contents, Synchronize"
					done
						
					qq fs_file_set_smb_attrs --id $fileID --read-only true
					qq fs_file_set_attr --id $fileID  --owner-sid $protectorSID
						
					qq fs_modify_acl --id $fileID add_entry --trustee sid:S-1-3-4 --type Denied --rights Write ACL
					qq fs_modify_acl --id $fileID add_entry --trustee sid:$protectorSID --type Allowed --rights "Read, Read ACL, Read EA, Read attr, Read contents, Synchronize"
						
					cp $dbDirectory/protectedFiles.json $dbDirectory/.protectedFiles.json.back
					jq --arg file "$file" --arg currentTime "$currentTime"  --arg fileID "$fileID" '.original_file_permissions[.original_file_permissions|length] |= . + {"file":($file),"file_id":"'$fileID'","protection_time":($currentTime),"file_last_modified_date":"'$modTime'",}'  $dbDirectory/protectedFiles.json > $dbDirectory/protectedFiles.json.temp	
					mv $dbDirectory/protectedFiles.json.temp $dbDirectory/protectedFiles.json
				fi
			fi
		elif [[ $fileType == ""FS_FILE_TYPE_DIRECTORY ]]
		then
			declare -a fileSIDs=$(qq fs_get_acl --id $fileID --json|jq -r '.aces|.[]|.trustee|.sid')
			
			for userSID in ${fileSIDs[@]}
			do
				existingFileCheck=$(jq -r '.original_file_permissions|.[]|select(.file_id=="'$fileID'")|.file_id' $dbDirectory'/'$protectedFiles)

                        	if [[ -z $existingFileCheck ]]
                        	then
					file=$(qq fs_resolve_paths --id $fileID|jq -r '.[].path')
					echo $file
					deleteCheck=$(qq fs_get_acl --id $fileID --json|jq -r '.aces|.[]|select(.trustee.sid == "'$userSID'")|select(.rights[]|contains ("DELETE"))')

					if [[ -n $deleteCheck ]]
					then
						qq fs_modify_acl --id $fileID  modify_entry --old-trustee sid:$userSID --new-rights "Execute/Traverse, Read, Write file"
						qq fs_modify_acl --id $fileID add_entry -t sid:S-1-3-4 -y Denied -r Write ACL
					fi

                                        cp $dbDirectory/protectedFiles.json $dbDirectory/.protectedFiles.json.back
					jq --arg file "$file" --arg currentTime "$currentTime"  --arg fileID "$fileID" '.original_file_permissions[.original_file_permissions|length] |= . + {"file":($file),"file_id":"'$fileID'","protection_time":($currentTime),"file_last_modified_date":"'$modTime'",}'  $dbDirectory/protectedFiles.json > $dbDirectory/protectedFiles.json.temp	
                                        mv $dbDirectory/protectedFiles.json.temp $dbDirectory/protectedFiles.json
				fi	
			done
		fi
	done
done
