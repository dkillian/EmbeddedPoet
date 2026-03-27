# Presidential Speeches — Session Log

---

## Session 1 — March 26, 2026

### What We Worked On
- Established project memory and documentation infrastructure for the presidential speeches qualitative coding activity.
- Explored the existing folder structure, scripts, and data files to reconstruct project context.

### What Was Decided
- Memory/documentation files will be scoped to individual activities (not stored at the workspace root), since the Embedded Poet workspace contains multiple NLP activities.
- Standard folder convention for well-defined activities: `scripts/`, `data/`, `viz/`, `tables/`, `models/`.
- Internal documentation file named `PresidentialSpeechesDocumentation.md` (distinct from a future public-facing GitHub `README.md`).
- PAP subtopics do not need to be duplicated in the documentation file — they live in `data/policy_agendas_codebook.csv`.
- Session logs (`PresidentialSpeechesLog.md`) and conversation transcripts (`PresidentialSpeechesConversations.md`) will be maintained going forward to track the evolution of the work.
- Memory files will use descriptive names rather than the default `AGENTS.md`.

### What Was Created
- `PresidentialSpeechesDocumentation.md` — internal reference file covering project overview, folder convention, file locations, PAP major topic codes, coding pipeline summary, and existing dataset description.
- `PresidentialSpeechesLog.md` — this file.
- `PresidentialSpeechesConversations.md` — running conversation transcript.

### Risks & Uncertainties
- The coding pipeline (`code_speech_passages.R`) currently only handles `.txt` files, but ~1,055 of the 1,059 speech files in `data/raw text/` are `.json`. A JSON parsing path does not yet exist.
- No coded output has been produced yet — the pipeline has not been run end-to-end.
- `tables/` and `models/` subdirectories do not yet exist.
- A public-facing GitHub `README.md` has not been written.

### Steps for Next Session
- Decide on scope: which speeches to code first (e.g., a single president, a single speech type, or a test run on one speech).
- Extend or rewrite the parsing step to handle `.json` speech files.
- Run the pipeline end-to-end on a single speech to validate output.
- Consider creating `tables/` and `models/` subdirectories.

---

## Session 2 — March 26, 2026

### What We Worked On
- Parsed Coolidge's "The Things That Are Unseen" (1923) into clean, analysis-ready objects.
- Built and ran a full pipeline: sentence segmentation → thematic passage grouping via GPT-4o → PAP topic coding via GPT-4o.
- Established script naming conventions and workflow discipline.

### What Was Decided
- Scripts follow a numbered stage convention: `01_clean_*`, `02_analyze_*`, `03_report_*`.
- All code produced in a session goes into a script unless otherwise specified.
- "Things Unseen" is a test case for a pipeline intended to generalize to the full 1,059-speech corpus. Scripts should be written with that generalizability in mind.
- Passage segmentation should operate at the sentence level (not paragraph level) to allow thematic boundaries to fall anywhere in the text.
- Passages and coded results are saved as separate `.rds` files so expensive API calls are not re-run unnecessarily.
- **Primary analytical interest is theme** — how themes emerge, evolve, and vary across presidents and speeches. PAP policy codes are scaffolding to help train the assistant, not the end goal.
- Up to 5 PAP codes per passage (with NA padding for unused slots); fewer codes are fine.

### What Was Created
- `scripts/01_clean_things_unseen.R` — parses speech, creates paragraph and sentence tibbles, saves to `data/`
- `scripts/02_analyze_things_unseen.R` — loads sentences, groups into passages, assigns PAP codes, saves to `data/`
- `data/things_unseen_paragraphs.rds` — 25-row tibble: `para_id`, `paragraph`
- `data/things_unseen_sentences.rds` — 182-row tibble: `para_id`, `sent_id`, `sentence`
- `data/things_unseen_passages.rds` — 22-row tibble: `passage_id`, `sent_ids`, `para_ids`, `theme`, `text`
- `data/things_unseen_coded.rds` — 22-row tibble: passages + up to 5 PAP code columns
- Updates to `scripts/code_speech_passages.R`:
  - Added 4 new OCR artifact fixes (`~hey`, `def enders`, `selfexpression`, `connnunity`)
  - Expanded `code_passage()` from 3 to 5 PAP codes
  - Added `group_sentences()` function for sentence-level passage grouping
  - Added exponential backoff retry logic to `code_passage()` for rate limit handling

### Risks & Uncertainties
- The TPM rate limit (30,000 tokens/min) is a bottleneck — manageable for a single speech but will need a more robust throttling strategy at corpus scale.
- The `parse_speech_passages()` function only handles `.txt` files; the vast majority of the corpus (~1,055 of 1,059 speeches) are `.json` files. A JSON parsing path is still needed.
- The 3-second delay between API calls is a rough fix; a more principled rate management approach will be needed for the full corpus.
- Passages 6 and 21 returned all-NA PAP codes (philosophical/spiritual content with no PAP policy mapping) — this will recur across the corpus and should be handled gracefully in analysis.

