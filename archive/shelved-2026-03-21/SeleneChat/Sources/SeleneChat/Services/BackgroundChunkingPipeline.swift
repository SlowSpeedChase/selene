import Foundation
import SeleneShared

@MainActor
class BackgroundChunkingPipeline: ObservableObject {

    @Published var isProcessing = false
    @Published var totalToProcess = 0
    @Published var processedCount = 0

    private let chunkingService = ChunkingService()
    private let databaseService = DatabaseService.shared
    private var timer: Timer?
    private let batchSize = 10

    func start() {
        Task { await processUnchunkedNotes() }

        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.processUnchunkedNotes()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func processUnchunkedNotes() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        do {
            let unchunkedIds = try await databaseService.getUnchunkedNoteIds(limit: batchSize)
            guard !unchunkedIds.isEmpty else { return }

            totalToProcess = unchunkedIds.count
            processedCount = 0

            for noteId in unchunkedIds {
                guard let note = try await databaseService.getNote(byId: noteId) else { continue }

                let chunkTexts = chunkingService.splitIntoChunks(note.content)

                for (index, chunkText) in chunkTexts.enumerated() {
                    let tokenCount = chunkingService.estimateTokens(chunkText)
                    let chunkId = try await databaseService.insertNoteChunk(
                        noteId: noteId,
                        chunkIndex: index,
                        content: chunkText,
                        topic: nil,
                        tokenCount: tokenCount,
                        embedding: nil
                    )

                    // Generate embedding via Ollama
                    do {
                        let embedding = try await OllamaService.shared.embed(text: chunkText)
                        try await databaseService.saveChunkEmbedding(chunkId: chunkId, embedding: embedding)
                    } catch {
                        print("[ChunkPipeline] Embedding failed for chunk \(chunkId): \(error)")
                    }

                    // Generate topic label via Apple Intelligence (if available)
                    if #available(macOS 26, *) {
                        do {
                            let appleService = AppleIntelligenceService()
                            if await appleService.isAvailable() {
                                let topic = try await appleService.labelTopic(chunk: chunkText)
                                try await databaseService.updateChunkTopic(chunkId: chunkId, topic: topic)
                            }
                        } catch {
                            print("[ChunkPipeline] Topic labeling failed for chunk \(chunkId): \(error)")
                        }
                    }
                }

                processedCount += 1
            }
        } catch {
            print("[ChunkPipeline] Processing failed: \(error)")
        }
    }
}
