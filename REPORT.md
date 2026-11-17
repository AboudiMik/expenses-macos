# Expenses — project report

Native macOS expense tracker with AI extraction and an AI chat assistant. Built on 17 November 2026 in one day, from an empty folder, with Claude Code driving the implementation under a written specification (`CLAUDE.md`).

## 1. What was built

| Area | Delivered |
|---|---|
| Import and extraction | PDF and image invoices, three in parallel; PDFKit text for digital PDFs, vision for scans and photos; a strict JSON-schema tool returns twelve fields; arithmetic, VAT-rate and date validation; one self-correction round; review flags; duplicate detection |
| Storage | SwiftData models `Expense` and `InvoiceChunk`, Keychain for the API key |
| Dashboard | KPI cards, spending over time on a date axis, category donut, top vendors, hover details, four period presets plus a custom range, category filter |
| Invoices | Sortable table, search, period filter, badge for items needing review, edit sheet, confirmed delete |
| Chat agent | Tool-use loop (max 6 steps) with eight tools; session history; pending-delete confirmation; tokens and seconds per answer |
| Semantic search | 500-character chunks embedded on device with `NLEmbedding`; hybrid cosine plus keyword scoring; keyword fallback |
| Dictation | `SFSpeechRecognizer` and `AVAudioEngine`, live transcript, English and Arabic, auto-send on stop |
| Quality and cost | Model routing (Haiku 5.5 for extraction, Sonnet 5.5 for chat), token usage per answer and per session, an Evaluation window with extraction and agent tests and Markdown export |
| Tooling | Sample invoice generator with ground truth, dataset preparation script, release script |

About 2,900 lines of Swift in 36 files, each under 200 lines, plus three Python tools.

## 2. How it works

**Import.** `InvoiceImporter` takes the picked files and runs up to three `InvoiceExtractor` tasks at once. For a PDF with text, PDFKit's text is sent as a message; otherwise the file goes as a base64 document or image block. The system prompt describes Saudi simplified tax invoices, tells the model to call the `record_invoice` tool, and names the watermarks found on sample data so they are not mistaken for a reason to refuse. The tool uses a strict schema, so the arguments are guaranteed to match. The result passes through `InvoiceValidator` (subtotal + VAT = total within 0.05, VAT ≈ 15%, date within the last five years and not in the future, vendor and total present). On failure the checks are returned to the model as the tool result and it re-reads once; if it still fails, the expense is saved with `needsReview` and notes. `ExpenseStore.add` saves the expense and `RAGService.index` chunks and embeds its text.

**Numbers.** Every figure on screen or in chat comes from `ExpenseStore`: `list`, `aggregate(by:)`, `total`. The dashboard reads them through `DashboardData.load`, and the agent reads them through the `query_spending` tool. The model never computes a sum.

**Chat.** `AgentService` keeps the conversation as Messages API turns. Each user message runs a loop: send history plus the eight tool definitions, execute every `tool_use` block through `AgentTools`, append the `tool_result` blocks, repeat until the model answers in text or six steps pass. Tools call `ExpenseStore`, `RAGService` or mutate `AppState`, which SwiftUI observes, so "show me last year by month" changes the dashboard immediately. `delete_expense` only records a pending action; the chat shows Delete and Cancel buttons and the store is touched only on Delete.

**Dictation.** `SpeechService` requests microphone and speech permissions, taps the audio engine, and streams partial results into the text field. On stop it waits up to 1.5 s for the final transcript and sends it through the same `AgentService.send` as typed text.

## 3. Frameworks and why

| Framework | Used for | Why |
|---|---|---|
| SwiftUI | All views, the settings scene, the evaluation window | Declarative, observes `AppState` and models so agent-driven UI changes need no plumbing |
| SwiftData | `Expense`, `InvoiceChunk`, cascade delete, lightweight migrations | Native persistence with `@Query` live updates; schema grew twice without data loss |
| Swift Charts | Bars, donut, horizontal bars, hover selection | Native, accessible, handles date axes and label thinning |
| PDFKit | Text extraction from digital PDFs | Avoids sending images when text exists; cheaper and exact |
| NaturalLanguage `NLEmbedding` | Sentence embeddings for invoice chunks | Fully on-device, no data leaves the Mac for search |
| Speech, AVFoundation | Dictation | On-device recognition for English; Arabic via Apple when needed |
| Security (Keychain) | API key | Never in code or defaults; app-scoped access |
| URLSession, Codable | Anthropic Messages API client | No third-party packages; one 150-line client with typed errors |
| Observation (`@Observable`) | `AppState`, services | Fine-grained updates with little boilerplate |

