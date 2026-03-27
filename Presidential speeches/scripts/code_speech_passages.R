# code_speech_passages.R
#
# Parses a presidential speech text file into thematic passages, then uses
# the OpenAI chat completions API to assign up to three Policy Agendas Project
# (PAP) topic codes to each passage.
#
# Requires:
#   - OPENAI_API_KEY in .Renviron
#   - policy_agendas_codebook.csv in the same folder as the speech
#   - openai, tidyverse, jsonlite packages

library(openai)
library(tidyverse)
library(jsonlite)

# ── 1. Parse speech text into passages ────────────────────────────────────────

parse_speech_passages <- function(txt_path) {

  raw <- readLines(txt_path, warn = FALSE)

  # Remove page artifacts: standalone page numbers, running headers, footnotes
  clean_lines <- raw |>
    (\(x) x[!str_detect(x, "^\\s*\\d+\\s*$")])() |>
    (\(x) x[!str_detect(x, "^\\s*\\d{3}\\s+THE (PRICE|THINGS)")])() |>
    (\(x) x[!str_detect(x, "^\\s*THE (THINGS THAT ARE UNSEEN|PRICE OF FREEDOM)\\s*\\d*\\s*$")])() |>
    (\(x) x[!str_detect(x, "At Wheaton College")])()

  # Use indentation (3+ leading spaces before a capital) to detect paragraph starts
  is_para_start <- str_detect(clean_lines, "^   +[A-Z]")

  paragraphs <- character(0)
  current    <- ""

  for (i in seq_along(clean_lines)) {
    line <- str_trim(clean_lines[i])
    if (nchar(line) == 0) next
    if (is_para_start[i] && nchar(current) > 0) {
      paragraphs <- c(paragraphs, str_squish(current))
      current    <- line
    } else {
      current <- paste(current, line)
    }
  }
  if (nchar(current) > 0) paragraphs <- c(paragraphs, str_squish(current))

  # Fix common OCR artifacts
  paragraphs <- paragraphs |>
    str_replace_all("-\\s+",   "")  |>
    str_replace_all("t~at",    "that") |>
    str_replace_all("Svch",    "Such") |>
    str_replace_all("1nake",   "make") |>
    str_replace_all("!t ",        "It ")          |>
    str_replace_all(",America",   ", America")    |>
    str_replace_all("~hey",       "They")         |>
    str_replace_all("def enders", "defenders")    |>
    str_replace_all("selfexpression", "self-expression") |>
    str_replace_all("connnunity", "community")    |>
    str_replace_all("~",          "")             |>
    (\(x) x[nchar(x) > 80])()

  paragraphs
}


# ── 1b. Parse a JSON speech file into paragraphs ──────────────────────────────

parse_json_speech <- function(json_path, min_chars = 80) {

  raw        <- jsonlite::fromJSON(json_path)
  transcript <- raw$transcript

  # Split on <br /> paragraph breaks
  paragraphs <- stringr::str_split(transcript, "<br />\\n?")[[1]]

  # Strip any remaining HTML tags
  paragraphs <- stringr::str_remove_all(paragraphs, "<[^>]+>")

  # Normalize whitespace
  paragraphs <- stringr::str_squish(paragraphs)

  # Filter short paragraphs (salutations, headings, etc.)
  paragraphs <- paragraphs[nchar(paragraphs) > min_chars]

  paragraphs
}


# ── Helper: extract JSON from a model response string ─────────────────────────

extract_json <- function(text) {
  # Strip markdown code fences if present
  text <- str_remove_all(text, "```json|```")
  # Extract the first JSON object or array
  m <- str_extract(text, "\\{[\\s\\S]*\\}|\\[[\\s\\S]*\\]")
  fromJSON(m)
}


# ── 2. Group paragraphs into passages via LLM ─────────────────────────────────

