# Taskflow tf_FSS_Stage_Load

Replaces IDQ workflow `wf_FSS_Stage_Load`. Create it as a **Taskflow** (not a linear taskflow) because the workflow runs mapping tasks in parallel.

## IDQ workflow

```mermaid
flowchart LR
  u-ywskcynfefcdhktygm-fnw(["Start_Event"])
  u-ywskdcnfefcdhktygm-fnw(["End_Event"])
  u-nmo2ysngefcdhktygm-fnw["m_Tgt_C_S_FSS_Pty_Validation"]
  u-nmo2yingefcdhktygm-fnw{"Inclusive_Gateway"}
  u-nmo2yyngefcdhktygm-fnw["m_Tgt_C_S_FSS_Pty"]
  u-nmo2zcngefcdhktygm-fnw{"Inclusive_Gateway1"}
  u-nmo2zsngefcdhktygm-fnw["m_Tgt_C_S_FSS_Pty_Rle_Alt_Id"]
  u-nmo2zingefcdhktygm-fnw["m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr"]
  u-nmo2zyngefcdhktygm-fnw{"Inclusive_Gateway2"}
  u-nmo20cngefcdhktygm-fnw{"Inclusive_Gateway3"}
  u-nmo20sngefcdhktygm-fnw["Command_Task"]
  u-ahwarzgpefcmxyg8zczd2q["m_Tgt_C_S_FSS_Pty_Addr"]
  u-ahwasdgpefcmxyg8zczd2q["m_Tgt_C_S_FSS_Pty_Rle_Rel"]
  u-ywskcynfefcdhktygm-fnw --> u-nmo2ysngefcdhktygm-fnw
  u-nmo2ysngefcdhktygm-fnw --> u-nmo2yingefcdhktygm-fnw
  u-nmo2yingefcdhktygm-fnw --> u-nmo2yyngefcdhktygm-fnw
  u-nmo2yingefcdhktygm-fnw -->|default| u-nmo2zcngefcdhktygm-fnw
  u-nmo2yyngefcdhktygm-fnw --> u-nmo2zcngefcdhktygm-fnw
  u-nmo2zcngefcdhktygm-fnw --> u-nmo2zyngefcdhktygm-fnw
  u-nmo2zsngefcdhktygm-fnw --> u-nmo20cngefcdhktygm-fnw
  u-nmo2zingefcdhktygm-fnw --> u-nmo20cngefcdhktygm-fnw
  u-nmo2zyngefcdhktygm-fnw -->|default| u-nmo20cngefcdhktygm-fnw
  u-nmo2zyngefcdhktygm-fnw --> u-ahwarzgpefcmxyg8zczd2q
  u-nmo2zyngefcdhktygm-fnw --> u-nmo2zsngefcdhktygm-fnw
  u-nmo2zyngefcdhktygm-fnw --> u-nmo2zingefcdhktygm-fnw
  u-nmo2zyngefcdhktygm-fnw --> u-ahwasdgpefcmxyg8zczd2q
  u-nmo20cngefcdhktygm-fnw --> u-nmo20sngefcdhktygm-fnw
  u-nmo20sngefcdhktygm-fnw --> u-ywskdcnfefcdhktygm-fnw
  u-ahwarzgpefcmxyg8zczd2q --> u-nmo20cngefcdhktygm-fnw
  u-ahwasdgpefcmxyg8zczd2q --> u-nmo20cngefcdhktygm-fnw
```

## CDI taskflow

```mermaid
flowchart LR
  s(["Start"])
  p0["Data Task<br/>mct_Tgt_C_S_FSS_Pty_Validation"]
  s --> p0
  p1{{"Parallel Paths 1"}}
  p0 --> p1
  p1b0s0["Data Task<br/>mct_Tgt_C_S_FSS_Pty"]
  p1 --> p1b0s0
  p2{{"Parallel Paths 2"}}
  p1b0s0 --> p2
  p2b0s0["Data Task<br/>mct_Tgt_C_S_FSS_Pty_Addr"]
  p2 --> p2b0s0
  p2b1s0["Data Task<br/>mct_Tgt_C_S_FSS_Pty_Rle_Alt_Id"]
  p2 --> p2b1s0
  p2b2s0["Data Task<br/>mct_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr"]
  p2 --> p2b2s0
  p2b3s0["Data Task<br/>mct_Tgt_C_S_FSS_Pty_Rle_Rel"]
  p2 --> p2b3s0
  p3["Command Task<br/>Command_Task"]
  p2b0s0 --> p3
  p2b1s0 --> p3
  p2b2s0 --> p3
  p2b3s0 --> p3
  p4(["End"])
  p3 --> p4
```

## Steps

| # | Step | Runs | Notes |
|---|---|---|---|
| 0 | Data Task | `mct_Tgt_C_S_FSS_Pty_Validation` |  |
| 1 | Parallel Paths | path 1: `mct_Tgt_C_S_FSS_Pty` | Data Tasks in a path run in sequence; all paths must complete before the next step (same as the IDQ join gateway). |
| 2 | Parallel Paths | path 1: `mct_Tgt_C_S_FSS_Pty_Addr`<br>path 2: `mct_Tgt_C_S_FSS_Pty_Rle_Alt_Id`<br>path 3: `mct_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`<br>path 4: `mct_Tgt_C_S_FSS_Pty_Rle_Rel` | Data Tasks in a path run in sequence; all paths must complete before the next step (same as the IDQ join gateway). |
| 3 | Command Task | Command_Task | IDQ command `touch ${var:sys.WorkflowName}.ind`, working directory `/opt/apps/informatica/SrcFiles/Indicators`. See below. |
| 4 | End |  |  |

## Mapping tasks

Create one mapping task per mapping. IDQ mapping-task settings and their CDI home:

| Mapping task | Mapping | Date format (Advanced session property *Default date format*) | High precision (*Enable high precision*) | Tracing (*Override tracing*) | Sort order |
|---|---|---|---|---|---|
| `mct_Tgt_C_S_FSS_Pty_Validation` | [`m_Tgt_C_S_FSS_Pty_Validation`](mappings/m_Tgt_C_S_FSS_Pty_Validation.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_FSS_Pty` | [`m_Tgt_C_S_FSS_Pty`](mappings/m_Tgt_C_S_FSS_Pty.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_FSS_Pty_Rle_Alt_Id` | [`m_Tgt_C_S_FSS_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` | [`m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_FSS_Pty_Addr` | [`m_Tgt_C_S_FSS_Pty_Addr`](mappings/m_Tgt_C_S_FSS_Pty_Addr.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_FSS_Pty_Rle_Rel` | [`m_Tgt_C_S_FSS_Pty_Rle_Rel`](mappings/m_Tgt_C_S_FSS_Pty_Rle_Rel.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |

Each Data Task: *On error* = **Fail taskflow** (IDQ aborts the workflow when a mapping task fails). Pass the parameter file through the mapping task *Parameter file* setting (see the `.param` file).

## Command task

IDQ runs `touch ${var:sys.WorkflowName}.ind` on the DIS host. In the CDI taskflow add a **Command Task** step that runs on the Linux Secure Agent runtime environment:

| Field | Value |
|---|---|
| Runtime Environment | the Linux Secure Agent group used by the mapping tasks |
| Script File Name | `/bin/sh` |
| Input Arguments | `-c "touch wf_FSS_Stage_Load.ind"` |
| Work Directory | `/opt/apps/informatica/SrcFiles/Indicators` |

`${var:sys.WorkflowName}` resolved to `wf_FSS_Stage_Load` so the indicator file name downstream consumers watch does not change. The agent user needs write access to the working directory.
