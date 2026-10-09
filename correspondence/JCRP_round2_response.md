# Response to the editor and reviewers — JCRP round 2

<!--
回覆信來源檔（單一來源）。審稿意見原文不在此重抄：manuscript/R/build_revision.R 依編號（R1.1、R2.1…）從
correspondence/JCRP_decision_round2.md 讀取。每節：Response 段落＋Changes 段落；數字一律用 {{代號}}。
教學示範：本回覆由 AI 撰寫；真實投稿時須由作者親自撰寫。
-->

## Opening

We thank the editor and the reviewers for their further review. We have addressed each remaining point below. In the marked revised manuscript, changes since the first revision are shown in blue and underlined (new text) and in red and struck through (deleted text), including the new column of Table 1; the Summary of Changes below gives the page of each change. The analysis of the weighted distribution of treatment periods was not prespecified and is labeled post hoc.

## R1.1

Response: We agree that causal language is not appropriate for an observational study. We note that the Conclusion did not claim an EFS benefit: it stated that the data were insufficient to assess EFS or OS. Nevertheless, we have revised the wording so that no part of it can be read as causal. The Conclusion of the Abstract now begins "In this observational cohort, dual HER2 blockade was associated with a higher pCR rate," and the concluding paragraph of the Discussion states that the data were insufficient to determine whether dual blockade is associated with longer EFS or OS. As requested, the concluding paragraph now states the main assumptions in one sentence: interpreting the association as an effect of the regimen assumes that no unmeasured factor influenced both treatment choice and pCR and that every patient could have received either regimen (positivity). We add that the positivity assumption was only partly met because the regimens were used in different years. We also replaced "the effect in patients for whom both regimens were realistic options" with "an association" in the Discussion.

Changes: Abstract (Conclusion); Discussion (third paragraph and concluding paragraph).

## R2.1

Response: The completed STROBE checklist was provided with the first revision as a separate file. It is now labeled Supplementary File S2, cited in the Methods, and listed in the Supplementary Material. The page number for each item refers to the clean revised manuscript and was updated for this revision.

Changes: Methods (Study Design and Data Sources); Supplementary Material (Supplementary File S2); STROBE checklist.

## R2.2

Response: Table 1 now shows SMDs both before and after overlap weighting. After weighting, the SMD was {{max_smd_after_other}} for every characteristic except the treatment period, for which it was {{smd_period_after}}. This finding is important, and we thank the reviewer for the request. Year of treatment start entered the prespecified propensity-score model as a continuous variable, so overlap weighting balanced the mean year exactly but not the distribution of treatment periods: in a post hoc analysis, {{era_early_w_dual}} of the weighted dual-blockade group and {{era_early_w_single}} of the weighted single-blockade group started treatment in 2012–2015. We now report this in the Results, Discussion, and limitations. Two analyses address it. When year was modeled with a natural spline (post hoc analysis from the first revision; Supplementary Table S4), the SMD for treatment period after weighting fell to {{smd_period_after_spline}} and the OR for pCR was {{or_spline}}, similar to the primary estimate ({{pcr_or}}). The prespecified analysis restricted to patients who started treatment in 2016–2019 gave an OR of {{pcr_or_s1}}. We have kept the prespecified primary analysis and interpret it with this limitation.

Changes: Table 1 (new column and revised footnotes); Methods (Statistical Analysis, post hoc analyses); Results (Patients; Post Hoc Analyses); Discussion (third paragraph and limitations).

## Closing

We hope that the revised manuscript is now suitable for publication in the Journal of Cancer Research and Practice.
