// ExportManager.swift
// AuraShift — экспорт данных (CSV — Free, XLSX — Pro)

import Foundation
import SwiftUI
import CoreData

// MARK: - ExportManager

final class ExportManager {
    static let shared = ExportManager()
    private init() {}

    // MARK: - CSV Export (Free)

    /// Генерирует CSV файл за указанный период
    func generateCSV(
        incomes: [Income],
        expenses: [Expense],
        currency: String,
        from startDate: Date,
        to endDate: Date
    ) -> URL? {
        let dataset = filteredDataset(incomes: incomes, expenses: expenses, from: startDate, to: endDate)

        var rows: [String] = ["Дата,Тип,Категория,Сумма,Валюта,Примечание"]
        for row in dataset.rows {
            rows.append([
                csvEscape(row.dateText),
                csvEscape(row.entryType),
                csvEscape(row.category),
                String(format: "%.2f", row.amount),
                csvEscape(currency),
                csvEscape(row.note)
            ].joined(separator: ","))
        }

        let totalIncome  = dataset.totalIncome
        let totalExpense = dataset.totalExpense
        rows.append("")
        rows.append("Итого,Доходы,,\(String(format: "%.2f", totalIncome)),\(currency),")
        rows.append("Итого,Расходы,,\(String(format: "%.2f", totalExpense)),\(currency),")
        rows.append("Итого,Баланс,,\(String(format: "%.2f", totalIncome - totalExpense)),\(currency),")

        let csvString = rows.joined(separator: "\n")

        // Сохраняем во временную папку
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let fileName = "AuraShift-\(dateFormatter.string(from: startDate))-\(dateFormatter.string(from: endDate)).csv"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            // UTF-8 с BOM для корректного открытия в Excel
            var data = Data([0xEF, 0xBB, 0xBF])
            if let csvData = csvString.data(using: .utf8) {
                data.append(csvData)
            }
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("❌ Ошибка записи CSV: \(error)")
            return nil
        }
    }

    // MARK: - XLSX Export (Pro)

    func generateXLSX(
        incomes: [Income],
        expenses: [Expense],
        currency: String,
        from startDate: Date,
        to endDate: Date
    ) -> URL? {
        let dataset = filteredDataset(incomes: incomes, expenses: expenses, from: startDate, to: endDate)
        guard !dataset.rows.isEmpty else { return nil }

        var sheetRows: [[XLSXCellValue]] = []
        sheetRows.append([
            .text("Дата"),
            .text("Тип"),
            .text("Категория"),
            .text("Сумма"),
            .text("Валюта"),
            .text("Примечание")
        ])

        for row in dataset.rows {
            sheetRows.append([
                .text(row.dateText),
                .text(row.entryType),
                .text(row.category),
                .number(row.amount),
                .text(currency),
                .text(row.note)
            ])
        }

        sheetRows.append([])
        sheetRows.append([
            .text("Итого"), .text("Доходы"), .text(""),
            .number(dataset.totalIncome), .text(currency), .text("")
        ])
        sheetRows.append([
            .text("Итого"), .text("Расходы"), .text(""),
            .number(dataset.totalExpense), .text(currency), .text("")
        ])
        sheetRows.append([
            .text("Итого"), .text("Баланс"), .text(""),
            .number(dataset.totalIncome - dataset.totalExpense), .text(currency), .text("")
        ])

        guard let xlsxData = XLSXBuilder.build(sheetName: "AuraShift", rows: sheetRows) else {
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let fileName = "AuraShift-\(dateFormatter.string(from: startDate))-\(dateFormatter.string(from: endDate)).xlsx"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try xlsxData.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("❌ Ошибка записи XLSX: \(error)")
            return nil
        }
    }

    // MARK: - Helpers

    private typealias ExportRowTuple = (sortDate: Date, dateText: String, entryType: String, category: String, amount: Double, note: String)
    private typealias FilteredDataset = (rows: [ExportRowTuple], totalIncome: Double, totalExpense: Double)

    private func filteredDataset(
        incomes: [Income],
        expenses: [Expense],
        from startDate: Date,
        to endDate: Date
    ) -> FilteredDataset {
        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDate)) ?? endDate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        var rows: [ExportRowTuple] = []

        let filteredIncomes = incomes.compactMap { i -> Income? in
            guard let d = i.date, d >= start, d < end else { return nil }
            return i
        }.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }

        for inc in filteredIncomes {
            guard let date = inc.date else { continue }
            rows.append((
                sortDate: date,
                dateText: dateFormatter.string(from: date),
                entryType: "Доход",
                category: inc.type ?? "Работа",
                amount: inc.hoursWorked * inc.hourlyRate + inc.tips + inc.floatingAmount,
                note: inc.note ?? ""
            ))
        }

        let filteredExpenses = expenses.compactMap { e -> Expense? in
            guard let d = e.date, d >= start, d < end else { return nil }
            return e
        }.sorted { ($0.date ?? Date()) < ($1.date ?? Date()) }

        for exp in filteredExpenses {
            guard let date = exp.date else { continue }
            rows.append((
                sortDate: date,
                dateText: dateFormatter.string(from: date),
                entryType: "Расход",
                category: exp.category ?? "Другое",
                amount: exp.amount,
                note: exp.notes ?? ""
            ))
        }

        rows.sort { lhs, rhs in
            if lhs.sortDate == rhs.sortDate {
                return lhs.entryType < rhs.entryType
            }
            return lhs.sortDate < rhs.sortDate
        }

        let totalIncome = filteredIncomes.reduce(0.0) { $0 + $1.hoursWorked * $1.hourlyRate + $1.tips + $1.floatingAmount }
        let totalExpense = filteredExpenses.reduce(0.0) { $0 + $1.amount }
        return (rows: rows, totalIncome: totalIncome, totalExpense: totalExpense)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

