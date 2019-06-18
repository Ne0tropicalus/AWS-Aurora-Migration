export aurora_tgt=${1}
echo "show databases" | mysql --login-path=${aurora_tgt} --disable-column-names | while read db
do
  echo "Searching ${db} for triggers and dropping them"
  echo "select concat('drop trigger ${db}.', trigger_name, ';') from information_schema.triggers where trigger_schema = '${db}'" | \
	mysql --login-path=${aurora_tgt}  --disable-column-names | \
        mysql --login-path=${aurora_tgt}
done
