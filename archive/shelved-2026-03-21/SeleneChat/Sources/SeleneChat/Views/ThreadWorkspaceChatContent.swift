import SeleneShared
// ThreadWorkspaceChatContent.swift
// SeleneChat
//
// Child view for thread workspace chat that uses @ObservedObject for proper
// Combine subscription to ThreadWorkspaceChatViewModel's @Published properties.
// Fixes: message disappearing on send until refresh.

import SwiftUI

struct ThreadWorkspaceChatContent: View {
    @ObservedObject var viewModel: ThreadWorkspaceChatViewModel
    @Binding var chatInput: String
    var onConfirmActions: () -> Void

    @State private var isConfirmingActions = false

    var body: some View {
        VStack(spacing: 0) {
            // Chat header
            HStack {
                Text("CHAT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                if viewModel.isProcessing {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.messages.isEmpty {
                            chatEmptyState
                        } else {
                            ForEach(viewModel.messages) { message in
                                chatMessageRow(message)
                                    .id(message.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) {
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
            }

            // Pending actions banner
            if !viewModel.pendingActions.isEmpty {
                pendingActionsBanner(viewModel.pendingActions)
            }

            Divider()

            // Input
            chatInputArea
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Empty State

    private var chatEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Ask about this thread")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text("\"What should I focus on next?\" or \"Break this down into tasks\"")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Message Row

    private func chatMessageRow(_ message: Message) -> some View {
        HStack {
            if message.isUser { Spacer(minLength: 40) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.isUser ? "You" : "Selene")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(10)
                    .background(message.isUser ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(12)
            }

            if !message.isUser { Spacer(minLength: 40) }
        }
    }

    // MARK: - Pending Actions Banner

    private func pendingActionsBanner(_ actions: [ActionExtractor.ExtractedAction]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.orange)
                Text("Suggested Tasks (\(actions.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                HStack(spacing: 8) {
                    Circle()
                        .fill(energyColor(action.energy))
                        .frame(width: 8, height: 8)
                    Text(action.description)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(action.timeframe.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Button("Create in Things") {
                    onConfirmActions()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button("Dismiss") {
                    viewModel.dismissActions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    private func energyColor(_ energy: ActionExtractor.ExtractedAction.EnergyLevel) -> Color {
        switch energy {
        case .high: return .red
        case .medium: return .orange
        case .low: return .green
        }
    }

    // MARK: - Chat Input

    private var chatInputArea: some View {
        HStack(spacing: 8) {
            TextField("Ask about this thread...", text: $chatInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit { sendChatMessage() }

            Button(action: { sendChatMessage() }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(chatInput.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .blue)
            }
            .buttonStyle(.plain)
            .disabled(chatInput.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isProcessing)
        }
        .padding()
    }

    private func sendChatMessage() {
        let content = chatInput.trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return }
        chatInput = ""

        Task {
            await viewModel.sendMessage(content)
        }
    }
}
