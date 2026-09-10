import Foundation

/// A word a recogniser heard, with where it heard it.
public struct RecognizedWord: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// When one word of the text was spoken.
///
/// Plain times rather than the caller's own word type. What a word is on the page,
/// which line it sits in and which of its letters are painted, belongs to the caller;
/// these come back in reading order to be put back onto it.
public struct WordSpan: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}

/// One word of the text lined up with one word of what was heard, or with the two
/// that stood in for it: neither side agrees with the other about where a word ends,
/// so a match can span a pair on either side.
public struct WordMatch: Sendable, Equatable {
    public let expected: Range<Int>
    public let heard: Range<Int>

    public init(expected: Range<Int>, heard: Range<Int>) {
        self.expected = expected
        self.heard = heard
    }
}

/// Puts a recogniser's output against the text that was read, and hands back when
/// each word of that text was spoken.
///
/// This is not transcription: the words are known in advance. The recogniser is
/// only asked where they are, and it will get some of them wrong, the more so the
/// further the text is from what it was trained on ("Feed'st" comes back as
/// "feedst", "thou" as "thy"). So words are matched by how alike they sound on
/// paper rather than by equality, and anything left unmatched has its time
/// interpolated from the words around it, which keeps a run of missed words from
/// collapsing onto one instant.
public enum TranscriptAligner {
    /// How alike two words must be to count as the same word. Below this the pair
    /// is treated as two different words rather than one misheard one.
    public static let matchThreshold = 0.6

    /// - Parameter weighting: how long each word takes to say, which is how the time
    ///   of an unmatched run is shared out. English by default; a language whose
    ///   syllables it cannot count brings its own.
    public static func align(
        expected: [String],
        heard: [RecognizedWord],
        duration: TimeInterval,
        weighting: any SpeechWeighting = EnglishSyllableWeighting()
    ) -> [WordSpan] {
        guard !expected.isEmpty else { return [] }
        guard !heard.isEmpty else { return [] }

        let pairs = match(expected: expected, heard: heard, weighting: weighting)
        return fill(expected: expected, pairs: pairs, duration: duration, weighting: weighting)
    }

    /// Needleman-Wunsch over the two sequences: both are in reading order, so the
    /// alignment may skip words on either side but never reorder them.
    /// The words go in as they are printed. `pair` normalises them itself, and it counts
    /// the parts of a hyphenated compound before it does: handing it words already
    /// stripped of their hyphens tells it every word prints as one, and a compound heard
    /// as three words can then never be matched at all.
    static func match(
        expected: [String],
        heard: [RecognizedWord],
        weighting: any SpeechWeighting = EnglishSyllableWeighting()
    ) -> [Int: RecognizedWord] {
        let matches = pair(
            expected: expected,
            heard: heard.map(\.text),
            threshold: matchThreshold
        )
        return matches.reduce(into: [Int: RecognizedWord]()) { result, match in
            // The whole of what was heard, however many words it was written down as:
            // "world-without-end" is one word to the reader and three to the recogniser,
            // and it lasts until the last of them ends.
            let start = heard[match.heard.lowerBound].start
            let end = heard[match.heard.upperBound - 1].end
            guard match.expected.count > 1 else {
                result[match.expected.lowerBound] = RecognizedWord(
                    text: heard[match.heard.lowerBound].text, start: start, end: end
                )
                return
            }
            // Printed as several words and heard as one -- "every where" written down as
            // "everywhere". They were each given the whole of it, which leaves them lying
            // on top of one another and the first with nothing to be found at once the
            // ends are tidied. Shared out by speech weight instead, in reading order.
            let weights = match.expected.map { speechWeight(of: expected[$0], using: weighting) }
            let total = weights.reduce(0, +)
            var cursor = start
            for (index, weight) in zip(match.expected, weights) {
                let length = (end - start) * weight / total
                // Still the word that was heard, as on the other branch: this is a share
                // of one token's time, not a token of its own, and calling it by the
                // printed word would make the same field mean two different things.
                result[index] = RecognizedWord(
                    text: heard[match.heard.lowerBound].text, start: cursor, end: cursor + length
                )
                cursor += length
            }
        }
    }

    /// The alignment itself, over plain words: which words of the one turned out to
    /// be which words of the other.
    ///
    /// Aligning the whole utterance at once is what lets a reader be told which words
    /// they got wrong rather than only where they first went wrong: a word mangled in
    /// the middle of the line no longer hides the correct words after it.
    /// - Parameter equivalent: pairs to treat as the same word however unalike they
    ///   look, asked as (written, heard, the written word before it). Without it
    ///   "heir" and "air" are two words to the alignment, and the patch that knows
    ///   better never gets asked. The predecessor comes along because a patch may be
    ///   confined to one turn of phrase, and only the alignment knows what stands
    ///   where. Asked on either side joined up as well, because a recogniser writes a
    ///   hyphenated compound as two words and two written words as one, and both are
    ///   one entry in the patch table.
    public static func pair(
        expected: [String],
        heard: [String],
        threshold: Double,
        equivalent: ((String, String, String?) -> Bool)? = nil
    ) -> [WordMatch] {
        guard !expected.isEmpty, !heard.isEmpty else { return [] }
        let alignment = Alignment(
            expected: expected.map(normalize),
            heard: heard.map(normalize),
            threshold: threshold,
            equivalent: equivalent,
            parts: expected.map(printedParts)
        )
        return alignment.matches(in: alignment.scores())
    }

