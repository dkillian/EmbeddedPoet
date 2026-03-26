# Dickinson explore

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

# TOKENIZE ---- 

# standard ---- 

custom_stops <- tibble(
    word = c(stop_words$word,
             "’s","'s","’t","'t","n't","’m","'m",
             "’ve","'ve","’ll","'ll","’d","'d","”","“","'", "\"","—","-")
) %>% distinct()

tokens <- emily %>%
    mutate(text_clean = text %>%
               str_replace_all("\\u2014|—", " — ") %>%
               str_replace_all("–", " - ") %>%
               str_squish()) %>%
    unnest_tokens(word, text_clean, token = "words") %>%
    anti_join(custom_stops, by = "word") %>%
    filter(str_detect(word, "[[:alpha:]]"))

# preserve dashes and case ---- 

# Splits on whitespace only, after spacing out em/en dashes — and – .

custom_word_tokenizer <- function(x) {
    # x is a character vector (length = number of rows being tokenized)
    lapply(x, function(s) {
        if (is.na(s) || !nzchar(s)) return(character(0))
        s %>%
            str_replace_all("\\u2014|—", " — ") %>%  # em dash as its own token
            str_replace_all("–", " - ") %>%          # en dash as its own token
            str_squish() %>%
            str_split("\\s+") %>%
            .[[1]]
    })
}

#emily_tokens_custom

# line table

emily_lines <- emily %>%
    mutate(
        poem_text = as.character(text),
        poem_text = str_replace_all(poem_text, "\r\n", "\n")
    ) %>%
    transmute(id, title, lines = str_split(poem_text, "\n")) %>%
    unnest_longer(lines, values_to = "line_text") %>%
    group_by(id) %>%
    mutate(line_index = row_number()) %>%
    ungroup() %>%
    mutate(line_text = str_trim(line_text)) %>%
    filter(line_text != "")



# tokenize by line

tokens_by_line <- emily_lines %>%
    unnest_tokens(
        output = word,
        input  = line_text,
        token  = custom_word_tokenizer,
        to_lower = FALSE
    )

# tokenize by poem 

tokens_by_poem <- emily %>%
    transmute(id, title, poem_text = as.character(text)) %>%
    unnest_tokens(
        output   = word,
        input    = poem_text,
        token    = custom_word_tokenizer,  # <- list per row
        to_lower = FALSE
    )


# case-preserving n-grammer

ngrammer <- function(n) {
    force(n)
    function(x) {
        # x is a character vector; return list of char vectors
        lapply(x, function(s) {
            if (is.na(s) || !nzchar(s)) return(character(0))
            w <- custom_word_tokenizer(s)[[1]]
            if (length(w) < n) return(character(0))
            vapply(seq_len(length(w) - n + 1),
                   function(i) paste(w[i:(i+n-1)], collapse = " "),
                   character(1))
        })
    }
}

bigrams_by_line <- emily_lines %>%
    unnest_tokens(bigram, line_text, token = ngrammer(2), to_lower = FALSE)

trigrams_by_line <- emily_lines %>%
    unnest_tokens(trigram, line_text, token = ngrammer(3), to_lower = FALSE)

quadgrams_by_line <- emily_lines %>%
    unnest_tokens(quadgram, line_text, token = ngrammer(4), to_lower = FALSE)

quingrams_by_line <- emily_lines %>%
    unnest_tokens(quingram, line_text, token = ngrammer(5), to_lower = FALSE)

# sanity check 

# Should print a few tokens and include dash tokens "—" or "-"
tokens_by_line %>% filter(word %in% c("—","-")) %>% slice_head(n = 10)

# Confirm nothing lowercased:
any(grepl("[A-Z]", tokens_by_line$word))  # should be TRUE for Dickinson


# counts ---- 

n_tokens <- nrow(tokens_by_poem)
n_lines  <- nrow(emily_lines)
n_poems  <- dplyr::n_distinct(tokens_by_poem$id)

counts <- tibble(poems = n_poems,
                 tokens = n_tokens, 
                 lines = n_lines)

counts

lines_poem <- emily_lines %>%
    group_by(title) %>%
    tally() %>%
    arrange(desc(n)) %>%
    mutate(tile = ntile(n, 4))

lines_poem

describe(lines_poem$n)
Desc(lines_poem$n)

ggplot(lines_poem, aes(n)) + 
    geom_density()

ggplot(lines_poem, aes(x=n)) +
    geom_bar() +
    scale_x_continuous(breaks=seq(0, 40, by=2)) 


tile_rng <- lines_poem %>%
    group_by(tile) %>%
    mutate(low = min(n),
           high=max(n),
           range=paste(low, "-", high-1, sep="")) %>%
    #distinct(tile, .keep_all=TRUE) %>%
    select(-title, -n)

tile_rng

ot <- tile_rng %>%
    group_by(tile) %>%
    mutate(n=n()) %>%
    distinct(tile, .keep_all=TRUE) 

