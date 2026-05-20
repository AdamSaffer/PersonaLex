# ============================================================================ #
# PersonaLex: Step 3 — Run the Classifier ----
# ============================================================================ #
#
## PURPOSE ----
# 
# This script applies the PersonaLex classifier to a dataset of short-form
# text bios and returns a binary (0/1) classification for each category and
# subcategory in the lexicon.
#
# This script has two sections:
#
#   SECTION A — Simple classification (recommended starting point)
#     Runs the classifier on a single data frame in memory. Suitable for
#     datasets up to roughly 500,000 rows depending on available RAM.
#     Use this section with the included sample_bios.csv to verify your
#     setup before running on your own data.
#
#   SECTION B — Parallel classification for large datasets
#     Splits the data into shards and distributes classification across
#     multiple CPU cores using the future and future.apply packages.
#     Recommended for datasets of 500,000+ rows.
#
## BEFORE YOU RUN THIS SCRIPT ----
# 
# 1. You must have already run 02_build_classifier.R, which produces
#    classifier.rds in your working directory.
#
# 2. Your text data must be a CSV or RDS file with at least two columns:
#      id   — a unique identifier for each record (character or numeric)
#      text — the short-form text to classify (e.g., a social media bio)
#
#    >>> REPLACE YOUR DATA <<<
#    Search this script for ">>> REPLACE" to find every place you need
#    to substitute your own file path or column names.
#
# 3. Required packages (first time only). If you are using renv,
#    run renv::restore() instead.
#
#    install.packages(c("dplyr", "readr", "purrr",
#                       "future", "future.apply"))   # future packages for Section B only
#
## OUTPUT ----
# 
# Section A: classified_results.rds and classified_results.csv
# Section B: classified_all.rds (merged from parallel shards)
#
## OUTPUT COLUMN NAMES ----
# 
# The classifier returns one column per category and subcategory.
# All values are binary: 1 = term detected, 0 = not detected.
# Multi-label classification is supported: a bio can be tagged for
# multiple categories simultaneously.
#
# Category columns use the category name directly:
#   religion, race, skintone, ethnicity, military, issue, political, sport
#
# Subcategory columns use the format <category>_<subcategory>:
#   religion_christian, religion_jewish, race_black, political_left, etc.
#
# ============================================================================ #


# ============================================================================ #
# SECTION A: Simple Classification ----
# ============================================================================ #
# Use this section to run the classifier on a manageable dataset.
# This is the best starting point for new users.
# ============================================================================ #


# ---------------------------------------------------------------------------- #
## A1. Load packages  ----
# ---------------------------------------------------------------------------- #

library(dplyr)
library(readr)
library(purrr)


# ---------------------------------------------------------------------------- #
## A2. Load the classifier ----
# ---------------------------------------------------------------------------- #
# This reads the compiled classifier object produced by 02_build_classifier.R.
# If you have not yet run that script, do so before continuing.

clf <- readRDS("classifier.rds")

# The classification functions (.detect, classify_bios, pretty_names) were
# defined and saved as part of the classifier environment in 02_build_classifier.R.
# They need to be available in this session. If you are running this script
# fresh (without having run 02 in the same session), source the functions below.
#
# Uncomment and run this line if classify_bios() is not found:
# source("02_build_classifier.R")


# ---------------------------------------------------------------------------- #
## A3. Load your text data  ----
# ---------------------------------------------------------------------------- #
# >>> REPLACE YOUR DATA <<<
# Replace "sample_bios.csv" with the path to your own data file.
#
# Your data must have at minimum:
#   - An ID column (any name; default expected: "id")
#   - A text column containing the bios or short-form text (default: "text")
#
# Examples:
#   my_data <- read_csv("path/to/my_bios.csv")
#   my_data <- readRDS("path/to/my_bios.rds")
#
# If your columns have different names, update id_col and text_col in A4.

my_data <- read_csv("sample_bios.csv",
                    col_types = cols(
                      id   = col_character(),
                      text = col_character()
                    ))

# Preview and confirm
message("Data loaded: ", nrow(my_data), " rows.")
head(my_data)


# ---------------------------------------------------------------------------- #
## A4. Run the classifier  ----
# ---------------------------------------------------------------------------- #
# classify_bios() applies every category and subcategory pattern to each row.
#
# >>> REPLACE YOUR DATA <<<
# If your ID column is not named "id", update id_col below.
# If your text column is not named "text", update text_col below.
#
# Example with different column names:
#   results <- classify_bios(my_data, clf, id_col = "user_id", text_col = "bio")

