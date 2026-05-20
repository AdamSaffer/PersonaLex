# ============================================================================ #
# PersonaLex: Step 1 — Load the Classifier Lexicon ----
# ============================================================================ #
#
## PURPOSE ----
# 
# This script loads the PersonaLex classifier lexicon (CSV file) into R and
# saves it as an .rds file for use in the next step (02_build_classifier.R).
#
## BEFORE YOU RUN THIS SCRIPT ----
#
# 1. Download the PersonaLex classifier lexicon CSV from the UMN Technology
#    Commercialization landing page:
#    https://license.umn.edu/product/personalex-validated-short-text-classifier-for-identities-interests-and-issues
#
# 2. Save the downloaded file as:
#      personalex_classifier_v1.csv
#    in the same folder as this script.
#
# 3. Install required packages (first time only). If you are using renv,
#    run renv::restore() instead of install.packages().
#
#    install.packages(c("dplyr", "readr"))
#
# OUTPUT ----
#
# lexicon_df.rds — the lexicon saved as an R data file, ready for
#                     02_build_classifier.R
#
# NOTE ON NAMING ----
# This object is called lexicon_df to distinguish the raw lexicon database
# (the CSV of terms) from the compiled classifier object (clf) that is built
# from it in 02_build_classifier.R.
# ============================================================================ #

# ---------------------------------------------------------------------------- #
# 1. Load packages ----
# ---------------------------------------------------------------------------- #

library(dplyr)
library(readr)

# ---------------------------------------------------------------------------- #
# 2. Load the classifier lexicon CSV ----
# ---------------------------------------------------------------------------- #
# This reads the PersonaLex lexicon into a data frame called lexicon_df.
# Each row represents a group of terms associated with a specific category,
# subcategory, and term type.
#
# If your CSV file is saved in a different location, update the path below.
# Example: lexicon_df <- read_csv("path/to/personalex_classifier_v1.csv")

lexicon_df <- read_csv(
  "personalex_classifier_v1.csv",
  col_types = cols(.default = col_character())  # read all columns as text
)

# Quick check: confirm the file loaded correctly
message("Lexicon loaded: ", nrow(lexicon_df), " rows and ",
        ncol(lexicon_df), " columns.")

# Preview the first few rows
head(lexicon_df)

# Check the structure of the data
glimpse(lexicon_df)


# ---------------------------------------------------------------------------- #
# 3. Validate expected columns are present ----
# ---------------------------------------------------------------------------- #
# The lexicon should contain these seven columns. If any are missing, check
# that you downloaded the correct file from the landing page.

expected_cols <- c("category", "subcategory", "term_type",
                   "terms", "include", "description", "references")

missing_cols <- setdiff(expected_cols, names(lexicon_df))

if (length(missing_cols) > 0) {
  stop("The following expected columns are missing from the CSV: ",
       paste(missing_cols, collapse = ", "),
       "\nPlease confirm you are using personalex_classifier_v1.csv.")
} else {
  message("All expected columns found. Lexicon looks correct.")
}


# ---------------------------------------------------------------------------- #
# 4. Save for use in the next step ----
# ---------------------------------------------------------------------------- #
# Saving as .rds preserves column types and is faster to reload than CSV.
# 02_build_classifier.R will read this file.

saveRDS(lexicon_df, file = "lexicon_df.rds")

message("lexicon_df.rds saved. You are ready to run 02_build_classifier.R.")