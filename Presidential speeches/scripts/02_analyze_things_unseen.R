# 02_analyze_things_unseen.R
#
# Groups sentences from "The Things That Are Unseen" into thematic passages
# via GPT-4o, then assigns up to five PAP topic codes to each passage.
#
# Inputs:
#   data/things_unseen_sentences.rds
#   data/policy_agendas_codebook.csv
#
# Outputs:
#   data/things_unseen_passages.rds   -- grouped passages with sent/para provenance
#   data/things_unseen_coded.rds      -- passages with PAP codes

library(tidyverse)
library(jsonlite)
library(openai)

source("C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/scripts/code_speech_passages.R")

base_path    <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/data"
codebook_path <- file.path(base_path, "policy_agendas_codebook.csv")

# ── 1. Load clean data ────────────────────────────────────────────────────────

things_unseen_sentences <- readRDS(file.path(base_path, "things_unseen_sentences.rds"))

# ── 2. Group sentences into thematic passages ─────────────────────────────────

message("Grouping sentences into passages...")
things_unseen_passages <- group_sentences(things_unseen_sentences)
message(sprintf("  %d passages identified", nrow(things_unseen_passages)))

saveRDS(things_unseen_passages, file.path(base_path, "things_unseen_passages.rds"))

# ── 3. Assign PAP codes to each passage ───────────────────────────────────────

message("Building codebook string...")
codebook_string <- build_codebook_string(codebook_path)

message("Coding passages (1 API call per passage)...")
things_unseen_coded <- things_unseen_passages |>
  mutate(codes = purrr::map(seq_len(nrow(things_unseen_passages)), \(i) {
    message(sprintf("  coding passage %d / %d", i, nrow(things_unseen_passages)))
    Sys.sleep(3)
    code_passage(things_unseen_passages$text[[i]], codebook_string)
  })) |>
  unnest(codes)

saveRDS(things_unseen_coded, file.path(base_path, "things_unseen_coded.rds"))

# ── 4. Manual code corrections ────────────────────────────────────────────────
# Passages with philosophical/spiritual content returned NA codes from the model.
# Two custom subcodes were added to the codebook and applied manually:
#   610 - Epistemic Humility (passage 6)
#   611 - Education for Moral and Spiritual Development (passage 21)

things_unseen_coded <- things_unseen_coded |>
  mutate(
    major_code_1    = if_else(passage_id %in% c(6, 21), 6L,          major_code_1),
    major_name_1    = if_else(passage_id %in% c(6, 21), "Education", major_name_1),
    subtopic_code_1 = case_when(
      passage_id == 6  ~ 610L,
      passage_id == 21 ~ 611L,
      TRUE             ~ subtopic_code_1
    ),
    subtopic_name_1 = case_when(
      passage_id == 6  ~ "Epistemic Humility",
      passage_id == 21 ~ "Education for Moral and Spiritual Development",
      TRUE             ~ subtopic_name_1
    )
  )

saveRDS(things_unseen_coded, file.path(base_path, "things_unseen_coded.rds"))
