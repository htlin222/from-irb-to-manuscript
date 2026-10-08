# 治療分組與收案相關定義的測試。執行：make test-analysis
library(testthat)
source(test_path("..", "R", "definitions.R"))

dm <- fread(test_path("..", "drug_map.csv"), colClasses = "character", na.strings = "")
d <- as.IDate

orders <- function(...) {
  o <- rbindlist(list(...))
  o[, order_d := d(order_date)]
  map_orders(o, dm)
}
o <- function(id, date, drug) data.table(study_id = id, order_date = date, drug_name = drug)
surg <- function(id, date) data.table(study_id = id, surg_d = d(date))
no_fu <- data.table(study_id = character(), recurrence_type = character(), rec_d = as.IDate(character()))

test_that("drug map has unique raw names per agent and no fuzzy matches", {
  expect_false(anyDuplicated(dm[, .(raw_name, agent)]) > 0)
  m <- map_orders(data.table(drug_name = "Trastuzumab emtansine"), dm)
  expect_equal(m$agent, "trastuzumab_emtansine")   # 名稱含 Trastuzumab，但是 T-DM1
  expect_setequal(map_orders(data.table(drug_name = "Phesgo 1200/600 SC"), dm)$agent,
                  c("pertuzumab", "trastuzumab"))
  expect_error(map_orders(data.table(drug_name = "Lapatinib"), dm), "drug_map")
})

test_that("chemo + trastuzumab + pertuzumab before surgery is dual", {
  s <- neoadjuvant_summary(
    orders(o("A", "2018-01-01", "Docetaxel"), o("A", "2018-01-01", "Herceptin"), o("A", "2018-01-01", "Perjeta")),
    surg("A", "2018-06-01"), no_fu)
  expect_equal(s$treatment_group, "dual")
  expect_equal(s$index_d, d("2018-01-01"))
  expect_true(s$neo_chemo)
})

test_that("Phesgo alone counts as both trastuzumab and pertuzumab", {
  s <- neoadjuvant_summary(orders(o("B", "2022-01-01", "Paclitaxel"), o("B", "2022-01-01", "Phesgo 1200/600 SC")),
                           surg("B", "2022-06-01"), no_fu)
  expect_equal(s$treatment_group, "dual")
})

test_that("pertuzumab only after surgery (adjuvant) stays single", {
  s <- neoadjuvant_summary(
    orders(o("C", "2016-01-01", "Taxotere"), o("C", "2016-01-01", "Trastuzumab"), o("C", "2016-07-01", "Pertuzumab")),
    surg("C", "2016-06-01"), no_fu)
  expect_equal(s$treatment_group, "single")
})

test_that("orders on the day of surgery are not neoadjuvant", {
  s <- neoadjuvant_summary(
    orders(o("D", "2016-01-01", "Taxotere"), o("D", "2016-01-01", "Trastuzumab"), o("D", "2016-06-01", "Pertuzumab")),
    surg("D", "2016-06-01"), no_fu)
  expect_equal(s$treatment_group, "single")
})

test_that("T-DM1 is not trastuzumab", {
  s <- neoadjuvant_summary(orders(o("E", "2021-01-01", "Kadcyla"), o("E", "2021-01-01", "Docetaxel")),
                           surg("E", "2021-06-01"), no_fu)
  expect_true(is.na(s$treatment_group))
  expect_true(s$neo_tdm1)
})

test_that("surgery before the first order is upfront surgery with no neoadjuvant therapy", {
  s <- neoadjuvant_summary(orders(o("F", "2015-03-01", "Docetaxel"), o("F", "2015-03-01", "Herceptin")),
                           surg("F", "2015-01-15"), no_fu)
  expect_true(s$upfront_surgery)
  expect_false(s$neo_trastuzumab)
  expect_true(is.na(s$treatment_group))
})

