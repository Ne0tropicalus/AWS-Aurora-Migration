#!/bin/bash

export instance=${1}
export target=${2}

echo "Starting at `date`"
echo "Dumping Triggers and stored procedures only from all databases"

/usr/bin/time -f "%E" mysqldump --login-path=${instance} --routines --no-create-info --no-data --no-create-db --skip-opt --databases --force `mysql --login-path=${instance} --skip-column-names -e "SELECT GROUP_CONCAT(schema_name SEPARATOR ' ') FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','performance_schema','information_schema');"`> ./post_out/${instance}.sql

echo "Correcting for RDS Aurora directives"
sed 's/\sDEFINER=`[^`]*`@`[^`]*`//g' -i ./post_out/${instance}.sql

echo "applying Stored procs and triggers to AWS Aurora cluster"
/usr/bin/time -f "%E" mysql --login-path=${target} -f < ./post_out/${instance}.sql

echo "getting indexes from source databases"
mysql --login-path=${instance} --skip-column-names < part-1.sql | while read db
do
  echo "database is $db"
  echo "--" >> ./post_out/${instance}_indexes.sql
  echo "USE $db ;" >> ./poar_dms/${instance}_indexes.sql
  /usr/bin/time -f "%E" mysql --login-path=${instance} --skip-column-names -e "set @db='${db}'; source ./part-2.sql;" >> ./post_out/${instance}_indexes.sql
done

grep -v "PRIMARY KEY" ${instance}_indexes.sql > ./post_out/${instance}_nopk.sql

echo "applying indexes to target Aurora cluster"
/usr/bin/time -f "%E" mysql --login-path=${target} --force < ./post_out/${instance}_nopk.sql 
echo "-------FINISHED AT `date` -------"
