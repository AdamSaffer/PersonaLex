# PersonaLex

**A validated computational lexicon classifier for detecting self-expressed social identity, interests, and issue concerns in short-form text.**

PersonaLex is an open-source tool designed for social science researchers who need a transparent, scalable, and empirically validated method for classifying short-form text data like social media bios into categories of self-expressed identity, interest areas, and issue concerns.

> **To access the lexicon database (CSV), visit the UMN Technology Commercialization landing page:** <https://license.umn.edu/product/personalex-validated-short-text-classifier-for-identities-interests-and-issues>

------------------------------------------------------------------------

## Overview

Studying self-expressed identity in digital media presents real methodological challenges. Manual coding is difficult to scale and prone to inconsistency. Machine learning and large language models are often proprietary "black boxes" that are difficult to interpret, replicate, or justify in academic research. Existing text analysis tools are typically built for general purposes like sentiment analysis and lack the specificity needed for identity-focused research.

PersonaLex addresses these challenges with a structured, validated lexicon of terms, phrases, and context-sensitive regular expression (regex) patterns organized by social identity category, interest area, and issue concern. The classifier is purpose-built for short-form text, theoretically informed, empirically validated, transparent, and fully documented — making it a robust alternative or complement to opaque models for researchers studying identity expression in digital spaces.

------------------------------------------------------------------------

## Classifier Categories

PersonaLex v1.0 classifies text across 8 top-level categories, each with subcategories:

| Category | Subcategories |
|------------------|------------------------------------------------------|
| **Religion** | Christian, Jewish, Muslim, Nonaligned, Other |
| **Race** | Multiracial, White, Black, Asian, Hispanic, Native/NA |
| **Skin Tone** | Dark, Light, Medium, Medium-Dark, Medium-Light |
| **Ethnicity** | Africa, Asia, Europe, North America, Oceania, South America |
| **Military** | Army, National Guard, Navy, Marine Corps, Air Force, Coast Guard, Space Force, Judge Advocate General |
| **Issue** | General, Guns & Crime, Racial Justice, Immigration, Disability, LGBTQ+, Economic, Union & Labor, Healthcare, Gender |
| **Political** | General, Left, Right |
| **Sport** | General, D1, WNBA, NWSL, MLS, NBA, NFL, MLB, NHL |

Classification is binary (1 = detected, 0 = not detected) and multi-label — a single bio can be tagged for multiple categories simultaneously.

------------------------------------------------------------------------

## Validation

PersonaLex was developed through a rigorous multi-phase validation process:

