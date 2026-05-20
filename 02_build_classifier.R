# ============================================================================ #
# PersonaLex: Step 2 — Build the Classifier Object ----
# ============================================================================ #
#
## PURPOSE ----
#
# This script takes the classifier lexicon loaded in Step 1 (01_load_lexicon) 
# and compiles it into a structured classifier object (clf) that R can use 
# to classify text.
#
# The classifier handles:
#   - Parsing JSON-style term arrays from the lexicon
#   - Compiling regex patterns with proper word boundaries
#   - Organizing terms into a hierarchical category/subcategory structure
#   - Separating include terms (positive matches) from exclude terms
#     (negative lookarounds to prevent false positives)
#   - Chunking large pattern sets to avoid PCRE engine size limits
#
## BEFORE YOU RUN THIS SCRIPT  ----
#
# 1. You must have already run 01_load_lexicon.R, which produces
#    lexicon_df.rds in your working directory.
#
# 2. Required packages (first time only). If you are using renv,
#    run renv::restore() instead.
#
#    install.packages(c("dplyr", "tidyr", "stringr", "purrr",
#                       "tibble", "jsonlite"))
#
## OUTPUT ----
# 
# classifier.rds — the compiled classifier object (clf), ready for
#                  03_run_classifier.R
#
# NOTE ON NAMING ----
# 
# lexicon_df  = the raw CSV database of terms (loaded in Step 1)
# clf         = the compiled classifier object built from lexicon_df here
#
# ============================================================================ #


# ---------------------------------------------------------------------------- #
# 1. Load packages  ----
# ---------------------------------------------------------------------------- #

library(dplyr)
library(tidyr)
library(stringr)
library(purrr)
library(tibble)
library(jsonlite)


# ---------------------------------------------------------------------------- #
# 2. Load the lexicon data frame from 01_load_lexicon.R  ----
# ---------------------------------------------------------------------------- #

lexicon_df <- readRDS("lexicon_df.rds")
stopifnot("lexicon_df not found — please run 01_load_lexicon.R first." =
            exists("lexicon_df"))

message("lexicon_df loaded: ", nrow(lexicon_df), " rows.")


# ---------------------------------------------------------------------------- #
# 3. Helper functions ----
# ---------------------------------------------------------------------------- #
# These utilities handle the low-level work of parsing, compiling, and
# validating regex patterns. You do not need to modify these.

# --- Null-coalesce operator ---
# Returns y if x is NULL, empty, or all NA. Used throughout the builder
# to provide safe fallback values.
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0 || all(is.na(x))) y else x

# --- slug() ---
# Converts a string to a safe identifier: lowercase, spaces replaced with
# underscores, and non-alphanumeric characters removed.
# Example: "Issue Advocacy" -> "issue_advocacy"
slug <- function(x) {
  x |>
    tolower() |>
    str_replace_all("[^a-z0-9]+", "_") |>
    str_replace_all("(^_+|_+$)", "")
}

# --- strip_wrapping_quotes() ---
# Removes leading and trailing quote characters (straight or curly) that may
# appear around terms when exported from Google Sheets or Excel.
strip_wrapping_quotes <- function(v) {
  v <- as.character(v)
  v <- stringr::str_trim(v)
  v <- stringr::str_replace(v, '^[\\"""\'\']+', "")
  v <- stringr::str_replace(v, '[\\"""\'\']+$', "")
  v
}

# --- escape_literal() ---
# Escapes regex metacharacters in a string so it is treated as plain text.
# Used for terms that are not intended as regex patterns.
escape_literal <- function(x) {
  stringr::str_replace_all(x, "([\\^$.|?*+()\\[\\]{}])", "\\\\$1")
}

# --- has_explicit_bounds() / wrap_word_bounds() ---
# Checks whether a pattern already includes word boundaries (\b) or
# lookarounds. If not, wrap_word_bounds() adds non-word-character assertions
# on each side to prevent partial matches (e.g., "race" matching "embrace").
has_explicit_bounds <- function(p) {
  str_detect(p, "\\\\b|\\(\\?<=|\\(\\?<!|\\(\\?=|\\(\\?!")
}

