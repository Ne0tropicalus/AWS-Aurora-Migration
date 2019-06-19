CREATE TABLE public.database_audits  ( 
	audit_run_ts    timestamp    NOT NULL default current_timestamp,
	dbinstance 	varchar(100) NULL,
	schema_name	varchar(100) NULL,
	table_name 	varchar(100) NULL,
	row_count  	integer NULL 
	)
WITHOUT OIDS 
TABLESPACE pg_default;
CREATE INDEX audit_schema
	ON public.database_audits USING btree (schema_name text_ops, table_name text_ops);