message("Running classifier...")

results <- classify_bios(
  my_data,
  clf,
  id_col   = "id",    # >>> REPLACE if your ID column has a different name
  text_col = "text"   # >>> REPLACE if your text column has a different name
) |>
  dplyr::rename_with(pretty_names, .cols = -id)

message("Classification complete: ", nrow(results), " rows, ",
        ncol(results) - 1, " classification columns.")

# Preview results
head(results)


# ---------------------------------------------------------------------------- #
## A5. [Optional] Classify only specific categories or subcategories  ----
# ---------------------------------------------------------------------------- #
# By default, the classifier runs all 8 categories and all subcategories.
# If your research only requires certain categories, you can subset the
# classifier before running to improve speed and reduce output size.
#
# To see all available categories:
names(clf$categories)
#
# To see subcategories within a category (e.g., religion):
names(clf$categories$religion$subcategories)
#
# --- Option 1: Filter the classifier to specific categories only ---
# This example keeps only political and issue categories:
#
# clf_subset <- clf
# clf_subset$categories <- clf$categories[c("political", "issue")]
# results_subset <- classify_bios(my_data, clf_subset) |>
#   dplyr::rename_with(pretty_names, .cols = -id)
#
# --- Option 2: Select specific result columns after classification ---
# This example keeps only the top-level category columns (no subcategories):
#
# cat_cols <- c("id", names(clf$categories))  # top-level only
# results_cats_only <- results |> dplyr::select(dplyr::any_of(cat_cols))
#
# --- Option 3: Keep only subcategories for one category ---
# This example keeps only religion subcategory columns:
#
# results_religion <- results |>
#   dplyr::select(id, religion, dplyr::starts_with("religion_"))


# ---------------------------------------------------------------------------- #
## A6. Quick summary of classification results ----
# ---------------------------------------------------------------------------- #
# How many bios received at least one classification?

n_total     <- nrow(results)
flag_cols   <- setdiff(names(results), "id")
n_classified <- sum(rowSums(results[flag_cols]) >= 1L)
n_none       <- n_total - n_classified

message(n_classified, " of ", n_total, " bios (", 
        round(100 * n_classified / n_total, 1), "%) received at least one classification.")
message(n_none, " bios had no classifications.")

# Category-level totals
cat_cols <- names(clf$categories)
cat_totals <- results |>
  dplyr::summarise(dplyr::across(dplyr::any_of(cat_cols),
                                 ~ sum(.x == 1L, na.rm = TRUE))) |>
  tidyr::pivot_longer(everything(), names_to = "category", values_to = "count") |>
  dplyr::mutate(pct = round(100 * count / n_total, 2)) |>
  dplyr::arrange(dplyr::desc(count))

print(cat_totals)


# ---------------------------------------------------------------------------- #
## A7. Save results ----
# ---------------------------------------------------------------------------- #

saveRDS(results, file = "classified_results.rds")
write_csv(results, file = "classified_results.csv")

message("Results saved as classified_results.rds and classified_results.csv")


# ============================================================================ #
# SECTION B: Parallel Classification for Large Datasets (500k+ rows) ----
# ============================================================================ #
# This section shards your data into smaller files, distributes classification
# across multiple CPU cores, then merges the results into a single output file.
#
# Why parallel? The classifier is CPU-bound: each bio requires many regex
# evaluations. For large datasets (millions of rows), running sequentially
# can take hours. Parallel classification reduces this proportionally to the
# number of cores available.
#
# How it works:
#   1. Your full dataset is split into equal-sized shard files saved to disk.
#   2. Each worker process loads one shard, runs the classifier, and saves
#      its output — independently of other workers.
#   3. Once all shards are processed, the output files are merged into a
#      single classified_all.rds file.
#
# >>> REPLACE YOUR DATA <<<
# Search for ">>> REPLACE" below to update the data path and worker count.
# ============================================================================ #


# ---------------------------------------------------------------------------- #
## B1. Load packages for parallel processing  ----
# ---------------------------------------------------------------------------- #

library(dplyr)
library(readr)
library(purrr)
library(future)
library(future.apply)


# ---------------------------------------------------------------------------- #
## B2. Load the classifier  ----
# ---------------------------------------------------------------------------- #

clf <- readRDS("classifier.rds")
clf_path <- normalizePath("classifier.rds", mustWork = TRUE)

# As in Section A, the classification functions must be available.
# If running this script fresh, uncomment:
# source("02_build_classifier.R")