group_paragraphs <- function(paragraphs, model = "gpt-4o") {

  numbered <- paste(
    sprintf("[%d] %s", seq_along(paragraphs), paragraphs),
    collapse = "\n\n"
  )

  prompt <- paste0(
    "Below are numbered paragraphs from a speech. ",
    "Group consecutive paragraphs that share a common theme into passages. ",
    "Respond with ONLY a JSON array (no other text) where each element has:\n",
    "  - \"passage_id\": integer starting at 1\n",
    "  - \"paragraphs\": array of paragraph numbers included\n",
    "  - \"theme\": a concise label (10 words or fewer) describing the passage\n\n",
    "Paragraphs:\n\n", numbered
  )

  resp <- openai::create_chat_completion(
    model    = model,
    messages = list(
      list(role = "system", content = "You are a careful political science research assistant. Respond only with valid JSON."),
      list(role = "user",   content = prompt)
    ),
    temperature = 0
  )

  parsed <- extract_json(resp$choices$message.content)

  # Normalise: model may return array or object wrapping an array
  if (is.data.frame(parsed)) {
    passages_meta <- as_tibble(parsed)
  } else {
    passages_meta <- as_tibble(parsed[[1]])
  }

  # Build passage texts
  passages_meta |>
    rowwise() |>
    mutate(text = paste(paragraphs[unlist(paragraphs)], collapse = " ")) |>
    ungroup() |>
    mutate(paragraph_ids = map_chr(paragraphs, \(x) paste(unlist(x), collapse = ", "))) |>
    select(passage_id, paragraph_ids, theme, text)
}


# ── 3. Group sentences into passages via LLM ──────────────────────────────────

group_sentences <- function(sentences_tbl, model = "gpt-4o") {

  # sentences_tbl must have columns: para_id, sent_id, sentence
  sentences_tbl <- sentences_tbl |>
    mutate(global_id = row_number())

  numbered <- paste(
    sprintf("[%d] %s", sentences_tbl$global_id, sentences_tbl$sentence),
    collapse = "\n\n"
  )

  prompt <- paste0(
    "Below are numbered sentences from a speech. ",
    "Group consecutive sentences that share a common theme into passages. ",
    "Respond with ONLY a JSON array (no other text) where each element has:\n",
    "  - \"passage_id\": integer starting at 1\n",
    "  - \"sentences\": array of sentence numbers included\n",
    "  - \"theme\": a concise label (10 words or fewer) describing the passage\n\n",
    "Sentences:\n\n", numbered
  )

  resp <- openai::create_chat_completion(
    model    = model,
    messages = list(
      list(role = "system", content = "You are a careful political science research assistant. Respond only with valid JSON."),
      list(role = "user",   content = prompt)
    ),
    temperature = 0
  )

  parsed <- extract_json(resp$choices$message.content)

  if (is.data.frame(parsed)) {
    passages_meta <- as_tibble(parsed)
  } else {
    passages_meta <- as_tibble(parsed[[1]])
  }

  # Reconstruct text, sent_ids, and para_ids for each passage
  passages_meta |>
    rowwise() |>
    mutate(
      sent_ids = paste(unlist(sentences), collapse = ", "),
      text     = paste(
        sentences_tbl$sentence[sentences_tbl$global_id %in% unlist(sentences)],
        collapse = " "
      ),
      para_ids = paste(
        sort(unique(sentences_tbl$para_id[sentences_tbl$global_id %in% unlist(sentences)])),
        collapse = ", "
      )
    ) |>
    ungroup() |>
    select(passage_id, sent_ids, para_ids, theme, text)
}


# ── 4. Build a compact codebook string for the prompt ─────────────────────────

build_codebook_string <- function(codebook_path) {

  cb <- read_csv(codebook_path, show_col_types = FALSE)

  cb |>
    mutate(line = sprintf("%d (%s) > %d: %s",
                          major_code, major_name, subtopic_code, subtopic_name)) |>
    pull(line) |>
    paste(collapse = "\n")
}


# ── 4. Assign PAP codes to a single passage ───────────────────────────────────

