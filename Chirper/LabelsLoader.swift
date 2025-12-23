import Foundation

enum LabelsLoader {
    static func loadLabels(fileName: String, subdirectory: String?) throws -> [String] {
        guard let url = Bundle.main.url(
            forResource: fileName,
            withExtension: "txt",
            subdirectory: subdirectory
        ) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Labels file not found: \(fileName).txt"]
            )
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "Chirper",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to decode labels file"]
            )
        }

        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        return lines
    }
}


