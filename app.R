library(shiny)
library(bslib)
if (!requireNamespace("bsicons", quietly = TRUE)) install.packages("bsicons")
library(bsicons)
library(tidyverse)
library(openai)

# ── Poem ──────────────────────────────────────────────────────────────────────
poem_title  <- "Digging"
poem_author <- "Seamus Heaney"

poem_lines <- tibble(
  line_num = 1:31,
  stanza   = c(1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4,
               5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8),
  text = c(
    "Between my finger and my thumb",
    "The squat pen rests; snug as a gun.",
    "Under my window, a clean rasping sound",
    "When the spade sinks into gravelly ground:",
    "My father, digging. I look down",
    "Till his straining rump among the flowerbeds",
    "Bends low, comes up twenty years away",
    "Stooping in rhythm through potato drills",
    "Where he was digging.",
    "The coarse boot nestled on the lug, the shaft",
    "Against the inside knee was levered firmly.",
    "He rooted out tall tops, buried the bright edge deep",
    "To scatter new potatoes that we picked,",
    "Loving their cool hardness in our hands.",
    "By God, the old man could handle a spade.",
    "Just like his old man.",
    "My grandfather cut more turf in a day",
    "Than any other man on Toner's bog.",
    "Once I carried him milk in a bottle",
    "Corked sloppily with paper. He straightened up",
    "To drink it, then fell to right away",
    "Nicking and slicing neatly, heaving sods",
    "Over his shoulder, going down and down",
    "For the good turf. Digging.",
    "The cold smell of potato mould, the squelch and slap",
    "Of soggy peat, the curt cuts of an edge",
    "Through living roots awaken in my head.",
    "But I've no spade to follow men like them.",
    "Between my finger and my thumb",
    "The squat pen rests.",
    "I'll dig with it."
  )
)

# ── Embeddings ────────────────────────────────────────────────────────────────
# Pre-compute once on startup. To avoid the API call on every launch, save
# after the first run and reload:
#   saveRDS(line_emb, "line_emb.rds")
# Then replace the block below with:
#   line_emb <- readRDS("line_emb.rds")

l2_norm <- function(mat) mat / sqrt(rowSums(mat^2))

message("Computing line embeddings…")
line_emb      <- do.call(rbind, openai::create_embedding(
  model = "text-embedding-3-small",
  input = poem_lines$text
)$data$embedding)
line_emb_norm <- l2_norm(line_emb)
message("Ready.")

