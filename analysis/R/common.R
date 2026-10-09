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

# 資訊室更正：每筆以 (chart_no, table, field) 定位唯一一列，舊值不符就停止。回傳更正後資料與彙總紀錄。
apply_corrections <- function(raw, p = params()) {
  if (is.null(p$corrections)) return(list(raw = raw, applied = 0L))
  cx <- fread(file.path(RAW_DIR, p$corrections), colClasses = "character", na.strings = NULL)
  for (r in seq_len(nrow(cx))) {
    k <- names(p$raw_files)[match(paste0(cx$table[r], ".csv"), unlist(p$raw_files))]
    if (is.na(k) || !cx$field[r] %in% names(raw[[k]])) stop("更正檔第 ", r, " 列：表或欄位不存在")
    i <- which(raw[[k]]$chart_no == cx$chart_no[r])
    if (length(i) != 1 || raw[[k]][[cx$field[r]]][i] != cx$old_value[r]) {
      stop("更正檔第 ", r, " 列：找不到唯一一列或舊值與原始資料不符，未套用任何更正")
    }
    set(raw[[k]], i, cx$field[r], cx$new_value[r])
  }
  list(raw = raw, applied = nrow(cx))
}

# 讀全部原始表並套用資訊室更正（資料檢查與去識別化都用這個，確保兩者看到同一份資料）
read_all_raw <- function(p = params()) {
  raw <- lapply(setNames(names(p$raw_files), names(p$raw_files)), read_raw, p = p)
  apply_corrections(raw, p)
}

# 資料檢查中仍未解決的錯誤數（已查證並記錄在 analysis/data_queries.yaml 者不算）
unresolved_errors <- function() {
  val <- fread(file.path(RESULTS_DIR, "data_validation.csv"))
  val[level == "error" & !resolved, .N]
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