private enum XLSXCellValue {
    case text(String)
    case number(Double)
}

private enum XLSXBuilder {
    static func build(sheetName: String, rows: [[XLSXCellValue]]) -> Data? {
        let workbookXML = workbookXML(sheetName: sheetName)
        let worksheetXML = worksheetXML(rows: rows)
        let stylesXML = stylesXML()

        let files: [String: Data] = [
            "[Content_Types].xml": Data(contentTypesXML.utf8),
            "_rels/.rels": Data(relsRootXML.utf8),
            "xl/workbook.xml": Data(workbookXML.utf8),
            "xl/_rels/workbook.xml.rels": Data(workbookRelsXML.utf8),
            "xl/styles.xml": Data(stylesXML.utf8),
            "xl/worksheets/sheet1.xml": Data(worksheetXML.utf8)
        ]

        return ZipArchiveBuilder.build(files: files)
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

    private static let relsRootXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
    </Relationships>
    """

    private static let workbookRelsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
      <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
      <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
    </Relationships>
    """

    private static func workbookXML(sheetName: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"
                  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(xmlEscape(sheetName))" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """
    }

    private static func stylesXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <numFmts count="1">
            <numFmt numFmtId="164" formatCode="#,##0.00"/>
          </numFmts>
          <fonts count="2">
            <font>
              <sz val="11"/>
              <name val="SF Pro Text"/>
            </font>
            <font>
              <b/>
              <sz val="11"/>
              <name val="SF Pro Text"/>
            </font>
          </fonts>
          <fills count="2">
            <fill><patternFill patternType="none"/></fill>
            <fill><patternFill patternType="gray125"/></fill>
          </fills>
          <borders count="1">
            <border>
              <left/><right/><top/><bottom/><diagonal/>
            </border>
          </borders>
          <cellStyleXfs count="1">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0"/>
          </cellStyleXfs>
          <cellXfs count="3">
            <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
            <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
            <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
          </cellXfs>
          <cellStyles count="1">
            <cellStyle name="Normal" xfId="0" builtinId="0"/>
          </cellStyles>
        </styleSheet>
        """
    }

    private static func worksheetXML(rows: [[XLSXCellValue]]) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>
        """

        for (rowIndex, row) in rows.enumerated() {
            let excelRow = rowIndex + 1
            xml += "<row r=\"\(excelRow)\">"
            for (colIndex, cell) in row.enumerated() {
                let ref = "\(excelColumn(colIndex + 1))\(excelRow)"
                switch cell {
                case .text(let value):
                    let style = rowIndex == 0 ? " s=\"1\"" : ""
                    let escaped = xmlEscape(value)
                    let preserve = value.hasPrefix(" ") || value.hasSuffix(" ") ? " xml:space=\"preserve\"" : ""
                    xml += "<c r=\"\(ref)\"\(style) t=\"inlineStr\"><is><t\(preserve)>\(escaped)</t></is></c>"
                case .number(let value):
                    let style = " s=\"2\""
                    xml += "<c r=\"\(ref)\"\(style)><v>\(formatNumber(value))</v></c>"
                }
            }
            xml += "</row>"
        }

        xml += """
          </sheetData>
        </worksheet>
        """
        return xml
    }

    private static func excelColumn(_ value: Int) -> String {
        var number = value
        var result = ""
        while number > 0 {
            let modulo = (number - 1) % 26
            result = String(UnicodeScalar(65 + modulo)!) + result
            number = (number - modulo - 1) / 26
        }
        return result
    }