# ── Generator ─────────────────────────────────────────────────────────────────
generate_poetic_line <- function(query, n_context = 4) {
  query_vec <- openai::create_embedding(
    model = "text-embedding-3-small", input = query
  )$data$embedding[[1]] |> matrix(nrow = 1)

  sims    <- line_emb_norm %*% t(l2_norm(query_vec))
  top_idx <- order(sims, decreasing = TRUE)[seq_len(n_context)]

  context <- tibble(
    line_num   = poem_lines$line_num[top_idx],
    text       = poem_lines$text[top_idx],
    similarity = round(as.numeric(sims[top_idx]), 3)
  )

  prompt <- paste0(
    "You are writing in the style of '", poem_title, "' by ", poem_author, ".\n\n",
    "The following lines from the poem are most relevant to the theme '", query, "':\n\n",
    paste0("  ", context$text, collapse = "\n"), "\n\n",
    "Write a single new line of poetry in response to the theme: '", query, "'.\n",
    "Match the voice, concrete imagery, and rhythm of the lines above. ",
    "Return only the line itself, nothing else."
  )

  generated <- openai::create_chat_completion(
    model    = "gpt-4o-mini",
    messages = list(list(role = "user", content = prompt))
  )$choices$message.content |> trimws()

  list(query = query, context = context, generated = generated)
}

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- page_sidebar(
  title = paste0(poem_title, " \u2014 Poetic Line Generator"),
  theme = bs_theme(
    version  = 5,
    bg       = "#FAFAF8",
    fg       = "#1a1a1a",
    primary  = "#3d6b8e",
    base_font = font_google("Lora"),
    code_font = font_google("Source Code Pro")
  ),
  sidebar = sidebar(
    width = 300,
    textAreaInput(
      "query", "Theme or image",
      placeholder = "e.g. grief, the weight of inheritance, roots",
      rows = 3
    ),
    sliderInput(
      "n_context", "Lines to retrieve as context",
      min = 1, max = 8, value = 4, step = 1
    ),
    hr(),
    input_task_button(
      "generate", "Generate",
      icon  = bs_icon("feather"),
      class = "btn-primary w-100"
    ),
    hr(),
    # The poem for reference
    accordion(
      open = FALSE,
      accordion_panel(
        "The poem",
        icon = bs_icon("book"),
        tags$div(
          style = "font-family: Georgia, serif; font-size: 0.85em;
                   line-height: 1.8; white-space: pre-wrap;",
          paste(poem_lines$text, collapse = "\n") |>
            # Re-insert blank lines between stanzas
            (\(.) {
              stanza_breaks <- which(diff(poem_lines$stanza) != 0)
              lines <- str_split(., "\n")[[1]]
              for (i in rev(stanza_breaks)) {
                lines <- append(lines, "", after = i)
              }
              paste(lines, collapse = "\n")
            })()
        )
      )
    )
  ),
  # ── Main ──
  uiOutput("result_ui")
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  result <- reactiveVal(NULL)

  observeEvent(input$generate, {
    req(nchar(trimws(input$query)) > 0)

    result(NULL)  # clear previous while loading

    tryCatch(
      result(generate_poetic_line(
        query     = trimws(input$query),
        n_context = input$n_context
      )),
      error = function(e) {
        result(list(error = conditionMessage(e)))
      }
    )
  })

  output$result_ui <- renderUI({

    r <- result()

    # ── Placeholder ──
    if (is.null(r)) {
      return(
        card(
          height = 300,
          card_body(
            class = "d-flex flex-column align-items-center justify-content-center
                     text-muted gap-3",
            bs_icon("feather", size = "2.5em"),
            tags$p("Enter a theme or image and click Generate",
                   style = "font-size: 1.1em;")
          )
        )
      )
    }

    # ── Error ──
    if (!is.null(r$error)) {
      return(
        card(
          card_body(
            class = "text-danger",
            bs_icon("exclamation-triangle"),
            tags$strong(" Error: "),
            r$error
          )
        )
      )
    }

    # ── Result ──
    layout_columns(
      col_widths = c(5, 7),

      # Generated line
      card(
        card_header(
          bs_icon("feather"), " Generated line"
        ),
        card_body(
          tags$blockquote(
            class = "blockquote mb-2",
            style = "font-size: 1.25em; font-style: italic; line-height: 1.7;",
            r$generated
          ),
          tags$p(
            class = "text-muted",
            style = "font-size: 0.85em;",
            bs_icon("tag"), " ", r$query
          )
        )
      ),

      # Retrieved context
      card(
        card_header(
          bs_icon("search"), " Retrieved context"
        ),
        card_body(
          class = "p-0",
          tags$table(
            class = "table table-sm table-hover mb-0",
            tags$thead(
              class = "table-light",
              tags$tr(
                tags$th(style = "width: 2.5em;", "#"),
                tags$th("Line"),
                tags$th(style = "width: 5em; text-align: right;",
                        tooltip(
                          bs_icon("info-circle", title = "About similarity scores"),
                          "Cosine similarity to query"
                        ))
              )
            ),
            tags$tbody(
              lapply(seq_len(nrow(r$context)), function(i) {
                row <- r$context[i, ]
                tags$tr(
                  tags$td(
                    class = "text-muted",
                    row$line_num
                  ),
                  tags$td(
                    style = "font-family: Georgia, serif;",
                    row$text
                  ),
                  tags$td(
                    style = "text-align: right; font-variant-numeric: tabular-nums;",
                    row$similarity
                  )
                )
              })
            )
          )
        )
      )
    )
  })
}

shinyApp(ui, server)
