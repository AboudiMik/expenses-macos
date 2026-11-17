# Expenses

A native macOS expense tracker. Drop in invoices as PDFs or photos, Claude extracts the data, SwiftData stores it, Swift Charts draws it, and a chat panel (typed or dictated, English or Arabic) answers questions and drives the app.

## Architecture

How a question or an invoice moves through the app:

1. **Input**: a file picked in InvoicesView, or a message typed or dictated in ChatView
   (SpeechService turns speech into text on device where possible).
2. **Extraction**: InvoiceExtractor reads PDF text with PDFKit or sends the image, calls
   Claude with the strict `record_invoice` tool, validates the result, and corrects once.
3. **Storage**: ExpenseStore saves the Expense in SwiftData; RAGService chunks and embeds
   its text on device (NLEmbedding) as InvoiceChunk rows.
4. **Numbers**: DashboardView and the agent both read totals only from ExpenseStore
   (`list`, `aggregate`, `total`).
5. **Chat**: AgentService runs a Claude tool loop (max 6 steps) over AgentTools, which call
   ExpenseStore and RAGService or change AppState (period, granularity, category, screen).
6. **UI**: SwiftUI views observe AppState and the models, so a tool call updates the screen.

```
 Views ───────────────┐         AppState (@Observable)
 Dashboard · Invoices │◀──────── period · granularity · category · screen
 Chat · Settings      │                 ▲
 Evaluation           │                 │ show_chart / open_screen
          │           ▼                 │
   SpeechService   AgentService ──▶ AgentTools (8 tools)
   (on device)        │                 │
                      │        ┌────────┴────────┐
                      │        ▼                 ▼
                      │   ExpenseStore      RAGService (NLEmbedding, on device)
                      │   (all numbers)          │
                      │        │                 │
                      │   SwiftData: Expense 1─n InvoiceChunk
                      ▼
   InvoiceExtractor + InvoiceValidator ──▶ ClaudeClient (URLSession + Keychain)
   (PDFKit text or image)                      │
                                               ▼
                       POST https://api.anthropic.com/v1/messages
                       extraction: claude-haiku-5-5 · chat: claude-sonnet-5-5
```

Rules the code follows: every number shown or spoken comes from `ExpenseStore`; semantic search is only for what an invoice contains; the agent changes data only through tools, and delete waits for a click; UI state the agent can change lives in `AppState`.

## Requirements

- macOS 15 or later to run (the release build sets a 15.0 minimum; the source also compiles for 14.0 but was not tested there). Built and tested on macOS 27.
- Xcode 27 to build from source: the project uses Xcode 27's project format and Swift 6.2 language features
- A Claude API key from console.anthropic.com
- Internet access for the Anthropic API (dictation in Arabic may also use Apple's servers)
- Python 3 only for the optional sample generator and evaluation data tools

## Setup

```sh
git clone https://github.com/AboudiMik/expenses-macos.git ExpensesWorkspace
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

From the release zip: unzip `dist/Expenses.zip` and **double-click Expenses.app**. macOS will say it cannot verify the developer, because the app is signed ad hoc and not notarised. Click Done, then open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** next to Expenses, and confirm. This is needed once. On first launch a sheet asks for the API key: Settings (⌘,), paste the key, Save. macOS will ask once to allow microphone and speech recognition when you first click the microphone.

To rebuild the release: `tools/release.sh`.

### For reviewers

The app needs a Claude API key, which is sent to you separately from this zip and repository. It is a temporary key in a capped workspace and will be revoked after the review, so it is safe to try freely.

1. Unzip `Expenses.zip` and double-click **Expenses.app**. When macOS says it cannot verify the developer, click Done, then go to **System Settings → Privacy & Security**, click **Open Anyway**, and confirm. Once only.
2. On the welcome sheet click **Open Settings** (or press ⌘,), paste the key, click **Save key**. It is stored in your Keychain; nothing is written to disk in plain text.
3. Click **Import** and pick a few PDFs from `tools/samples`, then try the chat: "How much did I spend last month?", "Show my spending by category for all time", "What did I buy from Nahdi Pharmacy?"
4. Click the microphone, say a question, click stop. Allow microphone and speech recognition when macOS asks.
5. **Tools → Evaluation…** runs the extraction test on `tools/eval_images` and the agent test, and exports a Markdown report.

The sample PDFs are generated and fictional; the evaluation receipts are synthetic documents from the Bayanat Labs dataset (CC BY 4.0).

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
- The release build is unsigned (ad hoc) and not notarised, so the first launch goes through Privacy & Security → Open Anyway.
- Evaluation covers 15 generated PDFs and 20 synthetic Saudi receipts, not real-world scans.
- No authentication, sync or multi-user support.

## Next steps

- **Data sovereignty**: route extraction and chat to a self-hosted or in-Kingdom model endpoint; `ClaudeClient` is the single place to swap.
- **Arabic search**: multilingual embeddings (a small on-device model or a hosted embedding API) in `RAGService`.
- **Real-time voice**: streaming responses and barge-in instead of stop-then-send.
- **Authentication and sync**: per-user accounts and CloudKit or a server store for several devices.
- Backlog: `BACKLOG.md`. Dataset notes: `docs/datasets.md`.
