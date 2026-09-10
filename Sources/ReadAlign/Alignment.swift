/// One run of the alignment: the two word lists, and how much every way of lining
/// them up is worth.
///
/// Kept apart from the aligner because it answers a different question. This is the
/// table and what each way of lining the two lists up is worth; the aligner is what
/// turns the winning path into times.
struct Alignment {
    let expected: [String]
    let heard: [String]
    let threshold: Double
    /// Pairs the caller vouches for, whatever they look like.
    let equivalent: ((String, String, String?) -> Bool)?
    /// How many words print writes each expected word as, before the hyphens were
    /// normalised away. One for an ordinary word.
    let parts: [Int]

    /// Skipping a word on either side.
    let gapPenalty = -0.5
    /// Two words that are merely not opposites still share letters, so raw
    /// similarity would pair anything with anything rather than leave a word
    /// unpaired. Below the threshold a pairing is worse than passing both words
    /// over, which is what puts a false start outside the line instead of on top
    /// of its first words.
    let mismatchPenalty = -1.5

    /// Word boundaries are not agreed on: a recogniser hears "self-substantial" as
    /// two words and "whatever" as one, and neither is a mistake by the reader. So
    /// a word may also be matched against the two words next to it on the other
    /// side, joined up — but only on a near-exact match. Loosely, joining swallows
    /// the neighbouring word whole ("creatures we" would pass as "creatures"), and
    /// a swallowed word is one the reader never has to say.
    var joinThreshold: Double { max(threshold, 0.9) }

    /// A word with no letters in it, once normalised: a numeral, a stray mark, a
    /// token the recogniser emitted for a noise. Joining onto one is free, because
    /// it adds nothing to the joined string and so cannot lower the likeness, and a
    /// free join hands that token's whole stretch of the recording to its neighbour.
    /// Nothing is being joined there in any case: a join moves a boundary between two
    /// words, and this side has no word. Passing it over is what the gap is for.
    func joinable(_ words: ArraySlice<String>) -> Bool {
        words.allSatisfy { !$0.isEmpty }
    }

    func straight(_ row: Int, _ column: Int) -> Double {
        if equivalent?(expected[row], heard[column], row > 0 ? expected[row - 1] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(expected[row], heard[column]), against: threshold)
    }

    /// One written word against the `span` heard words ending at `column`, joined up.
    func joinedHeard(_ row: Int, _ column: Int, span: Int) -> Double {
        let parts = heard[(column - span + 1)...column]
        guard joinable(parts), !expected[row].isEmpty else { return mismatchPenalty }
        let joined = parts.joined()
        if equivalent?(expected[row], joined, row > 0 ? expected[row - 1] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(expected[row], joined), against: joinThreshold)
    }

    /// How many heard words one written word may be spread over. A compound is
    /// written with hyphens and heard as its parts, and print says how many there
    /// are: "swift-footed" is two, "world-without-end" three. Anything else may
    /// still take a pair, since a recogniser splits a long word wherever it likes.
    func spans(forExpectedAt row: Int) -> Int {
        max(2, parts[row])
    }

    /// The written pair is offered to the table joined up, exactly as the heard pair
    /// is on the other side. Without it a model that writes two written words as one
    /// is unpatchable: "in sense" comes back "incense", which is what those two words
    /// sound like said in a row, and similarity alone will not carry it over the join
    /// threshold. Narrowing the entry to the second word instead does not work, since
    /// the one heard word is then spent on it and the first has nothing left to match.
    func joinedExpected(_ row: Int, _ column: Int) -> Double {
        guard joinable(expected[(row - 1)...row]), !heard[column].isEmpty else { return mismatchPenalty }
        let joined = expected[row - 1] + expected[row]
        // The company is the word before the pair, so a patch confined to one turn of
        // phrase is confined the same way here as it is anywhere else.
        if equivalent?(joined, heard[column], row > 1 ? expected[row - 2] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(joined, heard[column]), against: joinThreshold)
    }

