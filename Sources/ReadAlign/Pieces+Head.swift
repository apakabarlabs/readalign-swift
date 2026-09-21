import Foundation

extension Pieces {
    static func recoveredHead(
        _ words: [RecognizedWord],
        in piece: [Float],
        sampleRate: Double,
        coveredPrefix: TimeInterval,
        asking: ([Float]) async throws -> [RecognizedWord]
    ) async rethrows -> [RecognizedWord] {
        guard let first = words.first,
            first.start - coveredPrefix >= Rules.shared.uncoveredHeadSeconds
        else { return words }
        let beforeFirst = Array(piece.prefix(Int(first.start * sampleRate)))
        guard let through = pauses(in: beforeFirst, sampleRate: sampleRate).last else {
            return words
        }
        let head = Array(piece[..<through])
        var recovered = try await asking(head)
        if recovered.isEmpty {
            for trim in Rules.shared.askAgainTrims {
                let shorter = head.count - Int(trim * sampleRate)
                guard shorter > 0 else { break }
                recovered = try await asking(Array(head[..<shorter]))
                if !recovered.isEmpty { break }
            }
        }
        guard !recovered.isEmpty else { return words }
        return recovered + words
    }
}
