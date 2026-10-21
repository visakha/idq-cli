--------------------------------------------------------------------------------------------------------------------
-- 03_ors_common_helpers.sql
--
-- Helpers shared by several sp_ors_main_* procedures (implemented here, unlike the assumed fn_dq_* functions).
--
-- | helper                  | purpose                                                                     |
-- |-------------------------|-----------------------------------------------------------------------------|
-- | fn_ors_helper01_common  | IDQ IS_NUMBER(): 1 when the string is a number, else 0                      |
-- | fn_ors_helper02_common  | new deactivation status from the hub state: H history / D deactivated / P   |
-- | fn_ors_helper03_common  | V_LOOKUP_CODE_VALUE lookup: source code -> MSTR_CODE_VALUE (any row)        |
-- | fn_ors_helper04_common  | EXC_LOOKUP_CODE_VALUE lookup: exception code -> EXCEPTION_DESC (any row)    |
-- | fn_ors_helper05_common  | EXC_LOOKUP_CODE_VALUE lookup: exception code -> EXCEPTION_TYPE (any row)    |
-- | fn_ors_helper06_common  | IDQ "blank" test: NULL or only white space (IDQ LENGTH(RTRIM(x)) = 0)        |
-- | fn_ors_helper07_common  | IDQ TO_DECIMAL(value, scale): non-numeric -> 0, NULL -> NULL                |
-- | fn_ors_helper08_common  | EXC_LOOKUP_CODE_VALUE lookup: exception code -> EXCEPTION_CODE (the code when |
-- |                         | it is configured, else NULL)                                                |
-- | fn_ors_helper09_common  | address score of exp_Score_and_Exception_details: '40' exception / '100'    |
-- | fn_ors_helper10_common  | address issue text of exp_Score_and_Exception_details (Addr_Issue_Desc)     |
-- | fn_ors_helper11_common  | exp_Address_Hold line 1: empty line 1 replaced by line 2                    |
-- | fn_ors_helper12_common  | exp_Address_Hold line 2: cleared when it repeats the held line 1            |
-- | sp_ors_helper02_common  | run log line: mapping, step, row count (DBMS_OUTPUT)                       |
--
-- The lookup functions run their own query per call, so they see committed reference data as of that call. They
-- are used only for reference tables that the mappings never write (code values, exception catalogue). Lookups on
-- tables a mapping also writes are joins (OUTER APPLY) inside the procedure, so they read the same snapshot as
-- the IDQ static lookup cache did.
--------------------------------------------------------------------------------------------------------------------

-- IDQ IS_NUMBER(): leading/trailing spaces allowed, optional sign, decimal point and exponent.
CREATE OR REPLACE FUNCTION fn_ors_helper01_common (
    p_value  IN VARCHAR2
) RETURN NUMBER
DETERMINISTIC
IS
BEGIN
    IF p_value IS NULL THEN
        RETURN NULL;   -- IDQ returns NULL for a NULL argument
    END IF;
    RETURN CASE WHEN REGEXP_LIKE(p_value, '^\s*[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?\s*$')
                THEN 1 ELSE 0 END;
END fn_ors_helper01_common;
/

-- New row of STG_<SRC>_PTY_INACTIVE_STS (Exp_New_Deactvn_Sts of the *_Pty_Validation mappings):
-- no hub cross-reference -> 'H' (history), HUB_STATE_IND = -1 -> 'D' (deactivated), otherwise 'P' (pending).
CREATE OR REPLACE FUNCTION fn_ors_helper02_common (
    p_hub_state_ind  IN NUMBER
) RETURN VARCHAR2
DETERMINISTIC
IS
BEGIN
    RETURN CASE WHEN p_hub_state_ind IS NULL THEN 'H'
                WHEN p_hub_state_ind = -1    THEN 'D'
                ELSE 'P' END;
END fn_ors_helper02_common;
/

-- V_LOOKUP_CODE_VALUE: CODE_TYPE = p_code_type AND SRC_SYS = p_src_sys AND SRC_CODE_VALUE = p_src_code.
-- p_code_type NULL means no code-type filter (as rule_Suffix_Std). Multiple matches: any row (IDQ "return any").
CREATE OR REPLACE FUNCTION fn_ors_helper03_common (
    p_code_type  IN VARCHAR2,
    p_src_sys    IN VARCHAR2,
    p_src_code   IN VARCHAR2
) RETURN VARCHAR2
IS
    l_mstr  V_LOOKUP_CODE_VALUE.MSTR_CODE_VALUE%TYPE;
