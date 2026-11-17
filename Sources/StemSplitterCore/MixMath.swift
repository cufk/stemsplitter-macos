import Foundation

public enum MixMath {
    public static func mixChannels(_ channels: [(input: [Float], gain: Float)], count: Int) -> [Float] {
        var output = [Float](repeating: 0, count: count)
        for (input, gain) in channels {
            let n = min(count, input.count)
            for i in 0..<n {
                output[i] += input[i] * gain
            }
        }
        return output
    }

    public static func clamp(_ values: [Float], min minimum: Float = -1, max maximum: Float = 1) -> [Float] {
        values.map { Swift.min(Swift.max($0, minimum), maximum) }
    }

    public static func applyGain(_ input: UnsafePointer<Float>, _ output: UnsafeMutablePointer<Float>, count: Int, gain: Float) {
        guard count > 0 else { return }
        for i in 0..<count {
            output[i] = input[i] * gain
        }
    }

    public static func accumulate(_ input: UnsafePointer<Float>, _ accumulator: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        for i in 0..<count {
            accumulator[i] += input[i]
        }
    }

    public static func clampChannel(_ buffer: UnsafeMutablePointer<Float>, count: Int, min minimum: Float = -1, max maximum: Float = 1) {
        guard count > 0 else { return }
        for i in 0..<count {
            let value = buffer[i]
            buffer[i] = Swift.min(Swift.max(value, minimum), maximum)
        }
    }

    public static func zero(_ buffer: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        for i in 0..<count {
            buffer[i] = 0
        }
    }
}
