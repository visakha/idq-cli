package com.idq.cli.core.target;

import java.time.LocalDateTime;

/// Columns every `C_S_*` staging table carries, as populated by the IDQ mappings.
///
/// The legacy MDM timeline columns (`VERSION_SEQ`, `PERIOD_REFERENCE_TIME`, `TIMELINE_ACTION`) are deliberately
/// absent: the timeline is stale and the mapping logic that derived them is not ported. `ROWID_OBJECT` and the
/// `DELETED_*` columns are never set by the mappings and are left to MDM.
///
/// `SRC_ROWID` is 30 characters in every `C_S_*` table; IDQ truncates longer keys to the target precision, and so
/// does [#srcRowid] / [#withSrcRowid].
public record MdmAudit(
        LocalDateTime periodStartDate,
        LocalDateTime periodEndDate,
        LocalDateTime lastUpdateDate,
        LocalDateTime createDate,
        String creator,
        String updatedBy,
        String srcRowid,
        Integer hubStateInd,
        LocalDateTime srcLastUpdDt) {

    public static final int SRC_ROWID_PRECISION = 30;

    public static MdmAudit srcRowid(String srcRowid) {
        return new MdmAudit(null, null, null, null, null, null, fit(srcRowid), null, null);
    }

    static String fit(String rowid) {
        return rowid == null || rowid.length() <= SRC_ROWID_PRECISION ? rowid : rowid.substring(0, SRC_ROWID_PRECISION);
    }

    public MdmAudit withSrcRowid(String rowid) {
        return new MdmAudit(periodStartDate, periodEndDate, lastUpdateDate, createDate, creator, updatedBy,
                fit(rowid), hubStateInd, srcLastUpdDt);
    }

    public MdmAudit period(LocalDateTime start, LocalDateTime end) {
        return new MdmAudit(start, end, lastUpdateDate, createDate, creator, updatedBy, srcRowid, hubStateInd,
                srcLastUpdDt);
    }

    public MdmAudit periodStart(LocalDateTime start) {
        return period(start, periodEndDate);
    }

    public MdmAudit lastUpdated(LocalDateTime when) {
        return new MdmAudit(periodStartDate, periodEndDate, when, createDate, creator, updatedBy, srcRowid,
                hubStateInd, srcLastUpdDt);
    }

    public MdmAudit created(LocalDateTime when) {
        return new MdmAudit(periodStartDate, periodEndDate, lastUpdateDate, when, creator, updatedBy, srcRowid,
                hubStateInd, srcLastUpdDt);
    }

    public MdmAudit by(String creatorName, String updatedByName) {
        return new MdmAudit(periodStartDate, periodEndDate, lastUpdateDate, createDate, creatorName, updatedByName,
                srcRowid, hubStateInd, srcLastUpdDt);
    }

    public MdmAudit hubState(Integer state) {
        return new MdmAudit(periodStartDate, periodEndDate, lastUpdateDate, createDate, creator, updatedBy, srcRowid,
                state, srcLastUpdDt);
    }

    public MdmAudit sourceUpdated(LocalDateTime when) {
        return new MdmAudit(periodStartDate, periodEndDate, lastUpdateDate, createDate, creator, updatedBy, srcRowid,
                hubStateInd, when);
    }
}
