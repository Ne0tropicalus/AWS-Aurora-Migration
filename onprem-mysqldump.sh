##############DATA FILE MYSQLDump Creation#####################

/usr/bin/mysql --batch --skip-column-names --force \
    -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','performance_schema','information_schema');" \
    | while read db
       do
       echo "Dumping $db"
       /usr/bin/mysqldump --skip-triggers --add-locks --no-create-info \
           --no-create-db  --databases --force $db > /datavolume/aurora-export/$db.data.sql
       echo "processing $db"
       /bin/cat /datavolume/aurora-export/$db.data.sql | \
         sed -e "s/ENCRYPTION='Y'//g; s/ENGINE=FEDERATED/ENGINE=InnoDB/g; s/CONNECTION='mysql[^']*'//g; s/DEFINER=\`[^\`]*\`@\`[^\`]*\`//g;" > /datavolume/aurora-export/$db.data.aurora.sql
       echo "GZipping $db"
       /bin/gzip /datavolume/aurora-export/$db.data.aurora.sql
       echo "Copy $db to S3"
       aws s3 cp /datavolume/aurora-export/$db.data.aurora.sql.gz s3://prod-mysql-dumpfiles/ARCHIVE2017/
       echo "cleaning sql"
       rm -fr /datavolume/aurora-export/$db.data.sql
    done

###########SCHEMA FILE MYSQLDump creation####################

/usr/bin/mysql --batch --skip-column-names --force \
   -e "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('mysql','performance_schema','information_schema');" \
   | while read db
     do
     echo "Dumping $db"
     /usr/bin/mysqldump --opt --routines --add-drop-database  --add-drop-trigger --no-data \
        --triggers --databases --force $db > /datavolume/aurora-export/$db.schema.sql
     echo "processing $db"
     /bin/cat /datavolume/aurora-export/$db.schema.sql | \
        sed -e "s/ENCRYPTION='Y'//g; s/ENGINE=ARCHIVE/ENGINE=InnoDB/g; s/ENGINE=FEDERATED/ENGINE=InnoDB/g; s/CONNECTION='mysql[^']*'//g; s/DEFINER=\`[^\`]*\`@\`[^\`]*\`//g;" > /datavolume/aurora-export/$db.schema.aurora.sql
     echo "GZipping $db"
     /bin/gzip /datavolume/aurora-export/$db.schema.aurora.sql
     echo "Copy $db to S3"
     aws s3 cp /datavolume/aurora-export/$db.schema.aurora.sql.gz s3://prod-mysql-dumpfiles/ARCHIVE2017/
     echo "cleaning sql"
     rm -fr /datavolume/aurora-export/$db.schema.sql
done