## 4. Why Claude, and what is sent

Claude is used for two jobs that rules cannot do well: reading messy, bilingual, variably laid-out invoices, and understanding natural-language requests and mapping them to tools. Two models are used: `claude-haiku-5-5` for extraction (cheap, fast, strong on structured output) and `claude-sonnet-5-5` for the chat agent (better tool planning and wording).

Data sent to the API, per request:

- **Extraction**: the invoice text or image, the system prompt, the tool schema. Nothing else from the database.
- **Chat**: the conversation so far, the system prompt (today's date, currency, rules), the tool definitions, and the results of tools the model called. Tool results contain only the rows or totals the question needed, for example "2026-10: 1230.52 SAR (2 invoices)" or the passages returned by search. The database is never sent whole.
- **Never sent**: the API key beyond the request header, file paths, Keychain contents, anything from other apps.

Embeddings for search are computed on device and never leave the Mac. Dictation audio is processed on device when the language supports it.

## 5. Development approach

The app was built with Claude Code in five phased prompts, each with a goal, a numbered build list and a "done when" line, following `CLAUDE.md` as the standing specification:

1. **Invoices in, expenses out**: model, Keychain, API client, extractor, store, invoices table.
2. **Dashboard**: `AppState`, sidebar, KPIs and three charts.
3. **Chat and control**: RAG, agent tools and loop, chat panel.
4. **Voice**: speech service, microphone button, language switch.
5. **Release**: polish, Release build, documentation.

Between phases came polish passes driven by hands-on testing: validation with self-correction, duplicate prompts, review badges, token usage, model routing, chart hover and date axes, table sorting and search, and the Evaluation window.

Working rules that mattered: numbers only from `ExpenseStore`; no third-party packages; files under 200 lines; never edit the Xcode project file by hand; build with `xcodebuild` after every phase and fix every error before stopping; every change ends with a list of files and a manual test script.

## 6. Testing

**Build**: `xcodebuild` Debug after every change and Release for the package, both clean with no warnings in app code.

**Manual tests after each phase**: import of 15 generated PDFs with values checked against the PDFs; edit and cancel; delete with confirmation; dashboard figures compared with SQL run directly on the SwiftData store for each period preset; the four chat scenarios from the specification ("How much did I spend last month?", "Show my expenses for the past year by month", "What did I buy from Nahdi Pharmacy?", "Add an expense of 50 SAR for coffee today"); dictation of "show me last year's expenses by month"; duplicate import prompt; a deliberately wrong total showing the review badge.

**Offline checks**: the API request and response shapes were verified by compiling the client types into a script and inspecting the JSON; schema migrations were tested by opening a copy of the real store with the new models; RAG search was probed with three questions; the validator and ground-truth comparer were exercised with good and bad inputs.

**Evaluation window**: extraction against 20 synthetic Saudi receipts from the Bayanat Labs dataset (CC BY 4.0, Arabic and English, some with Arabic-Indic numerals), first run with `claude-haiku-5-5`:

| Metric | Result |
|---|---|
| Files scored | 17 of 20 (3 refused as "placeholder", fixed afterwards) |
| Field accuracy | 99.3% overall |
| Vendor, VAT number, date, subtotal, VAT, total, currency | 100% |
| Invoice number | 94.1% (one placeholder) |
| Average time per receipt | 13.8 s |
| Tokens | 87,886 in total, about 4,400 per receipt |

The three failures all had the dataset's footer "Synthetic research sample — not a valid tax invoice". The prompt now names that watermark and a placeholder answer gets one retry; the re-run and the six-question agent test are the next items to execute.

**Bugs found and fixed by testing**: Claude filled placeholders on invoices marked "fictional sample"; the self-correction turn omitted the required `tool_result` block (HTTP 400); the dashboard could not reach data from 2023 with relative periods only; a Release of the sandbox lacked the entitlements for network, microphone and save panels.

## 7. Where to look

- `CLAUDE.md`: the specification and rules
- `README.md`: setup, running, features, tools, limitations, next steps
- `BACKLOG.md`: open polish items
- `docs/datasets.md`: candidate datasets for further evaluation
- `tools/evaluation.md`: the exported evaluation report
