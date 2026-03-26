# 01_clean_things_unseen.R
#
# Parses and segments Calvin Coolidge's "The Things That Are Unseen" (1923)
# into two tidy objects, then saves them to data/ for downstream analysis.
#
# This script serves as the first test case for a pipeline intended to
# generalize to the full corpus of presidential speeches.
#
# Outputs:
#   data/things_unseen_paragraphs.rds  -- one row per paragraph (25 rows)
#   data/things_unseen_sentences.rds   -- one row per sentence  (182 rows)
#
# Both share para_id as a common key.

library(tidyverse)
library(tokenizers)

source("C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/scripts/code_speech_passages.R")

# ── 1. Parse into clean paragraphs ────────────────────────────────────────────

txt_path <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/data/raw text/Calvin_Coolidge_1923-06-19T13_00_00-04_00_June_19,_1923__The_Things_That_Are_Unseen.txt"

things_unseen <- parse_speech_passages(txt_path)

# ── 2. Paragraph-level tibble ─────────────────────────────────────────────────

things_unseen_paragraphs <- tibble(
  para_id   = seq_along(things_unseen),
  paragraph = things_unseen
)

# ── 3. Sentence-level tibble ──────────────────────────────────────────────────

things_unseen_sentences <- tibble(
  para_id = seq_along(things_unseen),
  text    = things_unseen
) |>
  mutate(sentence = tokenize_sentences(text)) |>
  unnest(sentence) |>
  mutate(sent_id = row_number(), .by = para_id) |>
  select(para_id, sent_id, sentence)

# ── 4. Save to data/ ──────────────────────────────────────────────────────────

base_path <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/data"

saveRDS(things_unseen_paragraphs, file.path(base_path, "things_unseen_paragraphs.rds"))
saveRDS(things_unseen_sentences,  file.path(base_path, "things_unseen_sentences.rds"))
