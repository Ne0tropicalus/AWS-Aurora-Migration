#!/bin/bash

export kms_key_id="arn:aws:kms:us-east-1:027444825683:key/a0896f07-0b13-4051-8ee3-eb188debe532"
export subnet="prod-pm-student-subnet-grp"
export az="us-east-1c us-east-1b us-east-1a"
export ic="db.r5.large"
export mobile=12066436491

delete_dbi () {
  local id=${1}
  echo "---->Deleting STG-${id/-cluster/}-rw node"
  aws rds delete-db-instance \
          --db-instance-identifier STG-${id/-cluster/}-rw \
          --skip-final-snapshot
}

delete_dbc () {
  local id=${1}
  echo "----->Deleting STG-${id} cluster"
  aws rds delete-db-cluster \
          --db-cluster-identifier STG-${id} \
          --skip-final-snapshot
}

create_dbc () {
  local id=${1}
  local snapshot=${2}
  echo "=====>creating temp cluster from snapshot"
  aws rds restore-db-cluster-from-snapshot \
         --availability-zones ${az} \
         --db-cluster-identifier tmp-${id} \
         --snapshot-identifier ${snapshot} \
         --engine aurora-mysql \
         --db-subnet-group-name ${subnet} \
         --kms-key-id ${kms_key_id} \
         --enable-iam-database-authentication
}

create_dbi () {
  local id=${1}
  echo "=====>adding tmp-${id/-cluster/}-rw to cluster tmp-${id}"
  aws rds create-db-instance \
      --db-instance-identifier tmp-${id/-cluster/}-rw \
      --db-instance-class ${ic} \
      --engine aurora-mysql \
      --db-subnet-group-name ${subnet} \
      --db-cluster-identifier tmp-${id} 
}

rename_dbc () {
  local id=${1}
  while true;
     do
     status=`aws rds describe-db-clusters \
              --db-cluster-identifier tmp-${id} \
              --query="DBClusters[].Status" \
              --output text`
     echo "...Cluster ${id} is currently $status"
     if [ "${status}" == "available" ]; then 
        break 
     fi
     sleep 20
  done 
  echo "[[[Renaming Cluster STG-${id}]]]"
  aws rds modify-db-cluster \
          --db-cluster-identifier tmp-${id} \
          --new-db-cluster-identifier STG-${id} \
          --apply-immediately
}

rename_dbi () {
  local id=${1}
  while true;
     do
     status=`aws rds describe-db-instances \
              --db-instance-identifier tmp-${id/-cluster/}-rw \
              --query="DBInstances[].DBInstanceStatus" \
              --output text`
     echo "+++DB Instance tmp-${id/-cluster/}-rw is currently $status"
     if [ "${status}" == "available" ]; then
        break
     fi
     sleep 20
  done
  echo "{{{Renaming DB instance STG-${id/-cluster/}-rw}}}"
  aws rds modify-db-instance \
          --db-instance-identifier tmp-${id/-cluster/}-rw \
          --new-db-instance-identifier STG-${id/-cluster/}-rw \
          --apply-immediately
}

while read id
do 
    ########### Get most recent snapshot from cluster and store ##############
    export snapshot=`aws rds describe-db-cluster-snapshots \
          --snapshot-type automated \
          --db-cluster-identifier ${id} \
	  --query="reverse(sort_by(DBClusterSnapshots, &SnapshotCreateTime))[0]|DBClusterSnapshotIdentifier"`
    export snapshot=`echo ${snapshot} | sed 's/"//g'`
    echo "---=={processing $snapshot}==---"

   ############ Delete the previous database instance ################
   delete_dbi ${id}
   ############ Now delete the cluster - this also frees the older data ###########
   delete_dbc ${id}
   # The deletions take a while so will restore to a temporary set of names #
   ############ Create cluster from snapshot - this only creates a cluster container - stupid AWS :-( #####
   create_dbc ${id} ${snapshot}
   ############# Create db instance and add to cluster ###############
   create_dbi ${id}
   ############ Rename the cluster from tmp to STG ############
   rename_dbc ${id}
   ########### Rename the db instance from tmp to STG #########
   rename_dbi ${id}
done < aurora.list
echo "--==={COMPLETED STG Environment}===--"
aws sns publish --phone-number ${mobile} \
    --message "--==={COMPLETED STG Environment `date`}===--" 
