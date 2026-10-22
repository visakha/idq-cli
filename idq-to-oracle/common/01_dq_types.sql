--------------------------------------------------------------------------------------------------------------------
-- 01_dq_types.sql
--
-- SQL object types returned by the data-quality functions (fn_dq_*) that stand in for the IDQ mapplets and rules.
-- One type per mapplet output group; attribute names follow the mapplet output ports (snake_case).
-- The types are SQL-level (not PL/SQL) so the functions can be called from plain SQL inside the main procedures.
--
-- Drop order matters only when a type is changed: drop the dependent functions/procedures first or use FORCE.
--------------------------------------------------------------------------------------------------------------------

-- mplt_Name_Standardization_Indv_Member (and the TTF copy CopyOf_mplt_Name_Standardization_Indv_Member)
CREATE OR REPLACE TYPE t_dq_name_std FORCE AS OBJECT (
    first_name              VARCHAR2(50),   -- First_Name  (junk names blanked, junk characters removed, title case,
    mdl_name                VARCHAR2(50),   -- Mdl_Name     trailing numbers removed)
    lst_name                VARCHAR2(50),   -- Lst_Name
    full_name               VARCHAR2(255),  -- Full_Name   (rebuilt as first [middle] last)
    src_full_name           VARCHAR2(255),  -- Src_Full_Name (input full name, or first || ' ' || last)
    prfx_name               VARCHAR2(50),   -- Prfx_Name   (V_LOOKUP_CODE_VALUE PREFIX master code)
    src_prefix              VARCHAR2(50),   -- Src_Prefix
    prefix_exception_code   VARCHAR2(20),   -- Prefix_Exception_Code  ('Invalid_Prefix' or NULL)
    sfx_name                VARCHAR2(50),   -- Sfx_Name    (V_LOOKUP_CODE_VALUE SUFFIX master code)
    src_suffix              VARCHAR2(50),   -- Src_Suffix
    suffix_exception_code   VARCHAR2(300),  -- Suffix_Exception_Code  ('Invalid_Suffix' or NULL)
    org_name                VARCHAR2(255),  -- Org_Name
    dba_name                VARCHAR2(255)   -- DBA_Name
);
/

-- mplt_Name_Standardization_Trailing_Num_Removal (used inside the above, and directly by TRS m_Tgt_C_S_TRS_Pty_Nm)
CREATE OR REPLACE TYPE t_dq_name_parts FORCE AS OBJECT (
    first_name   VARCHAR2(30),   -- out_FName
    middle_name  VARCHAR2(30),   -- out_MName (IDQ quirk kept: returns the LAST name in the "ends in 0" keep branch)
    last_name    VARCHAR2(30),   -- out_LName
    full_name    VARCHAR2(255)   -- out_FullName
);
/

-- mplt_BirthDate_Validation
CREATE OR REPLACE TYPE t_dq_birth_date FORCE AS OBJECT (
    birth_date             DATE,           -- BirthDate (NULL when the exception fires)
    exception_code         VARCHAR2(100),  -- Exception_Code ('Invalid_Birth_Date' or NULL; computed, not looked up)
    exception_description  VARCHAR2(255),  -- Exception_Description (EXC_LOOKUP_CODE_VALUE.EXCEPTION_DESC)
    exception_type         VARCHAR2(100),  -- Exception_Type        (EXC_LOOKUP_CODE_VALUE.EXCEPTION_TYPE)
    attribute_name         VARCHAR2(100),  -- Attribute_Name ('Birth Date')
    attribute_value        DATE            -- Attribute_Value (the input birth date)
);
/

-- mplt_Gender_Validation
CREATE OR REPLACE TYPE t_dq_gender FORCE AS OBJECT (
    gender_code                   VARCHAR2(20),   -- Gender_Code (input, passed through)
    mdm_gender_code               VARCHAR2(10),   -- MDM_Gender_Code (M -> 1, F -> 2, B/U -> NULL; organisations NULL)
    gender_exception_code         VARCHAR2(100),  -- Gender_Exception_Code ('Invalid_Gender' or NULL; computed)
    gender_exception_description  VARCHAR2(255),  -- Gender_Exception_Description (EXC_LOOKUP_CODE_VALUE; NULL when
    gender_exception_type         VARCHAR2(100)   -- Gender_Exception_Type          the code is not configured)
);
/

