# Expenses

A native macOS expense tracker. Drop in invoices as PDFs or photos, Claude extracts the data, SwiftData stores it, Swift Charts draws it, and a chat panel (typed or dictated, English or Arabic) answers questions and drives the app.

## Architecture

```
┌──────────────────────────────── Expenses.app (SwiftUI, macOS) ─────────────────────────────────┐
│                                                                                                  │
│  Views                     AppState (@Observable)            Services                            │
│  ┌──────────────┐   period/granularity/category/screen   ┌─────────────────────────────────┐   │
│  │ DashboardView│◀──────────────────────────────────────▶│ ExpenseStore  (all numbers)     │   │
│  │ InvoicesView │                                        │   list · aggregate · total       │   │
│  │ ChatView     │──── text / dictation ────┐             │   add · update · delete          │   │
│  │ SettingsView │                          ▼             ├─────────────────────────────────┤   │
│  │ EvaluationView│                   AgentService ──────▶│ AgentTools (8 tools)            │   │
│  └──────────────┘                     tool loop ≤ 6      ├─────────────────────────────────┤   │
│         ▲                                  │             │ RAGService  (NLEmbedding, local) │   │
│   SpeechService                            │             ├─────────────────────────────────┤   │
│   (SFSpeechRecognizer,                     │             │ InvoiceExtractor + Validator    │   │
│    on-device when possible)                │             │   PDFKit text → record_invoice  │   │
│                                            ▼             └───────────────┬─────────────────┘   │
│                                      ClaudeClient (URLSession) ──────────┘                     │
│                                            │  x-api-key from KeychainStore                      │
│  SwiftData: Expense ──1:n──▶ InvoiceChunk  │                                                    │
└────────────────────────────────────────────┼────────────────────────────────────────────────────┘
                                             ▼
                              POST https://api.anthropic.com/v1/messages
                              extraction: claude-haiku-5-5 · chat: claude-sonnet-5-5
```

Rules the code follows: every number shown or spoken comes from `ExpenseStore`; semantic search is only for what an invoice contains; the agent changes data only through tools, and delete waits for a click; UI state the agent can change lives in `AppState`.

## Requirements

- macOS 14 or later (built and tested on macOS 27 with Xcode 27)
- Xcode 15 or later to build from source
- A Claude API key from console.anthropic.com
- Internet access for the Anthropic API (dictation in Arabic may also use Apple's servers)
- Python 3 only for the optional sample generator and evaluation data tools

## Setup

```sh
git clone <this repo> ExpensesWorkspace
cd ExpensesWorkspace
open Expenses/Expenses.xcodeproj
```

In Xcode, select the Expenses target → Signing & Capabilities and make sure App Sandbox has: Outgoing Connections (Client), Audio Input, and User Selected File set to Read/Write. Under the Info tab the two privacy strings for Microphone and Speech Recognition must be present. Pick your Apple ID as the Team so the Keychain stops asking after each build.

Optional sample data:

```sh
python3 -m venv tools/.venv && tools/.venv/bin/pip install reportlab pypdf pyarrow
tools/.venv/bin/python tools/make_samples.py            # 15 PDFs + ground_truth.json in tools/samples
tools/.venv/bin/python tools/make_samples.py --count 300 --months 24 --out ~/Desktop/bulk
```

## Run

From Xcode: press ⌘R.

From the release zip: unzip `dist/Expenses.zip`, then **right-click Expenses.app → Open** and confirm. The app is signed ad hoc, not notarised, so a plain double-click shows "cannot be opened" the first time. On first launch a sheet asks for the API key: Settings (⌘,), paste the key, Save. macOS will ask once to allow microphone and speech recognition when you first click the microphone.

To rebuild the release: `tools/release.sh`.

## Features

- **Import**: PDFs and images (PNG, JPEG, HEIC and more), three at a time with progress. Text PDFs are read with PDFKit; scans and photos go to Claude as images.
- **Extraction**: a strict `record_invoice` tool returns vendor, VAT number, invoice number, date, amounts, category and line items. Arithmetic and date checks run on every result; a failed check triggers one correction round, and persistent failures get a **Needs review** badge with notes. Duplicates (same vendor and invoice number) ask before saving.
- **Invoices**: sortable table, search, period filter, edit sheet, delete with confirmation.
- **Dashboard**: KPI cards, spending over time, category donut, top vendors, with hover details, period presets, custom date range, and a banner that points to your data when a period is empty.
- **Chat**: ask about totals, periods, categories, vendors and invoice contents; add, update and delete expenses; switch screens and chart settings. Each answer lists the tools, tokens and seconds used.
- **Dictation**: microphone button, live transcript, English or Arabic, on-device recognition where supported.
- **Evaluation** (Tools menu): score extraction against a labelled folder and the agent against six fixed questions; export Markdown.
- **Settings**: API key in Keychain, model names, token usage this session.

## The agent's tools

| Tool | What it does |
|---|---|
| `query_spending` | Totals grouped by day, month, year, category or vendor, or one total, for a date range, category and vendor filter. Source of every number. |
| `list_expenses` | Individual expenses with short ids for follow-up edits. |
| `search_invoices` | Hybrid semantic plus keyword search over invoice text; returns passages with vendor and date. |
| `add_expense` | Manual expense; VAT-inclusive total split at 15% unless given. |
| `update_expense` | Change fields of an expense by id; re-validated on save. |
| `delete_expense` | Marks a deletion pending; the user confirms with a button. |
| `show_chart` | Switch to the dashboard with period, granularity, category or a custom date range. |
| `open_screen` | Show Dashboard or Invoices. |

## Assumptions

- Invoices are mostly Saudi simplified tax invoices in SAR with 15% VAT; other currencies are stored but totals assume one currency.
- One user, one Mac, one database in the app's sandbox container.
- The API key owner is the user; usage is billed to their Anthropic account.

## Limitations

- Needs internet for extraction and chat. Nothing works offline except browsing saved data.
- Sentence embeddings are English-only on device; Arabic invoice text is found mainly by keyword matching.
- The release build is unsigned (ad hoc) and not notarised.
- Evaluation covers 15 generated PDFs and 20 synthetic Saudi receipts, not real-world scans.
- No authentication, sync or multi-user support.

## Next steps

- **Data sovereignty**: route extraction and chat to a self-hosted or in-Kingdom model endpoint; `ClaudeClient` is the single place to swap.
- **Arabic search**: multilingual embeddings (a small on-device model or a hosted embedding API) in `RAGService`.
- **Real-time voice**: streaming responses and barge-in instead of stop-then-send.
- **Authentication and sync**: per-user accounts and CloudKit or a server store for several devices.
- Backlog: `BACKLOG.md`. Dataset notes: `docs/datasets.md`.
