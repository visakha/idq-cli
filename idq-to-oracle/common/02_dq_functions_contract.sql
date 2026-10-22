--------------------------------------------------------------------------------------------------------------------
-- 02_dq_functions_contract.sql
--
-- CONTRACT of the data-quality functions (fn_dq_*) that do the work of the IDQ mapplets and rules.
--
-- These functions are ASSUMED TO EXIST in the target schema (they are shared by every mapping, see
-- docs/mappings/000_mapplets.md for the business rules). This file only fixes their names and signatures so the
-- sp_ors_main_* procedures compile:
--
--   * Each function is a 1:1 replacement of one IDQ mapplet / rule, called once per row.
--   * Lookups the mapplet does internally (V_LOOKUP_CODE_VALUE, EXC_LOOKUP_CODE_VALUE, REF_JUNK_NAME_LIST,
--     REF_PHN_AREA_CD, ref_MatchCode_Desc, ...) are done INSIDE the function.
--   * The bodies below are placeholders that raise ORA-20999. Do NOT run this file over the real implementations;
--     run it only in a scratch schema to compile the procedures, or replace each body with the real logic.
--
-- | IDQ mapplet / rule                                   | Oracle function                 | returns
-- |------------------------------------------------------|---------------------------------|------------------------------
-- | mplt_Name_Standardization_Indv_Member (+ TTF CopyOf) | fn_dq_std_name_indv_member      | t_dq_name_std
-- | mplt_Name_Standardization_Trailing_Num_Removal       | fn_dq_std_name_trailing_num     | t_dq_name_parts
-- | mplt_BirthDate_Validation                            | fn_dq_valid_birth_date          | t_dq_birth_date
-- | mplt_Gender_Validation                               | fn_dq_valid_gender              | t_dq_gender
-- | mplt_Ethnicity_Validation                            | fn_dq_valid_ethnicity           | t_dq_code_check
-- | mplt_Language_Validation                             | fn_dq_valid_language            | t_dq_code_check
-- | mplt_Race_Validation                                 | fn_dq_valid_race                | t_dq_code_check
-- | mplt_Race_Ind_Validation                             | fn_dq_valid_race_ind            | t_dq_race_ind
-- | rule_Suffix_Std                                      | fn_dq_std_suffix                | t_dq_suffix
-- | mplt_Date_Greater_Than_Fifty_Years                   | fn_dq_date_within_50y           | t_dq_date_50y
-- | rule_email_validation_v01 (+ local part / domain)    | fn_dq_valid_email               | t_dq_email
-- | rule_Phone_Std                                       | fn_dq_std_phone                 | t_dq_phone
-- | rule_Phone_Extension_Std                             | fn_dq_std_phone_ext             | t_dq_phone_ext
-- | rule_USA_SSN_Validation_post_June2011                | fn_dq_valid_ssn                 | t_dq_ssn
-- | rule_MEDICAID_ID_Std                                 | fn_dq_std_medicaid_id           | t_dq_ident
-- | rule_Member_Id_Std                                   | fn_dq_std_member_id             | t_dq_ident
-- | rule_CARE_ID_Std (CRE)                               | fn_dq_std_care_id               | t_dq_ident
-- | mplt_Global_Addr_Validation (+ rule_Addr_Line_*)     | fn_dq_valid_global_addr         | t_dq_address
-- | mplt_DST_Correction (TIMELINE)                       | fn_dq_dst_correction            | DATE
-- | mplt_Member_Pty_Rle_Phn_Normalization (TRS)          | fn_dq_norm_member_phn           | t_dq_member_phn_tab (pipelined)
-- | mplt_TRS_Pty_Rle_Alt_Id_Normalization (TRS)          | fn_dq_norm_trs_alt_id           | t_dq_trs_alt_id_tab (pipelined)
--
-- Set-level mapplets are not functions; the procedures that use them inline their SQL (and say so):
--   mplt_Member_Pty_Rle_Phn_Consolidation, mplt_Member_Pty_Rle_EAddr_Consolidation,
--   mplt_Member_Pty_Rle_Rel_Consolidation, mplt_Pty_Rle_Rel_Timeline_Validation (TIMELINE).
--
-- Every function is DETERMINISTIC with respect to its inputs for a given state of the reference tables and must be
-- callable from SQL (no DML, no COMMIT).
--------------------------------------------------------------------------------------------------------------------