-- mplt_Ethnicity_Validation, mplt_Language_Validation, mplt_Race_Validation
CREATE OR REPLACE TYPE t_dq_code_check FORCE AS OBJECT (
    src_code          VARCHAR2(100),  -- Ethnicity_Cd / Language_Cd / Race_Cd (input, passed through)
    src_sys           VARCHAR2(10),   -- Src_Sys (input, passed through)
    mstr_code_value   VARCHAR2(100),  -- MSTR_CODE_VALUE from V_LOOKUP_CODE_VALUE (code type ETHNICITY/LANGUAGE_CD/RACE)
    exception_code    VARCHAR2(255),  -- EXCEPTION_CODE as RETURNED by the EXC_LOOKUP_CODE_VALUE lookup:
                                      --   NULL when the code translates OR when the exception code is not configured
    exception_desc    VARCHAR2(255),  -- EXCEPTION_DESC
    exception_type    VARCHAR2(100)   -- EXCEPTION_TYPE
);
/

-- mplt_Race_Ind_Validation
CREATE OR REPLACE TYPE t_dq_race_ind FORCE AS OBJECT (
    mdm_race_cd        VARCHAR2(3),    -- MDM_Race_Cd (001..007)
    src_race_ind_list  VARCHAR2(40),   -- Src_Race_Ind_List ('WH<w>AA<b>AS<a>PI<p>NA<n>')
    exception_cd       VARCHAR2(255),  -- Exception_Cd   (EXC_LOOKUP_CODE_VALUE.EXCEPTION_CODE, i.e. NULL if not configured)
    exception_desc     VARCHAR2(255),  -- Exception_Desc
    exception_type     VARCHAR2(100)   -- Exception_Type
);
/

-- rule_Suffix_Std
CREATE OR REPLACE TYPE t_dq_suffix FORCE AS OBJECT (
    source_suffix          VARCHAR2(50),   -- Source_Suffix
    standardized_suffix    VARCHAR2(50),   -- Standardized_Suffix (V_LOOKUP_CODE_VALUE, no code-type filter)
    suffix_exception_code  VARCHAR2(300),  -- Suffix_Exception_Code ('Invalid_Suffix' or NULL; computed)
    suffix_exception_type  VARCHAR2(100),  -- Suffix_Exception_Type (looked up)
    suffix_exception_desc  VARCHAR2(255)   -- Suffix_Exception_Desc (looked up)
);
/

-- rule_email_validation_v01 (+ rule_email_LocalPart_validation_V1, rule_email_Domain_Subdomain_validation__V1)
CREATE OR REPLACE TYPE t_dq_email FORCE AS OBJECT (
    email_address   VARCHAR2(200),  -- EMAIL_ADDRESS (trimmed, lower case)
    exception_code  VARCHAR2(255),  -- EXCEPTION_CODE (looked up: 'Invalid_Email' when configured, else NULL)
    exception_desc  VARCHAR2(255),  -- EXCEPTION_DESC
    exception_type  VARCHAR2(100)   -- EXCEPTION_TYPE
);
/

-- rule_Phone_Std
CREATE OR REPLACE TYPE t_dq_phone FORCE AS OBJECT (
    phone                 VARCHAR2(30),   -- Phone (punctuation and white space removed)
    phone_exception_code  VARCHAR2(300),  -- Phone_Exception_Code (computed: Invalid_Phone_Number / Missing_AreaCode)
    phone_exception_type  VARCHAR2(100),  -- Phone_Exception_Type (looked up)
    phone_exception_desc  VARCHAR2(255)   -- Phone_Exception_Desc (looked up)
);
/

