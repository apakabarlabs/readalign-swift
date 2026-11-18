import Foundation

public enum SilenceHold {
    public static func held(
        _ spans: [WordSpan],
        samples: [Float],
        sampleRate: Double,
        limit: TimeInterval = Rules.shared.holdLimit
    ) -> [WordSpan] {
        let frames = energyFrames(of: samples, sampleRate: sampleRate)
        guard !frames.isEmpty else { return spans }
        let threshold = speechThreshold(of: frames)
        let eachFrame = Rules.shared.frameSeconds
        let duration = Double(samples.count) / sampleRate

        return spans.indices.map { index in
            let span = spans[index]
            let next = index + 1 < spans.count ? spans[index + 1].start : duration
            let ceiling = min(next, span.end + limit)
            var end = span.end
            var frame = Int(span.end / eachFrame)
            var wentQuiet = false
            while Double(frame + 1) * eachFrame <= ceiling, frame < frames.count {
                if frames[frame] < threshold {
                    wentQuiet = true
                } else if wentQuiet {
                    break
                }
                end = Double(frame + 1) * eachFrame
                frame += 1
            }
            return WordSpan(
                start: span.start,
                end: min(max(span.end, end), max(next, span.start))
            )
        }
    }

    /// Each word given the quiet on both sides of it, so that a cut along its edges keeps
    /// the consonants a recogniser leaves outside its mark.
    ///
    /// A start goes back from its mark through the word's own sound and then through the
    /// quiet before it, and stops where the recording speaks again; an end goes on the
    /// same way. Neither passes the middle of the gap to the neighbouring mark, the ends
    /// of the recording, or `limit` from its own mark. An edge that meets no quiet before
    /// one of those stays where it was: with no pause between two words there is nothing
    /// to give either of them. So does an edge that would move by less than
    /// `least_widening`, each edge judged on its own and the distance counted in samples.
    ///
    /// Where an edge between two words falls inside a sound, both words first meet in the
    /// middle of the nearest pause within `limit` of it: the recogniser marks a word from
    /// where it is sure of it, so the opening hiss of the next word, or the first stretch of
    /// a vowel it opens with, sounds before its mark. That holds for two words marked edge
    /// to edge and for two with a gap between their marks alike, since the gap can lie in
    /// the next word's own sound. The edge goes no further than the middle of either word,
    /// so a short word keeps the pause after it, and words whose marks overlap keep them.
    public static func widened(
        _ spans: [WordSpan],
        samples: [Float],
        sampleRate: Double,
        limit: TimeInterval = Rules.shared.holdLimit
    ) -> [WordSpan] {
        let frames = energyFrames(of: samples, sampleRate: sampleRate)
        guard !frames.isEmpty else { return spans }
        let threshold = speechThreshold(of: frames)
        let size = max(Int(Rules.shared.frameSeconds * sampleRate), 1)
        let eachFrame = Double(size) / sampleRate
        let duration = Double(samples.count) / sampleRate
        let spans = settled(spans, in: frames, at: sampleRate, within: limit)

        return spans.indices.map { index in
            let span = spans[index]
            var floor = max(0, span.start - limit)
            if index > 0 {
                floor = max(floor, (spans[index - 1].end + span.start) / 2)
            }
            var ceiling = min(duration, span.end + limit)
            if index + 1 < spans.count {
                ceiling = min(ceiling, (span.end + spans[index + 1].start) / 2)
            }

            var start = span.start
            var frame = (Int((span.start * sampleRate).rounded()) + size - 1) / size - 1
            var wentQuiet = false
            while frame >= 0, frame < frames.count, Double(frame + 1) * eachFrame > floor {
                if frames[frame] < threshold {
                    wentQuiet = true
                } else if wentQuiet {
                    break
                }
                start = max(Double(frame) * eachFrame, floor)
                frame -= 1
            }

            var end = span.end
            frame = Int((span.end * sampleRate).rounded()) / size
            var endWentQuiet = false
            while frame >= 0, frame < frames.count, Double(frame) * eachFrame < ceiling {
                if frames[frame] < threshold {
                    endWentQuiet = true
                } else if endWentQuiet {
                    break
                }
                end = min(Double(frame + 1) * eachFrame, ceiling)
                frame += 1
            }

            let least = (Rules.shared.leastWidening * sampleRate).rounded()
            let startMoves = ((span.start - start) * sampleRate).rounded() >= least
            let endMoves = ((end - span.end) * sampleRate).rounded() >= least
            return WordSpan(
                start: wentQuiet && startMoves ? start : span.start,
                end: endWentQuiet && endMoves ? end : span.end
            )
        }
    }

