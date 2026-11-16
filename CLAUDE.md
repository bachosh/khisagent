# Project memory: KhisAgent

AI assistant for credit risk managers: upload a client's bank account statement (CSV, XLSX/XLS,
text PDF, scanned PDF or photo), get a credit risk report, and chat about the statement.
Meant to be sold as SaaS. Rails 8.1, SQLite, Hotwire, Dart Sass, Propshaft, importmap.

## Local LLM: Ollama (same setup as ../khisfari)

- `http://localhost:11434`, model `gemma4:12b` (text + vision + tools). Override with `OLLAMA_URL`,
  `OLLAMA_MODEL`, `OLLAMA_NUM_CTX` (default 65536), `OLLAMA_NUM_PREDICT` (default 6144).
- All settings in `config/initializers/llm.rb`; build clients only via `LLM.agent_client` / `LLM.chat`
  (`app/services/llm.rb`). One num_ctx for every request: Ollama reloads the model when it changes.
- **Agents run with `think: false`** (report temperature 0.3, chat 0.4). With thinking on, gemma4:12b
  sometimes loops (repeating Georgian words) until num_predict; runs took 20-300s instead of ~12s.
- `num_predict` must stay set: without it a looping reply fills the whole context (minutes).
- Structured extraction uses Ollama `format` (JSON schema) on `/api/chat`; images go in `messages[].images`.

## Agent framework

Copied from ../khisfari (`app/services/agent/`, see AGENT_FRAMEWORK.md): GAME architecture, Runner,
FunctionCalling, ToolRegistry, SystemTools. Added here: `Agent::ProgressEnvironment` (UI progress per tool),
`Agent::Tools::StatementTools` (per-run registry bound to one user's statements, like AccessLogTools).

## Code layout: one folder (and module) per domain

| Domain | Models (tables) | Controllers / views | Services / jobs |
|---|---|---|---|
| `Chat::` | Conversation, Message (`chat_*`) | `chat/conversations`, `chat/messages` | `Chat::Submission`, `Chat::Responder`, `Chat::ReplyJob` |
| `Analysis::` | Statement, Operation, RiskReport (`analysis_*`) | `analysis/statements` (reports) | importer, parsers, metrics, risk agent, `Analysis::ProcessingJob` |
| `Auth::` | — (User, Session, Current stay top-level: Rails auth) | `auth/sessions`, `passwords`, `registrations`, `profiles` | — |

`app/models/chat.rb` / `analysis.rb` set `table_name_prefix` and `use_relative_model_naming?`, so routes,
params and dom ids stay short (`statement_path`, `params[:statement]`, `"statement_9"`); routes use
`scope module:`, URLs have no prefix. Cross-domain associations need `class_name:`. Partials are rendered
by full path (`"analysis/statements/statement"`). New domain code goes into the matching folders.

## Pipeline (`app/services/analysis/`)

Upload (`Chat::Submission`) → `Analysis::ProcessingJob` → `Analysis::Processor`:
1. `Importer`: `TableReader` + `TableMapper` (header keywords ka/en/ru; LLM maps columns only as fallback);
   text PDFs → `PdfLayoutParser` (no LLM: date-started rows, amounts by column position under each page's
   header; 36 pages in 0.3s vs 9-17 min with the LLM; verified on Bank of Georgia and TBC layouts — add a
   synthetic test per new bank layout in `pdf_layout_parser_test.rb`), `LLMExtractor` only if the layout is unknown or totals don't
   reconcile; scans/photos → pdftoppm images + `LLMExtractor` (vision). A reply cut at num_predict is split
   and re-read. Limits: 300 text pages, 40 scanned pages.
   `Reconciler` checks every import (opening + operations = closing per currency, or running balance) →
   `statement.reconciliation` ok/mismatch/unknown, shown on the report and given to the agent.
2. Stage I `Categorizer`: MCC → ISO 8583 processing code → keywords. Codes, categories and groups live in
   **`config/bank_codes.yml`, transcribed from the risk team's notes in `tmp/bankcodes/`** — use those
   files for codes, extend the yml, don't hardcode codes in Ruby. MCC 6051 is crypto only with a crypto merchant name.
3. Stage II `Metrics`: the 8 indicators from the notes, monthly table, the 4 warning trends,
   lenders, and a transparent rule-based `indicator_score` (starting point for the agent).
4. `RiskAgent` → `submit_risk_report` → `RiskReport` (score 0-100, level, recommendation, findings).
   Evidence ids are filtered to operations the model was actually shown (it invented ids before).
5. A summary message is posted to the chat. `Chat::ReplyJob` waits for files, then `Chat::Responder` answers.

Statements/messages broadcast Turbo Streams to the conversation (`turbo_stream_from @conversation`).
Dev uses the in-process async job adapter: a server restart loses running jobs (`Statement#stalled?` → retry button).

## UI

- Layout grid from khisfari (header, left-nav = chat history, messages-header = flash, main-header,
  main-content, right-nav = insights panel). SCSS: `abstracts/` (tokens incl. dark mode), `ganlageba/`,
  `componentebi/`, `pages/`. Components use only CSS custom properties from `abstracts/_tokens.scss`.
- Icons: Heroicons outline in `app/assets/svgs/`, `svg_icon("name")`. Fonts self-hosted (Inter, Noto Sans Georgian).
- i18n: `ka` (default) and `en`, `config/locales/{ka,en}.yml`; user.locale also sets the report language.
- Charts: plain HTML/CSS (cash flow uses validated categorical slots 1-2, blue/orange; table view below).

## Run / test

- `bin/dev` (server + css watch), `bin/rails db:seed` → demo@khisagent.ge / password123.
- Sample statement: `test/fixtures/files/sample_statement.{csv,xlsx}` (`script/generate_sample_statement.rb`).
- LAN testing: `BIND=0.0.0.0 bin/dev`; `lib/local_network_only.rb` (development only) admits only this PC
  and the Wi-Fi subnet (override `LAN_NETWORKS`).
- `bin/rails test` — no Ollama needed. Time zone Tbilisi. Production Docker image needs poppler-utils (added).