wrap_word_bounds <- function(p) {
  ifelse(has_explicit_bounds(p), p, paste0("(?<!\\w)", p, "(?!\\w)"))
}

# --- term_has_regex_meta() ---
# Returns TRUE if a term appears to contain regex syntax (metacharacters,
# escape sequences, lookarounds). This guides whether a term is compiled as
# a regex pattern or escaped as a literal string.
term_has_regex_meta <- function(x) {
  if (is.null(x)) return(FALSE)
  xs <- as.character(x)
  nz <- !is.na(xs) & nzchar(xs)
  out <- rep(FALSE, length(xs))
  if (any(nz)) {
    pat <- "(\\\\b|\\\\B|\\\\d|\\\\w|\\\\s|\\(\\?[:=!<])|[\\^$.|?*+()\\[\\]{}]"
    out[nz] <- grepl(pat, xs[nz], perl = TRUE)
  }
  out
}

# --- coerce_logical() / normalize_include() ---
# Robustly converts various representations of TRUE/FALSE (e.g., "yes", "1",
# "checked", "TRUE") into R logical values. normalize_include() defaults to
# TRUE for unrecognized values (include by default).
coerce_logical <- function(x, default = FALSE) {
  s <- tolower(trimws(as.character(x)))
  out <- ifelse(s %in% c("true", "t", "1", 
                         "yes", "y", "checked", 
                         "include", "pos"), TRUE,
         ifelse(s %in% c("false", "f", "0", 
                         "no", "n", "unchecked", 
                         "exclude", "neg"), FALSE,
                default))
  as.logical(out)
}

normalize_include <- function(x) {
  s <- tolower(trimws(as.character(x)))
  out <- ifelse(s %in% c("false", "f", "0", 
                         "no", "n", "unchecked", 
                         "exclude", "neg"), FALSE,
         ifelse(s %in% c("true", "t", "1", 
                         "yes", "y", "checked", 
                         "include", "pos"), TRUE,
                TRUE))
  as.logical(out)
}

# --- compile_term() ---
# Builds the final regex pattern for a single term by:
#   1. Escaping it if it is a literal string (not regex)
#   2. Adding word boundary assertions if not already present
#   3. Wrapping in a case-insensitive modifier unless case_sensitive = TRUE
compile_term <- function(term, 
                         is_regex = TRUE, 
                         case_sensitive = FALSE, 
                         whole_word = TRUE) {
  if (is.null(term) || is.na(term) || !nzchar(term)) return(NA_character_)
  pat <- if (isTRUE(is_regex)) term else escape_literal(term)
  if (isTRUE(whole_word)) pat <- wrap_word_bounds(pat)
  if (!isTRUE(case_sensitive)) pat <- paste0("(?i:", pat, ")")
  pat
}

# --- combine_alt() / combine_alt_chunked() ---
# Joins multiple regex patterns into a single alternation: (?:pat1|pat2|...).
# combine_alt_chunked() splits very large term lists into smaller chunks to
# avoid exceeding PCRE's internal size limit (~64KB per pattern). This is
# important for categories with many hundreds of terms.
combine_alt <- function(pats) {
  pats <- unique(pats[nzchar(pats)])
  if (!length(pats)) return(NA_character_)
  paste0("(?:", paste(pats, collapse = "|"), ")")
}

combine_alt_chunked <- function(pats, max_chars = 20000L, max_items = 400L) {
  pats <- unique(pats[nzchar(pats)])
  if (!length(pats)) return(character())
  chunks <- list()
  cur <- character()
  cur_len <- 0L
  push <- function() {
    if (length(cur)) {
      chunks[[length(chunks) + 1]] <<- paste0("(?:", 
                                              paste(cur, collapse = "|"), ")")
    }
    cur <<- character()
    cur_len <<- 0L
  }
  for (p in pats) {
    add_len <- nchar(p) + ifelse(length(cur) == 0, 3L, 1L)
    if (length(cur) >= max_items || (cur_len + add_len) > max_chars) push()
    cur <- c(cur, p)
    cur_len <- cur_len + add_len
  }
  push()
  unlist(chunks, use.names = FALSE)
}