BEGIN
    IF p_src_code IS NULL OR p_src_sys IS NULL THEN
        RETURN NULL;   -- an IDQ lookup condition never matches a NULL
    END IF;
    SELECT MAX(v.MSTR_CODE_VALUE)
      INTO l_mstr
      FROM V_LOOKUP_CODE_VALUE v
     WHERE (p_code_type IS NULL OR v.CODE_TYPE = p_code_type)
       AND v.SRC_SYS = p_src_sys
       AND v.SRC_CODE_VALUE = p_src_code
       AND ROWNUM = 1;
    RETURN l_mstr;
END fn_ors_helper03_common;
/

-- EXC_LOOKUP_CODE_VALUE.EXCEPTION_DESC for an exception code (NULL when the code is not configured).
CREATE OR REPLACE FUNCTION fn_ors_helper04_common (
    p_exception_code  IN VARCHAR2
) RETURN VARCHAR2
IS
    l_desc  EXC_LOOKUP_CODE_VALUE.EXCEPTION_DESC%TYPE;
BEGIN
    IF p_exception_code IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT MAX(e.EXCEPTION_DESC)
      INTO l_desc
      FROM EXC_LOOKUP_CODE_VALUE e
     WHERE e.EXCEPTION_CODE = p_exception_code
       AND ROWNUM = 1;
    RETURN l_desc;
END fn_ors_helper04_common;
/

-- EXC_LOOKUP_CODE_VALUE.EXCEPTION_TYPE for an exception code (NULL when the code is not configured).
CREATE OR REPLACE FUNCTION fn_ors_helper05_common (
    p_exception_code  IN VARCHAR2
) RETURN VARCHAR2
IS
    l_type  EXC_LOOKUP_CODE_VALUE.EXCEPTION_TYPE%TYPE;
BEGIN
    IF p_exception_code IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT MAX(e.EXCEPTION_TYPE)
      INTO l_type
      FROM EXC_LOOKUP_CODE_VALUE e
     WHERE e.EXCEPTION_CODE = p_exception_code
       AND ROWNUM = 1;
    RETURN l_type;
END fn_ors_helper05_common;
/

-- EXC_LOOKUP_CODE_VALUE.EXCEPTION_CODE as returned by a lookup: the code itself when it is configured, else NULL.
-- Mappings that write the looked-up code (not the computed one) therefore write NULL for unconfigured codes.
CREATE OR REPLACE FUNCTION fn_ors_helper08_common (
    p_exception_code  IN VARCHAR2
) RETURN VARCHAR2
IS
    l_code  EXC_LOOKUP_CODE_VALUE.EXCEPTION_CODE%TYPE;
BEGIN
    IF p_exception_code IS NULL THEN
        RETURN NULL;
    END IF;
    SELECT MAX(e.EXCEPTION_CODE)
      INTO l_code
      FROM EXC_LOOKUP_CODE_VALUE e
     WHERE e.EXCEPTION_CODE = p_exception_code
       AND ROWNUM = 1;
    RETURN l_code;
END fn_ors_helper08_common;
/

-- exp_Score_and_Exception_details.Score (address mappings of ECI, FSS, WIC and TRS): '40' sends the address to the
-- exception queue. String comparisons on the mailability score, as in IDQ. p_addr_tp_mstr is the master address type.
CREATE OR REPLACE FUNCTION fn_ors_helper09_common (
    p_addr_tp_mstr       IN VARCHAR2,
    p_mailability_score  IN VARCHAR2,
    p_match_code         IN VARCHAR2
) RETURN VARCHAR2
DETERMINISTIC
IS
BEGIN
    RETURN CASE WHEN p_addr_tp_mstr != '002' AND p_mailability_score <= '3' THEN '40'
                WHEN p_addr_tp_mstr = '002' AND p_mailability_score < '3'
                     AND SUBSTR(p_match_code, 1, 1) IN ('I', 'N') THEN '40'
                WHEN p_addr_tp_mstr IS NULL THEN '40'
                ELSE '100' END;
