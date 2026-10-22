--------------------------------------------------------------------------------------------------------------------
-- 01_snow_common_functions.sql
--
-- Scalar SQL UDFs shared by the sp_snow_main_* procedures: the IDQ mapplets and rules of
-- docs/mappings/000_mapplets.md, written out here (nothing is assumed to exist), plus small IDQ-semantics helpers.
--
-- Design (see ../README.md, "Mapplets and rules"):
--   * Every function is a pure SQL UDF: no table access, deterministic for its arguments. Snowflake inlines SQL
--     UDFs into the calling query, so they run set-based at the speed of the expression itself.
--   * A mapplet that looks something up (V_LOOKUP_CODE_VALUE, EXC_LOOKUP_CODE_VALUE, REF_JUNK_NAME_LIST,
--     REF_PHN_AREA_CD, ...) is split in two: the lookup is a LEFT JOIN in the calling procedure to one of the
--     lookup table functions of 02_snow_common_lookups.sql, and the looked-up value is passed in as an argument.
--     Snowflake officially supports correlated scalar subqueries only in WHERE clauses, so a UDF that queried a table
--     per row could fail to compile ("Unsupported subquery type") or run row by row.
--   * Mapplets with several outputs return an OBJECT; read it as obj:attribute::<type>.
--   * No Java UDF: every rule is a string/regex expression, which Snowflake evaluates vectorised inside the query.
--     A Java UDF would add a JVM hop per batch and be slower (see README, "Why no Java UDFs").
--
-- IDQ semantics kept on purpose (Snowflake differs from Oracle here):
--   * '' is NOT NULL in Snowflake, as in IDQ. The IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) is
--     fn_snow_helper03_common.
--   * Snowflake || returns NULL when any operand is NULL; IDQ treats NULL as ''. Concatenations of nullable values
--     are wrapped in NVL(x, '').
--   * VALIDATION: rule logic that decides an exception code. BAD DATA: how a bad value is changed (blanked,
--     truncated, cleaned) before it is written. Both are marked in the comments.
--
-- | function               | IDQ object / purpose                                                                 |
-- |------------------------|--------------------------------------------------------------------------------------|
-- | fn_snow_helper01_common | IDQ IS_NUMBER(): 1 / 0, NULL for NULL                                               |
-- | fn_snow_helper02_common | new deactivation status from the hub state: H history / D deactivated / P pending    |
-- | fn_snow_helper03_common | IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x) (BOOLEAN)                          |
-- | fn_snow_helper04_common | IDQ TO_DECIMAL(value, scale): non-numeric 0, NULL NULL                              |
-- | fn_snow_helper05_common | address score of exp_Score_and_Exception_details: '40' exception / '100'           |
-- | fn_snow_helper06_common | address issue text of exp_Score_and_Exception_details (Addr_Issue_Desc)             |
-- | fn_snow_helper07_common | exp_Address_Hold line 1: empty line 1 replaced by line 2                            |
-- | fn_snow_helper08_common | exp_Address_Hold line 2: cleared when it repeats the held line 1                    |
-- | fn_snow_helper09_common | token standardiser "remove custom strings" + remove multiple spaces + trim          |
-- | fn_snow_helper10_common | STD_remove_special_char (ref_special_char_list): keep letters, digits and spaces    |
-- | fn_snow_helper11_common | IDQ character labeler: letters X, zero 0, other digits 9                            |
-- | fn_snow_helper12_common | trailing-number removal, step 1: a 0 between letters becomes o                      |
-- | fn_snow_helper13_common | trailing-number removal, step 2: cut at the first digit (keep branch for ...0)      |
-- | fn_snow_helper14_common | mplt_Name_Standardization_Trailing_Num_Removal (OBJECT)                             |
-- | fn_snow_helper15_common | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf_) (OBJECT)                      |
-- | fn_snow_helper16_common | mplt_BirthDate_Validation: exception code                                           |
-- | fn_snow_helper17_common | mplt_Gender_Validation (OBJECT)                                                     |
-- | fn_snow_helper18_common | mplt_Race/Ethnicity/Language_Validation: exception code when the code is untranslated |
-- | fn_snow_helper19_common | mplt_Race_Ind_Validation (OBJECT)                                                   |
-- | fn_snow_helper20_common | rule_Suffix_Std: exception code                                                     |
-- | fn_snow_helper21_common | mplt_Date_Greater_Than_Fifty_Years: the date, or NULL                               |
-- | fn_snow_helper22_common | rule_email_validation_v01 + local part + domain rules (OBJECT)                      |
-- | fn_snow_helper23_common | rule_Phone_Std, step 1: std_to_number cleaning (10 characters)                      |
-- | fn_snow_helper24_common | rule_Phone_Std, step 2: exception code (area code looked up by the caller)          |
-- | fn_snow_helper25_common | rule_Phone_Extension_Std (OBJECT)                                                   |
-- | fn_snow_helper26_common | rule_USA_SSN_Validation_post_June2011 (OBJECT)                                      |
-- | fn_snow_helper27_common | rule_MEDICAID_ID_Std (OBJECT)                                                       |
-- | fn_snow_helper28_common | rule_Member_Id_Std (OBJECT)                                                         |
-- | fn_snow_helper29_common | exp_Prepare_For_Address_Validation: trailing STE / SUITE removed                    |
-- | fn_snow_helper30_common | rule_Addr_Line_Pre_Scrub1                                                           |
-- | fn_snow_helper31_common | rule_Addr_Line_Post_Scrub                                                           |
-- | fn_snow_helper32_common | state FIPS: AddressDoctor, else source state, else 48 for Texas zips                |
-- | fn_snow_helper33_common | county FIPS: Texas kept, unknown 999, other state 996                               |
-- | fn_snow_helper34_common | mplt_Global_Addr_Validation (pass-through validator, OBJECT)                        |
-- | fn_snow_helper35_common | mplt_DST_Correction (TIMELINE): end date corrected for daylight saving              |
-- | fn_snow_helper36_common | run log line: mapping, step, row count                                              |
-- | fn_snow_helper37_common | rule_CARE_ID_Std (CRE) (OBJECT)                                                      |
--------------------------------------------------------------------------------------------------------------------