# --- safe_regex_ok() / safe_regex_all() ---
# Test-compile a regex pattern against an empty string to detect hard errors.
# Warnings (e.g., for unusual but valid patterns) are suppressed; only errors
# that would cause grepl() to fail are flagged.
safe_regex_ok <- function(pat) {
  if (is.na(pat) || !nzchar(pat)) return(TRUE)
  tryCatch({
    withCallingHandlers({
      grepl(pat, "", perl = TRUE)
    }, warning = function(w) invokeRestart("muffleWarning"))
    TRUE
  }, error = function(e) FALSE)
}

safe_regex_all <- function(pats) {
  if (is.null(pats) || length(pats) == 0) return(TRUE)
  pats <- pats[!is.na(pats) & nzchar(pats)]
  if (!length(pats)) return(TRUE)
  all(vapply(pats, safe_regex_ok, logical(1)))
}

# --- parse_terms_cell() ---
# Parses the contents of a single cell in the `terms` column of the lexicon.
# Terms are stored as JSON arrays (e.g., ["word1", "word2"]).
# If the cell is not valid JSON, falls back to comma-separated parsing.
parse_terms_cell <- function(x) {
  if (is.null(x) || is.na(x)) return(character())
  s <- trimws(as.character(x))
  if (!nzchar(s)) return(character())

  # Normalize curly quotes to straight quotes for JSON validation
  s_norm <- stringr::str_replace_all(s, "[\u201c\u201d]", '"')
  s_norm <- stringr::str_replace_all(s_norm, "[\u2018\u2019]", "'")

  # Try JSON parsing first
  looks_bracketed <- stringr::str_detect(s_norm, "^\\s*\\[") &&
                     stringr::str_detect(s_norm, "\\]$")
  if (looks_bracketed && jsonlite::validate(s_norm)) {
    out <- jsonlite::fromJSON(s_norm)
    return(strip_wrapping_quotes(trimws(as.character(out))))
  }

  # Fallback: strip brackets and split by commas
  s2 <- s_norm
  if (looks_bracketed) {
    s2 <- sub("^\\s*\\[", "", s2)
    s2 <- sub("\\]\\s*$", "", s2)
  }
  parts <- strsplit(s2, ",", fixed = TRUE)[[1]]
  parts <- strip_wrapping_quotes(trimws(parts))
  parts[nzchar(parts)]
}


# ---------------------------------------------------------------------------- #
# 4. Classifier-building functions ---- 
# ---------------------------------------------------------------------------- #

# --- normalize_lexicon_df() ---
# Converts the raw lexicon data frame into a tidy, one-row-per-term table.
# Handles flexible column naming, expands multi-term cells, infers whether
# each term is a regex pattern or literal string, and applies logical coercions.
normalize_lexicon_df <- function(df) {
  # Find columns by name, accepting common variations
  pick <- function(keys) {
    idx <- which(tolower(names(df)) %in% tolower(keys))
    if (length(idx)) names(df)[idx[1]] else NA
  }
  c_category    <- pick(c("category", "cat", "group"))
  c_subcategory <- pick(c("subcategory", "subcat", "sub"))
  c_terms       <- pick(c("terms", "term", "patterns", 
                          "pattern", "regex", "strings", "phrases"))
  c_term_type   <- pick(c("term_type", "type", "tag"))
  c_include     <- pick(c("include", "is_include", "positive"))
  c_case        <- pick(c("case_sensitive"))
  c_whole       <- pick(c("whole_word"))

  stopifnot(!is.na(c_category), !is.na(c_terms))

  core <- tibble::tibble(
    "category"       = df[[c_category]] %||% "",
    "subcategory"    = if (!is.na(c_subcategory)) df[[c_subcategory]] else "",
    "terms_cell"     = if (!is.na(c_terms))       df[[c_terms]]       else "",
    "term_type"      = if (!is.na(c_term_type))   df[[c_term_type]]   else NA,
    "include"        = if (!is.na(c_include))      df[[c_include]]     else NA,
    "case_sensitive" = if (!is.na(c_case))         df[[c_case]]        else NA,
    "whole_word"     = if (!is.na(c_whole))        df[[c_whole]]       else NA
  )

  core |>
    mutate(parsed = purrr::map(terms_cell, parse_terms_cell)) |>
    tidyr::unnest_longer(parsed, values_to = "term", keep_empty = TRUE) |>
    dplyr::select(-dplyr::any_of(c("parsed", "terms_cell"))) |>
    mutate(
      across(c(category, subcategory, term), ~ as.character(.) %||% ""),
      term           = trimws(term),
      is_regex       = term_has_regex_meta(term),
      case_sensitive = coerce_logical(case_sensitive, default = FALSE),
      whole_word     = coerce_logical(whole_word, default = TRUE),
      include        = normalize_include(include)
    ) |>
    filter(nzchar(category), nzchar(term))
}

