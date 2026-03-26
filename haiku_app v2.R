library(shiny)
library(bslib)
library(bsicons)
library(tidyverse)
library(openai)
library(tidygraph)
library(ggraph)

# ── Load embeddings ───────────────────────────────────────────────────────────
message("Loading haiku embeddings…")
emb_data     <- readRDS("haiku_emb.rds")
haiku_id     <- emb_data$haiku_id
haiku_text   <- emb_data$text
haiku_source <- emb_data$source
haiku_gruen  <- emb_data$gruen_score
emb_norm     <- emb_data$emb_norm
rm(emb_data); gc()
message(sprintf("Loaded %d haikus.", length(haiku_id)))

# ── Syllable counting ─────────────────────────────────────────────────────────
count_syllables <- function(text) {
  text  <- gsub("[^a-zA-Z ]", " ", tolower(text))
  words <- strsplit(trimws(text), "\\s+")[[1]]
  words <- words[nchar(words) > 0]
  if (!length(words)) return(0L)
  n <- 0L
  for (w in words) {
    v <- nchar(gsub("[^aeiou]", "", w))
    if (grepl("[^aeiou]e$", w) && v > 1L) v <- v - 1L  # silent e
    n <- n + max(1L, v)
  }
  n
}

# ── Pre-compute line structure ────────────────────────────────────────────────
message("Computing corpus line syllable structure…")
haiku_split <- strsplit(haiku_text, " / ", fixed = TRUE)
haiku_line2 <- vapply(haiku_split,
                      function(x) if (length(x) >= 2L) x[2L] else NA_character_,
                      character(1L))
haiku_line3 <- vapply(haiku_split,
                      function(x) if (length(x) >= 3L) x[3L] else NA_character_,
                      character(1L))

syl2 <- vapply(ifelse(is.na(haiku_line2), "", haiku_line2),
               count_syllables, integer(1L), USE.NAMES = FALSE)
syl3 <- vapply(ifelse(is.na(haiku_line3), "", haiku_line3),
               count_syllables, integer(1L), USE.NAMES = FALSE)

idx_7syl <- which(!is.na(haiku_line2) & syl2 == 7L)
idx_5syl <- which(!is.na(haiku_line3) & syl3 == 5L)
message(sprintf("Candidates: %d \u00d7 7-syl line 2,  %d \u00d7 5-syl line 3",
                length(idx_7syl), length(idx_5syl)))

# ── Retrieval helpers ─────────────────────────────────────────────────────────
l2_norm <- function(x) x / sqrt(sum(x^2))

LINE_POOL <- 30L   # pool for no-keyword draws
KW_POOL   <- 100L  # pool for keyword interaction

