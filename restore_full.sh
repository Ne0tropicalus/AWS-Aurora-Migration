#!/bin/bash
export aurora_tgt=${2}
export bu_src=${1^^}

## grab schema backups from S3##

rm -f ./schema/${bu_src}/*.*
/usr/bin/time -f "%E" aws s3 sync s3://prod-mysql-dumpfiles/${bu_src}/ ./schema/${bu_src}/ --exclude "*" --include "*.schema.*"

## loop through the schema files - unzipping and applying to target Aurora ##

ls -1 ./schema/${bu_src}/*.gz | while read sfile
do
echo "----------[unzipping $sfile]----------"
/usr/bin/time -f "%E" gunzip $sfile
echo "=========={Processing $sfile}=========="
sed 's/\sDEFINER=`[^`]*`@`[^`]*`//g' -i ${sfile%.*} 
sed 's/ENGINE=MyISAM/ENGINE=InnoDB/g' -i ${sfile%.*}
sed 's|^DROP TABLE|-- DROP TABLE|g;s|^CREATE TABLE|CREATE TABLE IF NOT EXISTS|g' \
    ${sfile%.*} | egrep -v 'DROP DATABASE' | sed 's|^CREATE DATABASE|-- CREATE DATABASE|g' > ${sfile%.*}_POST_DROP 
/usr/bin/time -f "%E" mysql --login-path=${aurora_tgt} -f < ${sfile%.*}
echo "((((Moving and rezipping))))"
/usr/bin/time -f "%E" gzip ${sfile%.*}
mv ${sfile} ${sfile}.DONE 
done
echo "**************SCHEMA JOB COMPLETE******************"

echo "getting indexes from Aurora databases"
mysql --login-path=${aurora_tgt} --skip-column-names < part-a.sql | while IFS=, read db table
do
  echo "checking $db.$table"
  mysql --login-path=${aurora_tgt} --skip-column-names -e "set @db='${db}', @table='${table}'; source ./part-b.sql;" >> ./remove_${aurora_tgt}_indexes.sql
done

echo "********DROPPING INDEXES************"
mysql --login-path=${aurora_tgt} -f < ./remove_${aurora_tgt}_indexes.sql
mv ./remove_${aurora_tgt}_indexes.sql ./remove_${aurora_tgt}_indexes.DONE

echo "show databases" | mysql --login-path=${aurora_tgt} --disable-column-names | while read db
do
  echo "Searching ${db} for triggers and dropping them"
  echo "select concat('drop trigger ${db}.', trigger_name, ';') from information_schema.triggers where trigger_schema = '${db}'" | \
	mysql --login-path=${aurora_tgt}  --disable-column-names | \
        mysql --login-path=${aurora_tgt}
done
echo "******non-FK Indexes and Triggers dropped********"
## grab data backups from S3##

rm -f ./data/${bu_src}/*.gz
/usr/bin/time -f "%E" aws s3 sync s3://prod-mysql-dumpfiles/${bu_src}/ ./data/${bu_src}/ --exclude "*" --include "*.data.*"

## loop through the data files - unzipping and applying to target Aurora ##

ls -1 ./data/${bu_src}/*.gz | while read sfile
do
echo "----------[unzipping $sfile]----------"
/usr/bin/time -f "%E" gunzip $sfile
echo "=========={Processing $sfile}=========="
sed 's/\sDEFINER=`[^`]*`@`[^`]*`//g' -i ${sfile%.*} 
/usr/bin/time -f "%E" mysql --login-path=${aurora_tgt} -f < ${sfile%.*}
echo "((((Moving and rezipping))))"
/usr/bin/time -f "%E" gzip ${sfile%.*}
mv ${sfile} ${sfile}.DONE 
done
echo "**************DATA JOB COMPLETE******************"

## loop through the POST_DROP files ##
echo "----------Rebuilding indexes and adding triggers back--------------"

ls -1 ./schema/${bu_src}/*.sql_POST_DROP | while read sfile
do
echo "=========={Processing $sfile}=========="
/usr/bin/time -f "%E" mysql --login-path=${aurora_tgt} -f < ${sfile}
mv ${sfile} ${sfile}.DONE 
done
echo "!!!MYSQL Restore to Aurora completed!!!!"
