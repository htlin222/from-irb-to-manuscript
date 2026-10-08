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