retrieve_haikus <- function(line_text, keyword_text, n_line_only = 2L) {

  input_syl <- count_syllables(line_text)

  if (input_syl == 5L) {
    valid_idx <- idx_7syl
    get_line  <- function(i) haiku_line2[i]
    position  <- "Line 2 \u2014 7 syllables"
  } else if (input_syl == 7L) {
    valid_idx <- idx_5syl
    get_line  <- function(i) haiku_line3[i]
    position  <- "Line 3 \u2014 5 syllables"
  } else {
    return(list(syl_warning = input_syl))
  }

  has_kw   <- is.character(keyword_text) && nchar(trimws(keyword_text)) > 0
  kw_terms <- if (has_kw) {
    parts <- trimws(strsplit(keyword_text, ",")[[1]])
    parts[nchar(parts) > 0]
  } else character(0)

  # One API call for the line (+ keywords if present)
  message("[rh] calling API…")
  t_api    <- proc.time()
  all_vecs <- do.call(rbind, openai::create_embedding(
    model = "text-embedding-3-small",
    input = c(line_text, kw_terms)
  )$data$embedding)
  message(sprintf("[rh] API %.2fs", (proc.time() - t_api)["elapsed"]))

  line_vec <- l2_norm(all_vecs[1, ])

  # Line similarities for full corpus, then restrict to valid syllable index
  all_line_sims   <- as.numeric(emb_norm %*% line_vec)
  valid_line_sims <- all_line_sims[valid_idx]

  if (!has_kw) {

    # ── No keywords: top 3 + 4 randomly drawn from positions 4–30 ────────────
    pool_n    <- min(LINE_POOL, length(valid_idx))
    pool_rank <- order(valid_line_sims, decreasing = TRUE)[seq_len(pool_n)]
    pool_idx  <- valid_idx[pool_rank]
    pool_sims <- valid_line_sims[pool_rank]

    n_top   <- min(3L, pool_n)
    n_drawn <- 7L - n_top

    draw_pool <- if (pool_n > n_top) seq(n_top + 1L, pool_n) else integer(0)
    drawn_sel <- if (length(draw_pool) >= n_drawn) {
      sample(draw_pool, n_drawn)
    } else {
      draw_pool
    }

    sel_pos       <- c(seq_len(n_top), drawn_sel)
    result_idx    <- pool_idx[sel_pos]
    result_sims   <- pool_sims[sel_pos]
    result_type   <- c(rep("line_match", n_top),
                       rep("sampled",    length(drawn_sel)))
    result_labels <- c(paste("Line match", seq_len(n_top)),
                       paste("Nearby",     seq_len(length(drawn_sel))))

  } else {

    # ── Keywords: n line-only + remainder ranked by line × keyword sim ────────
    kw_vec <- l2_norm(colMeans(all_vecs[-1, , drop = FALSE]))

    pool_n    <- min(KW_POOL, length(valid_idx))
    pool_rank <- order(valid_line_sims, decreasing = TRUE)[seq_len(pool_n)]
    pool_idx  <- valid_idx[pool_rank]
    pool_line <- valid_line_sims[pool_rank]

    # Keyword sims for pool only (100 rows: fast)
    pool_kw <- as.numeric(emb_norm[pool_idx, ] %*% kw_vec)

    n_line <- min(n_line_only, pool_n)
    n_kw   <- 7L - n_line

    # Line-only slots: top n_line from pool
    line_idx  <- pool_idx[seq_len(n_line)]
    line_sims <- pool_line[seq_len(n_line)]

    # Keyword-interacted slots: rank remaining pool by line_sim × keyword_sim
    rem       <- seq(n_line + 1L, pool_n)
    combined  <- pmax(0, pool_line[rem]) * pmax(0, pool_kw[rem])
    kw_sel    <- order(combined, decreasing = TRUE)[seq_len(min(n_kw, length(rem)))]
    kw_idx    <- pool_idx[rem[kw_sel]]
    kw_sims   <- pool_line[rem[kw_sel]]

    result_idx    <- c(line_idx, kw_idx)
    result_sims   <- c(line_sims, kw_sims)
    result_type   <- c(rep("line_match",    length(line_idx)),
                       rep("kw_interacted", length(kw_idx)))
    result_labels <- c(paste("Line match",        seq_len(length(line_idx))),
                       paste("Line \u00d7 keyword", seq_len(length(kw_idx))))
  }

  list(
    position   = position,
    input_syl  = input_syl,
    input_line = line_text,
    has_kw     = has_kw,
    results    = tibble(
      label      = result_labels,
      type       = result_type,
      haiku_id   = haiku_id[result_idx],
      line_text  = vapply(result_idx, get_line, character(1L)),
      full_text  = haiku_text[result_idx],
      source     = haiku_source[result_idx],
      gruen      = haiku_gruen[result_idx],
      similarity = round(result_sims, 3)
    )
  )
}

# ── UI helpers ────────────────────────────────────────────────────────────────
full_haiku_html <- function(text) {
  HTML(paste(strsplit(text, " / ", fixed = TRUE)[[1]], collapse = "<br>"))
}

header_class <- function(type, is_sel) {
  if (is_sel) return("bg-primary text-white")
  switch(type,
    line_match    = "bg-light",
    kw_interacted = "bg-info bg-opacity-10",
    sampled       = "bg-success bg-opacity-10",
    "bg-light"
  )
}

