#!/bin/bash
#################################################################
# Requires:    mysql client for linux installed                 #
#              .mylogin.cnf in home directory (mysql config)    #
#              aws cli for linux                                #
#################################################################
export rootdir=/home/ubuntu/dumps
export code=/home/ubuntu/AWS-Aurora-Migration
export aurora_tgt=${2}
export bu_src=${1^^}

## grab schema backups from S3##

rm -f ${rootdir}/schema/${bu_src}/*.*
/usr/bin/time -f "%E" aws s3 sync s3://prod-mysql-dumpfiles/${bu_src}/ ${rootdir}/schema/${bu_src}/ --exclude "*" --include "*.schema.*"

## loop through the schema files - unzipping and applying to target Aurora ##

ls -1 ${rootdir}/schema/${bu_src}/*.gz | while read sfile
do
echo "----------[unzipping $sfile]----------"
/usr/bin/time -f "%E" gunzip $sfile
echo "=========={Processing $sfile}=========="
sed 's/\sDEFINER=`[^`]*`@`[^`]*`//g' -i ${sfile%.*} 
sed 's/ENGINE=[Mm][Yy][Ii][Ss][Aa][Mm]/ENGINE=InnoDB/g' -i ${sfile%.*}
sed 's|^DROP TABLE|-- DROP TABLE|g;s|^CREATE TABLE|CREATE TABLE IF NOT EXISTS|g' \
    ${sfile%.*} | egrep -v 'DROP DATABASE' | sed 's|^CREATE DATABASE|-- CREATE DATABASE|g' > ${sfile%.*}_POST_DROP 
/usr/bin/time -f "%E" mysql --login-path=${aurora_tgt} -f < ${sfile%.*}
echo "((((Moving and rezipping))))"
/usr/bin/time -f "%E" gzip ${sfile%.*}
mv ${sfile} ${sfile}.DONE 
done
echo "**************SCHEMA JOB COMPLETE******************"

echo "getting indexes from Aurora databases"
mysql --login-path=${aurora_tgt} --skip-column-names < ${code}/part-a.sql | while IFS=, read db table
do
  echo "checking $db.$table"
  mysql --login-path=${aurora_tgt} --skip-column-names -e "set @db='${db}', @table='${table}'; source ${code}/part-b.sql;" >> ${rootdir}/remove_${aurora_tgt}_indexes.sql
done

echo "********DROPPING INDEXES************"
mysql --login-path=${aurora_tgt} -f < ${rootdir}/remove_${aurora_tgt}_indexes.sql
mv ${rootdir}/remove_${aurora_tgt}_indexes.sql ${rootdir}/remove_${aurora_tgt}_indexes.DONE

echo "show databases" | mysql --login-path=${aurora_tgt} --disable-column-names | while read db
do
  echo "Searching ${db} for triggers and dropping them"
  echo "select concat('drop trigger ${db}.', trigger_name, ';') from information_schema.triggers where trigger_schema = '${db}'" | \
	mysql --login-path=${aurora_tgt}  --disable-column-names | \
        mysql --login-path=${aurora_tgt}
done
echo "******non-FK Indexes and Triggers dropped********"
## grab data backups from S3##

rm -f ${rootdir}/data/${bu_src}/*.gz
/usr/bin/time -f "%E" aws s3 sync s3://prod-mysql-dumpfiles/${bu_src}/ ${rootdir}/data/${bu_src}/ --exclude "*" --include "*.data.*"

## loop through the data files - unzipping and applying to target Aurora ##

ls -1 ${rootdir}/data/${bu_src}/*.gz | while read sfile
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

ls -1 ${rootdir}/schema/${bu_src}/*.sql_POST_DROP | while read sfile
do
echo "=========={Processing $sfile}=========="
/usr/bin/time -f "%E" mysql --login-path=${aurora_tgt} -f < ${sfile}
mv ${sfile} ${sfile}.DONE 
done
#############Create a tmp schema and appuser on all instances####################
mysql --login-path=${aurora_tgt} -f -e "CREATE DATABASE if not exists tmp;"
mysql --login-path=${aurora_tgt} -f -e "GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP ON *.* TO appuser@'%'IDENTIFIED BY 'PSch00l2k19!!';"
echo "!!!MYSQL Restore to Aurora completed!!!!"
