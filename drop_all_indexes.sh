#!/bin/bash

export instance=${1}
echo "getting indexes from Aurora databases"
mysql --login-path=${instance} --skip-column-names < part-a.sql | while IFS=, read db table
do
  echo "checking $db.$table"
  mysql --login-path=${instance} --skip-column-names -e "set @db='${db}', @table='${table}'; source ./part-b.sql;" >> ./remove_${instance}_indexes.sql
done

mysql --login-path=${instance} -f < ./remove_${instance}_indexes.sql
mv ./remove_${instance}_indexes.sql ./remove_${instance}_indexes.DONE
