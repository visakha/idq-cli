# Taskflow tf_TRS_Stage_Load_TOA

Replaces IDQ workflow `wf_TRS_Stage_Load_TOA`. Create it as a **Taskflow** (not a linear taskflow) because the workflow runs mapping tasks in parallel.

## IDQ workflow

```mermaid
flowchart LR
  u-9aklx6mwee6m-uvc1wbboq(["Start_Event"])
  u-9aklykmwee6m-uvc1wbboq(["End_Event"])
  u-adues6mxee6m-uvc1wbboq["m_Tgt_C_S_TRS_Stg_TOA"]
  u-9aklx6mwee6m-uvc1wbboq --> u-adues6mxee6m-uvc1wbboq
  u-adues6mxee6m-uvc1wbboq --> u-9aklykmwee6m-uvc1wbboq
```

## CDI taskflow

```mermaid
flowchart LR
  s(["Start"])
  p0["Data Task<br/>mct_Tgt_C_S_TRS_Stg_TOA"]
  s --> p0
  p1(["End"])
  p0 --> p1
```

## Steps

| # | Step | Runs | Notes |
|---|---|---|---|
| 0 | Data Task | `mct_Tgt_C_S_TRS_Stg_TOA` |  |
| 1 | End |  |  |

## Mapping tasks

Create one mapping task per mapping. IDQ mapping-task settings and their CDI home:

| Mapping task | Mapping | Date format (Advanced session property *Default date format*) | High precision (*Enable high precision*) | Tracing (*Override tracing*) | Sort order |
|---|---|---|---|---|---|
| `mct_Tgt_C_S_TRS_Stg_TOA` | [`m_Tgt_C_S_TRS_Stg_TOA`](mappings/m_Tgt_C_S_TRS_Stg_TOA.md) | MM/DD/YYYY HH24:MI:SS | true | normal | binary |

Each Data Task: *On error* = **Fail taskflow** (IDQ aborts the workflow when a mapping task fails). Pass the parameter file through the mapping task *Parameter file* setting (see the `.param` file).