ot

ggplot(tile_rng(aes(tile)))


# poem and line length ----

library(dplyr); library(ggplot2)

poem_lengths <- tokens_by_poem %>%
    count(id, name = "tokens_per_poem")

poem_lengths

line_lengths <- tokens_by_line %>%
    count(id, line_index, name = "tokens_per_line")

ggplot(poem_lengths, aes(tokens_per_poem)) +
    geom_histogram(bins = 40) +
    labs(title = "Tokens per Poem")

ggplot(line_lengths, aes(tokens_per_line)) +
    geom_histogram(bins = 40) +
    labs(title = "Tokens per Line")

poem_lengths %>% summarise(min = min(tokens_per_poem),
                           q1 = quantile(tokens_per_poem, .25),
                           median = median(tokens_per_poem),
                           mean = mean(tokens_per_poem),
                           q3 = quantile(tokens_per_poem, .75),
                           max = max(tokens_per_poem))


# dash and capitalization ---- 

style_by_poem <- tokens_by_poem %>%
    mutate(
        is_dash = stringr::str_detect(word, "^(—|-)$"),
        is_cap  = stringr::str_detect(word, "^[A-Z]") & !is_dash
    ) %>%
    group_by(id, title) %>%
    summarise(tokens = n(),
              dashes = sum(is_dash),
              dash_rate = dashes / tokens,
              cap_ratio = mean(is_cap),
              .groups = "drop")

# top dash-heavy poems
style_by_poem %>% arrange(desc(dash_rate)) %>% slice_head(n = 15)

# distribution viz
ggplot(style_by_poem, aes(dash_rate)) + geom_histogram(bins = 40) +
    labs(title = "Dash Rate per Poem")

ggplot(style_by_poem, aes(cap_ratio)) + geom_histogram(bins = 40) +
    labs(title = "Capitalization Ratio per Poem")


# vocab, zipf ---- 

library(tidytext)

# types (unique tokens) overall
vocab <- tokens_by_poem %>% distinct(word)
n_vocab <- nrow(vocab)

# frequency table
freq <- tokens_by_poem %>% count(word, sort = TRUE)

# hapax legomena rate (freq==1)
hapax_rate <- mean(freq$n == 1)

tibble(n_tokens = nrow(tokens_by_poem), n_vocab, hapax_rate)

freq <- freq %>% mutate(rank = row_number())

ggplot(freq, aes(rank, n)) +
    geom_point(alpha = 0.6, size = 1) +
    scale_x_log10() + scale_y_log10() +
    labs(title = "Zipf plot", x = "Rank (log)", y = "Frequency (log)")


heap <- tokens_by_poem %>%
    mutate(tok_idx = row_number()) %>%
    group_by(tok_idx = floor(tok_idx / 200) * 200) %>%  # bucket by 200 tokens
    summarise(types = n_distinct(word), tokens = dplyr::n(), .groups = "drop") %>%
    mutate(cum_tokens = cumsum(tokens),
           cum_types  = cumsum(types))

ggplot(heap, aes(cum_tokens, cum_types)) +
    geom_line() +
    labs(title = "Heaps' law (Types vs Tokens)")


# TOPICS ---- 

# Basic sanity + types
stopifnot(all(c("id","text") %in% names(emily)))

emily <- emily %>%
    mutate(
        id    = as.character(id),
        title = if ("title" %in% names(.)) as.character(title) else id,
        text  = as.character(text)
    )

# Stopword set (standard + a few contractions/punctuation bits)
custom_stops <- tibble(
    word = c(stop_words$word,
             "’s","'s","’t","'t","n't","’m","'m","’ve","'ve","’ll","'ll","’d","'d",
             "”","“","'", "\"")
) %>% distinct()

# Poem-level normalized tokens (for themes)
tokens_poem_norm <- emily %>%
    transmute(id, title, text_norm = text) %>%
    unnest_tokens(word, text_norm, token = "words", to_lower = TRUE) %>%
    anti_join(custom_stops, by = "word") %>%
    filter(str_detect(word, "\\p{L}"))  # keep alphabetic tokens only

# Quick check (optional)
tokens_poem_norm %>%
    count(id, name = "n_tokens") %>%
    arrange(desc(n_tokens)) %>%
    head()

# build dtm ---- 

# 1) Document–Term Matrix (one doc = one poem)
dtm_poem <- tokens_poem_norm %>%
    count(id, word, name = "n") %>%
    cast_dtm(document = id, term = word, value = n)

# Drop any empty documents (safety)
dtm_poem <- dtm_poem[row_sums(dtm_poem) > 0, ]

# 2) Fit LDA
k_poem <- 11  # try 8–15; we’ll refine later

lda_poem <- LDA(
    dtm_poem, k = k_poem, method = "Gibbs",
    control = list(seed = 1234, burnin = 1000, iter = 2000, thin = 100)
)

