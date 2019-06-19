select schema_name,
       table_name
from database_audits
where dbinstance = @onprem 
and audit_run_ts = (select max(j.audit_run_ts) from database_audits j where j.dbinstance = @onprem)
except
select schema_name,
       table_name
from database_audits
where dbinstance = @aurora 
and audit_run_ts = (select max(j.audit_run_ts) from database_audits j where j.dbinstance = @aurora)
order by schema_name, table_name;
