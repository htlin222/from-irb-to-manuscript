# Response to the editor and reviewers — JCRP round 1

<!--
回覆信來源檔（單一來源）。審稿意見原文不在此重抄：manuscript/revision.qmd 依編號（E1、R1.1…）從
correspondence/JCRP_decision_round1.md 讀取。每節：Response 段落＋Changes 段落；數字一律用 {{代號}}。
教學示範：本回覆由 AI 撰寫；真實投稿時須由作者親自撰寫。
-->

## Opening

We thank the editor and the two reviewers for their careful reading and constructive comments, which have improved the manuscript. We have addressed every comment below. In the marked revised manuscript, new text is shown in blue and underlined and deleted text in red and struck through; the Summary of Changes below gives the page of each change. Analyses added in response to the reviewers were not prespecified and are labeled post hoc throughout the manuscript.

## E1

Response: The revised structured abstract remains within 250 words and uses the four required headings: Background, Materials and Methods, Results, and Conclusion.

Changes: Abstract (revised to report the post hoc worst-case analysis and a tempered conclusion).

## E2

Response: In-text citations are Arabic numerals in superscript square brackets placed after punctuation, and the reference list follows the journal's Vancouver style, with the first six authors followed by et al. and journal abbreviations according to Index Medicus. Every reference was verified against PubMed and Crossref.

Changes: References (one reference added for the TRYPHAENA trial; numbering updated).

## E3

Response: All figure legends contain 40 words or fewer. The Data Availability Statement and the Use of Generative AI statement appear before the References.

Changes: No change needed.

## R1.1

Response: We agree that separating the effect of the regimen from that of the treatment era is the central challenge of this study, and we addressed it in three ways. First, the year of treatment start was included in the propensity-score model, and overlap weighting was chosen because the two eras overlapped little; this method gives the greatest weight to patients who could plausibly have received either regimen and avoids extreme weights. Second, as suggested, we now show the propensity-score distributions by group (new Supplementary Figure S2). The overlap was partial: the median propensity score was {{ps_median_dual}} with dual blockade and {{ps_median_single}} with trastuzumab alone, and patients who started treatment in 2016–2019 contributed {{weight_share_2016_2019}} of the overlap weights. Third, the prespecified analysis restricted to 2016–2019 gave an odds ratio (OR) of {{pcr_or_s1}}, and a new post hoc analysis that modeled year with a natural spline gave an OR of {{or_spline}}. We state in the Discussion that the estimate applies to patients for whom both regimens were realistic options.

Changes: Methods (Statistical Analysis, post hoc analyses); Results (Patients; Post Hoc Analyses); Discussion (third paragraph); Supplementary Figure S2 and Table S4.

## R1.2

Response: We agree that adjuvant trastuzumab emtansine (T-DM1) was used mainly in the dual-blockade era: among patients without pathologic complete response (pCR), {{tdm1_non_pcr_dual}} in the dual-blockade group and {{tdm1_non_pcr_single}} in the single-blockade group received T-DM1. We did not stratify the event-free survival (EFS) analysis by T-DM1, because T-DM1 is given only to patients with residual disease and therefore depends on the response to the neoadjuvant regimen; conditioning on it would introduce bias. Instead, we performed a post hoc analysis restricted to patients who started treatment in 2012–2019, before adjuvant T-DM1 was used at the study hospital. In this group, {{tdm1_2012_2019}} of the patients without pCR received T-DM1, and the hazard ratio (HR) for EFS was {{efs_hr_2012_2019}}, similar to that in the full cohort (HR, {{efs_hr|b}}). We also note that the primary analysis did not show a clear EFS difference between the regimens, and we have kept the conclusion that the data are insufficient to assess EFS.

Changes: Methods (Statistical Analysis, post hoc analyses); Results (Post Hoc Analyses); Discussion (fourth paragraph); Supplementary Table S4.

## R1.3

