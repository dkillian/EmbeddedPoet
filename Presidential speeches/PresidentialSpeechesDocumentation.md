# Presidential Speeches — Qualitative Coding Project

## Overview

This project applies the **Policy Agendas Project (PAP)** topic coding scheme to presidential speeches. The workflow uses the OpenAI API (GPT-4o) to (1) segment speech text into thematic passages and (2) assign up to three PAP topic codes to each passage.

---

## Folder Convention

Well-defined activities follow this standard structure:
```
Presidential speeches/
├── scripts/    # All R code files
├── data/       # Raw and processed data
├── viz/        # Visualizations
├── tables/     # Output tables
└── models/     # Saved models (if applicable)
```

## File Locations

All work lives under:
`C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/`

| Path | Description |
|------|-------------|
| `data/raw text/` | 1,059+ speech files (mostly `.json`, some `.txt`) spanning all U.S. presidents |
| `data/US-Exec_SOTU_2025.csv` | Pre-existing PAP-coded sentence-level data from the Comparative Agendas Project |
| `data/policy_agendas_codebook.csv` | PAP codebook: major code, major name, subtopic code, subtopic name |
| `data/Policy Agendas Project - Topics Codebook.pdf` | Source PDF for the codebook |
| `data/State of the Union Address - Codebook.pdf` | Supplementary SOTU codebook |
| `scripts/parse_policy_agendas_codebook.R` | Parses the PAP PDF into `policy_agendas_codebook.csv` using `pdftools` |
| `scripts/code_speech_passages.R` | Main coding pipeline (parse → group → code via GPT-4o) |
| `scripts/01_clean_things_unseen.R` | Parses and segments "The Things That Are Unseen" into paragraph and sentence tibbles; saves to `data/` |
| `data/things_unseen_paragraphs.rds` | 25-row tibble: `para_id`, `paragraph` |
| `data/things_unseen_sentences.rds` | 182-row tibble: `para_id`, `sent_id`, `sentence` |
| `viz/` | Empty — visualizations not yet created |
| `tables/` | Does not yet exist |
| `models/` | Does not yet exist |
| `PresidentialSpeechesDocumentation.md` | This file — internal project reference |
| `PresidentialSpeechesLog.md` | Session-by-session structured log (decisions, artifacts, risks, next steps) |
| `PresidentialSpeechesConversations.md` | Running transcript of assistant conversations |

---

## PAP Codebook Structure

21 major topic areas (no topic 11):

| Code | Name |
|------|------|
| 1 | Macroeconomics |
| 2 | Civil Rights, Minority Issues, and Civil Liberties |
| 3 | Health |
| 4 | Agriculture |
| 5 | Labor and Employment |
| 6 | Education |
| 7 | Environment |
| 8 | Energy |
| 9 | Immigration |
| 10 | Transportation |
| 12 | Law, Crime, and Family Issues |
| 13 | Social Welfare |
| 14 | Community Development and Housing Issues |
| 15 | Banking, Finance, and Domestic Commerce |
| 16 | Defense |
| 17 | Space, Science, Technology, and Communications |
| 18 | Foreign Trade |
| 19 | International Affairs and Foreign Aid |
| 20 | Government Operations |
| 21 | Public Lands and Water Management |

Subtopics are 3–4 digit codes (first 1–2 digits = major topic).

---

## Coding Pipeline (`code_speech_passages.R`)

Main function: `code_speech_passages(txt_path, codebook_path, model = "gpt-4o")`

**Steps:**
1. `parse_speech_passages()` — reads a `.txt` file, removes OCR artifacts and page headers, detects paragraph starts via 3+ leading spaces before a capital letter, returns a character vector of paragraphs (min length 80 chars).
2. `group_paragraphs()` — sends numbered paragraphs to GPT-4o; returns a tibble with `passage_id`, `paragraph_ids`, `theme`, `text`.
3. `build_codebook_string()` — formats `policy_agendas_codebook.csv` as a compact string for use in prompts.
4. `code_passage()` — sends each passage + codebook to GPT-4o; returns a wide-format row with up to 3 PAP codes (`major_code_1`, `major_name_1`, `subtopic_code_1`, `subtopic_name_1`, ... `_3`).

**Output:** A tibble with one row per passage, containing passage metadata + 12 code columns.

**Requirements:** `OPENAI_API_KEY` in `.Renviron`; packages `openai`, `tidyverse`, `jsonlite`.

---

## Existing Coded Data (`US-Exec_SOTU_2025.csv`)

Sentence-level PAP coding from the Comparative Agendas Project (Truman → present). Key columns:
- `id`, `doc_count`, `date`, `president`, `pres_party`, `congress`
- `description` — the sentence text
- `pap_majortopic`, `pap_subtopic` — PAP codes
- `source` — e.g., "Congressional Record"

---

## Speech File Format

Most files are `.json`; the `parse_speech_passages()` function targets `.txt` files with OCR-derived indentation (paragraph starts marked by 3+ leading spaces before a capital letter). A few `.txt` files exist (e.g., Calvin Coolidge speeches). JSON files would require a different parsing approach.

---

## Broader Goal

The work on "The Things That Are Unseen" is a test case for a pipeline intended to generalize to the full corpus of 1,059+ speeches. A future task is to consolidate the clean → analyze → report workflow into a single, corpus-wide pipeline that can be run on any speech or set of speeches.

Scripts should be written with generalizability in mind — functions that accept a file path or speech identifier as input, not hard-coded to a single speech.

## Script Naming Convention

Scripts follow a numbered stage prefix:
- `01_clean_*` — parse, fix, segment, save to `data/`
- `02_analyze_*` — load clean data, produce findings, save to `tables/` or `models/`
- `03_report_*` — load findings, produce outputs in `viz/` or as Quarto documents

## Notes

- The `viz/`, `tables/`, and `models/` directories do not yet exist.
- The pipeline makes one API call per passage (potentially many calls per speech).
- The `US-Exec_SOTU_2025.csv` dataset uses sentence-level granularity vs. the passage-level granularity of the new pipeline.
