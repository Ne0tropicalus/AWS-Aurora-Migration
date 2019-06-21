#!/bin/bash
#################################################################
# Requires:    postgres client for linux installed              #
#              .pgpass in home directory with embedded password #
#              mysql client for linux installed                 #
#              .mylogin.cnf in home directory (mysql config)    #
#              aws cli for linux                                #
#              route to postgres database ps-audit-db in aws    #
#################################################################
export audit_dir=/home/ubuntu/database_team
export paudit="psql -h ps-audit-db.c4nnkcktyqqd.us-east-1.rds.amazonaws.com -U pgadmin -p 5432 -d aurora-audits"

########CLEAN THE DIRECTORY#########
rm -fr ${audit_dir}/audits/${1}
mkdir ${audit_dir}/audits/${1}

echo "schema.table,row_count" > ${audit_dir}/audits/${1}_audit.csv

mysql --login-path=$1 --skip-column-names -f -e \
        "select distinct table_schema from information_schema.tables where table_schema not in \
        ('information_schema', 'sys', 'performance_schema', 'mysql', 'tmp');" | while read schema
  do
  echo "+++[Auditing tables in ${schema}]+++"
  mysql --login-path=$1 --skip-column-names -f -e \
        "select concat('select ', table_schema, '.', table_name, ' as schema_table, \
	   count(*) as row_count from ', \
         table_schema, '.', table_name, ' union ') as 'Query Row' \
         from information_schema.tables where table_schema = '${schema}';" \
	 > ${audit_dir}/audits/${1}/${schema}.out
  echo "(select null, null limit 0);" >> ${audit_dir}/audits/${1}/${schema}.out
  done

ls -1 ${audit_dir}/audits/${1}/*.out | while read auditsql
do
   mysql --login-path=$1 --skip-column-names -f < $auditsql | \
	   sed 's/\t/,/g' >> ${audit_dir}/audits/${1}_audit.csv
done

echo "-->uploading database audit to S3"
aws s3 cp ${audit_dir}/audits/${1}_audit.csv s3://aurora-database-audits/

echo "==>Inserting counts into postgres table"
cat ${audit_dir}/audits/${1}_audit.csv | sed 's/\./,/g' \
	| sed "s/^/${1},/g" \
	| $paudit -c "copy public.database_audits(dbinstance,schema_name,table_name,row_count) from STDIN csv header;"

echo "--==={Audit Complete for $1}===--"