    private static func formatNumber(_ value: Double) -> String {
        let formatted = String(format: "%.2f", value)
        return formatted.replacingOccurrences(of: ",", with: ".")
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private enum ZipArchiveBuilder {
    static func build(files: [String: Data]) -> Data? {
        var archive = Data()
        var centralDirectory = Data()
        var entriesCount: UInt16 = 0

        let sortedFiles = files.keys.sorted()
        let timestamp = dosTimestamp(date: Date())

        for path in sortedFiles {
            guard let payload = files[path] else { continue }
            guard let pathData = path.data(using: .utf8) else { return nil }
            let crc = CRC32.compute(payload)
            let offset = UInt32(archive.count)
            let payloadSize = UInt32(payload.count)
            let fileNameLen = UInt16(pathData.count)

            // Local file header
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20)) // version needed
            archive.appendLE(UInt16(0))  // flags
            archive.appendLE(UInt16(0))  // compression = store
            archive.appendLE(timestamp.time)
            archive.appendLE(timestamp.date)
            archive.appendLE(crc)
            archive.appendLE(payloadSize)
            archive.appendLE(payloadSize)
            archive.appendLE(fileNameLen)
            archive.appendLE(UInt16(0)) // extra length
            archive.append(pathData)
            archive.append(payload)

            // Central directory header
            centralDirectory.appendLE(UInt32(0x02014b50))
            centralDirectory.appendLE(UInt16(20)) // version made by
            centralDirectory.appendLE(UInt16(20)) // version needed
            centralDirectory.appendLE(UInt16(0))  // flags
            centralDirectory.appendLE(UInt16(0))  // compression
            centralDirectory.appendLE(timestamp.time)
            centralDirectory.appendLE(timestamp.date)
            centralDirectory.appendLE(crc)
            centralDirectory.appendLE(payloadSize)
            centralDirectory.appendLE(payloadSize)
            centralDirectory.appendLE(fileNameLen)
            centralDirectory.appendLE(UInt16(0)) // extra
            centralDirectory.appendLE(UInt16(0)) // comment
            centralDirectory.appendLE(UInt16(0)) // disk start
            centralDirectory.appendLE(UInt16(0)) // int attrs
            centralDirectory.appendLE(UInt32(0)) // ext attrs
            centralDirectory.appendLE(offset)
            centralDirectory.append(pathData)

            entriesCount &+= 1
        }

        let centralOffset = UInt32(archive.count)
        let centralSize = UInt32(centralDirectory.count)
        archive.append(centralDirectory)

        // End of central directory
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0)) // disk number
        archive.appendLE(UInt16(0)) // disk with central dir
        archive.appendLE(entriesCount)
        archive.appendLE(entriesCount)
        archive.appendLE(centralSize)
        archive.appendLE(centralOffset)
        archive.appendLE(UInt16(0)) // comment length

        return archive
    }

    private static func dosTimestamp(date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let comp = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((comp.year ?? 1980) - 1980, 0)
        let month = comp.month ?? 1
        let day = comp.day ?? 1
        let hour = comp.hour ?? 0
        let minute = comp.minute ?? 0
        let second = (comp.second ?? 0) / 2
        let dosTime = UInt16((hour << 11) | (minute << 5) | second)
        let dosDate = UInt16((year << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

private enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { value in
            var crc = UInt32(value)
            for _ in 0..<8 {
                if (crc & 1) == 1 {
                    crc = 0xEDB88320 ^ (crc >> 1)
                } else {
                    crc >>= 1
                }
            }
            return crc
        }
    }()

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<UInt16>.size))
    }

    mutating func appendLE(_ value: UInt32) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<UInt32>.size))
    }
}

// MARK: - ExportSheet (SwiftUI-обёртка для UIActivityViewController)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - ExportPeriod

enum ExportPeriod: String, CaseIterable, Identifiable {
    case thisMonth  = "Этот месяц"
    case lastMonth  = "Прошлый месяц"
    case last3Month = "3 месяца"
    case thisYear   = "Этот год"
    case allTime    = "Всё время"
    case custom     = "Выбрать период"

    var id: String { rawValue }

    var localizedTitle: String {
        NSLocalizedString(rawValue, comment: "export period title")
    }

    func dateRange() -> (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            return (start, now)
        case .lastMonth:
            let firstOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let firstOfLastMonth = cal.date(byAdding: .month, value: -1, to: firstOfThisMonth) ?? now
            let lastOfLastMonth  = cal.date(byAdding: .day, value: -1, to: firstOfThisMonth) ?? now
            return (firstOfLastMonth, lastOfLastMonth)
        case .last3Month:
            let start = cal.date(byAdding: .month, value: -3, to: now) ?? now
            return (start, now)
        case .thisYear:
            let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? now
            return (start, now)
        case .allTime:
            return (Date(timeIntervalSince1970: 0), now)
        case .custom:
            return (now, now) // будет переопределено через DatePicker
        }
    }
}