-- IDQ IS_NUMBER(): leading/trailing spaces allowed, optional sign, decimal point and exponent. NULL for NULL.
CREATE OR REPLACE FUNCTION fn_snow_helper01_common (p_value VARCHAR)
RETURNS NUMBER(1)
AS
$$
    CASE WHEN p_value IS NULL THEN NULL
         WHEN REGEXP_LIKE(p_value,
                  '[[:space:]]*[+-]?([0-9]+[.]?[0-9]*|[.][0-9]+)([eE][+-]?[0-9]+)?[[:space:]]*') THEN 1
         ELSE 0 END
$$;

-- New row of STG_<SRC>_PTY_INACTIVE_STS (Exp_New_Deactvn_Sts of the *_Pty_Validation mappings):
-- no hub cross-reference -> 'H' (history), HUB_STATE_IND = -1 -> 'D' (deactivated), otherwise 'P' (pending).
CREATE OR REPLACE FUNCTION fn_snow_helper02_common (p_hub_state_ind NUMBER)
RETURNS VARCHAR
AS
$$
    CASE WHEN p_hub_state_ind IS NULL THEN 'H'
         WHEN p_hub_state_ind = -1    THEN 'D'
         ELSE 'P' END
$$;

-- IDQ blank test LENGTH(RTRIM(x)) = 0 OR ISNULL(x). Snowflake, like IDQ and unlike Oracle, keeps '' apart from
-- NULL, so both halves are needed. RTRIM trims spaces only, as the IDQ function does.
CREATE OR REPLACE FUNCTION fn_snow_helper03_common (p_value VARCHAR)
RETURNS BOOLEAN
AS
$$
    p_value IS NULL OR LENGTH(RTRIM(p_value)) = 0
$$;

-- IDQ TO_DECIMAL(value, scale): the number rounded to the scale; a non-numeric string gives 0 and NULL gives NULL.
-- BAD DATA: a value that is not a number becomes 0 instead of failing the statement (TRY_TO_DECIMAL).
CREATE OR REPLACE FUNCTION fn_snow_helper04_common (p_value VARCHAR, p_scale NUMBER)
RETURNS NUMBER(38, 10)
AS
$$
    CASE WHEN p_value IS NULL THEN NULL
         WHEN fn_snow_helper01_common(p_value) = 0 THEN 0
         WHEN p_scale IS NULL THEN TRY_TO_DECIMAL(TRIM(p_value), 38, 10)
         ELSE ROUND(TRY_TO_DECIMAL(TRIM(p_value), 38, 10), p_scale) END
$$;

