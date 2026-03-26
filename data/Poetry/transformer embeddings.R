# transformer embeddings

library(reticulate)

transformers <- import("transformers")

torch <- import("torch")


# helpers

`%||%` <- function(x, y) if (is.null(x)) y else x

pool_mean <- function(X) { # X: tokens x dim numeric matrix
    if (nrow(X) == 0) return(rep(NA_real_, ncol(X)))
    colMeans(X)
}

# core function

embed_poems_token_first <- function(
        poems_lines,                # named list: poem_id -> character vector of lines
        model_name = "distilbert-base-uncased",
        device = NULL,              # "cpu" or "cuda"; NULL auto
        token_pool = c("mean"),     # (for now) mean pooling
        line_pool  = c("mean")      # (for now) mean pooling
) {
    token_pool <- match.arg(token_pool)
    line_pool  <- match.arg(line_pool)
    
    # Load tokenizer + model (one encoder)
    tok <- transformers$AutoTokenizer$from_pretrained(model_name, use_fast = TRUE)
    mdl <- transformers$AutoModel$from_pretrained(model_name)
    mdl$eval()
    
    # choose device
    if (is.null(device)) {
        device <- if (torch$cuda$is_available()) "cuda" else "cpu"
    }
    
    dev <- torch$device(device)
    mdl$to(dev)
    
    tokens_out <- list()
    line_vecs  <- list()
    poem_vecs  <- list()
    
    for (poem_id in names(poems_lines)) {
        lines <- poems_lines[[poem_id]]
        if (length(lines) == 0) next
        
        line_mat <- NULL
        
        for (i in seq_along(lines)) {
            line_text <- lines[[i]]
            
            # tokenize
            enc <- tok(
                line_text,
                return_tensors = "pt",
                truncation = TRUE,
                max_length = as.integer(512),
                add_special_tokens = TRUE
            )
            
            input_ids <- enc$input_ids$to(dev)
            attn_mask <- enc$attention_mask$to(dev)
            
            # forward pass -> last_hidden_state: [1, seq_len, hidden_dim]
            with(torch$no_grad(), {
                out <- mdl(input_ids = input_ids, attention_mask = attn_mask)
            })
            hs <- out$last_hidden_state  # torch tensor
            
            # move to cpu and convert to R matrix
            hs_cpu <- hs$detach()$cpu()
            ids_cpu <- input_ids$detach()$cpu()
            
            # squeeze batch dim
            hs_mat <- hs_cpu$squeeze(as.integer(0))$numpy()
            ids_vec <- as.integer(ids_cpu$squeeze(as.integer(0))$numpy())
            
            # tokens as strings (WordPiece/BPE; includes special tokens)
            toks <- tok$convert_ids_to_tokens(as.list(ids_vec))
            toks <- unlist(toks)
            
            # drop special tokens + keep ordering
            special <- tok$all_special_tokens
            keep <- !(toks %in% special)
            
            toks_keep <- toks[keep]
            hs_keep   <- hs_mat[keep, , drop = FALSE]
            
            # store token-level table (one row per token)
            if (length(toks_keep) > 0) {
                tokens_out[[length(tokens_out) + 1]] <- data.frame(
                    poem_id = poem_id,
                    line_no = i,
                    token_no = seq_along(toks_keep),
                    token = toks_keep,
                    stringsAsFactors = FALSE
                )
                # store embeddings separately for efficiency
                attr(tokens_out[[length(tokens_out)]], "embeddings") <- hs_keep
            }
            
            # pool token -> line
            line_vec <- pool_mean(hs_keep)
            line_mat <- rbind(line_mat, line_vec)
        }
        
        rownames(line_mat) <- paste0(poem_id, "::line", seq_len(nrow(line_mat)))
        line_vecs[[poem_id]] <- line_mat
        
        # pool line -> poem
        poem_vecs[[poem_id]] <- pool_mean(line_mat)
    }
    
    # Combine token tables and embeddings into one structure
    token_df <- if (length(tokens_out)) do.call(rbind, tokens_out) else data.frame()
    
    token_emb <- NULL
    if (nrow(token_df) > 0) {
        token_emb <- do.call(rbind, lapply(tokens_out, function(d) attr(d, "embeddings")))
    }
    
    line_mat_all <- if (length(line_vecs)) do.call(rbind, line_vecs) else matrix(numeric(0), 0, 0)
    poem_mat_all <- if (length(poem_vecs)) {
        m <- do.call(rbind, poem_vecs)
        rownames(m) <- names(poem_vecs)
        m
    } else matrix(numeric(0), 0, 0)
    
    structure(
        list(
            model_name = model_name,
            device = device,
            encoder = list(tokenizer = tok, model = mdl),
            tokens = list(data = token_df, embeddings = token_emb),
            lines  = line_mat_all,
            poems  = poem_mat_all,
            pooling = list(token_to_line = "mean", line_to_poem = "mean")
        ),
        class = "poem_embed_model"
    )
}


