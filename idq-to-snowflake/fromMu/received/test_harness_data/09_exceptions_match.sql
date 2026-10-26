-- =====================================================================
-- 09_exceptions_match.sql -- SUCCESS case: Exceptions match.
-- =====================================================================
-- Simulates: both sides flagged the same bad records.  Note
-- EXC_STG_BAD_REC_MEMB has NO unique key, so its compare key
-- is a best-effort tuple (individual + code + attribute +
-- attribute value + mapping).  The compare always appends a
-- note saying so -- that note is informational, not a failure.
--   IDQ side:       (1001, BAD_ADDR, ADDR_LINE_1, '??',
--                      m_Tgt_C_S_TRS_Pty_Rle_Addr),
--                    (1002, BAD_PHN, PHN_NUM, 'abc',
--                      m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr)
--   SNOWFLAKE side: identical.
-- Expected (with 00 loaded, filter Exceptions):
--   verdict MATCH, counts 2 vs 2, matched 2, and the dimension
--   message still contains the "no unique key" note.
-- =====================================================================

INSERT INTO TRS_ETL_WRK.EXC_STG_BAD_REC_MEMB
    (SRC_SYS_ID_1, EXCEPTION_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, DATA_SOURCE) VALUES
    (1001, 'BAD_ADDR', 'ADDR_LINE_1', '??', 'm_Tgt_C_S_TRS_Pty_Rle_Addr', 'IDQ'),
    (1002, 'BAD_PHN', 'PHN_NUM', 'abc', 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr', 'IDQ');

INSERT INTO TRS_ETL_WRK.EXC_STG_BAD_REC_MEMB
    (SRC_SYS_ID_1, EXCEPTION_CODE, ATTRIBUTE_NAME, ATTRIBUTE_VALUE, MAPPING_NAME, DATA_SOURCE) VALUES
    (1001, 'BAD_ADDR', 'ADDR_LINE_1', '??', 'm_Tgt_C_S_TRS_Pty_Rle_Addr', 'SNOWFLAKE'),
    (1002, 'BAD_PHN', 'PHN_NUM', 'abc', 'm_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr', 'SNOWFLAKE');
