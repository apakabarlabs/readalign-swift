struct Alignment {
    static let pair = 2

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
        if equivalent?(expected[row], heard[column], row > 0 ? expected[row - 1] : nil) == true {
            return 1
        }
        return worth(TranscriptAligner.similarity(expected[row], heard[column]), against: threshold)
    }

    func joinedHeard(_ row: Int, _ column: Int, span: Int) -> Double {
        let parts = heard[(column - span + 1)...column]
        guard joinable(parts), !expected[row].isEmpty else { return mismatchPenalty }
        let joined = parts.joined()
        if equivalent?(expected[row], joined, row > 0 ? expected[row - 1] : nil) == true {
            return 1
        }
        guard span <= spans(forExpectedAt: row) else { return -.infinity }
        return worth(TranscriptAligner.similarity(expected[row], joined), against: joinThreshold)
    }

    func spans(forExpectedAt row: Int) -> Int {
        max(Rules.shared.joinSpan, printedParts[row])
    }

    func consideredSpans(forExpectedAt row: Int) -> ClosedRange<Int> {
        Self.pair...max(spans(forExpectedAt: row), Rules.shared.vouchedJoinSpan)
    }

    func joinedExpected(_ row: Int, _ column: Int, span: Int) -> Double {
        let parts = expected[(row - span + 1)...row]
        guard joinable(parts), !heard[column].isEmpty else {
            return mismatchPenalty
        }
        let joined = parts.joined()
        if equivalent?(joined, heard[column], row >= span ? expected[row - span] : nil) == true {
            return 1
        }
        guard span <= Self.pair else { return -.infinity }
        return worth(TranscriptAligner.similarity(joined, heard[column]), against: joinThreshold)
    }

    func joinedPair(_ row: Int, _ column: Int) -> Double {
        guard joinable(expected[(row - 1)...row]), joinable(heard[(column - 1)...column]) else {
            return mismatchPenalty
        }
        let written = expected[row - 1] + expected[row]
        let said = heard[column - 1] + heard[column]
        if equivalent?(written, said, row > 1 ? expected[row - Self.pair] : nil) == true {
            return 1
        }
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
                for span in consideredSpans(forExpectedAt: row - 1) where column >= span {
                    best = max(
                        best,
                        score[row - 1][column - span] + joinedHeard(row - 1, column - 1, span: span)
                    )
                }
                if row >= Self.pair {
                    for span in Self.pair...min(row, Rules.shared.vouchedJoinSpan) {
                        let reached = score[row - span][column - 1]
                        best = max(best, reached + joinedExpected(row - 1, column - 1, span: span))
                    }
                }
                if row >= Self.pair, column >= Self.pair {
                    let reached = score[row - Self.pair][column - Self.pair]
                    best = max(best, reached + joinedPair(row - 1, column - 1))
                }
                score[row][column] = best
            }
        }
        return score
    }

    func joinedExpectedSpan(in score: [[Double]], cell: Double, at position: (Int, Int)) -> Int? {
        let (row, column) = position
        guard row >= Self.pair else { return nil }
        return (Self.pair...min(row, Rules.shared.vouchedJoinSpan)).first { span in
            cell == score[row - span][column - 1]
                + joinedExpected(row - 1, column - 1, span: span)
        }
    }

    func matches(in score: [[Double]]) -> [WordMatch] {
        var matches: [WordMatch] = []
        var (row, column) = (expected.count, heard.count)
        while row > 0, column > 0 {
            let cell = score[row][column]
            let straight = straight(row - 1, column - 1)
            if cell == score[row - 1][column - 1] + straight {
                if straight >= threshold {
                    matches.append(
                        WordMatch(expected: (row - 1)..<row, heard: (column - 1)..<column)
                    )
                }
                row -= 1
                column -= 1
            } else if let span = consideredSpans(forExpectedAt: row - 1).first(where: { span in
                column >= span
                    && cell == score[row - 1][column - span]
                        + joinedHeard(row - 1, column - 1, span: span)
            }) {
                if joinedHeard(row - 1, column - 1, span: span) >= joinThreshold {
                    matches.append(
                        WordMatch(expected: (row - 1)..<row, heard: (column - span)..<column)
                    )
                }
                row -= 1
                column -= span
            } else if row >= Self.pair, column >= Self.pair,
                cell == score[row - Self.pair][column - Self.pair] + joinedPair(row - 1, column - 1)
            {
                if joinedPair(row - 1, column - 1) >= joinThreshold {
                    let back = (row - Self.pair)..<row
                    matches.append(WordMatch(expected: back, heard: (column - Self.pair)..<column))
                }
                row -= Self.pair
                column -= Self.pair
            } else if let span = joinedExpectedSpan(in: score, cell: cell, at: (row, column)) {
                if joinedExpected(row - 1, column - 1, span: span) >= joinThreshold {
                    let back = (row - span)..<row
                    matches.append(WordMatch(expected: back, heard: (column - 1)..<column))
                }
                row -= span
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
