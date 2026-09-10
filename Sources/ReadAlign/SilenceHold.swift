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
        let frameSeconds = Rules.shared.frameSeconds
        let duration = Double(samples.count) / sampleRate

        return spans.indices.map { index in
            let span = spans[index]
            let next = index + 1 < spans.count ? spans[index + 1].start : duration
            let ceiling = min(next, span.end + limit)
            var end = span.end
            var frame = Int(span.end / frameSeconds)
            var wentQuiet = false
            while Double(frame + 1) * frameSeconds <= ceiling, frame < frames.count {
                if frames[frame] < threshold {
                    wentQuiet = true
                } else if wentQuiet {
                    break
                }
                end = Double(frame + 1) * frameSeconds
                frame += 1
            }
            return WordSpan(
                start: span.start,
                end: min(max(span.end, end), max(next, span.start))
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
        let sorted = frames.sorted()
        let louder = sorted[(sorted.count / 2)...]
        let mean = louder.reduce(0, +) / Double(louder.count)
        return max(mean, 1e-6)
    }
}
