# KhisAgent

AI bank statement analysis for credit risk managers. Upload a loan applicant's account statement
(CSV, Excel, PDF or a photo/scan), get a credit risk report with a score, indicators and evidence,
and ask follow-up questions in a chat. Runs entirely on a local Ollama model: statements never leave the server.

## Requirements

- Ruby 4.0.8, SQLite
- Ollama with `gemma4:12b` on `http://localhost:11434`
- `poppler-utils` (pdftotext, pdftoppm, pdfinfo) for PDF statements

## Start

```bash
bundle install
bin/rails db:prepare db:seed     # demo@khisagent.ge / password123
bin/dev                          # http://localhost:3000
```

Upload `test/fixtures/files/sample_statement.csv` to see a full analysis.

## Configuration

| Variable | Default | |
|---|---|---|
| `OLLAMA_URL` | `http://localhost:11434` | Ollama server |
| `OLLAMA_MODEL` | `gemma4:12b` | needs tools + vision |
| `OLLAMA_NUM_CTX` | `65536` | context window |
| `OLLAMA_NUM_PREDICT` | `6144` | max tokens per reply |

Operation codes (MCC, ISO 8583 processing codes) and the risk indicators are in `config/bank_codes.yml`.

## Tests

```bash
bin/rails test        # does not need Ollama
```

See `CLAUDE.md` for the architecture and `AGENT_FRAMEWORK.md` for the agent loop.