death <- c(
    "Because I could not stop for Death",
    "He kindly stopped for me",
    "The carriage held but just ourselves",
    "And Immortality"
)

death

death_lines

poems_lines <- list(poem_death = death)
poems_lines

emb <- embed_poems_token_first(
    poems_lines,
    model_name = "distilbert-base-uncased"  # change if you want
)

str(emb, max.level=2)
emb[3]

# token embeddings
head(emb$tokens$data)
dim(emb$tokens$embeddings)

death_wrds <- emb$tokens$data %>%
    mutate(id=1:nrow(.),
           id2=paste(line_no, token_no, sep="-"))

tmp <- death_wrds %>%
    select(id, id2, "word" = token)

tmp
str(tmp)

death_wrds_emb <- emb$tokens$embeddings %>%
    as.data.frame() %>%
    rownames_to_column(var="id") %>%
    mutate(id=as.integer(id)) %>%
    left_join(tmp) %>%
    select(id, id2, word, everything())

death_wrds_embL <- death_wrds_emb %>%
    pivot_longer(cols=-c(id, id2, word),
                 names_to="dim2",
                 values_to="value") %>%
    mutate(dim=as.integer(str_sub(dim2, 2))) %>%
    select(id, id2, word, dim, value)

head(death_wrds_embL)

# line embeddings

death

death_wrds

death_lines2 <- death_wrds %>%
    group_by(line_no) %>%
    reframe(line=paste(token, collapse=" "))

death_lines2

dim(emb$lines)

death_line_emb <- emb$lines %>%
    as_tibble() %>%
    mutate(line_no=1:4) %>%
    select(line_no, everything())

head(death_line_emb)

death_line_embL <- death_line_emb %>%
    pivot_longer(cols=-line_no,
                 names_to="dim2",
                 values_to="value") %>%
    mutate(dim=as.integer(str_sub(dim2,2))) %>%
    select(line_no, dim, value) %>%
    arrange(line_no, dim) %>%
    left_join(death_lines2) 

head(death_line_embL)
death_lines2

# poem embeddings
dim(emb$poems)
emb$poems["poem_death", ][1:10]



# Do the most salient tokens and lines correspond to the poem's themes? ---- 

poem_vec <- emb$poems["poem_death", ]
poem_vec

salient_lines(emb, "poem_death", poem_vec, top_n = 4)





# FUNCTIONS ---- 

# cosine ---- 

cosim <- function(A, v) {
    v <- as.numeric(v)
    (A %*% v) / (sqrt(rowSums(A^2)) * sqrt(sum(v^2)))
}

# salient tokens ----

salient_tokens <- function(emb, poem_id, line_no, target_vec, top_n = 20) {
    idx <- which(emb$tokens$data$poem_id == poem_id & emb$tokens$data$line_no == line_no)
    X <- emb$tokens$embeddings[idx, , drop = FALSE]
    s <- drop(cosim(X, target_vec))
    
    out <- emb$tokens$data[idx, c("poem_id","line_no","token_no","token")]
    out$salience <- s
    out[order(out$salience, decreasing = TRUE), ][seq_len(min(top_n, nrow(out))), ]
}

# salient lines ---- 

salient_lines <- function(emb, poem_id, target_vec, top_n = 5) {
    # rows for this poem (based on your rowname scheme "poem_id::lineK")
    rows <- grepl(paste0("^", poem_id, "::"), rownames(emb$lines))
    X <- emb$lines[rows, , drop = FALSE]
    s <- drop(cosim(X, target_vec))
    
    data.frame(
        line_row = rownames(X),
        salience = s,
        stringsAsFactors = FALSE
    )[order(-s), ][seq_len(min(top_n, nrow(X))), ]
}






### text package (line / poem embeddings) ---- 

library(text)

# text::textrpp_install() 
# run once per install or reset of environments

sea <- c( # line by line
    "On this wondrous sea,",
    "Sailing silently,",
    "Ho! pilot, ho!",
    "Knowest thou the shore",
    "Where no breakers roar,",
    "Where the storm is o'er?",
    "In the silent west",
    "Many sails at rest,",
    "Their anchors fast;",
    "Thither I pilot thee, -",
    "Land, ho! Eternity!",
    "Ashore at last!")

sea

sea2 <- "On this wondrous sea,
Sailing silently,"

sea2

?writeLines