Response: As stated in the Methods, patients whose disease progressed before surgery were classified as not achieving pCR. Excluding these patients ({{n_pbs_dual}} with dual blockade and {{n_pbs_single}} with trastuzumab alone) gave an OR of {{or_no_pbs}}. Patients operated on at another hospital were excluded because no pathology report was available. In new post hoc best-case and worst-case analyses that included these {{n_elsewhere_dual}} dual-blockade and {{n_elsewhere_single}} single-blockade patients, the OR was {{or_elsewhere_no_pcr}} if none of them achieved pCR and {{or_elsewhere_all_pcr}} if all did. Because most of these patients received trastuzumab alone, the worst-case assumption attenuated the association, and its confidence interval included the null value. We report this result in the Abstract, Results, and limitations and have tempered the Conclusion accordingly.

Changes: Abstract; Methods (Statistical Analysis, post hoc analyses); Results (Post Hoc Analyses); Discussion (limitations and conclusion); Supplementary Table S4.

## R1.4

Response: We agree that residual confounding is likely. The E-value for the primary OR was {{evalue_pcr}}, and that for its lower confidence limit was {{evalue_pcr_ci}}; an unmeasured confounder associated with both treatment and pCR by a risk ratio of approximately {{evalue_pcr}}, beyond the measured covariates, could explain away the observed association. These values are reported in the Results and discussed in the limitations, where we have corrected the scale of the E-value to the risk ratio.

Changes: Results (Sensitivity and Subgroup Analyses); Discussion (limitations); Supplementary Table S3.

## R2.1

Response: Time zero was the index date, defined as the date of the first neoadjuvant anticancer drug order, when eligibility was met and the treatment strategy began; all outcomes were measured from this date. Because treatment groups were defined by any pertuzumab use before surgery, a patient could in principle be classified as receiving single blockade because surgery or progression occurred before pertuzumab was added. We examined this post hoc. Pertuzumab was started on the index date in {{pz_from_index}} patients and later in {{pz_later}} patients (median, day {{pz_later_median_day}}, consistent with sequential regimens), whereas the earliest surgery or disease progression in the single-blockade group occurred on day {{single_min_day}}. Therefore, no patient was assigned to single blockade because of an early event, and immortal time bias is unlikely.

Changes: Methods (Treatment Groups and Outcomes); Results (Post Hoc Analyses).

## R2.2

Response: Median follow-up was estimated with the reverse Kaplan-Meier method and reported by group ({{median_fu_dual}} years for dual blockade and {{median_fu_single}} years for trastuzumab alone); the method is now stated in the Methods. As suggested, we also report a restricted time horizon: the five-year restricted mean survival time difference was {{rmst5_efs}} for EFS and {{rmst5_os}} for overall survival (OS), and with follow-up truncated at five years the HRs were {{efs_hr_5y}} for EFS and {{os_hr_5y}} for OS (post hoc). These results do not change our conclusions.

Changes: Methods (Statistical Analysis); Results (Event-Free and Overall Survival; Post Hoc Analyses); Supplementary Table S4.

## R2.3

Response: We agree. The OS analysis was exploratory and had few events. We now emphasize the confidence intervals rather than the P values, state that the wide confidence interval for OS is compatible with both a clinically important benefit and harm, and state in the Discussion that the OS results should be regarded as exploratory. The Conclusion states that the data were insufficient to determine the effect on OS.

Changes: Results (Event-Free and Overall Survival); Discussion (fourth paragraph).

## R2.4

Response: We now compare our findings with NeoSphere, TRYPHAENA, and PEONY, with published real-world cohorts from Turkey, Italy, China, and Spain, and with a meta-analysis of real-world studies. We have also expanded the first limitation to describe the consequences of the single-center design: the results reflect one institution's patient population, treatment practices, and pathology procedures and may not apply to other settings.

Changes: Discussion (second paragraph and limitations); References.

## Closing

We hope that the revised manuscript is now suitable for publication in the *Journal of Cancer Research and Practice*.
