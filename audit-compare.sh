#!/bin/bash
#################################################################
# Requires:    postgres client for linux installed              # 
#              .pgpass in home directory with embedded password #
#              aws cli for linux                                #
#              route to postgres database ps-audit-db in aws    #
#################################################################       
export audit_dir="~/database_team"
export paudit="psql -h ps-audit-db.c4nnkcktyqqd.us-east-1.rds.amazonaws.com -U pgadmin -p 5432 -d aurora-audits"
export code="~Aurora-Aurora-Migration"
export onprem=${1}
export aurora=${2}

$paudit -A -t -c \
	-v onprem=${onprem} \
	-v aurora=${aurora} \
        -f ${code}/missing_schemas.sql > ${audit_dir}/missing_schemas_${onprem}_${aurora}.out	

$paudit -A -t -c \
	-v onprem=${onprem} \
	-v aurora=${aurora} \
        -f ${code}/row_count_mismatch.sql > ${audit_dir}/row_count_mismatch_${onprem}_${aurora}.out	

echo "-->uploading audit comparisons to S3"
aws s3 cp ${audit_dir}/row_count_mismatch_${onprem}_${aurora}.out s3://aurora-database-audits/
aws s3 cp ${audit_dir}/row_count_mismatch_${onprem}_${aurora}.out s3://aurora-database-audits/

echo "--==={Audit comparisons completed for ${onprem} and ${aurora} }===--"
