import Foundation

extension String {
    func sanitizedFilename() -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let scalars = self.unicodeScalars.map { invalid.contains($0) ? "_" : Character($0) }
        let joined = String(scalars)
        return joined.replacingOccurrences(of: " ", with: "_")
    }
}