# --- regex_check() / diagnose_terms() ---
# Per-term diagnostics: test-compiles each pattern and records any failures.
# Results are stored in clf$bad_patterns so you can inspect and fix problem
# terms in the lexicon if needed.
regex_check <- function(pat) {
  if (is.null(pat) || is.na(pat) || !nzchar(pat)) {
    return(list(ok = TRUE, msg = NA_character_))
  }
  msg <- NULL
  ok <- tryCatch({
    withCallingHandlers({
      grepl(pat, "", perl = TRUE)
      TRUE
    }, warning = function(w) {
      if (is.null(msg)) msg <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    })
  }, error = function(e) {
    msg <<- conditionMessage(e)
    FALSE
  })
  list(ok = ok, msg = msg)
}

diagnose_terms <- function(nd) {
  chk <- nd |>
    mutate(.diag = purrr::map(compiled, regex_check)) |>
    tidyr::unnest_wider(.diag) |>
    mutate(ok = coerce_logical(ok, default = FALSE))
  list(
    bad_terms = chk |>
      dplyr::filter(!ok) |>
      dplyr::select(category, subcategory, term, compiled, msg),
    all = chk
  )
}

# --- build_classifier() ---
# The main builder function. Takes the raw lexicon data frame and returns a
# structured classifier object (clf) containing compiled regex patterns
# organized by category and subcategory.
#
# The returned object has this structure:
#   clf$meta                  — version, build time, source
#   clf$categories$<cat_id>   — one entry per category
#     $pattern_include        — vector of compiled regex chunks (include)
#     $pattern_exclude        — vector of compiled regex chunks (exclude)
#     $subcategories$<sub_id> — one entry per subcategory
#       $pattern_include / $pattern_exclude
#   clf$bad_patterns          — terms that failed to compile (inspect these)
build_classifier <- function(df, version = "v1", source = "csv") {
  nd <- normalize_lexicon_df(df) |>
    mutate(
      compiled = pmap_chr(
        list(term, is_regex, case_sensitive, whole_word),
        ~ compile_term(..1, ..2, ..3, ..4)
      ),
      cat_id = slug(category),
      sub_id = if_else(
        is.na(subcategory) | !nzchar(subcategory),
        "_root",
        slug(subcategory)
      )
    )

  # Diagnose and drop only hard-failing patterns
  .diag <- diagnose_terms(nd)

  diag_status <- .diag$all |>
    dplyr::transmute(compiled, ok = coerce_logical(ok, default = FALSE)) |>
    dplyr::group_by(compiled) |>
    dplyr::summarise(ok = all(ok), .groups = "drop")

  nd_ok <- nd |>
    dplyr::left_join(diag_status, by = "compiled") |>
    dplyr::mutate(ok = dplyr::coalesce(ok, TRUE)) |>
    dplyr::filter(ok) |>
    dplyr::select(-ok)

  collapsed <- nd_ok |>
    group_by(cat_id, category, sub_id, subcategory, include) |>
    summarise(
      patterns = list(combine_alt_chunked(compiled)),
      n_terms  = dplyr::n(),
      .groups  = "drop"
    ) |>
    tidyr::pivot_wider(
      id_cols     = c(cat_id, category, sub_id, subcategory),
      names_from  = include,
      values_from = c(patterns, n_terms),
      names_glue  = "{ifelse(.value == 'patterns', 'p', 'n')}_{ifelse(include, 'inc', 'exc')}"
    )

  cats <- collapsed |>
    group_split(cat_id, .keep = TRUE) |>
    set_names(unique(collapsed$cat_id)) |>
    purrr::imap(function(cat_df, cid) {
      label    <- dplyr::first(cat_df$category)
      cat_row  <- cat_df |> dplyr::filter(sub_id == "_root") |> 
        dplyr::slice_head(n = 1)
      sub_rows <- cat_df |> dplyr::filter(sub_id != "_root")

      sub_list <- purrr::pmap(
        sub_rows,
        function(cat_id, category, sub_id, 
                 subcategory, p_inc, p_exc, 
                 n_inc, n_exc) {
          list(
            id              = sub_id,
            label           = subcategory,
            pattern_include = (p_inc %||% list(character()))[[1]],
            pattern_exclude = (p_exc %||% list(character()))[[1]],
            n_terms_include = n_inc %||% 0L,
            n_terms_exclude = n_exc %||% 0L
          )
        }
      )
      names(sub_list) <- sub_rows$sub_id

      cat_inc <- if (nrow(cat_row)) (cat_row$p_inc %||% 
                                       list(character()))[[1]] else character()
      cat_exc <- if (nrow(cat_row)) (cat_row$p_exc %||% 
                                       list(character()))[[1]] else character()

      list(
        id              = cid,
        label           = label,
        pattern_include = cat_inc,
        pattern_exclude = cat_exc,
        subcategories   = sub_list
      )
    })

  structure(
    list(
      meta        = list(
        version  = version,
        built_at = format(Sys.time(), tz = "UTC", usetz = TRUE),
        source   = source
      ),
      categories  = cats,
      bad_patterns = .diag$bad_terms
    ),
    class = c("personalex_classifier", "list")
  )
}