-- exp_Score_and_Exception_details.Score (address mappings of ECI, FSS, WIC and TRS). VALIDATION: '40' sends the
-- address to the exception queue. The mailability score is compared as a STRING, as in IDQ (fragile, but exact for
-- the single-digit scores the validator returns). A NULL score falls through to '100' unless the type is unknown.
CREATE OR REPLACE FUNCTION fn_snow_helper05_common (p_addr_tp_mstr VARCHAR, p_mailability_score VARCHAR,
                                                    p_match_code VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN p_addr_tp_mstr <> '002' AND p_mailability_score <= '3' THEN '40'
         WHEN p_addr_tp_mstr = '002' AND p_mailability_score < '3'
              AND SUBSTR(p_match_code, 1, 1) IN ('I', 'N') THEN '40'
         WHEN p_addr_tp_mstr IS NULL THEN '40'
         ELSE '100' END
$$;

-- exp_Score_and_Exception_details.Addr_Issue_Desc: why the address scored '40' (NULL when it scored '100').
CREATE OR REPLACE FUNCTION fn_snow_helper06_common (p_addr_tp_mstr VARCHAR, p_mailability_score VARCHAR,
                                                    p_match_code VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN p_addr_tp_mstr <> '002' AND p_mailability_score <= '3' THEN 'Invalid Address'
         WHEN p_addr_tp_mstr = '002' AND p_mailability_score < '3'
              AND SUBSTR(p_match_code, 1, 1) IN ('I', 'N') THEN 'Invalid Address'
         WHEN p_addr_tp_mstr IS NULL THEN 'Invalid Address Type' END
$$;

-- exp_Address_Hold.out_ADDR_LINE_1: an empty (blank) first line is replaced by the second line.
CREATE OR REPLACE FUNCTION fn_snow_helper07_common (p_line_1 VARCHAR, p_line_2 VARCHAR)
RETURNS VARCHAR
AS
$$
    IFF(fn_snow_helper03_common(p_line_1), p_line_2, p_line_1)
$$;

-- exp_Address_Hold.out_ADDR_LINE_2: the second line is cleared when it equals the held first line.
CREATE OR REPLACE FUNCTION fn_snow_helper08_common (p_line_1 VARCHAR, p_line_2 VARCHAR)
RETURNS VARCHAR
AS
$$
    IFF(fn_snow_helper07_common(p_line_1, p_line_2) = p_line_2, NULL, p_line_2)
$$;

-- IDQ token standardiser with "Remove Custom Strings" of single characters, removeMultipleSpaces and trim:
-- every character of p_chars is removed, runs of spaces become one space, the result is trimmed.
-- BAD DATA: junk characters are dropped from the value that is written.
CREATE OR REPLACE FUNCTION fn_snow_helper09_common (p_value VARCHAR, p_chars VARCHAR)
RETURNS VARCHAR
AS
$$
    REGEXP_REPLACE(TRIM(TRANSLATE(p_value, p_chars, '')), ' {2,}', ' ')
$$;

-- STD_remove_special_char: removes the entries of the IDQ reference table ref_special_char_list (shared content,
-- not in the exports; treated as every character that is neither a letter nor a digit, as the Java port does),
-- collapses spaces and trims. Nothing left -> NULL (same decision as com.idq.cli.core.rules.SpecialCharacters).
-- BAD DATA: special characters are dropped from the identifier that is written.
CREATE OR REPLACE FUNCTION fn_snow_helper10_common (p_value VARCHAR)
RETURNS VARCHAR
AS
$$
    NULLIF(REGEXP_REPLACE(TRIM(REGEXP_REPLACE(p_value, '[^[:alnum:] ]', '')), ' {2,}', ' '), '')
$$;

-- IDQ character labeler as used by the name mapplets: letters X, the digit zero 0, other digits 9, anything else
-- unchanged. (The IDQ labelers use content sets that are not in the export; this is what the expressions test.)
CREATE OR REPLACE FUNCTION fn_snow_helper11_common (p_value VARCHAR)
RETURNS VARCHAR
AS
$$
    REGEXP_REPLACE(REGEXP_REPLACE(p_value, '[[:alpha:]]', 'X'), '[1-9]', '9')
$$;

-- Trailing-number removal, step 1 (first labeler): a 0 between two letters becomes the letter o, unless the value
-- ends in a digit (J0hn -> John, but J0hn2 stays for step 2). BAD DATA.
CREATE OR REPLACE FUNCTION fn_snow_helper12_common (p_name VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN p_name IS NULL THEN NULL
         WHEN CONTAINS(fn_snow_helper11_common(p_name), 'X0X')
              AND NOT REGEXP_LIKE(TRIM(p_name), '.*[0-9]') THEN REPLACE(p_name, '0', 'o')
         ELSE p_name END
$$;

-- Trailing-number removal, step 2 (second labeler): the value is cut at its first digit (Smith2 -> Smith). When the
-- value ends in 0 and the two characters before the last are not both digits 1-9, the IDQ expression returns
-- p_keep instead (the caller passes the value itself, except for the middle name, see fn_snow_helper14_common).
-- The result is trimmed. BAD DATA.
CREATE OR REPLACE FUNCTION fn_snow_helper13_common (p_name VARCHAR, p_keep VARCHAR)
RETURNS VARCHAR
AS
$$
    TRIM(CASE WHEN p_name IS NULL THEN NULL
              WHEN NOT (LENGTH(TRIM(p_name)) >= 3
                        AND SUBSTR(fn_snow_helper11_common(TRIM(p_name)), LENGTH(TRIM(p_name)) - 2, 2) = '99')
                   AND RIGHT(TRIM(p_name), 1) = '0' THEN p_keep
              WHEN REGEXP_INSTR(p_name, '[0-9]') > 0 THEN SUBSTR(p_name, 1, REGEXP_INSTR(p_name, '[0-9]') - 1)
              ELSE p_name END)
$$;

-- mplt_Name_Standardization_Trailing_Num_Removal (also called directly by m_Tgt_C_S_TRS_Pty_Nm).
-- Returns OBJECT {first_name, middle_name, last_name, full_name}; full_name is rebuilt as first [middle] last
-- (p_full_name is accepted for the mapplet signature but, as in IDQ, not used).
-- IDQ quirk kept: in the "ends in 0" keep branch the middle-name expression returns the LAST name.
CREATE OR REPLACE FUNCTION fn_snow_helper14_common (p_first_name VARCHAR, p_middle_name VARCHAR,
                                                    p_last_name VARCHAR, p_full_name VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'first_name',  fn_snow_helper13_common(fn_snow_helper12_common(p_first_name),
                                               fn_snow_helper12_common(p_first_name)),
        'middle_name', fn_snow_helper13_common(fn_snow_helper12_common(p_middle_name),
                                               fn_snow_helper12_common(p_last_name)),
        'last_name',   fn_snow_helper13_common(fn_snow_helper12_common(p_last_name),
                                               fn_snow_helper12_common(p_last_name)),
        'full_name',   TRIM(NVL(fn_snow_helper13_common(fn_snow_helper12_common(p_first_name),
                                                        fn_snow_helper12_common(p_first_name)), '')
                            || IFF(fn_snow_helper03_common(fn_snow_helper13_common(
                                       fn_snow_helper12_common(p_middle_name), fn_snow_helper12_common(p_last_name))),
                                   '',
                                   ' ' || TRIM(fn_snow_helper13_common(fn_snow_helper12_common(p_middle_name),
                                                                       fn_snow_helper12_common(p_last_name))))
                            || ' '
                            || NVL(LTRIM(fn_snow_helper13_common(fn_snow_helper12_common(p_last_name),
                                                                 fn_snow_helper12_common(p_last_name))), '')))
$$;

-- mplt_Name_Standardization_Indv_Member (and the identical TTF copy CopyOf_mplt_Name_Standardization_Indv_Member).
-- The caller does the four lookups of the mapplet and passes the results:
--   p_std_prefix    V_LOOKUP_CODE_VALUE CODE_TYPE 'PREFIX' (lkp_V_Lookup_Prfx_Code_Value), key (p_src_system, prefix)
--   p_std_suffix    V_LOOKUP_CODE_VALUE CODE_TYPE 'SUFFIX' (lkp_V_Lookup_Sfx_Code_Value),  key (p_src_system, suffix)
--   p_first_junk    REF_JUNK_NAME_LIST edit limitation NULL / 'FIRST' has UPPER(TRIM(first name)) (Lookup__JUNK_FNAME)
--   p_last_junk     REF_JUNK_NAME_LIST edit limitation NULL / 'LAST'  has UPPER(TRIM(last name))  (Lookup_JUNK_LNAME)
-- Steps: junk first / last names blanked (BAD DATA), junk characters removed per field, title case, trailing numbers
-- removed (fn_snow_helper14_common), full name rebuilt. VALIDATION: a non-blank prefix / suffix that does not
-- translate gives Invalid_Prefix / Invalid_Suffix (returned; the member mappings do not write them).
-- Returns OBJECT {first_name, middle_name, last_name, full_name, src_full_name, prfx_name, src_prefix,
--                 prefix_exception_code, sfx_name, src_suffix, suffix_exception_code}.
CREATE OR REPLACE FUNCTION fn_snow_helper15_common (p_first_name VARCHAR, p_mdl_name VARCHAR, p_lst_name VARCHAR,
                                                    p_full_name VARCHAR, p_prfx_name VARCHAR, p_sfx_name VARCHAR,
                                                    p_std_prefix VARCHAR, p_std_suffix VARCHAR,
                                                    p_first_junk BOOLEAN, p_last_junk BOOLEAN)
RETURNS OBJECT
AS
$$
    OBJECT_INSERT(OBJECT_INSERT(OBJECT_INSERT(OBJECT_INSERT(OBJECT_INSERT(OBJECT_INSERT(OBJECT_INSERT(
        fn_snow_helper14_common(
            INITCAP(fn_snow_helper09_common(IFF(NVL(p_first_junk, FALSE), NULL, p_first_name),
                                            '~!`@#$%^&*()_+=":;?/.>,<' || CHR(9)), ' '),
            INITCAP(fn_snow_helper09_common(p_mdl_name,
                                            '~`!@#$%^&*()_-+=}{[]|\\"'':;?/>.<,' || CHR(9)), ' '),
            INITCAP(fn_snow_helper09_common(IFF(NVL(p_last_junk, FALSE), NULL, p_lst_name),
                                            '~`!@#$%^&*()_+=|\\}{[]";:?>.<,' || CHR(9)), ' '),
            INITCAP(fn_snow_helper09_common(NVL(p_full_name, NVL(TRIM(p_first_name), '') || ' '
                                                             || NVL(TRIM(p_lst_name), '')),
                                            '~`!@#$%^*()_+=\\|}]{[":;?/>.<,' || CHR(9)), ' ')),
        'src_full_name', NVL(p_full_name, NVL(TRIM(p_first_name), '') || ' ' || NVL(TRIM(p_lst_name), ''))),
        'prfx_name', p_std_prefix),
        'src_prefix', p_prfx_name),
        'prefix_exception_code',
            IFF(NOT fn_snow_helper03_common(p_prfx_name) AND p_std_prefix IS NULL, 'Invalid_Prefix', NULL)),
        'sfx_name', p_std_suffix),
        'src_suffix', p_sfx_name),
        'suffix_exception_code',
            IFF(NOT fn_snow_helper03_common(p_sfx_name) AND p_std_suffix IS NULL, 'Invalid_Suffix', NULL))
$$;

-- mplt_BirthDate_Validation. VALIDATION: a member source and an individual party with a birth date after the run
-- start gives 'Invalid_Birth_Date' (the mapplet then returns a NULL birth date: BAD DATA, done by the caller with
-- IFF(code IS NULL, birth date, NULL)). IDQ compares with SYSDATE; p_run_ts is the run start of the procedure.
-- The description and type come from EXC_LOOKUP_CODE_VALUE (caller's join).
CREATE OR REPLACE FUNCTION fn_snow_helper16_common (p_birth_date TIMESTAMP_NTZ, p_party_type VARCHAR,
                                                    p_src_sys VARCHAR, p_run_ts TIMESTAMP_NTZ)
RETURNS VARCHAR
AS
$$
    IFF(p_src_sys IN ('P23', 'C21', 'P88', 'MAX', 'P84', 'PMR', 'TRS', 'CRE', 'ECI', 'WIC', 'FSS', 'TTF')
        AND p_party_type IN ('HCP', 'Indv', 'INDV', 'I')
        AND p_birth_date > p_run_ts, 'Invalid_Birth_Date', NULL)
$$;

-- mplt_Gender_Validation. Returns OBJECT {gender_code, mdm_gender_code, exception_code}.
-- The mapplet reads the gender through the variable port v_Gender_First_Digit, declared string(1): IDQ truncates
-- to the port precision, so only the FIRST character counts ('Male' -> 'M' -> '1'). BAD DATA.
-- MDM code: M -> '1', F -> '2', B / U -> NULL for individuals ('I', 'Indv', 'INDV', 'HCP'); organisations NULL.
-- VALIDATION: for member sources and individuals, a missing, numeric or other first character -> 'Invalid_Gender'.
CREATE OR REPLACE FUNCTION fn_snow_helper17_common (p_gender_code VARCHAR, p_party_type VARCHAR, p_src_sys VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'gender_code', p_gender_code,
        'mdm_gender_code',
            CASE WHEN p_party_type IN ('I', 'Indv', 'INDV', 'HCP') AND LEFT(p_gender_code, 1) IN ('B', 'U') THEN NULL
                 WHEN p_party_type IN ('I', 'Indv', 'INDV', 'HCP') AND LEFT(p_gender_code, 1) = 'M' THEN '1'
                 WHEN p_party_type IN ('I', 'Indv', 'INDV', 'HCP') AND LEFT(p_gender_code, 1) = 'F' THEN '2'
                 ELSE NULL END,
        'exception_code',
            IFF(TRIM(p_src_sys) IN ('P23', 'C21', 'P88', 'MAX', 'P84', 'PMR', 'TRS', 'CRE', 'ECI', 'WIC', 'FSS', 'TTF')
                AND p_party_type IN ('HCP', 'Indv', 'INDV', 'I')
                AND (p_gender_code IS NULL
                     OR fn_snow_helper01_common(LEFT(p_gender_code, 1)) = 1
                     OR LEFT(p_gender_code, 1) NOT IN ('M', 'F', 'U', 'B')),
                'Invalid_Gender', NULL))
$$;

-- mplt_Race_Validation / mplt_Ethnicity_Validation / mplt_Language_Validation. The caller looks the source code up in
-- V_LOOKUP_CODE_VALUE (code type RACE / ETHNICITY / LANGUAGE_CD) and passes the master code.
-- VALIDATION: no master code (including a missing source code) -> p_exception_code ('Invalid_Race',
-- 'Invalid_Ethnicity', 'Invalid_Language'). The mapplet OUTPUTS the code as returned by the EXC_LOOKUP_CODE_VALUE
-- lookup, i.e. NULL when the exception is not configured; the caller joins for that.
CREATE OR REPLACE FUNCTION fn_snow_helper18_common (p_mstr_code_value VARCHAR, p_exception_code VARCHAR)
RETURNS VARCHAR
AS
$$
    IFF(p_mstr_code_value IS NULL, p_exception_code, NULL)
$$;

-- mplt_Race_Ind_Validation: five 0/1 indicators. Returns OBJECT {mdm_race_cd, src_race_ind_list, exception_code}.
-- Exactly one gives 001 white, 002 black, 003 native american, 004 asian, 005 pacific islander; two give 006; more
-- give 007. VALIDATION: none, or a NULL indicator (the sum is then NULL) -> 'Invalid_Race' (computed; the mapplet
-- outputs the looked-up code). Source value 'WH<w>AA<b>AS<a>PI<p>NA<n>' (a NULL indicator adds nothing, as in IDQ).
CREATE OR REPLACE FUNCTION fn_snow_helper19_common (p_white_ind NUMBER, p_black_ind NUMBER, p_asian_ind NUMBER,
                                                    p_pacific_islander_ind NUMBER, p_native_american_ind NUMBER)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'mdm_race_cd',
            CASE WHEN p_white_ind + p_black_ind + p_asian_ind + p_pacific_islander_ind + p_native_american_ind = 2
                     THEN '006'
                 WHEN p_white_ind + p_black_ind + p_asian_ind + p_pacific_islander_ind + p_native_american_ind > 2
                     THEN '007'
                 WHEN p_white_ind + p_black_ind + p_asian_ind + p_pacific_islander_ind + p_native_american_ind = 0
                     THEN NULL
                 WHEN p_white_ind + p_black_ind + p_asian_ind + p_pacific_islander_ind + p_native_american_ind = 1
                     THEN CASE WHEN p_white_ind = 1 THEN '001'
                               WHEN p_black_ind = 1 THEN '002'
                               WHEN p_native_american_ind = 1 THEN '003'
                               WHEN p_asian_ind = 1 THEN '004'
                               WHEN p_pacific_islander_ind = 1 THEN '005' END
                 ELSE NULL END,
        'src_race_ind_list',
            'WH' || NVL(TO_VARCHAR(p_white_ind), '') || 'AA' || NVL(TO_VARCHAR(p_black_ind), '')
            || 'AS' || NVL(TO_VARCHAR(p_asian_ind), '') || 'PI' || NVL(TO_VARCHAR(p_pacific_islander_ind), '')
            || 'NA' || NVL(TO_VARCHAR(p_native_american_ind), ''),
        'exception_code',
            IFF(NVL(p_white_ind + p_black_ind + p_asian_ind + p_pacific_islander_ind + p_native_american_ind, 0) = 0,
                'Invalid_Race', NULL))
$$;

-- rule_Suffix_Std. The caller looks the suffix up in V_LOOKUP_CODE_VALUE WITHOUT a code-type filter (as the rule
-- does: any code type with a matching source value translates it). VALIDATION: a non-blank suffix that does not
-- translate -> 'Invalid_Suffix'.
CREATE OR REPLACE FUNCTION fn_snow_helper20_common (p_suffix VARCHAR, p_std_suffix VARCHAR)
RETURNS VARCHAR
AS
$$
    IFF(NOT fn_snow_helper03_common(p_suffix) AND p_std_suffix IS NULL, 'Invalid_Suffix', NULL)
$$;

-- mplt_Date_Greater_Than_Fifty_Years: out_Date_Diff = DATE_DIFF(Input_Date, SYSDATE, 'YY') is a string(10) port,
-- and out_Date compares it with the STRING '50' (Decode(True, out_Date_Diff > '50', NULL, Input_Date)).
-- Reproduced as IDQ runs it: the fractional year difference is turned into text (cut to 10 characters) and compared
-- as text. BAD DATA / likely defect (docs/common_insights.md 1.15): besides dates more than 50 years ahead, dates
-- 6 to 10 years ahead also become NULL ('6.2' > '50' as text), while dates 100+ years ahead are kept ('100' < '50').
-- p_run_ts stands for SYSDATE.
CREATE OR REPLACE FUNCTION fn_snow_helper21_common (p_input_date TIMESTAMP_NTZ, p_run_ts TIMESTAMP_NTZ)
RETURNS TIMESTAMP_NTZ
AS
$$
    IFF(LEFT(TO_VARCHAR((MONTHS_BETWEEN(p_input_date, p_run_ts) / 12)::FLOAT), 10) > '50', NULL, p_input_date)
$$;

-- rule_email_validation_v01 with rule_email_LocalPart_validation_V1 and rule_email_Domain_Subdomain_validation__V1.
-- Returns OBJECT {email_address, exception_code}: the address trimmed and lower-cased, and 'Invalid_Email' (computed;
-- the rule outputs the looked-up code, so the caller joins EXC_LOOKUP_CODE_VALUE) when (VALIDATION):
--   white space inside; the local-part rule's literal test (address = 'invalid'); no '@' or no '.' after the '@';
--   the domain before the last dot is empty, starts with '.' or '-', ends with '-', has '_' after its first
--   character, has characters outside a-z 0-9 . -, or has '..' after its first character (the IDQ test is
--   INDEXOF('..') < 1, so a leading '..' passes); '..' after the first character of the whole domain part;
--   the top-level domain is not 2 to 11 letters / digits. A NULL address is invalid.
CREATE OR REPLACE FUNCTION fn_snow_helper22_common (p_email VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'email_address', LOWER(TRIM(p_email)),
        'exception_code',
            CASE WHEN p_email IS NULL THEN 'Invalid_Email'
                 WHEN REGEXP_LIKE(TRIM(p_email), '.*[[:space:]].*') THEN 'Invalid_Email'
                 WHEN LOWER(TRIM(p_email)) = 'invalid' THEN 'Invalid_Email'
                 WHEN POSITION('@', p_email) = 0 OR POSITION('.', p_email, POSITION('@', p_email)) = 0
                     THEN 'Invalid_Email'
                 WHEN NOT (
                        -- domain part = everything after the first '@', trimmed, lower case
                        NOT (POSITION('_', NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                             '^(.*)[.][^.]*$', 1, 1, 'e', 1), '')) > 1
                             OR STARTSWITH(NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                             '^(.*)[.][^.]*$', 1, 1, 'e', 1), ''), '.')
                             OR STARTSWITH(NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                             '^(.*)[.][^.]*$', 1, 1, 'e', 1), ''), '-')
                             OR ENDSWITH(NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                           '^(.*)[.][^.]*$', 1, 1, 'e', 1), ''), '-'))
                        AND REGEXP_LIKE(NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                          '^(.*)[.][^.]*$', 1, 1, 'e', 1), ''), '[a-z0-9.-]+')
                        AND POSITION('..', NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                             '^(.*)[.][^.]*$', 1, 1, 'e', 1), '')) <= 1
                        AND POSITION('..', TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1)))) <= 1)
                     THEN 'Invalid_Email'
                 WHEN NOT (REGEXP_LIKE(NVL(REGEXP_SUBSTR(TRIM(LOWER(SUBSTR(p_email, POSITION('@', p_email) + 1))),
                                                         '[.]([^.]*)$', 1, 1, 'e', 1), ''), '[a-z0-9]{2,11}'))
                     THEN 'Invalid_Email'
                 ELSE NULL END)
