import Foundation

func require(_ value: @autoclosure () throws -> Bool) throws {
    let result = try value()
    precondition(result)
}

let root = FileManager.default.temporaryDirectory.appendingPathComponent("devnotes-export-check-\(UUID())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }

let csv = String(decoding: TableExporter.csvData(from: [["=1+1"], ["обычный текст"], ["строка\nс переносом"]]), as: UTF8.self)
precondition(csv.contains("'=1+1"))
precondition(csv.contains("обычный текст"))
precondition(csv.contains("\"строка\nс переносом\""))

let destination = root.appendingPathComponent("table.xlsx")
try Data("previous export".utf8).write(to: destination)
try TableExporter.writeXLSX([["Название", "Значение"], ["A & B", "=1+1"]], to: destination)
let unzip = Process()
let output = Pipe()
unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
unzip.arguments = ["-p", destination.path, "xl/worksheets/sheet1.xml"]
unzip.standardOutput = output
try unzip.run()
let xml = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
unzip.waitUntilExit()
precondition(unzip.terminationStatus == 0)
precondition(xml.contains("A &amp; B"))
precondition(xml.contains("t=\"inlineStr\""))
precondition(!xml.contains("<f>"))

// An unsuccessful destination write must preserve its existing contents.
let folder = root.appendingPathComponent("existing-folder")
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
let marker = folder.appendingPathComponent("keep.txt")
try Data("keep".utf8).write(to: marker)
var failed = false
do { try TableExporter.writeXLSX([["example"]], to: folder) }
catch { failed = true }
precondition(failed)
try require(try String(contentsOf: marker, encoding: .utf8) == "keep")
print("PASS: literal CSV, valid XLSX replacement, XML escaping, preservation on write failure. Temporary synthetic data only.")
