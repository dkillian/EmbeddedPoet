library(tidyverse)
library(pdftools)

pdf_path <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/Policy Agendas Project - Topics Codebook.pdf"
text <- pdf_text(pdf_path)

all_text <- paste(text, collapse = "\n")
lines <- str_split(all_text, "\n")[[1]]

# Major topics (no topic 11 in the PAP scheme)
major_topics <- tribble(
  ~major_code, ~major_name,
  1,  "Macroeconomics",
  2,  "Civil Rights, Minority Issues, and Civil Liberties",
  3,  "Health",
  4,  "Agriculture",
  5,  "Labor and Employment",
  6,  "Education",
  7,  "Environment",
  8,  "Energy",
  9,  "Immigration",
  10, "Transportation",
  12, "Law, Crime, and Family Issues",
  13, "Social Welfare",
  14, "Community Development and Housing Issues",
  15, "Banking, Finance, and Domestic Commerce",
  16, "Defense",
  17, "Space, Science, Technology, and Communications",
  18, "Foreign Trade",
  19, "International Affairs and Foreign Aid",
  20, "Government Operations",
  21, "Public Lands and Water Management"
)

# Extract subtopic lines (e.g., "  321: Regulation of drug industry...")
subtopic_lines <- str_subset(lines, "^\\s{0,6}\\d{3,4}: .+")

subtopic_df <- tibble(raw = subtopic_lines) |>
  mutate(
    subtopic_code = as.integer(str_extract(raw, "^\\s*(\\d{3,4})", group = 1)),
    subtopic_name = str_trim(str_remove(raw, "^\\s*\\d{3,4}: "))
  ) |>
  select(subtopic_code, subtopic_name)

# Infer major topic code from subtopic code range
codebook <- subtopic_df |>
  mutate(
    major_code = case_when(
      subtopic_code >= 2100 ~ 21L,
      subtopic_code >= 2000 ~ 20L,
      subtopic_code >= 1900 ~ 19L,
      subtopic_code >= 1800 ~ 18L,
      subtopic_code >= 1700 ~ 17L,
      subtopic_code >= 1600 ~ 16L,
      subtopic_code >= 1500 ~ 15L,
      subtopic_code >= 1400 ~ 14L,
      subtopic_code >= 1300 ~ 13L,
      subtopic_code >= 1200 ~ 12L,
      subtopic_code >= 1000 ~ 10L,
      subtopic_code >= 900  ~ 9L,
      subtopic_code >= 800  ~ 8L,
      subtopic_code >= 700  ~ 7L,
      subtopic_code >= 600  ~ 6L,
      subtopic_code >= 500  ~ 5L,
      subtopic_code >= 400  ~ 4L,
      subtopic_code >= 300  ~ 3L,
      subtopic_code >= 200  ~ 2L,
      subtopic_code >= 100  ~ 1L,
      TRUE ~ NA_integer_
    )
  ) |>
  left_join(major_topics, by = "major_code") |>
  select(major_code, major_name, subtopic_code, subtopic_name)

out_path <- "C:/Users/dkill/OneDrive/Documents/Embedded Poet/Presidential speeches/policy_agendas_codebook.csv"
write_csv(codebook, out_path)
