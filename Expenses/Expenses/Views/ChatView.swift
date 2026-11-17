import SwiftUI

struct ChatView: View {
    @Bindable var agent: AgentService
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Chat").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
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
            HStack(spacing: 8) {
                TextField("Ask about your expenses…", text: $draft, axis: .vertical)
                    .lineLimit(1...4).textFieldStyle(.plain).focused($focused)
                    .onSubmit { submit() }
                Button { submit() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.plain).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || agent.isWorking)
            }
            .padding(10)
        }
        .background(.background)
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
                if !message.toolsUsed.isEmpty {
                    Text("Tools: " + message.toolsUsed.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
