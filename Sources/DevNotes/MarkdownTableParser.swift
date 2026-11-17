import Foundation

enum MarkdownTableParser {
    static func parse(_ source: String) -> [[String]]? {
        let lines = source
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }

        let header = cells(in: lines[0])
        let separator = cells(in: lines[1])
        guard header.count >= 2,
              separator.count == header.count,
              separator.allSatisfy(isSeparatorCell) else { return nil }

        var result = [header]
        for line in lines.dropFirst(2) {
            var row = cells(in: line)
            guard !row.isEmpty else { continue }
            if row.count < header.count {
                row.append(contentsOf: Array(repeating: "", count: header.count - row.count))
            } else if row.count > header.count {
                row = Array(row.prefix(header.count))
            }
            result.append(row)
        }
        return result
    }

    private static func cells(in line: String) -> [String] {
        let normalized = line.replacingOccurrences(of: "\\|", with: "|")
        var parts = normalized
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }

        if normalized.hasPrefix("|") && parts.first?.isEmpty == true { parts.removeFirst() }
        if normalized.hasSuffix("|") && parts.last?.isEmpty == true { parts.removeLast() }
        return parts
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        let value = cell
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return value.count >= 3 && value.allSatisfy { $0 == "-" }
    }
}
