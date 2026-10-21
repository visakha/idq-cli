# Mapping documentation

One document per IDQ mapping, in workflow execution order. Shared mapplet logic
(name standardization, address validation, phone / e-mail rules, timestamps) is described in
[000_mapplets.md](000_mapplets.md).

Workflow order: TRS 001, 007, 002-006, 008-012; ECI 013-018; FSS 019-024; TTF 025-028; WIC 029-033; CRE 034.

| # | Mapping | Source | Sub-domain |
|---|---|---|---|
| [001](001_m_Tgt_C_S_TRS_Pty_OnGoing.md) | `m_Tgt_C_S_TRS_Pty_OnGoing` | TRS (TIERS) | Demographics (plus Role) |
| [002](002_m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing.md) | `m_Tgt_C_S_TRS_Pty_Mng_Attr_Auth_Rep_Ongoing` | TRS | Party-Managed-Attrib |
| [003](003_m_Tgt_C_S_TRS_Pty_Nm.md) | `m_Tgt_C_S_TRS_Pty_Nm` | TRS | Alternate-Name |
| [004](004_m_Tgt_C_S_TRS_Pty_Rle_Alt_Id.md) | `m_Tgt_C_S_TRS_Pty_Rle_Alt_Id` | TRS | Alternate-ID |
| [005](005_m_Tgt_C_S_TRS_Pty_Rle_Pln.md) | `m_Tgt_C_S_TRS_Pty_Rle_Pln` | TRS | Role |
| [006](006_m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr.md) | `m_Tgt_C_S_TRS_Pty_Rle_Phn_And_EAddr` | TRS | Phone-email |
| [007](007_m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw.md) | `m_Tgt_C_S_TRS_Pty_Mng_Attr_Sw` | TRS | Party-Managed-Attrib |
| [008](008_m_Tgt_C_S_TRS_Pty_Rle_TOA.md) | `m_Tgt_C_S_TRS_Pty_Rle_TOA` | TRS | Role |
| [009](009_m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem.md) | `m_Tgt_C_S_TRS_Pty_Rle_Rel_1_Mem_To_Mem` | TRS | Role |
| [010](010_m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP.md) | `m_Tgt_C_S_TRS_Pty_Rle_Rel_2_Mem_To_PCP` | TRS | Role |
| [011](011_m_Tgt_C_S_TRS_Addr_1.md) | `m_Tgt_C_S_TRS_Addr_1` | TRS | Address |
| [012](012_m_Tgt_C_S_TRS_Addr_2.md) | `m_Tgt_C_S_TRS_Addr_2` | TRS | Address |
| [013](013_m_Tgt_C_S_ECI_Pty_Validation.md) | `m_Tgt_C_S_ECI_Pty_Validation` | ECI | Demographics (party activation status) |
| [014](014_m_Tgt_C_S_ECI_Pty.md) | `m_Tgt_C_S_ECI_Pty` | ECI | Demographics (plus Role) |
| [015](015_m_Tgt_C_S_ECI_Pty_Addr.md) | `m_Tgt_C_S_ECI_Pty_Addr` | ECI | Address |
| [016](016_m_Tgt_C_S_ECI_Pty_Rle_Alt_Id.md) | `m_Tgt_C_S_ECI_Pty_Rle_Alt_Id` | ECI | Alternate-ID |
| [017](017_m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr.md) | `m_Tgt_C_S_ECI_Pty_Rle_Phn_And_EAddr` | ECI | Phone-email |
| [018](018_m_Tgt_C_S_ECI_Pty_Rle_Rel.md) | `m_Tgt_C_S_ECI_Pty_Rle_Rel` | ECI | Role |
| [019](019_m_Tgt_C_S_FSS_Pty_Validation.md) | `m_Tgt_C_S_FSS_Pty_Validation` | FSS | Demographics (party activation status) |
| [020](020_m_Tgt_C_S_FSS_Pty.md) | `m_Tgt_C_S_FSS_Pty` | FSS | Demographics (plus Role) |
| [021](021_m_Tgt_C_S_FSS_Pty_Addr.md) | `m_Tgt_C_S_FSS_Pty_Addr` | FSS | Address |
| [022](022_m_Tgt_C_S_FSS_Pty_Rle_Alt_Id.md) | `m_Tgt_C_S_FSS_Pty_Rle_Alt_Id` | FSS | Alternate-ID |
| [023](023_m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr.md) | `m_Tgt_C_S_FSS_Pty_Rle_Phn_And_EAddr` | FSS | Phone-email |
| [024](024_m_Tgt_C_S_FSS_Pty_Rle_Rel.md) | `m_Tgt_C_S_FSS_Pty_Rle_Rel` | FSS | Role |
| [025](025_m_Tgt_C_S_TTF_Pty_Validation.md) | `m_Tgt_C_S_TTF_Pty_Validation` | TTF | Demographics (party activation status) |
| [026](026_m_Tgt_C_S_TTF_Pty.md) | `m_Tgt_C_S_TTF_Pty` | TTF | Demographics (plus Role) |
| [027](027_m_Tgt_C_S_TTF_Pty_Rle_Alt_Id.md) | `m_Tgt_C_S_TTF_Pty_Rle_Alt_Id` | TTF | Alternate-ID |
| [028](028_m_Tgt_C_S_TTF_Pty_Rle_Phn.md) | `m_Tgt_C_S_TTF_Pty_Rle_Phn` | TTF | Phone-email |
| [029](029_m_Tgt_C_S_WIC_Pty_Validation.md) | `m_Tgt_C_S_WIC_Pty_Validation` | WIC | Demographics (party activation status) |
| [030](030_m_Tgt_C_S_WIC_Pty.md) | `m_Tgt_C_S_WIC_Pty` | WIC | Demographics (plus Role) |
| [031](031_m_Tgt_C_S_WIC_Pty_Addr.md) | `m_Tgt_C_S_WIC_Pty_Addr` | WIC | Address |
| [032](032_m_Tgt_C_S_WIC_Pty_Rle_Alt_Id.md) | `m_Tgt_C_S_WIC_Pty_Rle_Alt_Id` | WIC | Alternate-ID |
| [033](033_m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr.md) | `m_Tgt_C_S_WIC_Pty_Rle_Phn_And_EAddr` | WIC | Phone-email |
| [034](034_m_Tgt_C_S_CRE_CARE_Clients.md) | `m_Tgt_C_S_CRE_CARE_Clients` | CRE (CARE clients) | Demographics (plus Role), Address, Phone-email, Alternate-ID |
