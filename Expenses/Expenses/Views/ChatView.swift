import SwiftUI

struct ChatView: View {
    @Bindable var agent: AgentService
    @State private var speech = SpeechService()
    @AppStorage("speechLanguage") private var speechLanguage = SpeechLanguage.english.rawValue
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Chat").font(.headline)
                Spacer()
                Picker("Dictation language", selection: $speechLanguage) {
                    ForEach(SpeechLanguage.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 90)
                .disabled(speech.isRecording)
                .help("Dictation language")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if agent.messages.isEmpty { hint }
                        ForEach(agent.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if agent.isWorking {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").foregroundStyle(.secondary) }
                                .id("working")
                        }
                    }
                    .padding(12)
                }
                .onChange(of: agent.messages.count) { scroll(proxy) }
                .onChange(of: agent.isWorking) { scroll(proxy) }
            }
            Divider()
            if let error = speech.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 12).padding(.top, 6)
            }
            HStack(spacing: 8) {
                micButton
                TextField(speech.isRecording ? "Listening…" : "Ask about your expenses…", text: $draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).focused($focused)
                    .onSubmit { submit() }
                    .disabled(speech.isRecording)
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.plain)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || agent.isWorking || speech.isRecording)
            }
            .padding(12)
            .background(speech.isRecording ? Color.red.opacity(0.08) : Color.clear)
        }
        .background(.background)
        .onChange(of: speech.transcript) { if speech.isRecording { draft = speech.transcript } }
    }

    private var micButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                .font(.title2)
                .foregroundStyle(speech.isRecording ? .red : .secondary)
                .symbolEffect(.pulse, isActive: speech.isRecording)
        }
        .buttonStyle(.plain)
        .disabled(agent.isWorking)
        .help(speech.isRecording ? "Stop and send" : "Dictate")
    }

    private func toggleRecording() async {
        if speech.isRecording {
            let text = await speech.stop()
            draft = text
            if !text.isEmpty { submit() }
        } else {
            speech.language = SpeechLanguage(rawValue: speechLanguage) ?? .english
            draft = ""
            await speech.start()
        }
    }

    private var hint: some View {
        Text("Try: \"How much did I spend last month?\" or \"Show my expenses for the past year by month\".")
            .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            Text(message.text)
                .padding(10).background(Color.accentColor.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .trailing)
        case .notice:
            Text(message.text).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                Text(message.text).textSelection(.enabled)
                    .padding(10).background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                if message.pendingDeleteId != nil, let expense = agent.pendingDelete {
                    HStack {
                        Button("Delete \(expense.vendor)", role: .destructive) { agent.confirmDelete() }
                        Button("Cancel") { agent.cancelDelete() }
                    }
                    .controlSize(.small)
                }
                Text(usageLine(message)).font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func usageLine(_ message: ChatMessage) -> String {
        var parts: [String] = []
        if !message.toolsUsed.isEmpty { parts.append("Tools: " + message.toolsUsed.joined(separator: ", ")) }
        if message.inputTokens + message.outputTokens > 0 {
            parts.append("\(message.inputTokens.formatted()) in / \(message.outputTokens.formatted()) out")
            parts.append(String(format: "%.1f s", message.seconds))
        }
        return parts.joined(separator: " · ")
    }

    private func submit() {
        let text = draft
        draft = ""
        focused = true
        Task { await agent.send(text) }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        withAnimation {
            if agent.isWorking { proxy.scrollTo("working", anchor: .bottom) }
            else if let last = agent.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
        }
    }
}
