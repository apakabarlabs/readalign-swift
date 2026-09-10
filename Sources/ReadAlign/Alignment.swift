struct Alignment {
    let expected: [String]
    let heard: [String]
    let threshold: Double
    let equivalent: ((String, String, String?) -> Bool)?
    let printedParts: [Int]

    let gapPenalty = Rules.shared.gapPenalty
    let mismatchPenalty = Rules.shared.mismatchPenalty

    var joinThreshold: Double { max(threshold, Rules.shared.joinFloor) }

    func joinable(_ words: ArraySlice<String>) -> Bool {
        words.allSatisfy { !$0.isEmpty }
    }

    func straight(_ row: Int, _ column: Int) -> Double {
        if equivalent?(expected[row], heard[column], row > 0 ? expected[row - 1] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(expected[row], heard[column]), against: threshold)
    }

    func joinedHeard(_ row: Int, _ column: Int, span: Int) -> Double {
        let parts = heard[(column - span + 1)...column]
        guard joinable(parts), !expected[row].isEmpty else { return mismatchPenalty }
        let joined = parts.joined()
        if equivalent?(expected[row], joined, row > 0 ? expected[row - 1] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(expected[row], joined), against: joinThreshold)
    }

    func spans(forExpectedAt row: Int) -> Int {
        max(Rules.shared.joinSpan, printedParts[row])
    }

    func joinedExpected(_ row: Int, _ column: Int) -> Double {
        guard joinable(expected[(row - 1)...row]), !heard[column].isEmpty else { return mismatchPenalty }
        let joined = expected[row - 1] + expected[row]
        if equivalent?(joined, heard[column], row > 1 ? expected[row - 2] : nil) == true { return 1 }
        return worth(TranscriptAligner.similarity(joined, heard[column]), against: joinThreshold)
    }

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
