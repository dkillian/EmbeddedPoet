
prob <- function(x) {
     1 / ( 1 + exp(-x) )
}

logit <- function(p) {
     log( p / (1 - p) )
}

x <- -3:3

prob(x)

plot(x, prob(x), type="b", col="blue", ylim=c(0,1),
     xlab="x", ylab="Probability", main="Logistic Function")

logit(x)

plot(x, logit(prob(x)), type="b", col="red",
     xlab="x", ylab="Logit(Probability)", main="Logit Function")


library(word2vec)

# wondrous sea ---- 

sea <- c(
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

model_sea <- word2vec(
    x = sea,
    type = "skip-gram",   # or "cbow"
    dim = 50,             # embedding size
    window = 5,           # context window
    iter = 30,            # epochs
    min_count = 1,        # keep all words in tiny demo
    negative = 5          # negative sampling
)

# Embedding matrix: rows = words, cols = dimensions

E_sea <- as.matrix(model_sea)

rownames(E_sea)[1:5]  # peek at vocab


# death ---- 

# Suppose you have a poem as a character vector (one line per element)
death <- c(
    "Because I could not stop for Death",
    "He kindly stopped for me",
    "The carriage held but just ourselves",
    "And Immortality"
)

death

# 1. Basic cleaning (lowercase, remove punctuation)
#poem_clean <- tolower(gsub("[^a-z\\s]", " ", poem))
#poem_clean <- gsub("\\s+", " ", poem_clean)
#poem_clean

# 2. Train the model (tiny demo—use more poems for richer results)

?word2vec

model_death <- word2vec(
    x = death,
    type = "skip-gram",
    dim = 50,
    window = 3,
    iter = 50,
    min_count = 1,
    negative = 5
)

E_death <- as.matrix(model_death)

rownames(E_death)

death_df <- E_death %>%
    as.data.frame() %>%
    rownames_to_column("word") %>%
    pivot_longer(cols = -word,
                 names_to = "dimension",
                 values_to = "value")

head(death_df)
    
str(ot)
head(ot)

# Similar words
predict(model_death, 
        newdata = "Death",
        type = "nearest", top_n = 5)

predict(model_sea, 
        newdata = "sea",
        type = "nearest", top_n = 5)

predict(model_death, newdata = "Immortality", type = "nearest", top_n = 5)

death

# pca ---- 

pca_death <- prcomp(E_death, scale. = TRUE)

pca_death_df <- tibble(
    word = rownames(E_death),
    PC1 = pca_death$x[, 1],
    PC2 = pca_death$x[, 2]
)

pca_death_df

ggplot(pca_death_df, aes(PC1, PC2, label = word)) +
    geom_point(size = 3) +
    geom_text(vjust = -0.6) +
    theme_minimal() +
    labs(title = "Word2Vec Embeddings (PCA)")


# umpa ---- 

library(uwot)

umap_coords <- umap(E_death, n_neighbors = 5, min_dist = 0.3)

umap_df <- tibble(
    word = rownames(E_death),
    UMAP1 = umap_coords[, 1],
    UMAP2 = umap_coords[, 2]
)

umap_df

ggplot(umap_df, aes(UMAP1, UMAP2, label = word)) +
    geom_point(size = 3) +
    geom_text(vjust = -0.6) +
    theme_minimal() +
    labs(title = "Word2Vec Embeddings (UMAP)")




