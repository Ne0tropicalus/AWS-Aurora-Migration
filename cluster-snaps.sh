#!/bin/bash
#################################################################
# Requires:    jq                                               #
#              mysql client for linux installed                 #
#              .mylogin.cnf in home directory (mysql config)    #
#              aws cli for linux                                #
#              slack webhook api with keys                      #
#################################################################

#####################################################################
# This same script can be run daily as well as weekly               #
# Just pass either 'w' or 'd' at the command line-default is daily  # 
#####################################################################

export slackweb="https://hooks.slack.com/services/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"
export slackchnl="aurora-snapshots"
export user="AWS Aurora"
export cdate=`date +%Y%m%d`
tdate=0
if [ "${1}" == "w" ]; then
   tdate=60
else
   tdate=7
fi
export fdate=`date --date=' - '''${tdate}''' days' +%Y%m%d`
err_cnt=0

function slackweb()
{
    local user=$1
    local text="`eval TZ='America/Los_Angeles' date` $2"

    escapedText=$(echo ${text} | sed 's/"/\"/g' | sed "s/'/\'/g" )
    json="{\"channel\": \"${slackchnl}\", \"username\":\"${user}\", \"icon_emoji\":\"ghost\", \"attachments\": [{\"color\":\"danger\" , \"text\": \"$escapedText\"}]}"
    while [[ "$( curl -s -d "payload=$json" "${slackweb}")" != "ok" ]]; do sleep 5; done
}


slackweb "Aurora_notify" "*<Beginning Aurora Snapshots>*"
while read cluster
do
    slackweb "Aurora_notify" ":database: => Backing up $cluster"
    /usr/bin/time -f "%E" aws rds create-db-cluster-snapshot \
       --db-cluster-snapshot-identifier "${cluster}-${1}-${cdate}" \
       --db-cluster-identifier "${cluster}"
   if [ "$?" -eq "255" ]; then
      slackweb "Aurora_notify" ":sadpanda: ${cluster} snapshot failed"
      err_cnt="$((err_cnt+1))"
      echo $err_cnt
   fi
done <<< "$(aws rds describe-db-clusters | jq -r '.DBClusters[].DBClusterIdentifier')"

if [ $err_cnt -gt 0 ]; then
   slackweb "Aurora_notify" ":chaos: *<Aurora Snapshots FAILURE>*"
   exit 1
fi

aws rds describe-db-cluster-snapshots --snapshot-type manual | \
    jq -r '.DBClusterSnapshots[] | [.DBClusterSnapshotIdentifier, .SnapshotCreateTime] | @csv' | \
    sed 's/"//g' | while IFS=, read cluster snaptime
do
  export d1=$(date -d "$fdate" +%s)
  export d2=$(date -d "$snaptime" +%s)
#  export ddiff=$(( (d1 - d2) / 86400 ))
  if [[ $d2 -le $d1 ]]; then
      echo "[[[[[rolling off aged snapshot $cluster]]]]]"
      slackweb "Aurora_notify" ":heavy_minus_sign: [rolling off aged snapshot $cluster]"
      aws rds delete-db-cluster-snapshot --db-cluster-snapshot-identifier "$cluster"
  fi
done
slackweb "Aurora_notify" ":white_check_mark: *<COMPLETED Aurora Snapshots>*"