# --- validate_classifier() ---
# Checks that every compiled pattern block in the classifier is valid.
# Returns a table flagging any category or subcategory where patterns
# failed to compile. An empty result means everything is clean.
validate_classifier <- function(clf) {
  purrr::imap_dfr(clf$categories, function(cat_obj, cid) {
    tibble(
      level      = "category",
      id         = cid,
      label      = cat_obj$label,
      include_ok = safe_regex_all(cat_obj$pattern_include),
      exclude_ok = safe_regex_all(cat_obj$pattern_exclude)
    ) |>
      dplyr::bind_rows({
        if (!length(cat_obj$subcategories)) {
          tibble()
        } else {
          purrr::imap_dfr(cat_obj$subcategories, function(sub_obj, sid) {
            tibble(
              level      = "subcategory",
              id         = paste(cid, sid, sep = "/"),
              label      = sub_obj$label,
              include_ok = safe_regex_all(sub_obj$pattern_include),
              exclude_ok = safe_regex_all(sub_obj$pattern_exclude)
            )
          })
        }
      })
  })
}


# ---------------------------------------------------------------------------- #
# 5. Classification functions ----
# ---------------------------------------------------------------------------- #
# These are the functions used by 03_run_classifier.R to apply the classifier
# to a data frame of bios.

# --- .detect() ---
# Tests a vector of text strings against a vector of compiled regex patterns.
# Returns TRUE for any string that matches at least one pattern. Supports
# multiple pattern chunks (produced by combine_alt_chunked).
.detect <- function(txt, pat_vec) {
  if (is.null(pat_vec) || length(pat_vec) == 0) return(rep(FALSE, length(txt)))
  pats <- pat_vec[!is.na(pat_vec) & nzchar(pat_vec)]
  if (!length(pats)) return(rep(FALSE, length(txt)))
  res <- rep(FALSE, length(txt))
  for (p in pats) res <- res | grepl(p, txt, perl = TRUE)
  res
}

