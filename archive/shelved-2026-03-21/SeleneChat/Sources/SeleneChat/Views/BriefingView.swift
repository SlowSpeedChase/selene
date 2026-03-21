import SeleneShared
// SeleneChat/Sources/Views/BriefingView.swift
import SwiftUI

struct BriefingView: View {
    @StateObject private var viewModel = BriefingViewModel()
    @EnvironmentObject var databaseService: DatabaseService

    var onDismiss: () -> Void
    var onDiscussCard: (BriefingCard) -> Void

    var body: some View {
        ZStack {
            Color(.windowBackgroundColor)
                .ignoresSafeArea()

            content
        }
        .onAppear {
            if case .notLoaded = viewModel.state.status {
                Task {
                    await viewModel.loadBriefing()
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.status {
        case .notLoaded:
            EmptyView()

        case .loading:
            loadingView

        case .loaded(let briefing):
            loadedView(briefing)

        case .failed(let message):
            errorView(message)
        }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Preparing your morning briefing...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Loaded State

    private func loadedView(_ briefing: StructuredBriefing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Intro text
                Text(briefing.intro)
                    .font(.title3)
                    .lineSpacing(4)
                    .padding(.top, 16)

                if briefing.isEmpty {
                    emptyState
                } else {
                    // What Changed section
                    if !briefing.whatChanged.isEmpty {
                        briefingSection(
                            title: "What Changed",
                            icon: "arrow.triangle.2.circlepath",
                            cards: briefing.whatChanged
                        )
                    }

                    // Needs Attention section
                    if !briefing.needsAttention.isEmpty {
                        briefingSection(
                            title: "Needs Attention",
                            icon: "exclamationmark.triangle",
                            cards: briefing.needsAttention
                        )
                    }

                    // Connections section
                    if !briefing.connections.isEmpty {
                        briefingSection(
                            title: "Connections",
                            icon: "link",
                            cards: briefing.connections
                        )
                    }
                }

                // Done button
                HStack {
                    Spacer()
                    Button(action: { onDismiss() }) {
                        Text("Done")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 600)
        }
    }

    // MARK: - Section Builder

    private func briefingSection(title: String, icon: String, cards: [BriefingCard]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(.primary)

            VStack(spacing: 8) {
                ForEach(cards) { card in
                    BriefingCardView(card: card, onDiscuss: onDiscussCard)
                        .environmentObject(databaseService)
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(.green)

            Text("All caught up!")
                .font(.headline)

            Text("No new activity since last time.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Error State

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)

            Text("Couldn't generate briefing")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            VStack(spacing: 12) {
                Button("Try Again") {
                    Task {
                        await viewModel.loadBriefing()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Skip") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }
}
