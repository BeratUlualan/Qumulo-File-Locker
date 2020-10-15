
#!/bin/bash

echo -en "Protection Policy Name:"
read protectionPolicy

#echo -en "Protection User: "
#read protectionUsername
protectionUsername="protector"

protectionUserSID=$(qq ad_name_to_accounts -n "$protectionUsername"|jq -r '.[]|.sid')
echo $protectionUserSID

#echo -en "Configuration Credential Path:"
#read dbDirectory
dbDirectory="/history/protector"

echo -en "Protected Directory Path:"
read protectedDirectory

echo -en "Commit time:"
read commitTime

echo -en "Do you want to enable this rule? (yes/no):"
read protectionEnablement

qq snapshot_create_policy hourly_or_less --enabled --name $protectionPolicy'_5min'  --path $protectedDirectory  --time-to-live 7days --timezone "Europe/Istanbul" --period 5minutes
fiveminPolicyID=$(qq snapshot_list_policies |jq '.entries|.[]|select (.name|tostring|contains("'$protectionPolicy''_5min'"))|.id')

qq snapshot_create_policy daily --enabled --name $protectionPolicy'_daily' --path $protectedDirectory --time-to-live 3months --timezone "Europe/Istanbul" --days-of-week "ALL" --at "00:30"
dailyPolicyID=$(qq snapshot_list_policies |jq '.entries|.[]|select (.name|tostring|contains("'$protectionPolicy''_daily'"))|.id')

qq snapshot_create_policy daily --enabled --name $protectionPolicy'_weekly' --path $protectedDirectory --time-to-live 12months --timezone "Europe/Istanbul" --days-of-week "SUN" --at "01:00"
weeklyPolicyID=$(qq snapshot_list_policies |jq '.entries|.[]|select (.name|tostring|contains("'$protectionPolicy''_weekly'"))|.id')

qq snapshot_create_policy monthly --enabled --name $protectionPolicy'_monthly' --path $protectedDirectory --time-to-live "" --timezone "Europe/Istanbul" --day-of-month "1" --at "02:00"
monthlyPolicyID=$(qq snapshot_list_policies |jq '.entries|.[]|select (.name|tostring|contains("'$protectionPolicy''_monthly'"))|.id')


cp $dbDirectory/credentials.json $dbDirectory/.credentials.json.back

jq --arg protectedDirectory "$protectedDirectory" --arg protectionUsername "$protectionUsername" --arg commitTime "$commitTime" --arg 5minPolicyID "$fiveminPolicyID" --arg dailyPolicyID "$dailyPolicyID" --arg weeklyPolicyID "$weeklyPolicyID" --arg monthlyPolicyID "$monthlyPolicyID" '.main_credentials[.main_credentials|length] |= . + {"protection_enablement":"'$protectionEnablement'","protection_policy":"'$protectionPolicy'","db_directory":"'$dbDirectory'","protected_directory":"'$protectedDirectory'","commit_time":"'$commitTime'","protection_username":"'$protectionUsername'","protection_user_sid":"'$protectionUserSID'","5min_snapshot_policy_id":"'$fiveminPolicyID'","daily_snapshot_policy_id":"'$dailyPolicyID'","weekly_snapshot_policy_id":"'$weeklyPolicyID'","monthly_snapshot_policy_id":"'$monthlyPolicyID'" ,}'  $dbDirectory/credentials.json > $dbDirectory/credentials.json.temp

mv $dbDirectory/credentials.json.temp $dbDirectory/credentials.json
