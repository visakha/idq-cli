package com.idq.cli.source.ttf;

import java.time.LocalDateTime;
import org.springframework.data.relational.core.mapping.Table;

/// Spring Data JDBC entities that mirror, column for column, the TTF source tables and views read by
/// `wf_TTF_Stage_Load`.
///
/// The mappings read through their `IdqMapInitQuery` records in [TtfQueries]; these entities
/// are the raw-table view used by the audit reports (`adhoc_runs_TTF`). Source tables have no primary key, so the
/// records carry no `@Id` and are only ever read.
///
/// `STG_TTF_PTY_INACTIVE_STS` is written by the validation mapping: see [TtfTargets.InactiveStatus].
public final class TtfSources {

    private TtfSources() {}

    @Table("V_TTF_ETL_SRC")
    public record EtlSrc(Long demographicsId, String ptySrcKey, Long year, Long month, String zip, Integer sexid,
            Integer countyid, String gestageatenrollment, String raceethnicityid, Integer ethnicity, Long submissionid,
            Integer active, String medicaidid, String firstname, String lastname, String middlename, LocalDateTime dob,
            LocalDateTime loadDate, LocalDateTime createddate, LocalDateTime updateddate, String phone,
            Long fyclientsId, Long contractid, Long clientsId, String clientcode, Long contractorid,
            LocalDateTime submissionUpdateddate, LocalDateTime submitdate, LocalDateTime reportfordate,
            String clientExistsFlag) {}
}