END fn_ors_helper09_common;
/

-- exp_Score_and_Exception_details.Addr_Issue_Desc: why the address scored '40' (NULL when it scored '100').
CREATE OR REPLACE FUNCTION fn_ors_helper10_common (
    p_addr_tp_mstr       IN VARCHAR2,
    p_mailability_score  IN VARCHAR2,
    p_match_code         IN VARCHAR2
) RETURN VARCHAR2
DETERMINISTIC
IS
BEGIN
    RETURN CASE WHEN p_addr_tp_mstr != '002' AND p_mailability_score <= '3' THEN 'Invalid Address'
                WHEN p_addr_tp_mstr = '002' AND p_mailability_score < '3'
                     AND SUBSTR(p_match_code, 1, 1) IN ('I', 'N') THEN 'Invalid Address'
                WHEN p_addr_tp_mstr IS NULL THEN 'Invalid Address Type' END;
END fn_ors_helper10_common;
/

-- exp_Address_Hold.out_ADDR_LINE_1: an empty first line is replaced by the second line.
CREATE OR REPLACE FUNCTION fn_ors_helper11_common (
    p_line_1  IN VARCHAR2,
    p_line_2  IN VARCHAR2
) RETURN VARCHAR2
DETERMINISTIC
IS
BEGIN
    RETURN CASE WHEN TRIM(p_line_1) IS NULL THEN p_line_2 ELSE p_line_1 END;
END fn_ors_helper11_common;
/

-- exp_Address_Hold.out_ADDR_LINE_2: the second line is cleared when it equals the held first line.
CREATE OR REPLACE FUNCTION fn_ors_helper12_common (
    p_line_1  IN VARCHAR2,
    p_line_2  IN VARCHAR2
) RETURN VARCHAR2
DETERMINISTIC
IS
BEGIN
    RETURN CASE WHEN fn_ors_helper11_common(p_line_1, p_line_2) = p_line_2 THEN NULL ELSE p_line_2 END;
END fn_ors_helper12_common;
/

-- IDQ blank test. In IDQ an empty string is not NULL, so the mappings test LENGTH(RTRIM(x)) = 0 and ISNULL(x)
-- separately; in Oracle '' is NULL and RTRIM('  ') is NULL, so both collapse to "x is NULL or white space only".
-- Returns 1 / 0.
CREATE OR REPLACE FUNCTION fn_ors_helper06_common (
    p_value  IN VARCHAR2
) RETURN NUMBER
DETERMINISTIC
IS
BEGIN
    RETURN CASE WHEN p_value IS NULL OR RTRIM(p_value) IS NULL THEN 1 ELSE 0 END;
END fn_ors_helper06_common;
/

-- IDQ TO_DECIMAL(value, scale): the number rounded to the scale; a non-numeric string gives 0 and NULL gives NULL
-- (IDQ / PowerCenter conversion-function behaviour).
CREATE OR REPLACE FUNCTION fn_ors_helper07_common (
    p_value  IN VARCHAR2,
    p_scale  IN PLS_INTEGER DEFAULT NULL
) RETURN NUMBER
DETERMINISTIC
IS
    l_num  NUMBER;
BEGIN
    IF p_value IS NULL THEN
        RETURN NULL;
    END IF;
    IF fn_ors_helper01_common(p_value) = 0 THEN
        RETURN 0;
    END IF;
    l_num := TO_NUMBER(TRIM(p_value));
    RETURN CASE WHEN p_scale IS NULL THEN l_num ELSE ROUND(l_num, p_scale) END;
END fn_ors_helper07_common;
/

-- One log line per step (rows inserted); replace with an audit table if needed.
CREATE OR REPLACE PROCEDURE sp_ors_helper02_common (
    p_mapping_name  IN VARCHAR2,
    p_step          IN VARCHAR2,
    p_rows          IN NUMBER
)
IS
BEGIN
    DBMS_OUTPUT.PUT_LINE(TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.FF3') || ' ' || p_mapping_name || ' '
                         || p_step || ': ' || p_rows || ' row(s)');
END sp_ors_helper02_common;
/
