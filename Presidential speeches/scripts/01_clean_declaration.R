# 01_clean_declaration.R
#
# Parses Coolidge's "Declaration of Independence Anniversary Commemoration"
# (July 5, 1926) from JSON into analysis-ready paragraph and sentence tibbles.
#
# Outputs:
#   data/declaration_paragraphs.rds  — para_id, paragraph
#   data/declaration_sentences.rds   — para_sent_id, sent_seq, para_id, sent_id, sentence

library(tidyverse)
library(tokenizers)
source("scripts/code_speech_passages.R")

base_path <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/data"
json_path <- file.path(
  base_path, "raw text/speeches raw",
  "Calvin_Coolidge_1926-07-05T18_54_00-04_00_July_5,_1926__Declaration_of_Independence_Anniversary_Commemoration.json"
)

# ── 1. Paragraphs ──────────────────────────────────────────────────────────────

raw_paragraphs <- parse_json_speech(json_path)

declaration_paragraphs <- tibble(
  para_id   = seq_along(raw_paragraphs),
  paragraph = raw_paragraphs
)

saveRDS(declaration_paragraphs, file.path(base_path, "declaration_paragraphs.rds"))

# ── 2. Sentences ───────────────────────────────────────────────────────────────

declaration_sentences <- declaration_paragraphs |>
  mutate(sentence = tokenize_sentences(paragraph)) |>
  unnest(sentence) |>
  group_by(para_id) |>
  mutate(sent_id = row_number()) |>
  ungroup() |>
  mutate(
    para_sent_id = paste(para_id, sent_id, sep = "_"),
    sent_seq     = row_number()
  ) |>
  select(para_sent_id, sent_seq, para_id, sent_id, sentence)

saveRDS(declaration_sentences, file.path(base_path, "declaration_sentences.rds"))

message(sprintf("Done: %d paragraphs, %d sentences",
                nrow(declaration_paragraphs), nrow(declaration_sentences)))