-   Thematic review and term development by the research team
-   Independent coding by trained human coders with no involvement in term development
-   Multiple rounds of coder training by category and subcategory
-   Inter-coder reliability reaching acceptable levels across all categories (Krippendorff's α ranging from 0.760 to 0.962)
-   Classifier performance validated against human codes meeting acceptable standards for precision, recall, F1 score, and accuracy across all categories

<!--

| Category  | Precision | Recall |  F1   | Accuracy |
|-----------|:---------:|:------:|:-----:|:--------:|
| Religion  |   0.903   | 0.746  | 0.817 |  0.980   |
| Race      |   0.966   | 0.852  | 0.906 |  0.995   |
| Ethnicity |   0.956   | 0.733  | 0.830 |  0.986   |
| Military  |   0.933   | 0.875  | 0.903 |  0.997   |
| Issues    |   0.950   | 0.873  | 0.910 |  0.988   |
| Political |   0.723   | 0.846  | 0.780 |  0.976   |
| Sports    |   0.985   | 0.795  | 0.880 |  0.985   |
-->

------------------------------------------------------------------------

## Repository Contents

| File | Description |
|-------------------|----------------------------------------------------|
| `01_load_lexicon.R` | Loads the lexicon CSV into R and saves it as `lexicon_df.rds` |
| `02_build_classifier.R` | Compiles the lexicon into a structured classifier object (`clf`) |
| `03_run_classifier.R` | Applies the classifier to text data; includes both simple and parallel approaches |
| `sample_bios.csv` | 10,000 anonymized sample bios for testing and demonstration |
| `renv.lock` | Reproducible R environment file (use `renv::restore()` to replicate) |

> **The lexicon CSV (`personalex_classifier_v1.csv`) is not included in this repository.** It is available for download at the UMN Technology Commercialization landing page linked above.

------------------------------------------------------------------------

## Quick Start

### Requirements

-   R (≥ 4.1.0)
-   Required packages: `dplyr`, `tidyr`, `stringr`, `purrr`, `tibble`, `jsonlite`, `readr`
-   For parallel classification (large datasets): `future`, `future.apply`

Install all packages at once:

``` r
install.packages(c("dplyr", "tidyr", "stringr", "purrr",
                   "tibble", "jsonlite", "readr",
                   "future", "future.apply"))
```

Or, if using `renv` for reproducibility:

``` r
renv::restore()
```

### Step 1 — Download the lexicon

Download `personalex_classifier_v1.csv` from the [UMN landing page](https://license.umn.edu/product/personalex-validated-short-text-classifier-for-identities-interests-and-issues) and place it in the same folder as the scripts.

### Step 2 — Load the lexicon

``` r
source("01_load_lexicon.R")
```

This reads the CSV and saves `lexicon_df.rds`.

### Step 3 — Build the classifier

``` r
source("02_build_classifier.R")
```

This compiles the lexicon into a structured classifier object and saves `classifier.rds`.

### Step 4 — Run the classifier

``` r
source("03_run_classifier.R")
```

By default, this runs on `sample_bios.csv`. Replace the data path in Section A3 with your own file. For datasets of 500,000+ rows, use Section B (parallel classification).

### Example output

The classifier returns a data frame with one binary column per category and subcategory:

```         
# A tibble: 5 × 12
  id        religion  religion_christian  race  race_black  political  political_left  ...
  <chr>        <int>               <int> <int>       <int>      <int>           <int>
1 user_0001        1                   1     0           0          0               0
2 user_0002        0                   0     1           1          1               1
3 user_0003        0                   0     0           0          0               0
```

------------------------------------------------------------------------

## Applying PersonaLex to Your Own Data

Your input data needs two columns:

| Column | Description                                                |
|--------|------------------------------------------------------------|
| `id`   | A unique identifier for each record (character or numeric) |
| `text` | The short-form text to classify (e.g., a social media bio) |

In `03_run_classifier.R`, search for `>>> REPLACE` to find every line you need to update with your own file path or column names.

### Classifying only specific categories

If your research requires only a subset of categories, you can filter the classifier before running:

``` r
# Keep only political and issue categories
clf_subset <- clf
clf_subset$categories <- clf$categories[c("political", "issue")]

results <- classify_bios(my_data, clf_subset) |>
  dplyr::rename_with(pretty_names, .cols = -id)
```

------------------------------------------------------------------------

## Notes on Usage

-   The lexicon is not exhaustive and will evolve. Future versions will reflect updates to the term lists.
-   Term overlap across categories is possible and should be interpreted in the context of your research design.
-   The `terms` column in the lexicon includes both exact match strings and regular expressions. The implementation scripts handle both automatically.
-   Some rows in the lexicon have `include = FALSE`. These are exclusion terms used as negative lookarounds to reduce false positives. They are handled automatically by the classifier.

------------------------------------------------------------------------

## Citation

Please cite PersonaLex as:

> Saffer, A. J., Scacco, J. M., & Li, J. (2026). PersonaLex Database (v1.0) [Computational classifier of social media content for self-expressed identity, interests, and issues]. Retrieved from: <https://license.umn.edu/product/personalex-validated-short-text-classifier-for-identities-interests-and-issues>

------------------------------------------------------------------------

## License

For academic or non-commercial use only. See the license agreement at the UMN Technology Commercialization landing page.

------------------------------------------------------------------------

## Questions and Contributions

For feedback, questions, or suggested additions, contact the PersonaLex team:

-   Adam Saffer — [asaffer\@umn.edu](mailto:asaffer@umn.edu)
-   Joshua Scacco — [jscacco\@usf.edu](mailto:jscacco@usf.edu)
-   Jianing Li — [jianing.li\@rutgers.edu](mailto:jianing.li@rutgers.edu)

------------------------------------------------------------------------

*Created by Adam J. Saffer (University of Minnesota), Joshua M. Scacco (University of South Florida), and Jianing Li (Rutgers University).*