    private static func settled(
        _ spans: [WordSpan],
        in frames: [Double],
        at sampleRate: Double,
        within limit: TimeInterval
    ) -> [WordSpan] {
        let threshold = speechThreshold(of: frames)
        let eachFrame = Double(max(Int(Rules.shared.frameSeconds * sampleRate), 1)) / sampleRate
        let pauses = quietRuns(
            frames,
            threshold: threshold,
            atLeast: max(Int((Rules.shared.pauseSeconds / eachFrame).rounded()), 1)
        )
        var settled = spans
        for index in settled.indices.dropLast() {
            let word = settled[index]
            let following = settled[index + 1]
            guard (word.end * sampleRate).rounded() <= (following.start * sampleRate).rounded()
            else { continue }
            let touching =
                (word.end * sampleRate).rounded() == (following.start * sampleRate).rounded()
            let start = EdgeInSound(time: following.start, looksBack: true, looksOn: touching)
            let end = EdgeInSound(time: word.end, looksBack: touching, looksOn: true)
            let loud = [start, end].filter { edge in
                let frame = Int((edge.time / eachFrame).rounded())
                return frame > 0 && frame < frames.count
                    && frames[frame - 1] >= threshold && frames[frame] >= threshold
            }
            guard !loud.isEmpty else { continue }
            let lowest = (word.start + word.end) / 2
            let highest = (following.start + following.end) / 2
            let reachable = pauses.compactMap {
                run -> (distance: TimeInterval, middle: TimeInterval)? in
                let quietFrom = Double(run.lowerBound) * eachFrame
                let quietUntil = Double(run.upperBound) * eachFrame
                let distance =
                    loud.compactMap { edge -> TimeInterval? in
                        if quietUntil <= edge.time {
                            return edge.looksBack ? edge.time - quietUntil : nil
                        }
                        return edge.looksOn ? quietFrom - edge.time : nil
                    }.min() ?? .infinity
                let middle = (quietFrom + quietUntil) / 2
                guard distance <= limit, middle >= lowest, middle <= highest else { return nil }
                return (distance, middle)
            }
            guard let nearest = reachable.min(by: { $0.distance < $1.distance }) else { continue }
            settled[index] = WordSpan(start: word.start, end: nearest.middle)
            settled[index + 1] = WordSpan(start: nearest.middle, end: following.end)
        }
        return settled
    }

    private struct EdgeInSound {
        let time: TimeInterval
        let looksBack: Bool
        let looksOn: Bool
    }

    private static func quietRuns(
        _ frames: [Double],
        threshold: Double,
        atLeast: Int
    ) -> [Range<Int>] {
        var runs: [Range<Int>] = []
        var start: Int?
        for (index, energy) in frames.enumerated() {
            if energy < threshold {
                if start == nil { start = index }
            } else if let from = start {
                if index - from >= atLeast { runs.append(from..<index) }
                start = nil
            }
        }
        if let from = start, frames.count - from >= atLeast { runs.append(from..<frames.count) }
        return runs
    }

    public static var frameSeconds: TimeInterval { Rules.shared.frameSeconds }

    public static func energyFrames(of samples: [Float], sampleRate: Double) -> [Double] {
        let size = max(Int(Rules.shared.frameSeconds * sampleRate), 1)
        return stride(from: 0, to: samples.count, by: size).map { start in
            let end = min(start + size, samples.count)
            var sum = 0.0
            for index in start..<end { sum += Double(samples[index]) * Double(samples[index]) }
            return (sum / Double(end - start)).squareRoot()
        }
    }

    public static func speechThreshold(of frames: [Double]) -> Double {
        guard !frames.isEmpty else { return 0 }
        let room = frames.sorted()[Int(Double(frames.count) * Rules.shared.roomQuantile)]
        return max(
            room * Rules.shared.speechAboveRoom,
            Rules.shared.quietestRoom,
            speechLevel(of: frames) * Rules.shared.quietBelowVoice
        )
    }

    public static func speechLevel(of frames: [Double]) -> Double {
        guard !frames.isEmpty else { return Rules.shared.quietestSpeech }
        let quieter = Int(Double(frames.count) * (1 - Rules.shared.speechFromLoudestShare))
        let louder = frames.sorted()[quieter...]
        let mean = louder.reduce(0, +) / Double(louder.count)
        return max(mean, Rules.shared.quietestSpeech)
    }
}