-- mplt_Name_Standardization_Indv_Member: prefix/suffix via V_LOOKUP_CODE_VALUE (PREFIX / SUFFIX for p_src_system),
-- junk first/last names (REF_JUNK_NAME_LIST) blanked, junk characters removed, title case, trailing numbers removed
-- (fn_dq_std_name_trailing_num), full name rebuilt.
CREATE OR REPLACE FUNCTION fn_dq_std_name_indv_member (
    p_first_name  IN VARCHAR2,
    p_mdl_name    IN VARCHAR2,
    p_lst_name    IN VARCHAR2,
    p_full_name   IN VARCHAR2,
    p_prfx_name   IN VARCHAR2,
    p_sfx_name    IN VARCHAR2,
    p_org_name    IN VARCHAR2,
    p_dba_name    IN VARCHAR2,
    p_src_system  IN VARCHAR2
) RETURN t_dq_name_std
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_name_indv_member is assumed to exist');
END fn_dq_std_name_indv_member;
/

-- mplt_Name_Standardization_Trailing_Num_Removal: a 0 between letters becomes o; the value is cut at the first digit
-- unless it ends in 0 after a non-"99" label tail.
CREATE OR REPLACE FUNCTION fn_dq_std_name_trailing_num (
    p_first_name   IN VARCHAR2,
    p_middle_name  IN VARCHAR2,
    p_last_name    IN VARCHAR2,
    p_full_name    IN VARCHAR2
) RETURN t_dq_name_parts
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_name_trailing_num is assumed to exist');
END fn_dq_std_name_trailing_num;
/

-- mplt_BirthDate_Validation: member sources and individual parties with a birth date after SYSDATE get
-- 'Invalid_Birth_Date' and a NULL birth date; description/type from EXC_LOOKUP_CODE_VALUE.
CREATE OR REPLACE FUNCTION fn_dq_valid_birth_date (
    p_birth_date  IN DATE,
    p_party_type  IN VARCHAR2,
    p_src_sys     IN VARCHAR2
) RETURN t_dq_birth_date
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_birth_date is assumed to exist');
END fn_dq_valid_birth_date;
/

-- mplt_Gender_Validation: M -> 1, F -> 2, B/U -> NULL for individuals; missing, numeric or other -> 'Invalid_Gender'.
CREATE OR REPLACE FUNCTION fn_dq_valid_gender (
    p_gender_code  IN VARCHAR2,
    p_party_type   IN VARCHAR2,
    p_src_sys      IN VARCHAR2
) RETURN t_dq_gender
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_gender is assumed to exist');
END fn_dq_valid_gender;
/

-- mplt_Ethnicity_Validation: V_LOOKUP_CODE_VALUE code type ETHNICITY; untranslated -> 'Invalid_Ethnicity'.
CREATE OR REPLACE FUNCTION fn_dq_valid_ethnicity (
    p_ethnicity_cd  IN VARCHAR2,
    p_src_sys       IN VARCHAR2
) RETURN t_dq_code_check
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_ethnicity is assumed to exist');
END fn_dq_valid_ethnicity;
/

-- mplt_Language_Validation: code type LANGUAGE_CD; untranslated -> 'Invalid_Language'.
CREATE OR REPLACE FUNCTION fn_dq_valid_language (
    p_language_cd  IN VARCHAR2,
    p_src_sys      IN VARCHAR2
) RETURN t_dq_code_check
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_language is assumed to exist');
END fn_dq_valid_language;
/

-- mplt_Race_Validation: code type RACE; untranslated -> 'Invalid_Race'.
CREATE OR REPLACE FUNCTION fn_dq_valid_race (
    p_race_cd  IN VARCHAR2,
    p_src_sys  IN VARCHAR2
) RETURN t_dq_code_check
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_race is assumed to exist');
END fn_dq_valid_race;
/