# Quick sanity check (optional)
data.frame(
    docs  = nrow(dtm_poem),
    terms = ncol(dtm_poem),
    k     = k_poem,
    logLik = as.numeric(logLik(lda_poem))
)


# 3A) Top terms per topic (use to name themes)
poem_terms <- tidy(lda_poem, matrix = "beta") %>%
    group_by(topic) %>%
    slice_max(beta, n = 12, with_ties = FALSE) %>%
    ungroup()

poem_terms

# Quick, human-readable summary for labeling
topic_summaries <- poem_terms %>%
    group_by(topic) %>%
    arrange(desc(beta), .by_group = TRUE) %>%
    summarise(
        terms_list = list(term), # <- list of top terms
        top_terms = paste(head(term, 10), collapse = ", "), 
        .groups = "drop")

topic_summaries

# View(poem_terms)  # if in RStudio

# 3B) Topic mixture per poem (gamma) + dominant topic
poem_gamma <- tidy(lda_poem, matrix = "gamma")

poem_topics_view <- poem_gamma %>%
    group_by(document) %>%
    slice_max(gamma, n = 1, with_ties = FALSE) %>%
    ungroup() %>%
    mutate(topic = as.integer(topic)) %>%
    rename(id = document, topic_gamma = gamma) %>%
    left_join(distinct(emily, id, title), by = "id") %>%
    arrange(topic, desc(topic_gamma))

# Peek: most representative poems per topic
poem_topics_view %>%
    group_by(topic) %>%
    slice_max(topic_gamma, n = 5, with_ties = FALSE) %>%
    select(topic, id, title, topic_gamma)


# Simple rule-based labeler
suggest_label <- function(terms) {
    t <- tolower(unlist(terms))
    has <- function(words) any(str_detect(t, paste0("\\b(", paste(words, collapse="|"), ")\\b")))
    if (has(c("death","die","dying","grave","funeral","coffin","tomb","immortal","immortality","eternity"))) return("Death & Immortality")
    if (has(c("bee","bees","flower","flowers","bird","birds","brook","sun","snow","spring","summer","autumn","winter","wind","leaf","leaves","forest","woods","hill","meadow","rose"))) return("Nature & Seasons")
    if (has(c("god","heaven","soul","faith","prayer","church","christ","angel","angels","sabbath"))) return("Faith & Doubt")
    if (has(c("love","lover","beloved","heart","kiss","bride","bridegroom"))) return("Love & Heart")
    if (has(c("time","hour","hours","day","days","night","nights","noon","midnight","moment","year","years","clock"))) return("Time & Eternity")
    if (has(c("mind","brain","thought","think","sense","senses","seeing","see","sight","vision","eye","eyes"))) return("Mind & Perception")
    if (has(c("home","house","door","room","road","carriage","ride","town","village"))) return("Home & Place")
    if (has(c("war","battle","soldier","drum","flag","army","gun"))) return("War & Nation")
    if (has(c("sorrow","grief","pain","tears","sad","suffer","suffering","loss","bereft","aching"))) return("Pain & Sorrow")
    # fallback: use first 3 terms as a short label
    paste(head(t, 3), collapse = " / ")
}

topic_labels <- topic_summaries %>%
    mutate(label = vapply(terms_list, suggest_label, character(1))) %>%
    select(topic, label, top_terms)

# Attach labels to your poem-level dominance table
poem_topics_labeled <- poem_topics_view %>%
    left_join(topic_labels, by = "topic")

# Peek: top poems per labeled topic
poem_topics_labeled %>%
    group_by(topic, label) %>%
    slice_max(topic_gamma, n = 5, with_ties = FALSE) %>%
    select(topic, label, id, title, topic_gamma)

# EMBEDDING ---- 

# Tokenize lines for CONTENT (lowercase; remove stops/punct)
tokens_line_norm <- emily_lines %>%
    transmute(id, title, line_index, line_norm = line_text) %>%
    unnest_tokens(word, line_norm, token = "words", to_lower = TRUE) %>%
    anti_join(custom_stops, by = "word") %>%
    filter(str_detect(word, "\\p{L}"))

# Build a doc table: one normalized string per line document
lines_norm <- tokens_line_norm %>%
    reframe(
        doc_id    = paste(id, line_index, sep = ":"),
        text_norm = paste(word, collapse = " "),
        .by = c(id, title, line_index)
    ) %>%
    mutate(token_count = stringr::str_count(text_norm, "\\S+")) %>%
    filter(token_count >= 3) %>%
    select(-token_count)

# sanity check
lines_norm %>% slice_head(n = 5)
nrow(lines_norm)

# (Optional) keep only lines with a few tokens to avoid empty embeddings later
lines_norm <- lines_norm %>%
    mutate(token_count = str_count(text_norm, "\\S+")) %>%
    filter(token_count >= 3) %>%
    select(-token_count)

# Quick check
lines_norm %>% slice_head(n = 5)
nrow(lines_norm)  # number of line-docs to embed


# style-preserving norming of line tokens ---- 




