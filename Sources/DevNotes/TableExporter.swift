import AppKit
import Foundation
import UniformTypeIdentifiers

enum TableExporter {
    enum Format {
        case csv
        case xlsx

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .xlsx: return "xlsx"
            }
        }

        var contentType: UTType {
            switch self {
            case .csv: return .commaSeparatedText
            case .xlsx: return UTType(filenameExtension: "xlsx") ?? .data
            }
        }
    }

    enum ExportError: LocalizedError {
        case archiveFailed(String)

        var errorDescription: String? {
            switch self {
            case .archiveFailed(let message):
                return message.isEmpty ? "Не удалось создать Excel-файл." : message
            }
        }
    }

    static func export(_ table: [[String]], as format: Format, suggestedName: String) throws {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "\(safeFileName(suggestedName)).\(format.fileExtension)"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        switch format {
        case .csv:
            try csvData(from: table).write(to: destination, options: .atomic)
        case .xlsx:
            try writeXLSX(table, to: destination)
        }
    }

    static func csvData(from table: [[String]]) -> Data {
        let delimiter = Locale.current.decimalSeparator == "," ? ";" : ","
        let text = table.map { row in
            row.map { csvCell($0, delimiter: delimiter) }.joined(separator: delimiter)
        }.joined(separator: "\r\n")

        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    private static func csvCell(_ value: String, delimiter: String) -> String {
        // CSV has no cell types: keep formula-like note text literal in spreadsheets.
        let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
        let needsLiteralPrefix = first.map { "=+-@".contains($0) } == true
            || value.first.map { "\t\r\n".contains($0) } == true
        let value = needsLiteralPrefix ? "'" + value : value
        guard value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func writeXLSX(_ table: [[String]], to destination: URL) throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DevNotes-XLSX-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
        let archive = root.appendingPathComponent("table.xlsx")
        try fileManager.createDirectory(
            at: root.appendingPathComponent("_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("xl/_rels", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("xl/worksheets", isDirectory: true),
            withIntermediateDirectories: true
        )

        try write(contentTypesXML, to: root.appendingPathComponent("[Content_Types].xml"))
        try write(rootRelationshipsXML, to: root.appendingPathComponent("_rels/.rels"))
        try write(workbookXML, to: root.appendingPathComponent("xl/workbook.xml"))
        try write(workbookRelationshipsXML, to: root.appendingPathComponent("xl/_rels/workbook.xml.rels"))
        try write(stylesXML, to: root.appendingPathComponent("xl/styles.xml"))
        try write(sheetXML(for: table), to: root.appendingPathComponent("xl/worksheets/sheet1.xml"))

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", archive.path, "[Content_Types].xml", "_rels", "xl"]
        // Do not inherit user ZIPOPT flags that could alter archive contents.
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "C"]
        process.currentDirectoryURL = root
        process.standardError = errorPipe
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? ""
            throw ExportError.archiveFailed(message)
        }
        // Only replace the destination after packaging has completed successfully.
        try Data(contentsOf: archive).write(to: destination, options: .atomic)
    }

    private static func sheetXML(for table: [[String]]) -> String {
        let columnCount = max(table.map(\.count).max() ?? 0, 1)
        let rowCount = max(table.count, 1)
        let lastCell = "\(columnName(columnCount - 1))\(rowCount)"

        let columns = (0..<columnCount).map { column in
            let longest = table.compactMap { row in
                column < row.count ? row[column].count : nil
            }.max() ?? 0
            let width = min(max(Double(longest) * 1.05 + 3, 11), 48)
            return "<col min=\"\(column + 1)\" max=\"\(column + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }.joined()

        let rows = table.enumerated().map { rowIndex, row in
            let cells = (0..<columnCount).map { columnIndex in
                let value = columnIndex < row.count ? row[columnIndex] : ""
                let reference = "\(columnName(columnIndex))\(rowIndex + 1)"
                let style = rowIndex == 0 ? 1 : (rowIndex.isMultiple(of: 2) ? 2 : 0)
                return "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xmlEscaped(value))</t></is></c>"
            }.joined()
            let height = rowIndex == 0 ? 26 : 22
            return "<row r=\"\(rowIndex + 1)\" ht=\"\(height)\" customHeight=\"1\">\(cells)</row>"
        }.joined()

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <dimension ref="A1:\(lastCell)"/>
          <sheetViews><sheetView showGridLines="0" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
          <sheetFormatPr defaultRowHeight="20"/>
          <cols>\(columns)</cols>
          <sheetData>\(rows)</sheetData>
          <autoFilter ref="A1:\(lastCell)"/>
        </worksheet>
        """
    }

    private static func columnName(_ zeroBasedIndex: Int) -> String {
        var index = zeroBasedIndex + 1
        var result = ""
        while index > 0 {
            index -= 1
            let scalar = UnicodeScalar(65 + index % 26)!
            result.insert(Character(scalar), at: result.startIndex)
            index /= 26
        }
        return result
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func safeFileName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((cleaned.isEmpty ? "Таблица" : cleaned).prefix(80))
    }

    private static func write(_ value: String, to url: URL) throws {
        try Data(value.utf8).write(to: url, options: .atomic)
    }

    private static let contentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
      <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
      <Default Extension="xml" ContentType="application/xml"/>
      <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
      <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
      <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
    </Types>
    """

    private static let rootRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
      <sheets><sheet name="Таблица" sheetId="1" r:id="rId1"/></sheets>
    </workbook>
    """

    private static let workbookRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2">
        <font><sz val="11"/><name val="Arial"/><family val="2"/></font>
        <font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Arial"/><family val="2"/></font>
      </fonts>
      <fills count="4">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFE4572E"/><bgColor indexed="64"/></patternFill></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFF7F5F2"/><bgColor indexed="64"/></patternFill></fill>
      </fills>
      <borders count="2">
        <border><left/><right/><top/><bottom/><diagonal/></border>
        <border><left style="thin"><color rgb="FFD9D9D9"/></left><right style="thin"><color rgb="FFD9D9D9"/></right><top style="thin"><color rgb="FFD9D9D9"/></top><bottom style="thin"><color rgb="FFD9D9D9"/></bottom><diagonal/></border>
      </borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="3">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center" wrapText="1"/></xf>
        <xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>
      </cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}
