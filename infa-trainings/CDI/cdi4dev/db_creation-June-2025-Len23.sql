-- Using Postgres
Default user name: bpeluser pwd : bpel
-- create database
CREATE DATABASE sampledb
    WITH
    OWNER = bpeluser
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

COMMENT ON DATABASE sampledb
    IS 'for Informatica Labs';

CREATE SCHEMA sampleschema
    AUTHORIZATION bpeluser;


CREATE ROLE sample_role WITH
	LOGIN
	NOSUPERUSER
	NOCREATEDB
	NOCREATEROLE
	INHERIT
	NOREPLICATION
	NOBYPASSRLS
	CONNECTION LIMIT -1;

-- GRANT "IICS_ROLE" TO "IICS_SQL";


ALTER DATABASE sampledb OWNER TO sample_role;