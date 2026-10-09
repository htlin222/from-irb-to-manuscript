<!-- 結果：依 STROBE 第 13–17 項。教學示範：本段由 AI 撰寫；真實投稿時須由作者親自撰寫。 -->

## Patients

Of {{n_records}} registry records, {{n_duplicates}} duplicate records were removed, leaving {{n_patients}} patients (Figure 1). After exclusion of patients with clinical stage 0–I disease (n = {{n_excl_stage}}), distant metastasis at diagnosis (n = {{n_excl_m1}}), HER2-negative disease (n = {{n_excl_her2}}), no systemic therapy at the study hospital (n = {{n_excl_no_orders}}), and surgery at another hospital (n = {{n_excl_surgery_elsewhere}}), {{n_cohort}} patients were included: {{n_dual}} received trastuzumab plus pertuzumab and {{n_single}} received trastuzumab alone.

Baseline characteristics were similar between the groups except for the year of treatment start (SMD, {{smd_period_table1}}) and the use of anthracycline-based chemotherapy (SMD, {{smd_anthracycline_table1}}) (Table 1). Most patients who received trastuzumab alone started treatment in 2012–2015, whereas most patients who received dual blockade started treatment in 2020–2023. After overlap weighting, all covariates were exactly balanced (maximum absolute SMD, {{max_smd_after}}), and the effective sample sizes were {{ess_dual}} and {{ess_single}} patients, respectively. The median follow-up was {{median_fu}} years overall, {{median_fu_dual}} years for dual blockade, and {{median_fu_single}} years for trastuzumab alone.

## Pathologic Complete Response

In the unweighted data, pCR was achieved in {{pcr_crude_dual}} patients who received dual blockade and in {{pcr_crude_single}} patients who received trastuzumab alone (Table 2). Within treatment periods, however, crude pCR rates were higher with dual blockade (2012–2015: {{pcr_2012_2015_dual}} vs. {{pcr_2012_2015_single}}; 2016–2019: {{pcr_2016_2019_dual}} vs. {{pcr_2016_2019_single}}), and the overall pCR rate in 2020–2023, when only {{n_2020_2023_single}} patients received trastuzumab alone, was {{pcr_2020_2023_all}}. After overlap weighting, the pCR rate was {{pcr_w_dual}} with dual blockade and {{pcr_w_single}} with trastuzumab alone, a difference of {{pcr_rd}}; the OR was {{pcr_or}} ({{pcr_p}}).

## Event-Free and Overall Survival

EFS events occurred in {{efs_events_dual}} patients who received dual blockade and in {{efs_events_single}} patients who received trastuzumab alone. The weighted five-year EFS rates were {{efs_5y_dual}} and {{efs_5y_single}}, respectively (HR, {{efs_hr|b}}; {{efs_p}}) (Table 3, Figure 2). Deaths occurred in {{os_events_dual}} and {{os_events_single}} patients, and the weighted five-year OS rates were {{os_5y_dual}} and {{os_5y_single}} (HR, {{os_hr|b}}; {{os_p}}) (Figure 3). There was no evidence against proportional hazards for EFS ({{efs_ph_p}}) or OS ({{os_ph_p}}). Among patients who did not achieve pCR, adjuvant T-DM1 was given to {{tdm1_non_pcr_dual}} in the dual-blockade group and {{tdm1_non_pcr_single}} in the single-blockade group.

## Sensitivity and Subgroup Analyses

The direction of the association with pCR was consistent across sensitivity analyses (Table 2): the OR was {{pcr_or_s3}} with multivariable regression and {{pcr_or_s4}} when pCR was defined as ypT0 ypN0. In the cohort restricted to 2016–2019 ({{n_s1_dual}} and {{n_s1_single}} patients) and in the complete-case analysis, the ORs were {{pcr_or_s1}} and {{pcr_or_s6}}, respectively, with confidence intervals that included the null value. Propensity-score matching retained {{n_s2_pairs}} pairs and yielded a smaller estimate (OR, {{pcr_or_s2|b}}). The association did not differ by hormone receptor status (receptor-negative OR, {{or_hr_negative|b}}; receptor-positive OR, {{or_hr_positive|b}}; {{p_interaction_hr}} for interaction). The E-value for the primary OR was {{evalue_pcr}}, and that for its lower confidence limit was {{evalue_pcr_ci}}.
