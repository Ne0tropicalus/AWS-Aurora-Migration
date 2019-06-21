with compare as
(
 select a.audit_run_ts as most_recent_audit,
       a.schema_name,
       a.table_name,
       a.row_count as on_prem_count,
       b.row_count as aurora_count
 from database_audits a
 join database_audits b on a.schema_name = b.schema_name
 and a.table_name = b.table_name
 and a.dbinstance = :'onprem' 
 and a.audit_run_ts = (select max(j.audit_run_ts) from database_audits j where j.dbinstance = :'onprem')
 and b.dbinstance = :'aurora' 
 and b.audit_run_ts = (select max(j.audit_run_ts) from database_audits j where j.dbinstance = :'aurora')
)
select x.*, abs(x.aurora_count - x.on_prem_count) as difference
from compare x
where abs(x.aurora_count - x.on_prem_count) > 0
order by 5 desc;