test_that("progression before surgery ends the window at progression", {
  fu <- data.table(study_id = "G", recurrence_type = "Progression before surgery", rec_d = d("2019-04-01"))
  s <- neoadjuvant_summary(
    orders(o("G", "2019-01-01", "Docetaxel"), o("G", "2019-01-01", "Herceptin"), o("G", "2019-05-01", "Perjeta")),
    surg("G", NA_character_)[0], fu)
  expect_equal(s$window_end, d("2019-04-01"))
  expect_equal(s$treatment_group, "single")
})

test_that("no surgery and no progression leaves the window undefined", {
  s <- neoadjuvant_summary(orders(o("H", "2019-01-01", "Docetaxel"), o("H", "2019-01-01", "Herceptin")),
                           surg("H", NA_character_)[0], no_fu)
  expect_true(is.na(s$window_end))
  expect_true(is.na(s$treatment_group))
})

test_that("HER2 positive is IHC 3+ or ISH amplified", {
  expect_equal(her2_positive(c("3+", "2+", "2+", "2+", "1+"), c("", "Amplified", "Not amplified", "", "Amplified")),
               c(TRUE, TRUE, FALSE, FALSE, TRUE))
})

test_that("chemo backbone follows anthracycline > carboplatin > taxane", {
  expect_equal(chemo_backbone(c(TRUE, FALSE, FALSE, FALSE), c(TRUE, TRUE, FALSE, FALSE), c(TRUE, TRUE, TRUE, FALSE)),
               c("Anthracycline-based", "Carboplatin-based", "Taxane only", "Other"))
  s <- neoadjuvant_summary(
    orders(o("I", "2014-01-01", "Pharmorubicin"), o("I", "2014-01-01", "Endoxan"),
           o("I", "2014-03-01", "Taxotere"), o("I", "2014-03-01", "Herceptin"), o("I", "2014-09-01", "Paraplatin")),
    surg("I", "2014-08-01"), no_fu)
  expect_equal(s$chemo_backbone, "Anthracycline-based")
  expect_false(s$neo_platinum)   # carboplatin 在手術後，不算術前
})

test_that("percent fields parse with or without % and receptor cut-off is inclusive", {
  expect_equal(parse_pct(c("64%", "64", " 5% ", "", "n/a")), c(64, 64, 5, NA, NA))
  expect_equal(receptor_positive(c("0", "1", "0.5", "90", ""), cutoff = 1), c(FALSE, TRUE, FALSE, TRUE, NA))
})

test_that("pCR is ypT0/is ypN0; ITCs, micrometastases and no surgery are not pCR", {
  expect_equal(pcr(c("ypT0", "ypTis", "ypT0", "ypT0", "ypT1mi", "", "ypT0"),
                   c("ypN0", "ypN0", "ypN0(i+)", "ypN1mi", "ypN0", "ypN0", ""),
                   had_surgery = rep(TRUE, 7)),
               c(TRUE, TRUE, FALSE, FALSE, FALSE, NA, NA))
  expect_false(pcr(NA_character_, NA_character_, had_surgery = FALSE))   # 術前惡化、未手術
})

test_that("orders after death are dropped as unexecuted pre-orders", {
  ord <- data.table(study_id = c("J", "J", "K"), order_d = d(c("2020-01-01", "2020-06-01", "2020-06-01")))
  fu <- data.table(study_id = c("J", "K"), death_d = d(c("2020-03-01", NA)))
  expect_equal(drop_unexecuted_orders(ord, fu)[, .N, by = study_id]$N, c(1L, 1L))
})

test_that("follow-up ends at the later of last visit and last order, death date if dead, capped at cut-off", {
  end <- followup_end(last_contact_d = d(c("2024-01-01", "2024-05-01", "2024-01-01", "2025-11-01")),
                      last_order_d = d(c("2024-03-01", NA, "2024-03-01", "2026-02-01")),
                      death_d = d(c(NA, NA, "2024-02-01", NA)), cutoff = d("2025-12-31"))
  expect_equal(end, d(c("2024-03-01", "2024-05-01", "2024-02-01", "2025-12-31")))
})
