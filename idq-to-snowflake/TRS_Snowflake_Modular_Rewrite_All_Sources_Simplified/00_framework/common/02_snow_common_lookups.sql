--------------------------------------------------------------------------------------------------------------------
-- 02_snow_common_lookups.sql
--
-- The reference-data lookups of the IDQ mapplets and rules, as SQL table functions without arguments. A procedure
-- LEFT JOINs TABLE(fn_snow_helperNN_common()) on the lookup condition, which is how Snowflake runs a lookup
-- set-based (one hash join) instead of once per row.
--
-- Each function returns at most ONE row per lookup key, like the IDQ lookup with "Multiple matches: Return any row":
-- QUALIFY ROW_NUMBER() keeps one row, ordered so the choice is repeatable. The lookup filters of the IDQ
-- transformations are applied here. The functions are evaluated inside the calling statement, so they read the
-- same snapshot as the rest of that statement (IDQ static lookup cache).
--
-- | function               | IDQ lookup, key -> returns                                                           |
-- |------------------------|--------------------------------------------------------------------------------------|
-- | fn_snow_helper40_common | EXC_LOOKUP_CODE_VALUE (every rule's exception lookup): EXCEPTION_CODE -> DESC, TYPE   |
-- | fn_snow_helper41_common | V_LOOKUP_CODE_VALUE by code type (PREFIX, SUFFIX, RACE, ETHNICITY, LANGUAGE_CD, STATE, ...): CODE_TYPE, SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
-- | fn_snow_helper42_common | V_LOOKUP_CODE_VALUE without a code-type filter (rule_Suffix_Std): SRC_SYS, SRC_CODE_VALUE -> MSTR_CODE_VALUE |
-- | fn_snow_helper43_common | REF_JUNK_NAME_LIST (Lookup__JUNK_FNAME, Lookup_JUNK_LNAME): NAME -> IS_FIRST_JUNK, IS_LAST_JUNK |
-- | fn_snow_helper44_common | RDM.REF_PHN_AREA_CD with the rule_Phone_Std filter: NPA_ID -> SERVICE               |
-- | fn_snow_helper45_common | LOOKUP_CODE_VALUE by master code (PHN_USG_TP, ALT_ID_TP): CODE_TYPE, SRC_SYS, MSTR_REF_CODE -> MSTR_REF_LABEL |
-- | fn_snow_helper46_common | ref_MatchCode_Desc (mplt_Global_Addr_Validation): MATCH_CODE -> DESCRIPTION         |
-- | fn_snow_helper47_common | REF_DYLGHT_SVNGS_TM (mplt_DST_Correction, TIMELINE): DST                            |
--
-- An IDQ lookup condition never matches a NULL input, and neither does an equi-join, so no extra NULL handling is
-- needed in the callers.
--------------------------------------------------------------------------------------------------------------------

-- EXC_LOOKUP_CODE_VALUE: the exception catalogue. Joining it gives the description and type of a computed code,
-- and EXCEPTION_CODE itself is the code "as returned by the lookup", i.e. NULL when the code is not configured
-- (docs/common_insights.md section 3: several mappings write or route on that looked-up code).
CREATE OR REPLACE FUNCTION fn_snow_helper40_common ()
RETURNS TABLE (EXCEPTION_CODE VARCHAR, EXCEPTION_DESC VARCHAR, EXCEPTION_TYPE VARCHAR)
AS
$$
    SELECT e.EXCEPTION_CODE, e.EXCEPTION_DESC, e.EXCEPTION_TYPE
      FROM EXC_LOOKUP_CODE_VALUE e
     WHERE e.EXCEPTION_CODE IS NOT NULL
   QUALIFY ROW_NUMBER() OVER (PARTITION BY e.EXCEPTION_CODE
                                  ORDER BY e.EXCEPTION_DESC NULLS LAST, e.EXCEPTION_TYPE NULLS LAST) = 1
$$;

-- V_LOOKUP_CODE_VALUE with a CODE_TYPE filter: join on CODE_TYPE = '<type>' AND SRC_SYS AND SRC_CODE_VALUE.
CREATE OR REPLACE FUNCTION fn_snow_helper41_common ()
RETURNS TABLE (CODE_TYPE VARCHAR, SRC_SYS VARCHAR, SRC_CODE_VALUE VARCHAR, MSTR_CODE_VALUE VARCHAR)
AS
$$
    SELECT v.CODE_TYPE, v.SRC_SYS, v.SRC_CODE_VALUE, v.MSTR_CODE_VALUE
      FROM V_LOOKUP_CODE_VALUE v
     WHERE v.CODE_TYPE IS NOT NULL AND v.SRC_SYS IS NOT NULL AND v.SRC_CODE_VALUE IS NOT NULL
   QUALIFY ROW_NUMBER() OVER (PARTITION BY v.CODE_TYPE, v.SRC_SYS, v.SRC_CODE_VALUE
                                  ORDER BY v.MSTR_CODE_VALUE NULLS LAST) = 1
$$;

-- V_LOOKUP_CODE_VALUE WITHOUT a code-type filter (rule_Suffix_Std's lkp_V_LOOKUP_CODE_VALUE): any code type with a
-- matching source value translates it.
CREATE OR REPLACE FUNCTION fn_snow_helper42_common ()
RETURNS TABLE (SRC_SYS VARCHAR, SRC_CODE_VALUE VARCHAR, MSTR_CODE_VALUE VARCHAR)
AS
$$
    SELECT v.SRC_SYS, v.SRC_CODE_VALUE, v.MSTR_CODE_VALUE
      FROM V_LOOKUP_CODE_VALUE v
     WHERE v.SRC_SYS IS NOT NULL AND v.SRC_CODE_VALUE IS NOT NULL
   QUALIFY ROW_NUMBER() OVER (PARTITION BY v.SRC_SYS, v.SRC_CODE_VALUE
                                  ORDER BY v.MSTR_CODE_VALUE NULLS LAST, v.CODE_TYPE) = 1
$$;

-- REF_JUNK_NAME_LIST: a name is a junk FIRST name when a row with EDIT_LIMITATION NULL or 'FIRST' has it
-- (Lookup__JUNK_FNAME filter), a junk LAST name with NULL or 'LAST' (Lookup_JUNK_LNAME filter). Join on
-- NAME = UPPER(TRIM(<name>)). BAD DATA: the name mapplet blanks junk names.
-- (The table name has no BAK / date stamp; it is the live list, not a backup.)
CREATE OR REPLACE FUNCTION fn_snow_helper43_common ()
RETURNS TABLE (NAME VARCHAR, IS_FIRST_JUNK BOOLEAN, IS_LAST_JUNK BOOLEAN)
AS
$$
    SELECT j.NAME,
           BOOLOR_AGG(j.EDIT_LIMITATION IS NULL OR j.EDIT_LIMITATION = 'FIRST') AS IS_FIRST_JUNK,
           BOOLOR_AGG(j.EDIT_LIMITATION IS NULL OR j.EDIT_LIMITATION = 'LAST')  AS IS_LAST_JUNK
      FROM REF_JUNK_NAME_LIST j
     WHERE j.NAME IS NOT NULL
     GROUP BY j.NAME
$$;

-- RDM.REF_PHN_AREA_CD with the filter of rule_Phone_Std's Lookup_REF_PHN_AREA_CD (verbatim; this lookup already
-- ran against Snowflake in IDQ, through the Snowflake_PEI connection): in service (or in-service date reached),
-- geographic or toll-free, US or non-geographic. Join on NPA_ID = SUBSTR(<cleaned phone>, 1, 3).
CREATE OR REPLACE FUNCTION fn_snow_helper44_common ()
RETURNS TABLE (NPA_ID VARCHAR, SERVICE VARCHAR)
AS
$$
    SELECT a.NPA_ID::VARCHAR AS NPA_ID, a.SERVICE
      FROM RDM.REF_PHN_AREA_CD a
     WHERE (a.IN_SERVICE = 'Y' OR CURRENT_DATE() >= a.IN_SERVICE_DT)
       AND (a.SERVICE IS NULL OR a.SERVICE = 'Toll-Free')
       AND (a.COUNTRY = 'US' OR a.COUNTRY IS NULL)   -- omit Canada and Caribbean countries
       AND a.NPA_ID IS NOT NULL
   QUALIFY ROW_NUMBER() OVER (PARTITION BY a.NPA_ID ORDER BY a.SERVICE NULLS FIRST) = 1
$$;

-- LOOKUP_CODE_VALUE by master reference code (mplt_Member_Pty_Rle_Phn_Normalization PHN_USG_TP,
-- mplt_TRS_Pty_Rle_Alt_Id_Normalization ALT_ID_TP): join on CODE_TYPE AND MSTR_REF_CODE AND SRC_SYS.
CREATE OR REPLACE FUNCTION fn_snow_helper45_common ()
RETURNS TABLE (CODE_TYPE VARCHAR, SRC_SYS VARCHAR, MSTR_REF_CODE VARCHAR, MSTR_REF_LABEL VARCHAR)
AS
$$
    SELECT l.CODE_TYPE, l.SRC_SYS, l.MSTR_REF_CODE, l.MSTR_REF_LABEL
      FROM LOOKUP_CODE_VALUE l
     WHERE l.CODE_TYPE IS NOT NULL AND l.SRC_SYS IS NOT NULL AND l.MSTR_REF_CODE IS NOT NULL
   QUALIFY ROW_NUMBER() OVER (PARTITION BY l.CODE_TYPE, l.SRC_SYS, l.MSTR_REF_CODE
                                  ORDER BY l.MSTR_REF_LABEL NULLS LAST) = 1
$$;

-- ref_MatchCode_Desc (lkp_ref_MatchCode_Desc of mplt_Global_Addr_Validation; IDQ connection INFA_STAGE): the text of
-- an AddressDoctor match code. With the pass-through validator the match code is NULL, so nothing matches.
CREATE OR REPLACE FUNCTION fn_snow_helper46_common ()
RETURNS TABLE (MATCH_CODE VARCHAR, DESCRIPTION VARCHAR)
AS
$$
    SELECT r.MATCH_CODE, r.DESCRIPTION
      FROM REF_MATCHCODE_DESC r
     WHERE r.MATCH_CODE IS NOT NULL
   QUALIFY ROW_NUMBER() OVER (PARTITION BY r.MATCH_CODE ORDER BY r.DESCRIPTION NULLS LAST) = 1
$$;

-- REF_DYLGHT_SVNGS_TM (TIMELINE, mplt_DST_Correction): the daylight-saving change instants. Join on
-- DST = DATEADD(hour, 2, <end date>).
CREATE OR REPLACE FUNCTION fn_snow_helper47_common ()
RETURNS TABLE (DST TIMESTAMP_NTZ)
AS
$$
    SELECT DISTINCT d.DST::TIMESTAMP_NTZ AS DST
      FROM REF_DYLGHT_SVNGS_TM d
     WHERE d.DST IS NOT NULL
$$;