# ---------------------------------------------------------------------------- #
## B3. Load your full dataset ----
# ---------------------------------------------------------------------------- #
# >>> REPLACE YOUR DATA <<<
# Replace the path below with the path to your full dataset.
# Your data must have "id" (character) and "text" (character) columns.
# Update id_col and text_col in B5 if your columns have different names.

bios <- readRDS("your_full_bios.rds")   # >>> REPLACE with your file path

# Ensure id and text are character type
bios$id   <- as.character(bios$id)
bios$text <- as.character(bios$text)

message("Full dataset loaded: ", nrow(bios), " rows.")


# ---------------------------------------------------------------------------- #
## B4. Configure sharding  ----
# ---------------------------------------------------------------------------- #
# chunk_size controls how many rows go into each shard. Larger chunks use
# more RAM per worker; smaller chunks create more files. 500,000 rows per
# shard is a reasonable default for most systems with 16GB+ RAM.
# Reduce to 250,000 if you encounter memory errors.

chunk_size <- 5e5   # 500,000 rows per shard

shard_dir  <- "shards_rds"   # temporary folder for shard files
out_dir    <- "out_rds"      # folder for per-shard output files

dir.create(shard_dir, showWarnings = FALSE)
dir.create(out_dir,   showWarnings = FALSE)

# Write shards to disk only if they don't already exist.
# This allows you to resume a partial run without re-sharding.
if (length(list.files(shard_dir, "\\.rds$")) == 0L) {
  message("Sharding data...")
  n      <- nrow(bios)
  starts <- seq(1L, n, by = chunk_size)
  
  for (i in seq_along(starts)) {
    idx <- starts[i]:min(starts[i] + chunk_size - 1L, n)
    saveRDS(
      bios[idx, c("id", "text")],
      file.path(shard_dir, sprintf("bios_part_%05d.rds", i))
    )
  }
  rm(bios)
  gc()
  message("Sharding complete.")
} else {
  message("Existing shards found in '", shard_dir, "' — skipping re-sharding.")
  message("Delete the '", shard_dir, "' folder to re-shard from scratch.")
  rm(bios)
  gc()
}

shard_files <- list.files(shard_dir, pattern = "^bios_part_\\d+\\.rds$",
                          full.names = TRUE)
stopifnot("No shard files found." = length(shard_files) > 0L)
message(length(shard_files), " shard(s) ready for processing.")


# ---------------------------------------------------------------------------- #
## B5. Configure parallel workers ----
# ---------------------------------------------------------------------------- #
# >>> REPLACE YOUR DATA <<<
# Set workers to the number of CPU cores you want to use.
# The default uses half your available cores, leaving the rest for your system.
# On a dedicated server you can increase this; on a laptop, keep it lower.
#
# To see how many cores your machine has:
#   parallel::detectCores()

workers <- max(2L, floor(parallel::detectCores() / 2))

message("Using ", workers, " parallel workers.")
message("Total cores available: ", parallel::detectCores())


# ---------------------------------------------------------------------------- #
## B6. Define the worker function ----
# ---------------------------------------------------------------------------- #
# Each worker runs this function independently on one shard file.
# It loads the shard, loads the classifier, runs classification, and saves
# its output. Errors are caught and logged rather than stopping the whole run.

worker_fun <- function(f_in, i) {
  tryCatch({
    df <- readRDS(f_in)
    stopifnot(all(c("id", "text") %in% names(df)))
    
    # Each worker loads the classifier independently — this avoids passing
    # the large clf object across process boundaries.
    clf_local <- readRDS(clf_path)
    
    res_raw <- classify_bios(df, clf_local, id_col = "id", text_col = "text")
    
    # Ensure category column = 1 if any subcategory = 1
    for (cid in names(clf_local$categories)) {
      cat_col  <- paste0("cat__", cid)
      sub_cols <- grep(paste0("^sub__", cid, "__"), names(res_raw), value = TRUE)
      if (length(sub_cols)) {
        any_sub <- as.integer(
          rowSums(res_raw[, sub_cols, drop = FALSE] == 1L) > 0L
        )
        res_raw[[cat_col]] <- pmax(res_raw[[cat_col]], any_sub)
      }
    }
    
    res   <- dplyr::rename_with(res_raw, pretty_names, .cols = -id)
    f_out <- file.path(out_dir, sprintf("classified_part_%05d.rds", i))
    saveRDS(res, f_out)
    
    tibble::tibble(
      i        = i,
      shard_in = basename(f_in),
      file_out = basename(f_out),
      n        = nrow(res),
      ok       = TRUE,
      err      = NA_character_
    )
  }, error = function(e) {
    tibble::tibble(
      i        = i,
      shard_in = basename(f_in),
      file_out = NA_character_,
      n        = NA_integer_,
      ok       = FALSE,
      err      = conditionMessage(e)
    )
  })
}