$$;

-- rule_Phone_Std, step 1 (std_to_number): punctuation and white space removed (the ML 12/30/2024 fix).
-- BAD DATA: exp_validate_Phone.Phone is a string(10) port and IDQ truncates to the port precision, so the value
-- the rule checks and returns is cut to 10 characters (docs/common_insights.md 9, "port precision"). The caller
-- looks the area code SUBSTR(<result>, 1, 3) up in REF_PHN_AREA_CD (fn_snow_helper44_common).
CREATE OR REPLACE FUNCTION fn_snow_helper23_common (p_phone VARCHAR)
RETURNS VARCHAR
AS
$$
    LEFT(fn_snow_helper09_common(p_phone, '~`!@#$%^&*()_-+=}{[]|\\"'':;?/>.<, ' || CHR(9)), 10)
$$;

-- rule_Phone_Std, step 2 (exp_validate_Phone.EXCEPTION_CODE1), VALIDATION, first match wins:
--   not a number, not 10 digits, all zeros, 4th digit 0/1             -> 'Invalid_Phone_Number'
--   ECI and area code '000' (7-digit numbers padded by the mapping)     -> 'Missing_AreaCode'
--   area code not in REF_PHN_AREA_CD (p_npa_id NULL), 1st digit 0/1     -> 'Invalid_Phone_Number'
--   TRS / CRE / ECI main or other number (001 / 003) on a toll-free code -> 'Invalid_Phone_Number'
-- p_phone is the cleaned value of fn_snow_helper23_common; p_npa_id / p_area_service the area-code lookup result.
CREATE OR REPLACE FUNCTION fn_snow_helper24_common (p_phone VARCHAR, p_src_sys VARCHAR, p_usg_tp VARCHAR,
                                                    p_npa_id VARCHAR, p_area_service VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN NVL(fn_snow_helper01_common(p_phone), 0) = 0 THEN 'Invalid_Phone_Number'
         WHEN LENGTH(p_phone) <> 10 OR p_phone = '0000000000' THEN 'Invalid_Phone_Number'
         WHEN SUBSTR(p_phone, 4, 1) IN ('0', '1') THEN 'Invalid_Phone_Number'
         WHEN p_src_sys = 'ECI' AND SUBSTR(p_phone, 1, 3) = '000' THEN 'Missing_AreaCode'
         WHEN p_npa_id IS NULL THEN 'Invalid_Phone_Number'
         WHEN SUBSTR(p_phone, 1, 1) IN ('0', '1') THEN 'Invalid_Phone_Number'
         WHEN p_src_sys IN ('TRS', 'CRE', 'ECI') AND p_usg_tp IN ('001', '003') AND p_area_service = 'Toll-Free'
             THEN 'Invalid_Phone_Number'
         ELSE NULL END
$$;

-- rule_Phone_Extension_Std: special characters removed (BAD DATA); VALIDATION: when present it must be 2 to 6
-- digits, else 'Invalid_Phone_Number_Ext'. Returns OBJECT {phone_nbr_ext, exception_code}.
CREATE OR REPLACE FUNCTION fn_snow_helper25_common (p_phone_nbr_ext VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'phone_nbr_ext', fn_snow_helper10_common(p_phone_nbr_ext),
        'exception_code',
            IFF(fn_snow_helper10_common(p_phone_nbr_ext) IS NOT NULL
                AND (LENGTH(fn_snow_helper10_common(p_phone_nbr_ext)) NOT BETWEEN 2 AND 6
                     OR fn_snow_helper01_common(fn_snow_helper10_common(p_phone_nbr_ext)) = 0),
                'Invalid_Phone_Number_Ext', NULL))
$$;

-- rule_USA_SSN_Validation_post_June2011. Returns OBJECT {ssn_status, ssn_error_message}.
-- VALIDATION: ssn_status 'Valid' when the value is nine digits (dashes / spaces allowed) with area not 000, 666 or
-- 9xx, group not 00 and serial not 0000. IDQ labels the value with the USANATID1 token set of the Informatica
-- content, which encodes these published post-June-2011 SSA rules; the token set itself is not in the export.
-- ssn_error_message is the rule's own expression on the digits with '-', ' ' and 'X' / 'x' removed
-- (REPLACESTR(0, In_SSN, '-', ' ', 'X', '')); the area test is a string comparison ('> 899'), as in IDQ.
CREATE OR REPLACE FUNCTION fn_snow_helper26_common (p_ssn VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'ssn_status',
            IFF(REGEXP_LIKE(REPLACE(REPLACE(TRIM(p_ssn), '-', ''), ' ', ''), '[0-9]{9}')
                AND LEFT(REPLACE(REPLACE(TRIM(p_ssn), '-', ''), ' ', ''), 3) NOT IN ('000', '666')
                AND LEFT(REPLACE(REPLACE(TRIM(p_ssn), '-', ''), ' ', ''), 1) <> '9'
                AND SUBSTR(REPLACE(REPLACE(TRIM(p_ssn), '-', ''), ' ', ''), 4, 2) <> '00'
                AND SUBSTR(REPLACE(REPLACE(TRIM(p_ssn), '-', ''), ' ', ''), 6, 4) <> '0000',
                'Valid', 'Invalid'),
        'ssn_error_message',
            CASE WHEN NVL(LENGTH(TRIM(REGEXP_REPLACE(p_ssn, '[- Xx]', ''))), 0) <> 9 THEN 'Invalid SSN length'
                 WHEN SUBSTR(TRIM(REGEXP_REPLACE(p_ssn, '[- Xx]', '')), 1, 3) IN ('000', '666')
                      OR SUBSTR(TRIM(REGEXP_REPLACE(p_ssn, '[- Xx]', '')), 1, 3) > '899' THEN 'SSN area invalid'
                 WHEN SUBSTR(TRIM(REGEXP_REPLACE(p_ssn, '[- Xx]', '')), 4, 2) = '00' THEN 'SSN group invalid'
                 WHEN SUBSTR(TRIM(REGEXP_REPLACE(p_ssn, '[- Xx]', '')), 6, 4) = '0000' THEN 'SSN serial invalid'
                 ELSE 'No error' END)
$$;

-- rule_MEDICAID_ID_Std: special characters removed (STD_remove_special_Char) and the value held in a string(10)
-- port (cut to 10 characters, BAD DATA). VALIDATION: not 9 characters -> 'Invalid_Medicaid_Id'.
-- Returns OBJECT {id_value, exception_code}.
CREATE OR REPLACE FUNCTION fn_snow_helper27_common (p_medicaid_id VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'id_value', LEFT(fn_snow_helper10_common(p_medicaid_id), 10),
        'exception_code', IFF(LENGTH(LEFT(fn_snow_helper10_common(p_medicaid_id), 10)) <> 9,
                              'Invalid_Medicaid_Id', NULL))
$$;

-- rule_Member_Id_Std: as rule_MEDICAID_ID_Std; VALIDATION: not 9 or 10 characters -> 'Invalid_Member_Id'.
-- Returns OBJECT {id_value, exception_code}.
CREATE OR REPLACE FUNCTION fn_snow_helper28_common (p_member_id VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'id_value', LEFT(fn_snow_helper10_common(p_member_id), 10),
        'exception_code', IFF(LENGTH(LEFT(fn_snow_helper10_common(p_member_id), 10)) NOT IN (9, 10),
                              'Invalid_Member_Id', NULL))
$$;

-- exp_Prepare_For_Address_Validation: a trailing 'STE #', 'SUITE', 'STE.' or 'STE' (any case) is cut before the
-- validator (the result is the trimmed line without that tail; other lines are returned unchanged). BAD DATA.
CREATE OR REPLACE FUNCTION fn_snow_helper29_common (p_line VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN p_line IS NULL THEN NULL
         WHEN ENDSWITH(UPPER(TRIM(p_line)), 'STE #') THEN LEFT(TRIM(p_line), LENGTH(TRIM(p_line)) - 5)
         WHEN ENDSWITH(UPPER(TRIM(p_line)), 'SUITE') THEN LEFT(TRIM(p_line), LENGTH(TRIM(p_line)) - 5)
         WHEN ENDSWITH(UPPER(TRIM(p_line)), 'STE.')  THEN LEFT(TRIM(p_line), LENGTH(TRIM(p_line)) - 4)
         WHEN ENDSWITH(UPPER(TRIM(p_line)), 'STE')   THEN LEFT(TRIM(p_line), LENGTH(TRIM(p_line)) - 3)
         ELSE p_line END
$$;

-- rule_Addr_Line_Pre_Scrub1: upper case, junk characters removed (line 2 also removes '-', line 1 '_'), spaces
-- collapsed, '##' runs become '#', back slashes become slashes. BAD DATA.
CREATE OR REPLACE FUNCTION fn_snow_helper30_common (p_line VARCHAR, p_second_line BOOLEAN)
RETURNS VARCHAR
AS
$$
    REPLACE(REGEXP_REPLACE(
                fn_snow_helper09_common(UPPER(p_line),
                                        IFF(p_second_line, '$)(@^!~*%+-={}[]|:;"''<>?&', '$)(@^!~*%+_={}[]|:;"''<>?&')),
                '#{2,}', '#'),
            '\\', '/')
$$;

-- rule_Addr_Line_Post_Scrub: 'C/O' becomes 'c/o' and a dangling unit designator (#, APT, BLDG, DEPT, FL, HNGR, KEY,
-- LOT, PIER, RM, SLIP, SPC, STOP, STE, TRLR, UNIT) at the end of the line is dropped. BAD DATA.
CREATE OR REPLACE FUNCTION fn_snow_helper31_common (p_line VARCHAR)
RETURNS VARCHAR
AS
$$
    TRIM(REGEXP_REPLACE(
             REPLACE(IFF(STARTSWITH(REGEXP_REPLACE(TRIM(p_line), ' {2,}', ' '), 'C/O '),
                         'c/o ' || SUBSTR(REGEXP_REPLACE(TRIM(p_line), ' {2,}', ' '), 5),
                         REGEXP_REPLACE(TRIM(p_line), ' {2,}', ' ')),
                     ' C/O ', ' c/o '),
             '[[:space:]]+(#|APT|BLDG|DEPT|FL|HNGR|KEY|LOT|PIER|RM|SLIP|SPC|STOP|STE|TRLR|UNIT)$', '', 1, 0, 'i'))
$$;

-- State FIPS of mplt_Global_Addr_Validation: AddressDoctor's value, else the source state translated through
-- V_LOOKUP_CODE_VALUE 'STATE' (passed in), else '48' for Texas zip ranges (73301, 75001-79999 except 75502,
-- 88510-88589), else NULL.
CREATE OR REPLACE FUNCTION fn_snow_helper32_common (p_ad_state_fips VARCHAR, p_source_state_fips VARCHAR,
                                                    p_zip5 VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN NOT fn_snow_helper03_common(p_ad_state_fips) THEN p_ad_state_fips
         WHEN NOT fn_snow_helper03_common(p_source_state_fips) THEN p_source_state_fips
         WHEN p_zip5 = '73301'
              OR (p_zip5 BETWEEN '75001' AND '79999' AND p_zip5 <> '75502')
              OR p_zip5 BETWEEN '88510' AND '88589' THEN '48'
         ELSE NULL END
$$;

-- County FIPS of mplt_Global_Addr_Validation: kept for Texas (state FIPS 48), '999' when unknown, '996' for another
-- state.
CREATE OR REPLACE FUNCTION fn_snow_helper33_common (p_ad_state_fips VARCHAR, p_ad_county_fips VARCHAR)
RETURNS VARCHAR
AS
$$
    CASE WHEN p_ad_state_fips = '48' THEN p_ad_county_fips
         WHEN p_ad_county_fips IS NULL THEN '999'
         ELSE '996' END
$$;

-- mplt_Global_Addr_Validation (rule_Addr_Line_Pre_Scrub1, dq_Global_AddressValidation_Hybrid,
-- rule_Addr_Line_Post_Scrub and the FIPS / zip / geocode expressions).
--
-- dq_Global_AddressValidation_Hybrid is Informatica AddressDoctor, a licensed service that Snowflake does not have.
-- This function is the PASS-THROUGH validator (same as com.idq.cli.core.rules.PassThroughAddressValidator): every
-- expression of the mapplet runs, and the prepared input stands in for the service result. AddressDoctor-only
-- outputs (match code, mailability score, geocodes, CASS / DPV, building parts, ...) are NULL; latitude and
-- longitude are 0, as exp_Latt_Lngtd_Dec_Conv makes empty geocodes. With a NULL mailability score every address
-- with a known type scores '100' (fn_snow_helper05_common). To validate for real, replace this function by one
-- with the same signature that calls an address service through an external function, and keep the keys.
--
-- p_source_state_fips is the caller's lkp_State_Cd join: V_LOOKUP_CODE_VALUE CODE_TYPE 'STATE', key
-- (NVL(src_sys, 'TRS'), UPPER(TRIM(state))).
-- Returns OBJECT with the keys of the mapplet output used by the mappings (see the README for the full list):
--   delivery_address_line1, delivery_address_line2, city, postcode_complete, zip_cd_5, zip_cd_4_extn,
--   country_iso2_char, province_iso3, state_fips_cd, county_fips_cd, geocoding_latitude, geocoding_longitude,
--   match_code, mailability_score, address_type, ... (NULL keys are present so a real validator can fill them).
CREATE OR REPLACE FUNCTION fn_snow_helper34_common (p_address_1 VARCHAR, p_address_2 VARCHAR, p_city VARCHAR,
                                                    p_state VARCHAR, p_postal_code VARCHAR, p_country VARCHAR,
                                                    p_source_state_fips VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'delivery_address_line1', fn_snow_helper31_common(fn_snow_helper30_common(fn_snow_helper29_common(p_address_1), FALSE)),
        'delivery_address_line2', fn_snow_helper31_common(fn_snow_helper30_common(fn_snow_helper29_common(p_address_2), TRUE)),
        'city',                   p_city,
        'postcode_complete',      TRIM(p_postal_code),
        'zip_cd_5',               SUBSTR(TRIM(p_postal_code), 1, 5),
        'zip_cd_4_extn',          SUBSTR(TRIM(p_postal_code), 7, 4),
        'country_iso2_char',      p_country,
        'province_iso3',          NULL,
        'state_fips_cd',          fn_snow_helper32_common(NULL, p_source_state_fips, SUBSTR(TRIM(p_postal_code), 1, 5)),
        'county_fips_cd',         fn_snow_helper33_common(NULL, NULL),
        'geocoding_latitude',     0,
        'geocoding_longitude',    0,
        'geocoding_status',       NULL,
        'geocoding_complete',     NULL,
        'match_code',             NULL,
        'status_info_match_code', NULL,
        'status_info_result_percentage', NULL,
        'mailability_score',      NULL,
        'address_type',           NULL,
        'residential_delivery_indicator', NULL,
        'organization_complete',  NULL,
        'organization_name',      NULL,
        'organization_descriptor', NULL,
        'organization_department', NULL,
        'building_name',          NULL,
        'building_number',        NULL,
        'building_complete',      NULL,
        'street_number_complete', NULL,
        'sub_building_number',    NULL,
        'sub_building_complete',  NULL,
        'sub_building_descriptor', NULL,
        'early_warning_system_return_cd', NULL,
        'cass_error_code',        NULL,
        'dpv_confirmation',       NULL)
$$;

-- mplt_DST_Correction (TIMELINE). The caller looks up REF_DYLGHT_SVNGS_TM on DST = end date + 2 hours
-- (LKP_REF_DYLGHT_SVNGS_TM) and passes whether it matched. End date + 1 hour when start = end or when that lookup
-- matched; otherwise the end date unchanged (Informatica "fall back" duplicate-key workaround).
CREATE OR REPLACE FUNCTION fn_snow_helper35_common (p_period_start_date TIMESTAMP_NTZ,
                                                    p_period_end_date TIMESTAMP_NTZ, p_dst_matched BOOLEAN)
RETURNS TIMESTAMP_NTZ
AS
$$
    IFF(NVL(p_period_start_date = p_period_end_date, FALSE) OR NVL(p_dst_matched, FALSE),
        DATEADD(hour, 1, p_period_end_date), p_period_end_date)
$$;

-- One run-log line per step; the procedures append the lines to their return value and send them to the event
-- table with SYSTEM$LOG_INFO.
CREATE OR REPLACE FUNCTION fn_snow_helper36_common (p_mapping_name VARCHAR, p_step VARCHAR, p_rows NUMBER)
RETURNS VARCHAR
AS
$$
    TO_VARCHAR(CURRENT_TIMESTAMP(), 'YYYY-MM-DD HH24:MI:SS.FF3') || ' ' || NVL(p_mapping_name, '') || ' '
    || NVL(p_step, '') || ': ' || NVL(TO_VARCHAR(p_rows), '0') || ' row(s)'
$$;

-- rule_CARE_ID_Std (CRE): special characters removed (Std_CARE_ID, ref_special_char_list) and the value held in a
-- string(10) port (cut to 10 characters, BAD DATA). The rule's exception ports are not fed, so it never raises an
-- exception (exception_code is always NULL). Returns OBJECT {id_value, exception_code}.
CREATE OR REPLACE FUNCTION fn_snow_helper37_common (p_care_id VARCHAR)
RETURNS OBJECT
AS
$$
    OBJECT_CONSTRUCT_KEEP_NULL(
        'id_value', LEFT(fn_snow_helper10_common(p_care_id), 10),
        'exception_code', NULL)
$$;
