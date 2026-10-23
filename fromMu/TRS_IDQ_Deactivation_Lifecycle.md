# TRS IDQ — Deactivation Lifecycle

How a party or relationship deactivated in TIERS is removed from the MDM hub:
four stages across five workflows, driven by two log tables
(`STG_TRS_DEACTIVED_MEMBERS`, `STG_TRS_DEACTIVATED_RELATIONSHIPS`) and the
`PROCESSED_YN` flag. Detail for every object named here is in
`TRS_IDQ_Workflow_and_Mapping_Analysis.md` (§2 lifecycle, §6.3–§6.6).

```mermaid
flowchart TD
    subgraph S1["STAGE 1 · CAPTURE — in wf_TRS_Stage_Load_1_Ongoing, plus the History workflow"]
        T1["TIERS individual delta<br/>INACTIVE_IND = 'Y' or DELETE_SW = 'Y'<br/>(STG_TRS_D_DC_INDV + CV/MCI tables)"]
        C1["m_Tgt_C_S_TRS_Pty_Deactivation_1<br/>keep only NEW rows (not already in the log)"]
        LOGP[("STG_TRS_DEACTIVED_MEMBERS<br/>party deactivation log")]
        DEL1["DELETE from STG_TRS_VALID_MEMBERS<br/>(update-strategy delete — member leaves the valid spine)"]
        T2["STG_TRS_D_DC_RELATIONSHIPS_A<br/>keys resolved via valid-member spine (min_pk)"]
        C2["m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_1<br/>PTY_REL code lookup + C_B_PTY_RLE_REL_XREF check<br/>derives MERGE_YN / MASTER_RECORD_YN / SOFT_DELETE_YN"]
        LOGR[("STG_TRS_DEACTIVATED_RELATIONSHIPS<br/>relationship deactivation log")]
        H1["STG_TRS_H_DC_RELATIONSHIPS_A<br/>(history extract)"]
        C3["m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_History_Audit<br/>in wf_TRS_Pty_Rle_Rel_DeActivation_History"]
        T1 --> C1
        C1 -->|"write new rows, PROCESSED_YN = 'N'"| LOGP
        C1 --> DEL1
        T2 --> C2
        C2 -->|"new rows with ROWID_XREF present, PROCESSED_YN = 'N'"| LOGR
        C2 -->|"already soft-deleted in hub (SOFT_DELETE_YN = 'Y'):<br/>logged as PROCESSED_YN = 'Y' — never actioned"| LOGR
        H1 --> C3
        C3 --> LOGR
    end
    subgraph S2["STAGE 2 · COPY KEYS — the CopyList mappings (separate step, for re-runnability)"]
        CP["m_Tgt_C_S_TRS_Pty_Deactivation_2_CopyList<br/>in wf_TRS_Deactivation_Initial<br/>PROCESSED_YN <> 'Y', capped rownum <= 10000<br/>stamps SRC_SYS = 'TRS', EXPLODE_NODE_IND = 1"]
        Z1[("ZZ_UTL_UNMERGE_TREE_SRC_KEY<br/>truncate-load")]
        G1{"Gateway<br/>TgtRows > 0 ?"}
        CR["m_Tgt_C_S_TRS_Pty_Rle_Rel_DeActivation_2_CopyList<br/>in wf_TRS_Relationship_Deactivation<br/>nvl(PROCESSED_YN,'N') <> 'Y' and ROWID_XREF not null"]
        Z2[("ZZ_UTL_SOFTDEL_PTY_REL_SRC_KEY<br/>ALL keys, truncate-load")]
        Z3[("ZZ_UTL_UNMERGE_PTY_REL_ROWID_XREF<br/>merged only (MERGED_YN = 'Y'), truncate-load")]
        G2{"Gateway<br/>TgtRows > 0 ?"}
        CP --> Z1
        CP --> G1
        CR --> Z2
        CR --> Z3
        CR --> G2
    end
    subgraph S3["STAGE 3 · ACT — command tasks (key logic in scripts outside IDQ)"]
        SP["./unmerge_soft_delete_party.sh"]
        SR["./unmerge_soft_delete_relationship.sh"]
        ACT["MDM batch-group UNMERGE of the copied keys<br/>+ custom Oracle soft-delete procedure stages<br/>hub_state_ind = -1 records in MDM staging"]
        BATCH["MDM batch applies the staged records<br/>hub rows are SOFT-DELETED (state -1), not removed"]
        IND["Indicator file (.ind) written<br/>on success, or when there was no data"]
        G1 -->|"yes"| SP
        G1 -->|"no — skip"| IND
        G2 -->|"yes"| SR
        G2 -->|"no — skip"| IND
        SP --> ACT
        SR --> ACT
        ACT --> BATCH
        BATCH --> IND
    end
    subgraph S4["STAGE 4 · CLOSE — wf_TRS_Deactivation_Complete (runs after the MDM batch)"]
        MP["m_Tgt_C_S_TRS_Pty_Deactivation_4_Mark_Processed<br/>keys in ZZ_UTL_UNMERGE_TREE_SRC_KEY that match<br/>log rows still at 'N' → set PROCESSED_YN = 'Y' (DD_UPDATE)"]
        MR["m_Tgt_C_S_TRS_Pty_Rle_Rel_Deactivation_4_Mark_Processed<br/>only keys whose xref group shows MAX(HUB_STATE_IND) = -1<br/>→ set PROCESSED_YN = 'Y' (DD_UPDATE)"]
    end
    LOGP -->|"unprocessed rows"| CP
    LOGR -->|"unprocessed rows"| CR
    Z1 -.->|"keys to verify"| MP
    BATCH --> MP
    BATCH --> MR
    MP -->|"flag closed"| LOGP
    MR -->|"flag closed"| LOGR
    classDef log fill:#fff8e1,stroke:#f9a825,color:#795548;
    classDef util fill:#eceff1,stroke:#607d8b,color:#37474f;
    classDef script fill:#fbe9e7,stroke:#d84315,color:#bf360c;
    classDef hub fill:#e8f5e9,stroke:#2e7d32,color:#1b5e20;
    classDef map fill:#e3f2fd,stroke:#1565c0,color:#0d47a1;
    class LOGP,LOGR log;
    class Z1,Z2,Z3 util;
    class SP,SR script;
    class BATCH hub;
    class C1,C2,C3,CP,CR,MP,MR map;
```

## How to read it

- **Stage 1 — Capture** happens inside the Ongoing load (plus the History
  workflow for history/audit relationships). New deactivations are logged with
  `PROCESSED_YN = 'N'`; parties are also deleted from the valid-member spine.
  A relationship already soft-deleted in the hub is logged directly as `'Y'`
  and is never actioned.
- **Stage 2 — Copy** moves unprocessed keys into the MDM utility tables.
  It is a separate step by design (re-runnability). Gateways skip Stage 3
  entirely when a CopyList wrote 0 rows.
- **Stage 3 — Act** is the one black box: the unmerge + soft-delete work is
  done by shell scripts outside IDQ (`unmerge_soft_delete_party.sh`,
  `unmerge_soft_delete_relationship.sh`), staging `hub_state_ind = -1`
  records that the MDM batch applies. Nothing is physically deleted.
- **Stage 4 — Close** (`wf_TRS_Deactivation_Complete`) flips the flag to
  `'Y'`. The party mapping trusts the copied key table; the relationship
  mapping verifies the hub first (`MAX(HUB_STATE_IND) = -1`). Anything left
  at `'N'` is retried next cycle by design.
