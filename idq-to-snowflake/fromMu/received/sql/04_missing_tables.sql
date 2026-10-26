-- ============================================================================
-- 04_missing_tables.sql -- HAND-MAINTAINED, DO NOT REGENERATE
--
-- These four objects are read by the Snowflake ETL (via the
-- fn_snow_helper* lookup functions) but they were NOT in the Oracle
-- exports you supplied (sql_Ora.zip contains STAGING, LANDING and
-- HHS_MDM only, and no views at all).  The generator script therefore
-- cannot produce them, and inventing a full definition here would be
-- worse than saying so plainly.
--
-- BEFORE THE FIRST COPY RUN, replace each block below with the real
-- Oracle definition for that object:
--   1. In Oracle, run DBMS_METADATA.GET_DDL (or export the object) for
--      V_LOOKUP_CODE_VALUE, REF_JUNK_NAME_LIST, REF_MATCHCODE_DESC
--      and RDM.REF_PHN_AREA_CD (Oracle RDM), and translate it with the same rules
--      as scripts/generate_snowflake_ddl.py (VARCHAR2 -> VARCHAR,
--      NUMBER -> NUMBER(38,0), DATE -> DATE, TIMESTAMP -> TIMESTAMP_NTZ).
--   2. Apply the translated DDL to TRS_ETL_WRK in the source database
--      (these are inputs, not targets, so they carry no DATA_SOURCE
--      discriminator column).
--   3. Add the object to app/domain/catalog.py's INPUT_TABLES with its real
--      Oracle schema (set missing_from_exports=False), regenerate
--      app/domain/tables.py with scripts/generate_tables.py, and apply
--      the translated DDL to TRS_ETL_WRK.
--
-- What is in this file today is the MINIMAL shape the Snowflake
-- procedures actually query (columns taken verbatim from the
-- fn_snow_helper* functions that read them).  It is enough to let the
-- procedures compile and run if you load exactly these columns, but
-- it is NOT a substitute for the full Oracle definition.  Note the
-- v3 behaviour carefully: the copy job selects only the columns
-- listed in app/domain/tables.py (explicit, generated), so if the
-- real Oracle object has MORE columns than the minimal shape below,
-- those extra columns are silently NOT copied until you regenerate
-- tables.py from the full definition.  That is why step 3 above
-- (regenerate, do not just apply DDL) is mandatory, not optional.
-- ============================================================================

-- V_LOOKUP_CODE_VALUE: read by fn_snow_helper41/42_common.
--   Columns used: CODE_TYPE, SRC_SYS, SRC_CODE_VALUE, MSTR_CODE_VALUE.
--   Oracle schema: UNKNOWN from the supplied exports (IDQ lookup
--   connection; most likely STAGING -- confirm, do not guess, in
--   production).  This is a VIEW in Oracle; in Snowflake it is created
--   as a table here so the copy job can load it like any other input.
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.V_LOOKUP_CODE_VALUE (
    CODE_TYPE VARCHAR,
    SRC_SYS VARCHAR,
    SRC_CODE_VALUE VARCHAR,
    MSTR_CODE_VALUE VARCHAR
);
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.V_LOOKUP_CODE_VALUE (
    CODE_TYPE VARCHAR,
    SRC_SYS VARCHAR,
    SRC_CODE_VALUE VARCHAR,
    MSTR_CODE_VALUE VARCHAR
);

-- REF_JUNK_NAME_LIST: read by fn_snow_helper43_common.
--   Columns used: NAME, EDIT_LIMITATION (NULL or 'FIRST' / 'LAST').
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.REF_JUNK_NAME_LIST (
    NAME VARCHAR,
    EDIT_LIMITATION VARCHAR
);
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.REF_JUNK_NAME_LIST (
    NAME VARCHAR,
    EDIT_LIMITATION VARCHAR
);

-- REF_MATCHCODE_DESC: read by fn_snow_helper46_common.
--   Columns used: MATCH_CODE, DESCRIPTION.  (With the pass-through
--   address validator the match code is NULL, so nothing matches --
--   but the table must still exist for the procedure to compile.)
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.REF_MATCHCODE_DESC (
    MATCH_CODE VARCHAR,
    DESCRIPTION VARCHAR
);
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.REF_MATCHCODE_DESC (
    MATCH_CODE VARCHAR,
    DESCRIPTION VARCHAR
);

-- RDM.REF_PHN_AREA_CD: read by fn_snow_helper44_common (Snowflake_PEI
-- connection in IDQ; Oracle schema RDM, not in the supplied exports).
--   Columns used: NPA_ID, SERVICE, IN_SERVICE, IN_SERVICE_DT, COUNTRY.
--   In Snowflake the helper USED TO qualify it as RDM.REF_PHN_AREA_CD.
--   In v5 it reads it unqualified from TRS_ETL_WRK, like every other
--   helper (ETL-package change, not this file) -- so it is created
--   in TRS_ETL_WRK below; if your Snowflake account already has an
--   TRS_ETL_WRK schema with this table, skip this block and point the
--   copy job at it instead (see app/domain/catalog.py).
CREATE TABLE IF NOT EXISTS TRS_ETL_WRK.REF_PHN_AREA_CD (
    NPA_ID VARCHAR,
    SERVICE VARCHAR,
    IN_SERVICE VARCHAR,
    IN_SERVICE_DT DATE,
    COUNTRY VARCHAR
);
