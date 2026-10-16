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
    /// to give either of them.
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

            return WordSpan(
                start: wentQuiet ? min(start, span.start) : span.start,
                end: endWentQuiet ? max(end, span.end) : span.end
            )
        }
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
        return max(room * Rules.shared.speechAboveRoom, Rules.shared.quietestRoom)
    }

    public static func speechLevel(of frames: [Double]) -> Double {
        guard !frames.isEmpty else { return Rules.shared.quietestSpeech }
        let quieter = Int(Double(frames.count) * (1 - Rules.shared.speechFromLoudestShare))
        let louder = frames.sorted()[quieter...]
        let mean = louder.reduce(0, +) / Double(louder.count)
        return max(mean, Rules.shared.quietestSpeech)
    }
}