    /// Gives every expected word a start and an end: matched words keep the times they
    /// were heard at, unmatched runs are shared out by speech weight across the gap
    /// between their nearest matched neighbours, so a long word does not get the same
    /// slice of a pause as "a".
    ///
    /// A run can be left no gap at all. The recogniser writes "your self" as one word,
    /// the alignment matches that word to "self", and "your" is left between two marks
    /// that touch. Spread across nothing it comes out with no length, and no instant of
    /// the recording falls inside a word of no length: a mark that runs along the line
    /// as the recording plays passes straight over it, every time. Room then comes from
    /// the neighbour that was holding it -- the one dwelling longest on each syllable,
    /// which is the mark of a word that swallowed another.
    static func fill(
        expected: [String],
        pairs: [Int: RecognizedWord],
        duration: TimeInterval,
        weighting: any SpeechWeighting = EnglishSyllableWeighting()
    ) -> [WordSpan] {
        var timings: [WordSpan?] = Array(repeating: nil, count: expected.count)
        for (index, word) in pairs {
            timings[index] = WordSpan(start: word.start, end: word.end)
        }

        var index = 0
        while index < timings.count {
            guard timings[index] == nil else {
                index += 1
                continue
            }
            var runEnd = index
            while runEnd < timings.count, timings[runEnd] == nil {
                runEnd += 1
            }
            var first = index
            var last = runEnd
            var runStart = index > 0 ? timings[index - 1]?.end ?? 0 : 0
            var runFinish = runEnd < timings.count ? timings[runEnd]?.start ?? duration : duration

            if runFinish - runStart < roomEnough * Double(runEnd - index),
               let host = swallower(
                   of: index..<runEnd,
                   in: timings,
                   expected: expected,
                   weighting: weighting
               ),
               let stretch = timings[host] {
                // Nothing to spread into. Take the run's room out of the word that was
                // holding it, and time the two together across that word's own stretch.
                if host < index {
                    first = host
                    runStart = stretch.start
                } else {
                    last = host + 1
                    runFinish = stretch.end
                }
            }

            let weights = (first..<last).map { speechWeight(of: expected[$0], using: weighting) }
            let total = weights.reduce(0, +)
            var cursor = runStart
            for (offset, weight) in zip(first..<last, weights) {
                let length = max(runFinish - runStart, 0) * weight / total
                timings[offset] = WordSpan(start: cursor, end: cursor + length)
                cursor += length
            }
            index = runEnd
        }
        return timings.compactMap { $0 }
    }

    /// Shorter than this and a word has no stretch of the recording to be found at.
    private static let roomEnough: TimeInterval = 0.04

    /// Which neighbour of an unmatched run was holding the run's sound: the one dwelling
    /// longest on each of its own syllables. A word the recogniser ran another word into
    /// keeps both their sounds and so reads as unnaturally slow; its neighbour on the
    /// other side is saying only itself.
    private static func swallower(
        of run: Range<Int>,
        in timings: [WordSpan?],
        expected: [String],
        weighting: any SpeechWeighting
    ) -> Int? {
        func perSyllable(_ index: Int) -> Double? {
            guard timings.indices.contains(index), let timing = timings[index] else { return nil }
            return (timing.end - timing.start) / speechWeight(of: expected[index], using: weighting)
        }
        let before = perSyllable(run.lowerBound - 1)
        let after = perSyllable(run.upperBound)
        switch (before, after) {
        case let (before?, after?): return after >= before ? run.upperBound : run.lowerBound - 1
        case (_?, nil): return run.lowerBound - 1
        case (nil, _?): return run.upperBound
        case (nil, nil): return nil
        }
    }

    private static func speechWeight(of word: String, using weighting: any SpeechWeighting) -> Double {
        max(weighting.weight(of: word), 1)
    }

    /// Letters only, lowercased. Elision marks and punctuation are exactly what a
    /// recogniser drops or invents, so comparing without them compares what was
    /// actually said.
    public static func normalize(_ word: String) -> String {
        word.lowercased().filter { $0.isLetter }
    }

    /// How many words print writes this one as. A hyphenated compound is one written
    /// word and as many heard ones as it has parts, and normalising the hyphen away
    /// loses the count, so it is taken before.
    static func printedParts(_ word: String) -> Int {
        max(word.split(separator: "-").count, 1)
    }

    /// 1 for identical, 0 for nothing in common, by edit distance over length.
    static func similarity(_ left: String, _ right: String) -> Double {
        if left == right { return 1 }
        if left.isEmpty || right.isEmpty { return 0 }
        let distance = editDistance(Array(left), Array(right))
        return 1 - Double(distance) / Double(max(left.count, right.count))
    }

    private static func editDistance(_ left: [Character], _ right: [Character]) -> Int {
        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)

        for row in 1...left.count {
            current[0] = row
            for column in 1...right.count {
                let substitution = previous[column - 1] + (left[row - 1] == right[column - 1] ? 0 : 1)
                current[column] = min(substitution, previous[column] + 1, current[column - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[right.count]
    }
}