code_passage <- function(passage_text, codebook_string, model = "gpt-4o",
                         max_retries = 5) {

  prompt <- paste0(
    "You are coding text using the Policy Agendas Project (PAP) topic scheme.\n\n",
    "Assign up to FIVE codes that best describe the policy content of the passage below. ",
    "If a passage has fewer than five distinct policy topics, assign fewer codes. ",
    "Return a JSON object with a single key \"codes\" containing an array of objects, ",
    "each with:\n",
    "  - \"major_code\": integer\n",
    "  - \"major_name\": string\n",
    "  - \"subtopic_code\": integer\n",
    "  - \"subtopic_name\": string\n\n",
    "PAP Codebook (major_code (major_name) > subtopic_code: subtopic_name):\n",
    codebook_string, "\n\n",
    "Passage:\n", passage_text
  )

  # Retry with exponential backoff to handle rate limit errors
  resp <- NULL
  for (attempt in seq_len(max_retries)) {
    tryCatch({
      resp <- openai::create_chat_completion(
        model    = model,
        messages = list(
          list(role = "system", content = "You are a careful political science research assistant. Respond only with valid JSON."),
          list(role = "user",   content = prompt)
        ),
        temperature = 0
      )
    }, error = function(e) {
      if (attempt < max_retries && grepl("429", conditionMessage(e))) {
        wait <- 2 ^ attempt
        message(sprintf("    rate limit hit, retrying in %ds...", wait))
        Sys.sleep(wait)
      } else {
        stop(e)
      }
    })
    if (!is.null(resp)) break
  }

  parsed <- extract_json(resp$choices$message.content)

  codes_df <- as_tibble(parsed$codes)

  # Pad to 5 rows if fewer codes returned
  n_missing <- 5L - nrow(codes_df)
  if (n_missing > 0) {
    pad <- tibble(
      major_code    = NA_integer_,
      major_name    = NA_character_,
      subtopic_code = NA_integer_,
      subtopic_name = NA_character_
    )
    codes_df <- bind_rows(codes_df, pad[seq_len(n_missing), ])
  }

  codes_df <- codes_df[1:5, ]

  # Rename wide
  tibble(
    major_code_1    = codes_df$major_code[1],
    major_name_1    = codes_df$major_name[1],
    subtopic_code_1 = codes_df$subtopic_code[1],
    subtopic_name_1 = codes_df$subtopic_name[1],
    major_code_2    = codes_df$major_code[2],
    major_name_2    = codes_df$major_name[2],
    subtopic_code_2 = codes_df$subtopic_code[2],
    subtopic_name_2 = codes_df$subtopic_name[2],
    major_code_3    = codes_df$major_code[3],
    major_name_3    = codes_df$major_name[3],
    subtopic_code_3 = codes_df$subtopic_code[3],
    subtopic_name_3 = codes_df$subtopic_name[3],
    major_code_4    = codes_df$major_code[4],
    major_name_4    = codes_df$major_name[4],
    subtopic_code_4 = codes_df$subtopic_code[4],
    subtopic_name_4 = codes_df$subtopic_name[4],
    major_code_5    = codes_df$major_code[5],
    major_name_5    = codes_df$major_name[5],
    subtopic_code_5 = codes_df$subtopic_code[5],
    subtopic_name_5 = codes_df$subtopic_name[5]
  )
}


# ── 5. Main function: parse + group + code ────────────────────────────────────

code_speech_passages <- function(
    txt_path,
    codebook_path = file.path(dirname(txt_path), "policy_agendas_codebook.csv"),
    model         = "gpt-4o"
) {

  message("Parsing speech: ", basename(txt_path))
  paragraphs <- parse_speech_passages(txt_path)
  message(sprintf("  %d paragraphs extracted", length(paragraphs)))

  message("Grouping paragraphs into passages…")
  passages <- group_paragraphs(paragraphs, model = model)
  message(sprintf("  %d passages identified", nrow(passages)))

  message("Building codebook string…")
  codebook_string <- build_codebook_string(codebook_path)

  message("Coding passages (1 API call per passage)…")
  coded <- passages |>
    mutate(codes = purrr::map(seq_len(nrow(passages)), \(i) {
      message(sprintf("  coding passage %d / %d", i, nrow(passages)))
      code_passage(passages$text[[i]], codebook_string, model = model)
    })) |>
    unnest(codes)

  coded
}
