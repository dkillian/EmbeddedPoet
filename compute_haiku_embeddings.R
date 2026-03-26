# compute_haiku_embeddings.R
#
# Embed all haikus using OpenAI text-embedding-3-small and save the result.
# Run once; the output is loaded by haiku_app.R at startup.
#
# Requires: OPENAI_API_KEY in .Renviron (run usethis::edit_r_environ())
#
# Output: haiku_emb.rds — a list with fields:
#   $haiku_id  integer row IDs (1:n)
#   $text      character vector of haiku texts
#   $source    character vector of sources
#   $gruen_score  numeric quality scores
#   $emb_norm  L2-normalised embedding matrix (n × 1536)

library(openai)

# ── Config ────────────────────────────────────────────────────────────────────
DATA_PATH        <- "data/Poetry/haikus.csv"
CHECKPOINT_DIR   <- "haiku_embeddings_cache"
OUTPUT_PATH      <- "haiku_emb.rds"
BATCH_SIZE       <- 500   # texts per API call (max 2048; 500 is conservative)
CHECKPOINT_EVERY <- 10    # save checkpoint every N batches
SLEEP_SECONDS    <- 0.25  # pause between batches to respect rate limits

# ── Helpers ───────────────────────────────────────────────────────────────────

l2_norm <- function(mat) mat / sqrt(rowSums(mat^2))

embed_batch <- function(texts) {
  result <- openai::create_embedding(
    model = "text-embedding-3-small",
    input = texts
  )
  do.call(rbind, result$data$embedding)
}

# ── Load data ─────────────────────────────────────────────────────────────────

message("Loading haikus from ", DATA_PATH)

haikus <- read_csv(DATA_PATH, show_col_types = FALSE) |>
  mutate(haiku_id = row_number())

texts <- haikus$text
n     <- length(texts)

batches   <- split(seq_len(n), ceiling(seq_len(n) / BATCH_SIZE))
n_batches <- length(batches)

message(sprintf("%d haikus → %d batches of up to %d", n, n_batches, BATCH_SIZE))

# ── Resume from checkpoint ────────────────────────────────────────────────────

if (!dir.exists(CHECKPOINT_DIR)) dir.create(CHECKPOINT_DIR)

checkpoint_path <- file.path(CHECKPOINT_DIR, "progress.rds")

if (file.exists(checkpoint_path)) {
  progress    <- readRDS(checkpoint_path)
  emb_list    <- progress$emb_list
  start_batch <- progress$last_batch + 1
  message(sprintf("Resuming from batch %d / %d", start_batch, n_batches))
} else {
  emb_list    <- vector("list", n_batches)
  start_batch <- 1L
}

# ── Embed ─────────────────────────────────────────────────────────────────────

for (i in seq(start_batch, n_batches)) {
  idx <- batches[[i]]

  emb_list[[i]] <- tryCatch(
    embed_batch(texts[idx]),
    error = function(e) {
      stop(sprintf("API error on batch %d: %s", i, conditionMessage(e)))
    }
  )

  message(sprintf(
    "[%d / %d]  rows %d–%d embedded",
    i, n_batches, min(idx), max(idx)
  ))

  # Checkpoint
  if (i %% CHECKPOINT_EVERY == 0 || i == n_batches) {
    saveRDS(list(emb_list = emb_list, last_batch = i), checkpoint_path)
    message(sprintf("  → checkpoint saved (batch %d)", i))
  }

  Sys.sleep(SLEEP_SECONDS)
}

# ── Combine, normalise, and save ──────────────────────────────────────────────
message("Combining batches and normalising…")
emb_raw  <- do.call(rbind, emb_list)
emb_norm <- l2_norm(emb_raw)

saveRDS(
  list(
    haiku_id    = haikus$haiku_id,
    text        = haikus$text,
    source      = haikus$source,
    gruen_score = haikus$gruen_score,
    emb_norm    = emb_norm
  ),
  OUTPUT_PATH
)

size_mb <- file.size(OUTPUT_PATH) / 1e6
message(sprintf("Done. Saved to %s (%.1f MB)", OUTPUT_PATH, size_mb))

# Clean up checkpoint
if (file.exists(checkpoint_path)) {
  file.remove(checkpoint_path)
  message("Checkpoint cleaned up.")
}