-- mplt_Race_Ind_Validation: five 0/1 indicators -> 001..007; none (or a NULL indicator) -> 'Invalid_Race'.
CREATE OR REPLACE FUNCTION fn_dq_valid_race_ind (
    p_white_ind             IN NUMBER,
    p_black_ind             IN NUMBER,
    p_asian_ind             IN NUMBER,
    p_pacific_islander_ind  IN NUMBER,
    p_native_american_ind   IN NUMBER
) RETURN t_dq_race_ind
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_race_ind is assumed to exist');
END fn_dq_valid_race_ind;
/

-- rule_Suffix_Std: V_LOOKUP_CODE_VALUE without a code-type filter; non-blank untranslated -> 'Invalid_Suffix'.
CREATE OR REPLACE FUNCTION fn_dq_std_suffix (
    p_suffix   IN VARCHAR2,
    p_src_sys  IN VARCHAR2
) RETURN t_dq_suffix
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_suffix is assumed to exist');
END fn_dq_std_suffix;
/

-- mplt_Date_Greater_Than_Fifty_Years: a date more than 50 years after SYSDATE becomes NULL (open ended).
CREATE OR REPLACE FUNCTION fn_dq_date_within_50y (
    p_input_date  IN DATE
) RETURN t_dq_date_50y
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_date_within_50y is assumed to exist');
END fn_dq_date_within_50y;
/

-- rule_email_validation_v01: trimmed, lower case; 'Invalid_Email' per the local-part / domain / TLD rules.
CREATE OR REPLACE FUNCTION fn_dq_valid_email (
    p_email  IN VARCHAR2
) RETURN t_dq_email
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_email is assumed to exist');
END fn_dq_valid_email;
/

-- rule_Phone_Std: punctuation removed; Invalid_Phone_Number / Missing_AreaCode (ECI '000'); area code checked in
-- REF_PHN_AREA_CD (in service, US or non-geographic; Snowflake current_date() = SYSDATE); TRS/CRE/ECI main and other
-- numbers (001/003) may not use a toll-free area code.
CREATE OR REPLACE FUNCTION fn_dq_std_phone (
    p_phone    IN VARCHAR2,
    p_src_sys  IN VARCHAR2,
    p_usg_tp   IN VARCHAR2
) RETURN t_dq_phone
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_phone is assumed to exist');
END fn_dq_std_phone;
/

-- rule_Phone_Extension_Std: special characters removed; 2..6 digits else 'Invalid_Phone_Number_Ext'.
CREATE OR REPLACE FUNCTION fn_dq_std_phone_ext (
    p_phone_nbr_ext  IN VARCHAR2
) RETURN t_dq_phone_ext
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_phone_ext is assumed to exist');
END fn_dq_std_phone_ext;
/

-- rule_USA_SSN_Validation_post_June2011: nine digits, area not 000/666/9xx, group not 00, serial not 0000.
CREATE OR REPLACE FUNCTION fn_dq_valid_ssn (
    p_ssn  IN VARCHAR2
) RETURN t_dq_ssn
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_ssn is assumed to exist');
END fn_dq_valid_ssn;
/

-- rule_MEDICAID_ID_Std: special characters removed; not 9 characters -> 'Invalid_Medicaid_Id'.
CREATE OR REPLACE FUNCTION fn_dq_std_medicaid_id (
    p_medicaid_id  IN VARCHAR2
) RETURN t_dq_ident
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_medicaid_id is assumed to exist');
END fn_dq_std_medicaid_id;
/

-- rule_Member_Id_Std: special characters removed; not 9 or 10 characters -> 'Invalid_Member_Id'.
CREATE OR REPLACE FUNCTION fn_dq_std_member_id (
    p_member_id  IN VARCHAR2
) RETURN t_dq_ident
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_member_id is assumed to exist');
END fn_dq_std_member_id;
/

-- rule_CARE_ID_Std (CRE): special characters removed (ref_special_char_list); the rule raises no exception (its
-- exception ports are not fed, so exception_code / _type / _desc are always NULL).
CREATE OR REPLACE FUNCTION fn_dq_std_care_id (
    p_care_id  IN VARCHAR2
) RETURN t_dq_ident
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_std_care_id is assumed to exist');
END fn_dq_std_care_id;
/

