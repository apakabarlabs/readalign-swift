import Foundation

/// Cutting a recording into the pieces a recogniser is given one at a time.
///
/// Every side that listens to the same reading has to cut it the same way. A piece
/// boundary changes what comes back near it, and a runtime left to cut on its own cuts
/// elsewhere: a forty-second reading handed whole to one recogniser and in fifteen-second
/// windows to another is two different questions, and the answers cannot be held against
/// each other. So the cut is made here, by rule, before any of them is asked.
public enum Pieces {
    /// A cut goes in the middle of the quiet, as far from the word on either side as it gets.
    private static let halves = 2

    /// Where the recording is quiet for long enough that a cut there takes no word in half.
    ///
    /// The middle of each stretch of quiet, in samples. A stop inside a word is quiet too,
    /// which is why a pause has a length to reach before it counts as one.
    public static func pauses(in samples: [Float], sampleRate: Double) -> [Int] {
        let frames = SilenceHold.energyFrames(of: samples, sampleRate: sampleRate)
        guard !frames.isEmpty else { return [] }
        let threshold = SilenceHold.speechThreshold(of: frames)
        // Quiet is only quiet between speech. Where nothing stands above the threshold
        // there is no voice to pause, and the whole recording would otherwise read as one
        // long pause and offer its own middle as a place to cut.
        guard frames.contains(where: { $0 >= threshold }) else { return [] }
        let eachFrame = Rules.shared.frameSeconds
        let quietEnough = max(Int(Rules.shared.pauseSeconds / eachFrame), 1)

        var found: [Int] = []
        var quiet = 0
        for (index, energy) in frames.enumerated() {
            if energy < threshold {
                quiet += 1
                continue
            }
            if quiet >= quietEnough {
                let middleOfTheQuiet = quiet / halves
                found.append(Int(Double(index - middleOfTheQuiet) * eachFrame * sampleRate))
            }
            quiet = 0
        }
        if quiet >= quietEnough {
            let middleOfTheQuiet = quiet / halves
            found.append(Int(Double(frames.count - middleOfTheQuiet) * eachFrame * sampleRate))
        }
        return found
    }

    /// The pieces the recording is asked in, in samples, each overlapping the one before.
    ///
    /// A piece ends at the last pause that leaves it long enough to carry a line and short
    /// enough for the runtime to take whole; where no pause falls there, it ends on length
    /// alone, because a piece that grows to find a pause is the very window this avoids.
    /// The next piece begins one pause earlier than the last ended, so every word is heard
    /// whole by at least one of them.
    public static func cuts(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
        let longest = Int(Rules.shared.pieceSeconds * sampleRate)
        guard samples.count > longest, longest > 0 else { return [0 ..< samples.count] }
        let shortest = Int(Rules.shared.pieceSeconds * Rules.shared.shortestPieceShare * sampleRate)
        let marks = pauses(in: samples, sampleRate: sampleRate)

        var pieces: [Range<Int>] = []
        var start = 0
        while samples.count - start > longest {
            let cut = marks.last { $0 > start + shortest && $0 < start + longest } ?? start + longest
            pieces.append(start ..< cut)
            // One pause back, but never back past half a piece: the overlap is there to
            // carry the words at the seam, and a pause near the start of this piece would
            // hand the next one almost the same range, over and over.
            start = marks.last { $0 < cut && $0 >= start + shortest } ?? cut
        }
        pieces.append(start ..< samples.count)
        return pieces
    }

    /// One transcript out of what each piece came back with.
    ///
    /// The pieces overlap, so the words at a seam arrive twice, and the second copy is
    /// dropped by time and text together: the same word marked within `same_moment` of
    /// one already kept is one word. Placed where it falls in the whole recording, so a
    /// caller hands over what it was given piece by piece and gets the reading back.
    ///
    /// A piece the recogniser had nothing to say about is an answer, not a failure: a
    /// stretch of silence is transcribed as no words at all. A count of transcripts that
    /// does not match the count of pieces is a failure, and is refused rather than
    /// quietly paired off until the shorter of the two runs out.
    public static func joined(
        _ heard: [[RecognizedWord]],
        at pieces: [Range<Int>],
        sampleRate: Double
    ) throws -> [RecognizedWord] {
        guard heard.count == pieces.count else {
            throw PiecesError.unevenPieces(heard: heard.count, pieces: pieces.count)
        }
        var reading: [RecognizedWord] = []
        for (words, piece) in zip(heard, pieces) {
            let offset = Double(piece.lowerBound) / sampleRate
            for word in words {
                let placed = RecognizedWord(
                    text: word.text,
                    start: word.start + offset,
                    end: word.end + offset
                )
                if !reading.contains(where: { sameWord($0, placed) }) {
                    reading.append(placed)
                }
            }
        }
        return reading
    }

    static func sameWord(_ kept: RecognizedWord, _ word: RecognizedWord) -> Bool {
        abs(kept.start - word.start) < Rules.shared.sameMoment
            && TranscriptAligner.normalize(kept.text) == TranscriptAligner.normalize(word.text)
    }
}

public enum PiecesError: Error, Equatable {
    case unevenPieces(heard: Int, pieces: Int)
}
