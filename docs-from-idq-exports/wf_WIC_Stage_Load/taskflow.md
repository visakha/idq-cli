# Taskflow tf_WIC_Stage_Load

Replaces IDQ workflow `wf_WIC_Stage_Load`. Create it as a **Taskflow** (not a linear taskflow) because the workflow runs mapping tasks in parallel.

## IDQ workflow

```mermaid
flowchart LR
  u-vbpta9omee-nwckuqkz-mq(["Start_Event"])
  u-vbptbnomee-nwckuqkz-mq(["End_Event"])
  u-vbptcdomee-nwckuqkz-mq{"Inclusive_Gateway"}
  u-vbptctomee-nwckuqkz-mq{"Inclusive_Gateway1"}
  u-vbptc9omee-nwckuqkz-mq["Command_Task"]
  u-vbptd9omee-nwckuqkz-mq{"Inclusive_Gateway2"}
  u-vbptenomee-nwckuqkz-mq{"Inclusive_Gateway3"}
  u-880qodomee-nwckuqkz-mq["m_Tgt_C_S_WIC_Pty_Validation"]
  u-udnvutooee-nwckuqkz-mq["m_Tgt_C_S_WIC_Pty"]
  u-udnvvnooee-nwckuqkz-mq["m_Tgt_C_S_WIC_Pty_Addr"]
  u-udnvvdooee-nwckuqkz-mq["m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr"]
  u-udnvvtooee-nwckuqkz-mq["m_Tgt_C_S_WIC_Pty_Rle_Alt_Id"]
  u-vbpta9omee-nwckuqkz-mq --> u-880qodomee-nwckuqkz-mq
  u-vbptcdomee-nwckuqkz-mq -->|default| u-vbptctomee-nwckuqkz-mq
  u-vbptcdomee-nwckuqkz-mq --> u-udnvvnooee-nwckuqkz-mq
  u-vbptcdomee-nwckuqkz-mq --> u-udnvvdooee-nwckuqkz-mq
  u-vbptcdomee-nwckuqkz-mq --> u-udnvvtooee-nwckuqkz-mq
  u-vbptctomee-nwckuqkz-mq --> u-vbptc9omee-nwckuqkz-mq
  u-vbptc9omee-nwckuqkz-mq --> u-vbptbnomee-nwckuqkz-mq
  u-vbptd9omee-nwckuqkz-mq -->|default| u-vbptenomee-nwckuqkz-mq
  u-vbptd9omee-nwckuqkz-mq --> u-udnvutooee-nwckuqkz-mq
  u-vbptenomee-nwckuqkz-mq --> u-vbptcdomee-nwckuqkz-mq
  u-880qodomee-nwckuqkz-mq --> u-vbptd9omee-nwckuqkz-mq
  u-udnvutooee-nwckuqkz-mq --> u-vbptenomee-nwckuqkz-mq
  u-udnvvnooee-nwckuqkz-mq --> u-vbptctomee-nwckuqkz-mq
  u-udnvvdooee-nwckuqkz-mq --> u-vbptctomee-nwckuqkz-mq
  u-udnvvtooee-nwckuqkz-mq --> u-vbptctomee-nwckuqkz-mq
```

## CDI taskflow

```mermaid
flowchart LR
  s(["Start"])
  p0["Data Task<br/>mct_Tgt_C_S_WIC_Pty_Validation"]
  s --> p0
  p1{{"Parallel Paths 1"}}
  p0 --> p1
  p1b0s0["Data Task<br/>mct_Tgt_C_S_WIC_Pty"]
  p1 --> p1b0s0
  p2{{"Parallel Paths 2"}}
  p1b0s0 --> p2
  p2b0s0["Data Task<br/>mct_Tgt_C_S_WIC_Pty_Addr"]
  p2 --> p2b0s0
  p2b1s0["Data Task<br/>mct_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr"]
  p2 --> p2b1s0
  p2b2s0["Data Task<br/>mct_Tgt_C_S_WIC_Pty_Rle_Alt_Id"]
  p2 --> p2b2s0
  p3["Command Task<br/>Command_Task"]
  p2b0s0 --> p3
  p2b1s0 --> p3
  p2b2s0 --> p3
  p4(["End"])
  p3 --> p4
```

## Steps

| # | Step | Runs | Notes |
|---|---|---|---|
| 0 | Data Task | `mct_Tgt_C_S_WIC_Pty_Validation` |  |
| 1 | Parallel Paths | path 1: `mct_Tgt_C_S_WIC_Pty` | Data Tasks in a path run in sequence; all paths must complete before the next step (same as the IDQ join gateway). |
| 2 | Parallel Paths | path 1: `mct_Tgt_C_S_WIC_Pty_Addr`<br>path 2: `mct_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`<br>path 3: `mct_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | Data Tasks in a path run in sequence; all paths must complete before the next step (same as the IDQ join gateway). |
| 3 | Command Task | Command_Task | IDQ command `touch ${var:sys.WorkflowName}.ind`, working directory `/opt/apps/informatica/SrcFiles/Indicators`. See below. |
| 4 | End |  |  |

## Mapping tasks

Create one mapping task per mapping. IDQ mapping-task settings and their CDI home:

| Mapping task | Mapping | Date format (Advanced session property *Default date format*) | High precision (*Enable high precision*) | Tracing (*Override tracing*) | Sort order |
|---|---|---|---|---|---|
| `mct_Tgt_C_S_WIC_Pty_Validation` | [`m_Tgt_C_S_WIC_Pty_Validation`](mappings/m_Tgt_C_S_WIC_Pty_Validation.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_WIC_Pty` | [`m_Tgt_C_S_WIC_Pty`](mappings/m_Tgt_C_S_WIC_Pty.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_WIC_Pty_Addr` | [`m_Tgt_C_S_WIC_Pty_Addr`](mappings/m_Tgt_C_S_WIC_Pty_Addr.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | [`m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr`](mappings/m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |
| `mct_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | [`m_Tgt_C_S_WIC_Pty_Rle_Alt_Id`](mappings/m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |

Each Data Task: *On error* = **Fail taskflow** (IDQ aborts the workflow when a mapping task fails). Pass the parameter file through the mapping task *Parameter file* setting (see the `.param` file).

Workflow variables `MappingTaskSuccessful` are declared but never assigned or read in the IDQ workflow: not ported.

## Command task

IDQ runs `touch ${var:sys.WorkflowName}.ind` on the DIS host. In the CDI taskflow add a **Command Task** step that runs on the Linux Secure Agent runtime environment:

| Field | Value |
|---|---|
| Runtime Environment | the Linux Secure Agent group used by the mapping tasks |
| Script File Name | `/bin/sh` |
| Input Arguments | `-c "touch wf_WIC_Stage_Load.ind"` |
| Work Directory | `/opt/apps/informatica/SrcFiles/Indicators` |

`${var:sys.WorkflowName}` resolved to `wf_WIC_Stage_Load` so the indicator file name downstream consumers watch does not change. The agent user needs write access to the working directory.