### Additional Work (Session Close)
- User reviewed the two all-NA passages and proposed manual codes.
- Two custom subcodes added to `policy_agendas_codebook.csv` under Education (major code 6):
  - **610 — Epistemic Humility** (passage 6: on humility, the limits of knowledge, scholarly self-awareness)
  - **611 — Education for Moral and Spiritual Development** (passage 21: the climactic passage calling for spiritual development, moral power, character, and culture over material progress)
- Confirmed that passage 6 is a weaker fit for 611 — its focus is epistemic rather than broadly moral/spiritual.
- Important clarification: **the project is building a custom thematic coding scheme** that uses PAP as a starting scaffold. PAP comparability with external datasets is not a concern. Custom codes will be added as needed as the corpus reveals themes that PAP does not capture.
- `things_unseen_coded.rds` re-saved with corrected codes.
- Manual corrections captured as a permanent step in `02_analyze_things_unseen.R`.

### Steps for Next Session
- Examine the 22 coded passages more closely — are the thematic groupings sensible?
- Begin work on a JSON speech parser to unlock the bulk of the corpus.
- Begin thinking about how to generalize `01_clean_*` and `02_analyze_*` into corpus-wide pipeline functions.
- Consider whether additional custom codes are needed as more speeches are processed.

---

## Session 3 — March 27, 2026

### What We Worked On
- Resumed after a session interruption; reconstructed context from transcript and log files.
- Continued user-defined passage coding for "The Things That Are Unseen": added passage 3 (sents. 171–177) — the rhetorical climax of the speech.
- Consolidated all "Things Unseen" user passages into `things_unseen_coded.rds` alongside the GPT-grouped passages.
- Began work on a second Coolidge speech: "Declaration of Independence Anniversary Commemoration" (July 5, 1926).
- Added `parse_json_speech()` to `code_speech_passages.R` to handle the JSON corpus format.
- Ran a full GPT first pass on the Declaration speech: sentence grouping (23 passages) and PAP coding.

### What Was Decided
- The custom thematic scheme is the primary analytical lens; PAP is retained as a reference baseline but codes are expected to be overwritten or supplemented.
- Custom themes are stored in `custom_theme_1` through `custom_theme_5` columns alongside PAP code columns.
- Three custom theme labels established for "Things Unseen": **"Pre-industrial labor as artistic expression"** (sents. 32–40), **"The artisan as guardian of liberty"** (sents. 41–44), and **"Education for Moral and Spiritual Development"** (sents. 171–177).
- What began as a single passage (sents. 32–44) was split into two when it became clear each theme applied most precisely to a distinct sentence range.
- **Open question (to revisit each session):** When two themes co-occur in a passage, should they be combined into one passage with multiple codes, or split into separate passages for tighter attribution? Splitting favors precision in idea-tracking; combining preserves argumentative arcs.
- "The Things That Are Unseen" is complete for now. Work on user-defined passages for the Declaration speech will begin next session.

### What Was Created
- `data/things_unseen_passages_user.rds` — user-defined passages tibble (3 passages) with PAP codes and custom theme columns
- Updated `data/things_unseen_coded.rds` — now 24 rows: 22 GPT passages + 3 user passages, with `source` column
- Updated `data/things_unseen_sentences.rds` — now includes `para_sent_id` and `sent_seq`
- Updated `scripts/01_clean_things_unseen.R` — generates the two new identifier columns
- `scripts/01_clean_declaration.R` — parses Declaration speech JSON into paragraphs and sentences
- `scripts/02_analyze_declaration.R` — GPT grouping and PAP coding pipeline for the Declaration speech
- `data/declaration_paragraphs.rds` — 31-row tibble: `para_id`, `paragraph`
- `data/declaration_sentences.rds` — 207-row tibble: `para_sent_id`, `sent_seq`, `para_id`, `sent_id`, `sentence`
- `data/declaration_passages.rds` — 23-row tibble: GPT-grouped passages with themes
- `data/declaration_coded.rds` — 23-row tibble: passages + PAP codes + custom_theme columns (all NA, pending user input)
- Updated `scripts/code_speech_passages.R` — added `parse_json_speech()` function

### Risks & Uncertainties
- PAP codes are a poor fit for founding-era philosophical and religious content; they are particularly unhelpful for the Declaration speech. Custom themes will do the real work.
- GPT passage 7 in "Things Unseen" (sents. 29–44) overlaps with user passages 1 and 2 (32–40 and 41–44). This will need to be addressed in corpus-level analysis.
- Rate limiting from the OpenAI API was encountered during the Declaration coding pass; the exponential backoff handled it, but a more principled throttling strategy will be needed at corpus scale.
- A dedicated analysis script (`02_analyze_things_unseen_user.R`) for the user passage workflow still needs to be created.

### Steps for Next Session
- Begin user-defined passage coding for the Declaration of Independence speech.
- Revisit the split-vs-combine question as new passages are added.
- Create `scripts/02_analyze_things_unseen_user.R` to formalize the user passage workflow.
- Consider whether a growing custom theme vocabulary needs its own reference file (analogous to `policy_agendas_codebook.csv`).
- Begin thinking about generalizing the clean and analyze scripts into corpus-wide pipeline functions.
