# Expenses

Native macOS expense tracker. Users import invoices, the app extracts the data, and an AI chat (typed or dictated) answers questions and controls the app.

## Layout
- Workspace root: this folder (git repo, CLAUDE.md, tools/, dist/)
- Xcode project: Expenses/Expenses.xcodeproj
- Swift source: Expenses/Expenses/ (new files go here; Xcode picks them up automatically)
- Sample invoices: tools/samples/

## Stack
- Swift, SwiftUI, macOS 14+
- SwiftData (storage), Swift Charts (graphs), PDFKit (PDF text), NaturalLanguage NLEmbedding (on-device embeddings), Speech and AVFoundation (dictation)
- Claude through the Anthropic Messages API with URLSession: POST https://api.anthropic.com/v1/messages, headers x-api-key, anthropic-version: 2023-06-01, content-type: application/json
- No third-party packages
- Model name is a constant in Config.swift (default claude-sonnet-5-5). The API key is entered in Settings and stored in the Keychain, never in code

## Source structure (inside Expenses/Expenses/)
- ExpensesApp.swift, AppState.swift, Config.swift
- Models/: Expense, InvoiceChunk
- Services/: ClaudeClient, InvoiceExtractor, ExpenseStore, RAGService, AgentService, SpeechService, KeychainStore
- Views/: DashboardView, InvoicesView, ChatView, SettingsView

## Data model
Expense: vendor, vatNumber, invoiceNumber, date, subtotal, vatAmount, total, currency (default SAR), category, details, fileName, rawText, createdAt
Categories: Food, Transport, Utilities, Office, Software, Travel, Health, Other

## Rules
- Numbers (totals, per day, per month, comparisons) always come from ExpenseStore functions, never from RAG or the model's memory
- RAG is only for questions about what an invoice contains
- The agent changes data only through tools, and delete needs user confirmation
- UI state the agent can change (period, granularity, category filter, selected screen) lives in AppState
- Do not edit project.pbxproj by hand. If a new file is not compiled, stop and tell me to add it in Xcode
- If strict concurrency errors appear, mark the type @MainActor instead of restructuring
- Keep files under 200 lines. Do not add features that were not asked for
- After every phase run this and fix all errors before stopping:
  xcodebuild -project Expenses/Expenses.xcodeproj -scheme Expenses -destination 'platform=macOS' build 2>&1 | tail -30
- Keep replies short: list files changed and what I should test by hand
