# 02_analyze_declaration.R
#
# Groups sentences from the Declaration of Independence Anniversary
# Commemoration (Coolidge, July 5, 1926) into thematic passages via GPT-4o,
# then assigns up to 5 PAP topic codes per passage.
#
# Inputs:
#   data/declaration_sentences.rds
#   data/policy_agendas_codebook.csv
#
# Outputs:
#   data/declaration_passages.rds  — 23-row tibble: passage_id, sent_ids, para_ids, theme, text
#   data/declaration_coded.rds     — passages + PAP codes + custom_theme columns

library(tidyverse)
source("scripts/code_speech_passages.R")

base_path     <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/data"
codebook_path <- file.path(base_path, "policy_agendas_codebook.csv")

declaration_sentences <- readRDS(file.path(base_path, "declaration_sentences.rds"))

# ── 1. Group sentences into passages ──────────────────────────────────────────

message("Grouping sentences into passages...")
declaration_passages <- group_sentences(declaration_sentences, model = "gpt-4o")
message(sprintf("  %d passages identified", nrow(declaration_passages)))

saveRDS(declaration_passages, file.path(base_path, "declaration_passages.rds"))

# ── 2. Code passages via PAP ───────────────────────────────────────────────────

codebook_string <- build_codebook_string(codebook_path)

message("Coding passages...")
coded_list <- vector("list", nrow(declaration_passages))

for (i in seq_len(nrow(declaration_passages))) {
  message(sprintf("  passage %d / %d", i, nrow(declaration_passages)))
  coded_list[[i]] <- code_passage(declaration_passages$text[[i]], codebook_string)
  Sys.sleep(3)
}

declaration_coded <- bind_cols(declaration_passages, bind_rows(coded_list)) |>
  mutate(
    source         = "gpt",
    custom_theme_1 = NA_character_,
    custom_theme_2 = NA_character_,
    custom_theme_3 = NA_character_,
    custom_theme_4 = NA_character_,
    custom_theme_5 = NA_character_
  )

saveRDS(declaration_coded, file.path(base_path, "declaration_coded.rds"))
message("Done.")