-- rule_Phone_Extension_Std
CREATE OR REPLACE TYPE t_dq_phone_ext FORCE AS OBJECT (
    phone_nbr_ext                 VARCHAR2(30),
    phone_nbr_ext_exception_code  VARCHAR2(300),  -- 'Invalid_Phone_Number_Ext' or NULL (computed)
    phone_nbr_ext_exception_type  VARCHAR2(100),
    phone_nbr_ext_exception_desc  VARCHAR2(255)
);
/

-- rule_USA_SSN_Validation_post_June2011
CREATE OR REPLACE TYPE t_dq_ssn FORCE AS OBJECT (
    ssn_status         VARCHAR2(15),   -- Out_SSN_Status ('Valid' / 'Invalid')
    ssn_error_message  VARCHAR2(100)   -- Out_SSN_Error_Message
);
/

-- rule_MEDICAID_ID_Std, rule_Member_Id_Std, rule_CARE_ID_Std
CREATE OR REPLACE TYPE t_dq_ident FORCE AS OBJECT (
    id_value        VARCHAR2(50),   -- Medicaid_Id / Member_Id / CARE_ID (special characters removed)
    exception_code  VARCHAR2(300),  -- Invalid_Medicaid_Id / Invalid_Member_Id or NULL (computed); CARE id: NULL
    exception_type  VARCHAR2(100),  -- looked up
    exception_desc  VARCHAR2(255)   -- looked up
);
/

-- mplt_Date_Greater_Than_Fifty_Years
CREATE OR REPLACE TYPE t_dq_date_50y FORCE AS OBJECT (
    input_date      DATE,
    out_date_diff   VARCHAR2(10),   -- DATE_DIFF(Input_Date, SYSDATE, 'YY')
    out_date        DATE            -- NULL when the date is more than 50 years away, else the input date
);
/

-- mplt_Global_Addr_Validation (AddressDoctor through dq_Global_AddressValidation_Hybrid, plus the scrub rules)
CREATE OR REPLACE TYPE t_dq_address FORCE AS OBJECT (
    delivery_address_line1          VARCHAR2(240),  -- DeliveryAddressLine1 (after rule_Addr_Line_Post_Scrub)
    delivery_address_line2          VARCHAR2(240),  -- DeliveryAddressLine2
    city                            VARCHAR2(255),  -- City (LocalityComplete1)
    postcode_complete               VARCHAR2(20),   -- PostcodeComplete
    zip_cd_5                        VARCHAR2(10),   -- Zip_cd_5
    zip_cd_4_extn                   VARCHAR2(10),   -- Zip_cd_4_extn
    province_iso3                   VARCHAR2(10),   -- ProvinceISO3
    country_iso2_char               VARCHAR2(2),    -- CountryISO2Char
    mailability_score               VARCHAR2(10),   -- MailabilityScore
    match_code                      VARCHAR2(10),   -- MatchCode
    match_code_description          VARCHAR2(255),  -- MatchCode_Description (ref_MatchCode_Desc)
    status_info_match_code          VARCHAR2(10),   -- StatusInfoMatchCode
    status_info_result_percentage   VARCHAR2(10),   -- StatusInfoResultPercentage
    address_type                    VARCHAR2(10),   -- AddressType
    county_fips_cd                  VARCHAR2(3),    -- CountyFederalInformationProcessingStandardCode (Texas kept,
                                                    --   unknown 999, other state 996)
    state_fips_cd                   VARCHAR2(2),    -- StateFederalInformationProcessingStandardCode
    geocoding_latitude              NUMBER(38,6),   -- GeoCodingLatitude  (0 when empty)
    geocoding_longitude             NUMBER(38,6),   -- GeoCodingLongitude (0 when empty)
    geocoding_status                VARCHAR2(50),   -- GeocodingStatus
    geocoding_complete              VARCHAR2(255),  -- GeoCodingGeocodingComplete
    residential_delivery_indicator  VARCHAR2(10),   -- ResidentialDeliveryIndicator
    organization_complete           VARCHAR2(255),
    organization_descriptor         VARCHAR2(255),
    organization_department         VARCHAR2(255),
    organization_name               VARCHAR2(255),
    building_number                 VARCHAR2(50),
    building_complete               VARCHAR2(255),
    building_name                   VARCHAR2(255),
    building_complete_with_sub_bldg VARCHAR2(255),
    street_number_complete          VARCHAR2(50),
    street_complete_with_number1    VARCHAR2(255),
    sub_building_number             VARCHAR2(50),
    sub_building_complete           VARCHAR2(255),
    sub_building_descriptor         VARCHAR2(50),
    early_warning_system_return_cd  VARCHAR2(10),
    congressional_district          VARCHAR2(10),
    cass_error_code                 VARCHAR2(10),
    record_type                     VARCHAR2(10),
    dpv_confirmation                VARCHAR2(10),   -- DeliveryPointValidationConfirmation
    msa_id                          VARCHAR2(10),
    cbsa_id                         VARCHAR2(10),
    cmsa_id                         VARCHAR2(10),
    census_tract_number             VARCHAR2(10),
    census_block_number             VARCHAR2(10),
    census_block_group              VARCHAR2(10),
    place_fips_cd                   VARCHAR2(10),
    minor_civil_division_id         VARCHAR2(10)
);
/