# --- classify_bios() ---
# The main classification function. Takes a data frame of bios and the
# compiled classifier object, and returns a data frame with one column
# per category and subcategory (0/1 binary flags).
#
# Arguments:
#   bios     — a data frame with at least two columns: an ID column and a
#              text column containing the bio text to classify
#   clf      — the compiled classifier object from build_classifier()
#   id_col   — name of the ID column (default: "id")
#   text_col — name of the text column (default: "text")
#
# Returns a tibble with columns: id, cat__<category>, sub__<cat>__<subcat>
# Use pretty_names() to rename columns to a cleaner format.
classify_bios <- function(bios, clf, id_col = "id", text_col = "text") {
  stopifnot(
    "id column not found in bios"   = id_col   %in% names(bios),
    "text column not found in bios" = text_col %in% names(bios)
  )

  ids   <- bios[[id_col]]
  texts <- as.character(bios[[text_col]])
  out   <- list(id = ids)

  for (cid in names(clf$categories)) {
    cat_obj <- clf$categories[[cid]]

    # Subcategory hits
    any_sub <- rep(FALSE, length(texts))
    if (length(cat_obj$subcategories)) {
      sub_names <- names(cat_obj$subcategories)
      sub_mat <- sapply(sub_names, function(sid) {
        sub_obj <- cat_obj$subcategories[[sid]]
        as.integer(
          .detect(texts, sub_obj$pattern_include) &
          !.detect(texts, sub_obj$pattern_exclude)
        )
      }, simplify = TRUE)

      # Ensure matrix shape when there is only one subcategory
      if (is.null(dim(sub_mat))) {
        sub_mat <- matrix(sub_mat, ncol = 1, dimnames = list(NULL, sub_names))
      }

      for (j in seq_along(sub_names)) {
        out[[paste0("sub__", cid, "__", sub_names[j])]] <- sub_mat[, j]
      }

      any_sub <- apply(sub_mat, 1L, function(row) any(row == 1L))
    }

    # Category-level hit: root terms OR any subcategory match
    root_hit <- .detect(texts, cat_obj$pattern_include) &
                !.detect(texts, cat_obj$pattern_exclude)
    out[[paste0("cat__", cid)]] <- as.integer(root_hit | any_sub)
  }

  tibble::as_tibble(out)
}

# --- pretty_names() ---
# Renames classifier output columns from internal format to readable format.
# Examples:
#   cat__religion          -> religion
#   sub__religion__christian -> religion_christian
pretty_names <- function(nm) {
  nm <- sub("^cat__", "", nm)
  nm <- sub("^sub__", "", nm)
  gsub("__", "_", nm, fixed = TRUE)
}


# ---------------------------------------------------------------------------- #
# 6. Build the classifier ----
# ---------------------------------------------------------------------------- #

message("Building classifier from lexicon...")

clf <- build_classifier(
  lexicon_df,
  version = "v1.0",
  source  = "personalex_classifier_v1.csv"
)

message("Classifier built successfully.")
message("Categories: ", paste(names(clf$categories), collapse = ", "))


# ---------------------------------------------------------------------------- #
# 7. Inspect and validate the classifier ----
# ---------------------------------------------------------------------------- #
# Review clf$meta to confirm the version and build time.
clf$meta

# validate_classifier() checks that all compiled pattern blocks are valid.
validation_results <- validate_classifier(clf)

# This checks that all compiled patterns are valid.
# An empty result (0 rows) means everything compiled cleanly.
failed <- dplyr::filter(validation_results, !include_ok | !exclude_ok)

if (nrow(failed) == 0) {
  message("Validation passed: all patterns compiled successfully.")
} else {
  warning("Some patterns failed validation. See output below.")
  print(failed)
}

# clf$bad_patterns lists any individual terms that failed to compile.
clf$bad_patterns

# An empty tibble here is the expected result for a clean lexicon.
if (nrow(clf$bad_patterns) > 0) {
  message("Terms that failed to compile (inspect these):")
  print(clf$bad_patterns)
} else {
  message("No bad patterns detected.")
}

# ---------------------------------------------------------------------------- #
# 8. Save the classifier ----
# ---------------------------------------------------------------------------- #
# Saving 'clf' as .rds for loading without rebuilding in future sessions. 

saveRDS(clf, file = "classifier.rds")

message("classifier.rds saved. You are ready to run 03_run_classifier.R.")

# To reload the classifier in a future session without rebuilding:
# clf <- readRDS("classifier.rds")
