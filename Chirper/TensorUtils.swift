import Foundation

enum TensorUtils {
    static func data(from floats: [Float]) -> Data {
        var array = floats
        return Data(bytes: &array, count: array.count * MemoryLayout<Float>.size)
    }

    static func data(from ints: [Int16]) -> Data {
        var array = ints
        return Data(bytes: &array, count: array.count * MemoryLayout<Int16>.size)
    }

    static func data(from ints: [Int32]) -> Data {
        var array = ints
        return Data(bytes: &array, count: array.count * MemoryLayout<Int32>.size)
    }

    static func floats(from data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { ptr -> [Float] in
            let buffer = ptr.bindMemory(to: Float.self)
            return Array(buffer.prefix(count))
        }
    }

    static func softmax(_ logits: [Float]) -> [Float] {
        guard !logits.isEmpty else { return [] }
        let maxLogit = logits.max() ?? 0
        let exps = logits.map { expf($0 - maxLogit) }
        let sumExp = exps.reduce(0, +)
        guard sumExp > 0 else { return Array(repeating: 0, count: logits.count) }
        return exps.map { $0 / sumExp }
    }

    static func top1(_ values: [Float]) -> (Int, Float)? {
        guard let max = values.max(), let idx = values.firstIndex(of: max) else {
            return nil
        }
        return (idx, max)
    }
}