-- mplt_Global_Addr_Validation: suite stripping, pre-scrub, AddressDoctor, post-scrub, state/county FIPS, zip split.
CREATE OR REPLACE FUNCTION fn_dq_valid_global_addr (
    p_address_1    IN VARCHAR2,
    p_address_2    IN VARCHAR2,
    p_city         IN VARCHAR2,
    p_state        IN VARCHAR2,
    p_postal_code  IN VARCHAR2,
    p_country      IN VARCHAR2,
    p_src_sys      IN VARCHAR2
) RETURN t_dq_address
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_valid_global_addr is assumed to exist');
END fn_dq_valid_global_addr;
/

-- mplt_DST_Correction (TIMELINE): end date + 1 hour when start = end, or when end + 2 hours is a daylight-saving
-- change (REF_DYLGHT_SVNGS_TM); otherwise the end date unchanged.
CREATE OR REPLACE FUNCTION fn_dq_dst_correction (
    p_period_start_date  IN DATE,
    p_period_end_date    IN DATE
) RETURN DATE
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_dst_correction is assumed to exist');
END fn_dq_dst_correction;
/

-- mplt_Member_Pty_Rle_Phn_Normalization (TRS, row-multiplying): normalizes three phone slots into rows, runs
-- rule_Phone_Std on each, drops slots whose cleaned number is NULL (Filter_Null_Phone_Nums) and builds the key with
-- the usage master code (LOOKUP_CODE_VALUE PHN_USG_TP). Called as TABLE(fn_dq_norm_member_phn(...)).
CREATE OR REPLACE FUNCTION fn_dq_norm_member_phn (
    p_period_start_date  IN DATE,
    p_pty_fk             IN VARCHAR2,
    p_src_sys            IN VARCHAR2,
    p_case_number        IN VARCHAR2,
    p_usg_tp_primary     IN VARCHAR2,
    p_phn_tp_primary     IN VARCHAR2,
    p_phn_num_primary    IN VARCHAR2,
    p_usg_tp_secondary   IN VARCHAR2,
    p_phn_tp_secondary   IN VARCHAR2,
    p_phn_num_secondary  IN VARCHAR2,
    p_usg_tp_tertiary    IN VARCHAR2,
    p_phn_tp_tertiary    IN VARCHAR2,
    p_phn_num_tertiary   IN VARCHAR2
) RETURN t_dq_member_phn_tab PIPELINED
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_norm_member_phn is assumed to exist');
    RETURN;
END fn_dq_norm_member_phn;
/

-- mplt_TRS_Pty_Rle_Alt_Id_Normalization (TRS, row-multiplying): validates the SSN (rule_USA_SSN_Validation_post_June2011;
-- invalid -> NULL value and 'Invalid_SSN'), the Medicaid id and the member id, normalizes the ids into rows, translates
-- the type with LOOKUP_CODE_VALUE ALT_ID_TP and drops empty values (FLTR_Remove_Null_Alt_IDs). Rows with an exception
-- code have is_valid = 'N': the IDQ mapplet writes those to EXC_STG_BAD_REC_MEMB itself; here the calling procedure
-- does. Called as TABLE(fn_dq_norm_trs_alt_id(...)).
CREATE OR REPLACE FUNCTION fn_dq_norm_trs_alt_id (
    p_pkey_src_object_pty     IN VARCHAR2,
    p_period_start_date       IN DATE,
    p_src_sys                 IN VARCHAR2,
    p_alt_id_val_member_id    IN VARCHAR2,
    p_alt_id_val_ssn          IN VARCHAR2,
    p_alt_id_val_medicaid_id  IN VARCHAR2,
    p_alt_id_val_ns_client_id IN VARCHAR2,
    p_cv_ind                  IN VARCHAR2
) RETURN t_dq_trs_alt_id_tab PIPELINED
IS
BEGIN
    RAISE_APPLICATION_ERROR(-20999, 'contract stub: fn_dq_norm_trs_alt_id is assumed to exist');
    RETURN;
END fn_dq_norm_trs_alt_id;
/
