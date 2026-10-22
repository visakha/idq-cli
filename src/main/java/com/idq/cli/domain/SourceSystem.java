package com.idq.cli.domain;

import java.util.List;

/// Source systems that feed the Member domain, each with its IDQ workflows and source tables.
///
/// TRS has two workflows, run one after the other by the daily parent workflow: `wf_TRS_Stage_Load_1_Ongoing`
/// (members, 001 to 012) and `wf_TRS_Stage_Load_TOA` (the type-of-assistance catalogue, 035).
public enum SourceSystem {
    TRS(List.of("wf_TRS_Stage_Load_1_Ongoing", "wf_TRS_Stage_Load_TOA"), "TIERS eligibility system", List.of(
            "STG_TRS_D_DC_INDV", "STG_TRS_D_CV_DC_MCI_INDV", "STG_TRS_D_CV_MCI_EDG_INDV_TOA", "STG_TRS_VALID_MEMBERS",
            "STG_TRS_DEACTIVED_MEMBERS", "STG_TRS_D_DC_PRIMARY_PAYEE", "STG_TRS_DC_PRIMARY_PAYEE",
            "STG_TRS_CV_ED_MCI_EDG_INDV", "STG_TRS_D_CV_ED_MCI_EDG_INDV", "STG_TRS_DC_CASES", "STG_TRS_D_DC_CASES",
            "STG_TRS_DC_CASE_INDV", "STG_TRS_D_CV_DC_MCI_ALIAS", "STG_TRS_D_DC_ALIAS", "STG_TRS_D_CV_DC_MRG_SPRT_INDV",
            "STG_TRS_H_DC_INDV", "STG_TRS_D_IN_MANAGED_CARE", "STG_TRS_D_DC_RELATIONSHIPS", "STG_TRS_D_INDV_ADDR",
            "STG_TRS_D_UNQ_ADDR", "STG_TRS_CD_REF", "STG_TRS_D_LU_TOA")),
    ECI(List.of("wf_ECI_Stage_Load"), "ECI child and family system", List.of(
            "STG_ECI_D_CHILD", "STG_ECI_D_FAMILY", "STG_ECI_D_MEDICAID", "STG_ECI_SN_CASE", "STG_ECI_SN_CHILD",
            "V_ECI_ETL_SRC_FAMILY_ADDRESS", "V_ECI_ETL_SRC_FAMILY_PHONE", "V_ECI_ETL_LU_DUP_CASES",
            "V_ECI_ETL_LU_FAMILY_VALIDATION", "STG_ECI_PTY_INACTIVE_STS")),
    FSS(List.of("wf_FSS_Stage_Load"), "FSS source system", List.of(
            "V_FSS_ETL_SRC", "V_FSS_ETL_SRC_RELATIONS", "STG_FSS_PTY_INACTIVE_STS")),
    TTF(List.of("wf_TTF_Stage_Load"), "TTF source system", List.of(
            "V_TTF_ETL_SRC", "STG_TTF_PTY_INACTIVE_STS")),
    WIC(List.of("wf_WIC_Stage_Load"), "Women, Infants and Children", List.of(
            "V_WIC_ETL_SRC", "STG_WIC_PTY_INACTIVE_STS")),
    CRE(List.of("wf_CRE_Stage_Load_Ongoing"), "CARE clients", List.of(
            "STG_CRE_D_CARE_CLIENTS", "STG_CRE_SN_CARE_CLIENTS", "STG_CRE_D_CARE_CASE_MAINT"));

    /// The first (main) workflow.
    public final String workflow;
    /// Every workflow of the source, in the order they run.
    public final List<String> workflows;
    public final String description;
    public final List<String> sourceTables;

    SourceSystem(List<String> workflows, String description, List<String> sourceTables) {
        this.workflow = workflows.getFirst();
        this.workflows = workflows;
        this.description = description;
        this.sourceTables = sourceTables;
    }

    /// The workflows for display, e.g. `wf_TRS_Stage_Load_1_Ongoing + wf_TRS_Stage_Load_TOA`.
    public String workflowNames() {
        return String.join(" + ", workflows);
    }

    /// `C_S_<SRC>_<suffix>`
    public String target(String suffix) {
        return "C_S_" + name() + "_" + suffix;
    }
}