    /// Both pairs joined up, for a boundary the recogniser put in the wrong place.
    ///
    /// "shouldst owe" comes back as "should stow": the sound is the same and only the
    /// gap between the words moved, so neither word matches its own and the reader is
    /// failed on two words they said. Joined on both sides the two spellings are one
    /// string, which is what says the reading was right.
    func joinedPair(_ row: Int, _ column: Int) -> Double {
        guard joinable(expected[(row - 1)...row]), joinable(heard[(column - 1)...column]) else {
            return mismatchPenalty
        }
        let written = expected[row - 1] + expected[row]
        let said = heard[column - 1] + heard[column]
        if equivalent?(written, said, row > 1 ? expected[row - 2] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(written, said), against: joinThreshold)
    }

    private func worth(_ similarity: Double, against bar: Double) -> Double {
        similarity >= bar ? similarity : mismatchPenalty
    }

    /// Needleman-Wunsch over the two sequences: both are in reading order, so the
    /// alignment may skip words on either side but never reorder them.
    func scores() -> [[Double]] {
        var score = Array(
            repeating: Array(repeating: 0.0, count: heard.count + 1),
            count: expected.count + 1
        )
        for row in 1...expected.count {
            score[row][0] = Double(row) * gapPenalty
        }
        for column in 1...heard.count {
            score[0][column] = Double(column) * gapPenalty
        }
        for row in 1...expected.count {
            for column in 1...heard.count {
                var best = score[row - 1][column - 1] + straight(row - 1, column - 1)
                best = max(best, score[row - 1][column] + gapPenalty)
                best = max(best, score[row][column - 1] + gapPenalty)
                for span in 2...spans(forExpectedAt: row - 1) where column >= span {
                    best = max(
                        best,
                        score[row - 1][column - span] + joinedHeard(row - 1, column - 1, span: span)
                    )
                }
                if row >= 2 {
                    best = max(best, score[row - 2][column - 1] + joinedExpected(row - 1, column - 1))
                }
                if row >= 2, column >= 2 {
                    best = max(best, score[row - 2][column - 2] + joinedPair(row - 1, column - 1))
                }
                score[row][column] = best
            }
        }
        return score
    }

    /// Walks the best path back and keeps the matches it made on the way.
    func matches(in score: [[Double]]) -> [WordMatch] {
        var matches: [WordMatch] = []
        var row = expected.count
        var column = heard.count
        while row > 0, column > 0 {
            let cell = score[row][column]
            let straight = straight(row - 1, column - 1)
            if cell == score[row - 1][column - 1] + straight {
                if straight >= threshold {
                    matches.append(WordMatch(expected: (row - 1)..<row, heard: (column - 1)..<column))
                }
                row -= 1
                column -= 1
            } else if let span = (2...spans(forExpectedAt: row - 1)).first(where: { span in
                column >= span
                    && cell == score[row - 1][column - span] + joinedHeard(row - 1, column - 1, span: span)
            }) {
                if joinedHeard(row - 1, column - 1, span: span) >= joinThreshold {
                    matches.append(WordMatch(expected: (row - 1)..<row, heard: (column - span)..<column))
                }
                row -= 1
                column -= span
            } else if row >= 2, column >= 2,
                      cell == score[row - 2][column - 2] + joinedPair(row - 1, column - 1) {
                if joinedPair(row - 1, column - 1) >= joinThreshold {
                    matches.append(WordMatch(expected: (row - 2)..<row, heard: (column - 2)..<column))
                }
                row -= 2
                column -= 2
            } else if row >= 2, cell == score[row - 2][column - 1] + joinedExpected(row - 1, column - 1) {
                if joinedExpected(row - 1, column - 1) >= joinThreshold {
                    matches.append(WordMatch(expected: (row - 2)..<row, heard: (column - 1)..<column))
                }
                row -= 2
                column -= 1
            } else if cell == score[row - 1][column] + gapPenalty {
                row -= 1
            } else {
                column -= 1
            }
        }
        return matches.reversed()
    }
}
