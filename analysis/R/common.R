# 共用：讀研究事實、驗證原始資料 checksum、讀原始檔、記錄軟體與資料版本。
# 由專案根目錄執行（make 會這樣做）。
suppressPackageStartupMessages({
  library(data.table)
})

RAW_DIR <- "data/raw"
RESULTS_DIR <- "results"

params <- function() yaml::read_yaml("analysis/params.yaml")

drug_map <- function() fread("analysis/drug_map.csv", colClasses = "character", na.strings = "")

# 研究事實來自 config.toml（單一來源）。data_period 依序含三個日期：收案起、收案迄、追蹤截止。
study_facts <- function(path = "config.toml") {
  cfg <- RcppTOML::parseTOML(path)
  m <- regmatches(cfg$dates$data_period,
                  gregexpr("(\\d{4})年(\\d{2})月(\\d{2})日", cfg$dates$data_period))[[1]]
  if (length(m) != 3) {
    stop("config.toml dates.data_period 應含三個日期（收案起、收案迄、追蹤截止），實際找到 ", length(m), " 個")
  }
  d <- as.IDate(gsub("(\\d{4})年(\\d{2})月(\\d{2})日", "\\1-\\2-\\3", m))
  list(irb_no = cfg$study$irb_no, enroll_start = d[1], enroll_end = d[2], fu_cutoff = d[3])
}

# 比對 data/raw/MANIFEST.sha256；任何不符就停止，不讀被改過的資料。
verify_manifest <- function() {
  man <- fread(file.path(RAW_DIR, "MANIFEST.sha256"), header = FALSE, sep = " ",
               col.names = c("sha256", "file"), strip.white = TRUE)
  man[, actual := vapply(file, function(f) {
    p <- file.path(RAW_DIR, f)
    if (file.exists(p)) digest::digest(file = p, algo = "sha256") else NA_character_
  }, "")]
  man[, ok := !is.na(actual) & actual == sha256]
  if (!all(man$ok)) {
    stop("原始資料與 MANIFEST.sha256 不符：", paste(man[!(ok), file], collapse = ", "))
  }
  man[, .(file, sha256)]
}

# 一律以文字讀入，空白保留為 ""，型別轉換與檢查由呼叫端負責。
read_raw <- function(key, p = params()) {
  fread(file.path(RAW_DIR, p$raw_files[[key]]), colClasses = "character", na.strings = NULL)
}

as_date <- function(x) as.IDate(ifelse(grepl("^\\d{4}-\\d{2}-\\d{2}$", x), x, NA_character_))

# 每份結果旁邊放一個 provenance 檔：哪個程式版本、哪份資料、哪些軟體產生的
write_provenance <- function(name, outputs, pkgs = character(), manifest = verify_manifest()) {
  pr <- provenance(manifest, c(CORE_PKGS, pkgs))
  dir.create(file.path(RESULTS_DIR, "provenance"), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(list(
    outputs = outputs, script = sub(".*--file=", "", grep("--file=", commandArgs(FALSE), value = TRUE)),
    generated = pr$generated, git_commit = pr$git_commit, r_version = pr$r_version,
    packages = pr$packages, raw_data_sha256 = setNames(as.list(manifest$sha256), manifest$file)
  ), file.path(RESULTS_DIR, "provenance", paste0(name, ".json")), auto_unbox = TRUE, pretty = TRUE)
}

CORE_PKGS <- c("data.table", "yaml", "RcppTOML", "digest", "jsonlite")

provenance <- function(manifest, pkgs = CORE_PKGS) {
  git <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE),
                                error = function(e) NA_character_)
  dirty <- length(git("status", "--porcelain", "--", "analysis", "config.toml")) > 0
  list(
    generated = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    git_commit = paste0(git("rev-parse", "--short", "HEAD"), if (dirty) "（分析程式有未存檔修改）" else ""),
    r_version = R.version.string,
    packages = paste(sprintf("%s %s", pkgs, vapply(pkgs, function(p) as.character(packageVersion(p)), "")),
                     collapse = "、"),
    manifest = manifest
  )
}