-- mplt_Member_Pty_Rle_Phn_Normalization (TRS): one row per non-empty phone slot (Primary / Secondary / Tertiary)
CREATE OR REPLACE TYPE t_dq_member_phn_row FORCE AS OBJECT (
    period_start_date  DATE,
    pty_fk             VARCHAR2(255),
    pref_lvl           VARCHAR2(20),   -- 'Primary' / 'Secondary' / 'Tertiary'
    usg_tp             VARCHAR2(20),
    phn_tp             VARCHAR2(20),
    phn_num            VARCHAR2(30),   -- rule_Phone_Std output (cleaned)
    dq_exception       VARCHAR2(255),  -- Phone_Exception_Desc (looked up)
    dq_exception_code  VARCHAR2(300),  -- Phone_Exception_Code (computed)
    pkey_src_object    VARCHAR2(255),  -- PTY_FK || '|Member|' || PHN_TP || '|' || usage master code || '|' || PHN_NUM
    src_sys            VARCHAR2(10),
    pty_rle_fk         VARCHAR2(255),  -- PTY_FK || '|Member'
    case_number        VARCHAR2(50)
);
/
CREATE OR REPLACE TYPE t_dq_member_phn_tab FORCE AS TABLE OF t_dq_member_phn_row;
/

-- mplt_TRS_Pty_Rle_Alt_Id_Normalization (TRS): one row per non-empty alternate id (Medicaid id 002, SSN 004,
-- member id 007, NIS client id 009); is_valid = 'Y' for RTR_Invalid_Alt_Ids.Valid_Alt_ID, 'N' for the default group
CREATE OR REPLACE TYPE t_dq_trs_alt_id_row FORCE AS OBJECT (
    pkey_src_object_alt_id  VARCHAR2(255),  -- PKEY_SRC_OBJECT_PTY || '|Member|' || ALT_ID_TP_CD_MSTR || '|' || ALT_ID_VAL
    pkey_src_object_pty     VARCHAR2(255),
    pty_rle_fk              VARCHAR2(55),   -- PKEY_SRC_OBJECT_PTY || '|Member'
    period_start_date       DATE,
    alt_id_val              VARCHAR2(50),
    alt_id_typ              VARCHAR2(20),   -- MSTR_REF_CODE of LOOKUP_CODE_VALUE ALT_ID_TP
    alt_id_label            VARCHAR2(100),  -- MSTR_REF_LABEL (written as ATTRIBUTE_NAME of the exception row)
    dq_excp                 VARCHAR2(300),  -- exception description
    dq_excp_cd              VARCHAR2(300),  -- exception code
    src_sys                 VARCHAR2(10),
    cv_ind                  VARCHAR2(10),
    is_valid                VARCHAR2(1)
);
/
CREATE OR REPLACE TYPE t_dq_trs_alt_id_tab FORCE AS TABLE OF t_dq_trs_alt_id_row;
/
