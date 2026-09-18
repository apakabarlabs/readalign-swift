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
    /// whole by at least one of them, and never less than `least_overlap` earlier: where no
    /// pause offers itself the two pieces would otherwise meet edge to edge and share
    /// nothing, and a word invented at the edge of one would have nothing to be caught
    /// against.
    public static func cuts(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
        let longest = Int(Rules.shared.pieceSeconds * sampleRate)
        guard samples.count > longest, longest > 0 else { return [0 ..< samples.count] }
        let shortest = Int(Rules.shared.pieceSeconds * Rules.shared.shortestPieceShare * sampleRate)
        let least = Int(Rules.shared.leastOverlap * sampleRate)
        let marks = pauses(in: samples, sampleRate: sampleRate)

        var pieces: [Range<Int>] = []
        var start = 0
        while samples.count - start > longest {
            let cut = marks.last { $0 > start + shortest && $0 < start + longest } ?? start + longest
            pieces.append(start ..< cut)
            // One pause back, but never back past half a piece: the overlap is there to
            // carry the words at the seam, and a pause near the start of this piece would
            // hand the next one almost the same range, over and over.
            let atAPause = marks.last { $0 < cut && $0 >= start + shortest }
            start = min(atAPause ?? cut, max(start + shortest, cut - least))
        }
        pieces.append(start ..< samples.count)
        return pieces
    }

    /// One transcript out of what each piece came back with.
    ///
    /// The pieces overlap, so the words at a seam arrive twice, and the second copy is
    /// dropped by the text: the longest run the two pieces say alike inside the overlap
    /// is found, and everything the coming piece says up to the end of it comes off.
    /// Placed where it falls in the whole recording, so a caller hands over what it was
    /// given piece by piece and gets the reading back.
    ///
    /// By the text and not by the clock, because the clock is the one thing two builds of
    /// one model do not share: the same word decoded in two pieces comes back a fifth of a
    /// second apart on one runtime and differently again on the next, so a rule that asks
    /// how close two marks are decides differently on each of them. The words agree where
    /// the marks do not.
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
        var coveredTo = 0.0
        for (words, piece) in zip(heard, pieces) {
            let offset = Double(piece.lowerBound) / sampleRate
            let placed = words.map { word in
                RecognizedWord(text: word.text, start: word.start + offset, end: word.end + offset)
            }
            let seam = agreement(reading, placed, from: offset, upTo: coveredTo)
            reading.removeLast(seam.keptAfterIt)
            reading += placed.dropFirst(seam.comingUpToIt)
            coveredTo = Double(piece.upperBound) / sampleRate
        }
        return reading
    }

    /// Where the two pieces stop saying the same thing: what comes off each side of a seam.
    struct Seam {
        /// Words to take off the end of the reading so far.
        let keptAfterIt: Int
        /// Words to take off the front of the coming piece.
        let comingUpToIt: Int
    }

    /// The longest run the two pieces say alike in the ground they both cover.
    ///
    /// Only words inside that ground can be a second copy, so the search is held to it: a
    /// word the reading genuinely says twice, further along, is out of reach and stays.
    ///
    /// The run is looked for anywhere inside the overlap rather than at its edges, because
    /// a recogniser drops or invents a word at the edge of what it was given — one piece
    /// ended "...by time decease we" where the other heard no "we" — and a run pinned to
    /// the edges would find nothing and leave the whole overlap said twice. A run of one
    /// word is taken only when it is the whole of what the coming piece says in the
    /// overlap, or a word as common as "the" would pair with itself by chance.
    ///
    /// Past the run the coming piece is believed and the piece before it is not: they
    /// cover the same seconds there, and the one that goes on past them heard them with
    /// what follows while the other was hearing the last of what it was given.
    static func agreement(
        _ kept: [RecognizedWord],
        _ coming: [RecognizedWord],
        from overlapFrom: Double,
        upTo coveredTo: Double
    ) -> Seam {
        let nothing = Seam(keptAfterIt: 0, comingUpToIt: 0)
        let tail = kept.drop { word in word.start < overlapFrom }.map { word in
            TranscriptAligner.normalize(word.text)
        }
        let head = coming.prefix { word in word.start < coveredTo }.map { word in
            TranscriptAligner.normalize(word.text)
        }
        guard !tail.isEmpty, !head.isEmpty else { return nothing }

        var longest = 0
        var endsInTail = 0
        var endsInHead = 0
        for first in tail.indices {
            for second in head.indices {
                var run = 0
                while first + run < tail.count, second + run < head.count,
                      tail[first + run] == head[second + run] {
                    run += 1
                }
                if run > longest {
                    longest = run
                    endsInTail = first + run
                    endsInHead = second + run
                }
            }
        }
        guard longest > 1 || longest == head.count else { return nothing }
        return Seam(keptAfterIt: tail.count - endsInTail, comingUpToIt: endsInHead)
    }

    /// What one piece comes back as, asking again with less of its tail while nothing comes.
    ///
    /// Parakeet answers some pieces of ordinary speech with no words at all, and whether it
    /// does turns on where the piece starts and how long it is together: the mel statistics
    /// are taken over the piece, so its length moves them, and past some edge the decoder
    /// predicts blank at every frame. Handing over a little less of the tail moves the piece
    /// off that edge. Nothing here tells speech from silence, so a piece that is genuinely
    /// silent pays for the whole list before answering nothing, which is why a piece shorter
    /// than `shortest_worth_asking_again` is not asked again at all.
    ///
    /// An answer won this way is missing whatever was said in the tail that was cut off. Each
    /// piece the recording is cut into overlaps the next, and that overlap is what covers it.
    /// Asking is `async` because every recogniser this is written for answers that way.
    public static func heard(
        of piece: [Float],
        sampleRate: Double,
        asking: ([Float]) async throws -> [RecognizedWord]
    ) async rethrows -> [RecognizedWord] {
        let words = try await asking(piece)
        guard words.isEmpty,
              Double(piece.count) / sampleRate >= Rules.shared.shortestWorthAskingAgain
        else { return words }

        for trim in Rules.shared.askAgainTrims {
            let shorter = piece.count - Int(trim * sampleRate)
            guard shorter > 0 else { break }
            let again = try await asking(Array(piece[0 ..< shorter]))
            if !again.isEmpty { return again }
        }
        return words
    }
}

public enum PiecesError: Error, Equatable {
    case unevenPieces(heard: Int, pieces: Int)
}