# ---------------------------------------------------------------------------- #
## B7. [Optional] Time a small test run before the full run ----
# ---------------------------------------------------------------------------- #
# Uncomment to estimate how long the full run will take before committing.
# This runs the classifier on 20,000 rows from the first shard.
#
# first_shard <- readRDS(shard_files[1])
# system.time({
#   probe <- classify_bios(first_shard[1:20000, ], clf)
# })
# # Multiply elapsed time by (nrow(full_data) / 20000) / workers
# # for a rough total time estimate.


# ---------------------------------------------------------------------------- #
## B8. Run the parallel classifier ----
# ---------------------------------------------------------------------------- #

options(future.wait.timeout = 1e8)  # allow long-running jobs to complete
future::plan(future::multisession, workers = workers)

message("Starting parallel classification across ", length(shard_files), " shards...")

run_log <- future.apply::future_lapply(
  seq_along(shard_files),
  function(i) worker_fun(shard_files[i], i),
  future.globals  = list(
    worker_fun    = worker_fun,
    classify_bios = classify_bios,
    pretty_names  = pretty_names,
    .detect       = .detect,
    shard_files   = shard_files,
    clf_path      = clf_path,
    out_dir       = out_dir
  ),
  future.packages = "dplyr",
  future.seed     = TRUE
)

# Reset to sequential processing when done
future::plan(future::sequential)

# Save and review the run log
run_log_df <- dplyr::bind_rows(run_log)
readr::write_csv(run_log_df, file.path(out_dir, "run_log.csv"))

message("Parallel run complete.")
print(dplyr::count(run_log_df, ok))

# Check for any failed shards
failed_shards <- dplyr::filter(run_log_df, !ok)
if (nrow(failed_shards) > 0) {
  warning(nrow(failed_shards), " shard(s) failed. See run_log.csv for details.")
  print(failed_shards)
}

# To monitor progress during a long run, open a separate R session and run:
# length(list.files("out_rds", "^classified_part_\\d+\\.rds$"))


# ---------------------------------------------------------------------------- #
## B9. Post-run checks ----
# ---------------------------------------------------------------------------- #

done_files <- list.files(out_dir, "^classified_part_\\d+\\.rds$")
done_idx   <- as.integer(sub("^classified_part_(\\d+)\\.rds$", "\\1", done_files))

message(length(done_idx), " of ", length(shard_files), " shards completed.")

if (length(done_idx) < length(shard_files)) {
  missing_idx <- setdiff(seq_along(shard_files), done_idx)
  warning("Missing output for shard(s): ", paste(missing_idx, collapse = ", "))
}

# Spot-check: output row count should match input shard row count
i_check <- done_idx[1]
n_in  <- nrow(readRDS(shard_files[i_check]))
n_out <- nrow(readRDS(file.path(out_dir, sprintf("classified_part_%05d.rds", i_check))))
message("Spot-check shard ", i_check, ": input rows = ", n_in,
        ", output rows = ", n_out,
        if (n_in == n_out) " [OK]" else " [MISMATCH — investigate]")


# ---------------------------------------------------------------------------- #
## B10. Merge all shards into a single output file ----
# ---------------------------------------------------------------------------- #

message("Merging classified shards...")

res_parts <- list.files(out_dir, "^classified_part_\\d+\\.rds$", full.names = TRUE)
ord       <- order(as.integer(sub("^.*classified_part_(\\d+)\\.rds$", "\\1",
                                  basename(res_parts))))
res_parts <- res_parts[ord]

classified_all <- purrr::map(res_parts, readRDS) |>
  dplyr::bind_rows()

message("Merge complete: ", nrow(classified_all), " total rows.")

# Confirm no duplicate IDs in the merged output
n_dupes <- sum(duplicated(classified_all$id))
if (n_dupes > 0) {
  warning(n_dupes, " duplicate IDs found in merged output. ",
          "Check your source data for duplicate records.")
} else {
  message("No duplicate IDs detected.")
}

# Clean up
rm(res_parts)
gc()


# ---------------------------------------------------------------------------- #
## B11. Save the merged output ----
# ---------------------------------------------------------------------------- #

saveRDS(classified_all, file = "classified_all.rds")
message("classified_all.rds saved.")

# Optional: also save as CSV (note: large files may take time to write)
# write_csv(classified_all, "classified_all.csv")
