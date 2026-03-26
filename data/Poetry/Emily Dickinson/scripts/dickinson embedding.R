# Dickinson
# embedding

# get data ---- 

library(tidytext)
library(topicmodels)
library(text2vec)
library(Rtsne)
library(slam)

getwd()
setwd("Poetry/Emily Dickinson")
setwd("..")

emily <- read_csv("data/dickinson_prepared_dk.csv")
head(emily)

emily[1,3] %>%
    unlist()

emily_rd <- read_csv("data/dickinson_prepared_dk.txt")
head(emily_rd)
str(emily_rd)
emily_rd[1]

# style-preserving tokenizing ----

# Keeps Capitals, hyphenated compounds (Bee-line), and dashes (— / -) as tokens.


set.seed(1234)

# 1) Input sanity --------------------------------------------------------------
stopifnot(all(c("id","text") %in% names(emily)))
emily <- emily %>%
    mutate(
        id    = as.character(id),
        title = if ("title" %in% names(.)) as.character(title) else id,
        text  = as.character(text)
    )

# 2) Build (or alias) a style-preserving line table ---------------------------
# One row per line, keep original casing & hyphenation; make dashes their own tokens.
if (!exists("emily_lines")) {
    emily_lines_style <- emily %>%
        mutate(poem_text = str_replace_all(text, "\r\n", "\n")) %>%
        transmute(id, title, lines = str_split(poem_text, "\n")) %>%
        unnest_longer(lines, values_to = "line_text") %>%
        group_by(id) %>% mutate(line_index = row_number()) %>%
        ungroup() %>%
        mutate(line_text = str_trim(line_text)) %>%
        filter(line_text != "")
} else {
    emily_lines_style <- emily_lines
}

# 3) Style-preserving tokenizer ------------------------------------------------
# - Keeps case
# - Keeps hyphenated compounds (Bee-line)
# - Turns em dash (—) and en dash (-) into standalone tokens
# - Strips only .,;:!?"“”‘’ to avoid junk tokens
tokenizer_style <- function(x) {
    lapply(x, function(s) {
        if (is.na(s) || !nzchar(s)) return(character(0))
        s %>%
            str_replace_all("\\u2014|—", " — ") %>%     # em dash as token
            str_replace_all("–", " - ") %>%             # en dash as token
            str_replace_all("[\\.,;:!\\?\"“”‘’']", " ") %>%  # strip other punct
            str_squish() %>%
            str_split("\\s+") %>%
            .[[1]]
    })
}

# 4) Iterator over lines -------------------------------------------------------
lines_docs <- emily_lines_style %>%
    transmute(doc_id = paste(id, line_index, sep = ":"), text = line_text)

it_lines_1 <- itoken(lines_docs$text,
                     ids = lines_docs$doc_id,
                     tokenizer = tokenizer_style,
                     progressbar = FALSE)

# 5) Vocabulary + TCM (for GloVe) ---------------------------------------------
# Tune these if desired:
min_count <- 5L        # drop very rare tokens
window    <- 5L        # context window for co-occurrence

vocab <- create_vocabulary(it_lines_1)
vocab <- prune_vocabulary(vocab, term_count_min = min_count)
vectorizer <- vocab_vectorizer(vocab)

# Rebuild iterator (consumed above) and create TCM
it_lines_2 <- itoken(lines_docs$text,
                     ids = lines_docs$doc_id,
                     tokenizer = tokenizer_style,
                     progressbar = FALSE)

tcm <- create_tcm(it_lines_2, vectorizer, skip_grams_window = window)

# 6) Train GloVe and build word vectors ---------------------------------------
rank_dim <- 100L       # embedding dimension
glove <- GlobalVectors$new(rank = rank_dim, x_max = 10)
wv_main <- glove$fit_transform(tcm, n_iter = 20, convergence_tol = 0.01, n_threads = 1)
wv_ctx  <- glove$components
word_vectors <- wv_main + t(wv_ctx)   # matrix: terms x rank_dim

# 7) Compute line embeddings (average of word vectors) ------------------------
# Tokenize each line once and average the vectors of tokens that exist in vocab
terms_available <- rownames(word_vectors)

# Build token list per line
line_tokens <- tokenizer_style(lines_docs$text)
names(line_tokens) <- lines_docs$doc_id

embed_line <- function(tokens, m) {
    ok <- tokens[tokens %in% rownames(m)]
    if (length(ok) == 0) return(rep(0, ncol(m)))   # all-zero if no known tokens
    colMeans(m[ok, , drop = FALSE])
}

emb_mat <- do.call(rbind, lapply(line_tokens, embed_line, m = word_vectors))
rownames(emb_mat) <- lines_docs$doc_id
colnames(emb_mat) <- paste0("dim_", seq_len(ncol(emb_mat)))

# 8) Final table: id, title, line_index, doc_id + embedding dims --------------
line_embeddings <- tibble(doc_id = rownames(emb_mat)) %>%
    separate_wider_delim(doc_id, ":", names = c("id","line_index")) %>%
    mutate(line_index = as.integer(line_index)) %>%
    left_join(distinct(emily_lines_style, id, title, line_index), by = c("id","line_index")) %>%
    bind_cols(as_tibble(emb_mat))

# 9) Quick sanity prints -------------------------------------------------------
message("Lines embedded: ", nrow(line_embeddings))
message("Vocab size (kept): ", nrow(word_vectors))
# Example: first few rows
print(line_embeddings %>% select(id, title, line_index, starts_with("dim_")) %>% slice_head(n = 3))
# ----------------------------------------------------------------------------- 