# ── Tree plot ─────────────────────────────────────────────────────────────────
make_tree_plot <- function(r) {
  res <- r$results
  n   <- nrow(res)

  trunc28 <- function(x) ifelse(nchar(x) > 28, paste0(substr(x, 1, 28), "\u2026"), x)

  nodes <- data.frame(
    label = c(trunc28(r$input_line), trunc28(res$line_text)),
    type  = c("input", res$type),
    stringsAsFactors = FALSE
  )
  edges <- data.frame(from = rep(1L, n), to = seq(2L, n + 1L))

  y_leaves <- (seq_len(n) - (n + 1) / 2) * 1.4

  g <- tbl_graph(nodes = nodes, edges = edges, directed = TRUE)

  ggraph(g, layout = "manual", x = c(0, rep(2, n)), y = c(0, y_leaves)) +
    geom_edge_link(color = "#bbbbbb", alpha = 0.8) +
    geom_node_label(
      aes(label = label, fill = type),
      size          = 3,
      hjust         = 0.5,
      label.padding = unit(0.35, "lines"),
      label.r       = unit(0.15, "lines"),
      label.size    = 0.2
    ) +
    scale_fill_manual(
      values = c(
        input         = "#3d6b8e",
        line_match    = "#eeeeee",
        kw_interacted = "#d0edf5",
        sampled       = "#d0edd5"
      ),
      guide = "none"
    ) +
    coord_cartesian(clip = "off") +
    theme_void() +
    theme(
      plot.background = element_rect(fill = "#FAFAF8", color = NA),
      plot.margin     = margin(10, 100, 10, 100)
    )
}

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- page_sidebar(
  title = "Haiku Line Retrieval",
  theme = bs_theme(
    version   = 5,
    bg        = "#FAFAF8",
    fg        = "#1a1a1a",
    primary   = "#3d6b8e",
    base_font = font_google("Lora"),
    code_font = font_google("Source Code Pro")
  ),

  sidebar = sidebar(
    width = 290,
    textAreaInput(
      "line_input", "Your line",
      placeholder = "e.g. On a leafless branch",
      rows = 2
    ),
    uiOutput("syl_count_ui"),
    hr(),
    textAreaInput(
      "keyword_input", "Keywords or phrases",
      placeholder = "e.g. silence, the weight of winter",
      rows = 2
    ),
    tags$p(
      class = "text-muted",
      style = "font-size: 0.78em; margin-top: -0.5em;",
      "Separate multiple entries with commas."
    ),
    sliderInput(
      "n_line_only",
      tooltip(
        "Line-only results",
        "With keywords: how many results are based on line similarity alone before keyword interaction kicks in."
      ),
      min = 1, max = 4, value = 2, step = 1
    ),
    hr(),
    input_task_button(
      "retrieve", "Retrieve",
      icon  = bs_icon("search"),
      class = "btn-primary w-100"
    )
  ),

  uiOutput("results_ui")
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  results      <- reactiveVal(NULL)
  selected_idx <- reactiveVal(NULL)

  output$syl_count_ui <- renderUI({
    text <- input$line_input
    if (is.null(text) || nchar(trimws(text)) == 0) return(NULL)
    n   <- count_syllables(trimws(text))
    cls <- if (n %in% c(5L, 7L)) "text-success" else "text-warning"
    lbl <- switch(as.character(n),
      "5" = "5 syllables \u2192 retrieving 7-syllable line 2",
      "7" = "7 syllables \u2192 retrieving 5-syllable line 3",
      sprintf("%d syllables \u2014 enter a 5- or 7-syllable line", n)
    )
    tags$p(class = cls, style = "font-size: 0.78em; margin-top: -0.4em;", lbl)
  })

  observeEvent(input$retrieve, {
    req(nchar(trimws(input$line_input)) > 0)
    results(NULL)
    selected_idx(NULL)

    t0 <- proc.time()
    tryCatch({
      res <- retrieve_haikus(
        line_text    = trimws(input$line_input),
        keyword_text = trimws(input$keyword_input),
        n_line_only  = as.integer(input$n_line_only)
      )
      message(sprintf("[retrieve] done in %.2fs", (proc.time() - t0)["elapsed"]))
      results(res)
    },
    error = function(e) {
      message(sprintf("[retrieve] ERROR: %s", conditionMessage(e)))
      results(list(error = conditionMessage(e)))
    })

    update_task_button("retrieve", session = session)
  })

  output$tree_plot <- renderPlot({
    r <- results()
    req(!is.null(r), is.null(r$syl_warning), is.null(r$error), !is.null(r$results))
    make_tree_plot(r)
  }, bg = "#FAFAF8")

  for (i in 1:7) {
    local({
      ii <- i
      observeEvent(input[[paste0("select_", ii)]], {
        selected_idx(ii)
      }, ignoreInit = TRUE, ignoreNULL = TRUE)
    })
  }

  output$results_ui <- renderUI({

    r <- results()

    if (is.null(r)) {
      return(card(
        height = 280,
        card_body(
          class = "d-flex flex-column align-items-center justify-content-center text-muted gap-3",
          bs_icon("search", size = "2.5em"),
          tags$p("Enter a line and click Retrieve", style = "font-size: 1.1em;")
        )
      ))
    }

    if (!is.null(r$syl_warning)) {
      return(card(card_body(
        class = "text-warning",
        bs_icon("exclamation-triangle"), " ",
        sprintf(
          "Input has ~%d syllables. Enter a 5-syllable line (retrieves line 2) or a 7-syllable line (retrieves line 3).",
          r$syl_warning
        )
      )))
    }

    if (!is.null(r$error)) {
      return(card(card_body(
        class = "text-danger",
        bs_icon("exclamation-triangle"), tags$strong(" Error: "), r$error
      )))
    }

    sel <- selected_idx()
    res <- r$results

    haiku_cards <- lapply(seq_len(nrow(res)), function(i) {
      row    <- res[i, ]
      is_sel <- isTRUE(sel == i)

      card(
        height = 290,
        class  = if (is_sel) "border-primary shadow-sm" else NULL,
        card_header(
          class = header_class(row$type, is_sel),
          style = "font-size: 0.78em; font-weight: 700; letter-spacing: 0.04em;
                   text-transform: uppercase;",
          row$label
        ),
        card_body(
          style = "display: flex; flex-direction: column; justify-content: space-between;",
          tags$p(
            style = "font-family: Georgia, serif; font-style: italic;
                     font-size: 1.05em; line-height: 1.9; margin-bottom: 0.4em;",
            row$line_text
          ),
          tags$p(
            style = "font-family: Georgia, serif; font-size: 0.75em;
                     color: #aaa; line-height: 1.7; margin-bottom: 0.5em;",
            full_haiku_html(row$full_text)
          ),
          tags$div(
            tags$p(
              class = "text-muted",
              style = "font-size: 0.72em; margin-bottom: 0.4em;",
              bs_icon("person"), " ", row$source,
              tags$span(style = "margin-left: 0.5em;",
                        sprintf("sim %.3f", row$similarity)),
              if (!is.na(row$gruen))
                tags$span(style = "margin-left: 0.5em;",
                          sprintf("q %.2f", row$gruen))
            ),
            actionButton(
              inputId = paste0("select_", i),
              label   = if (is_sel) tagList(bs_icon("check2"), " Selected") else "Select",
              class   = if (is_sel) "btn-primary btn-sm w-100"
                        else        "btn-outline-secondary btn-sm w-100"
            )
          )
        )
      )
    })

    selected_ui <- if (!is.null(sel)) {
      row <- res[sel, ]
      card(
        class = "mb-3 border-primary",
        card_header(
          class = "bg-primary text-white",
          bs_icon("bookmark-check-fill"),
          sprintf(" Selected \u2014 %s", r$position)
        ),
        card_body(
          tags$p(
            style = "font-family: Georgia, serif; font-size: 1.1em;
                     line-height: 2; margin-bottom: 0;",
            tags$span(style = "color: #aaa;", r$input_line), tags$br(),
            tags$em(row$line_text)
          ),
          tags$p(
            class = "text-muted",
            style = "font-size: 0.82em; margin-top: 0.4em;",
            bs_icon("person"), " ", row$source, " \u2014 ", row$label
          )
        )
      )
    }

    tagList(
      selected_ui,
      tags$p(
        class = "text-muted mb-2",
        style = "font-size: 0.82em;",
        bs_icon("info-circle"), " Retrieving: ", tags$strong(r$position)
      ),
      card(
        full_screen = TRUE,
        max_height  = "340px",
        card_header(bs_icon("diagram-3"), " Retrieval tree"),
        plotOutput("tree_plot", height = "280px")
      ),
      layout_column_wrap(
        width  = "250px",
        !!!haiku_cards
      )
    )
  })
}

shinyApp(ui, server, options = list(launch.browser = TRUE))
