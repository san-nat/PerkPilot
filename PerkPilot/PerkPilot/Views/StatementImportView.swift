import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - StatementImportView
//
// Import flow: pick a CSV/PDF → parse → preview (with warnings and the
// detected format) → confirm. Nothing is written to the store until the
// user taps "Import". Raw files are never persisted anywhere.

struct StatementImportView: View {
    var preselectedCardStableId: String?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<CardItem> { !$0.isArchived }, sort: \CardItem.canonicalName)
    private var cards: [CardItem]

    @State private var cardStableId: String = ""
    @State private var periodKey: String = Self.currentMonthKey()
    @State private var showingPicker = false

    @State private var fileName = ""
    @State private var source: StatementSource = .csv
    @State private var csvResult: CSVParseResult?
    @State private var pdfResult: PDFParseResult?
    @State private var mapping: ColumnMapping?
    @State private var negativeIsCharge = true
    @State private var pdfFlipSigns = false
    @State private var parseError: String?

    private static func currentMonthKey() -> String {
        RecurrenceEngine.periodKey(cadence: .monthly, date: Date()) ?? "2026-10"
    }

    private var parsed: [ParsedTransaction] {
        if let csvResult { return csvResult.transactions }
        if let pdfResult {
            // PDF sign convention is a guess — let the user flip it if the
            // preview shows charges on the wrong side.
            pdfResult.transactions.map { tx in
                var t = tx
                if pdfFlipSigns { t.amount = -t.amount }
                return t
            }
        }
        return []
    }

    private var warnings: [String] {
        (csvResult?.warnings ?? []) + (pdfResult?.warnings ?? [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Privacy") {
                    Label(
                        "Statements stay on this iPhone. They're parsed here, never uploaded, and excluded from any future sync.",
                        systemImage: "lock.shield"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Section("Statement") {
                    Picker("Card", selection: $cardStableId) {
                        ForEach(cards, id: \.stableId) { card in
                            Text(card.canonicalName).tag(card.stableId)
                        }
                    }
                    MonthPicker(periodKey: $periodKey)
                    Button(fileName.isEmpty ? "Choose file…" : fileName) {
                        showingPicker = true
                    }
                    if let profile = csvResult?.detectedProfile {
                        LabeledContent("Detected format", value: profile)
                    }
                }

                if let parseError {
                    Section {
                        Text(parseError).foregroundStyle(.red).font(.callout)
                    }
                }

                if csvResult?.needsManualMapping == true,
                   let headers = csvResult?.headers, !headers.isEmpty {
                    Section("Map columns") {
                        Text("This layout wasn't recognized. Tell PerkPilot which column is which — nothing is imported until you confirm.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ColumnMappingPicker(headers: headers, mapping: mappingBinding)
                            .onChange(of: mapping) { _, _ in remap() }
                        Toggle("Charges are negative numbers", isOn: $negativeIsCharge)
                            .onChange(of: negativeIsCharge) { _, _ in remap() }
                        Text("Chase and Citi show charges as negative; Amex and Discover show them as positive.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !parsed.isEmpty {
                    Section("Preview — \(parsed.count) transactions") {
                        if pdfResult != nil {
                            Text("PDF parsing is best-effort. \(Int((pdfResult?.lowConfidenceShare ?? 0) * 100))% of rows are low-confidence — review the flagged ones after import, or use CSV for full accuracy.")
                                .font(.callout)
                                .foregroundStyle(.orange)
                            Toggle("Charges appear as positive numbers", isOn: $pdfFlipSigns)
                                .font(.callout)
                        }
                        ForEach(parsed.prefix(8), id: \.sourceLine) { tx in
                            ParsedRowPreview(tx: tx)
                        }
                        if parsed.count > 8 {
                            Text("…and \(parsed.count - 8) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !warnings.isEmpty {
                    Section("Skipped rows (\(warnings.count))") {
                        ForEach(warnings.prefix(5), id: \.self) { w in
                            Text(w).font(.caption).foregroundStyle(.secondary)
                        }
                        if warnings.count > 5 {
                            Text("…and \(warnings.count - 5) more").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Import statement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { doImport() }
                        .disabled(parsed.isEmpty || cardStableId.isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingPicker,
                allowedContentTypes: [.commaSeparatedText, .pdf, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handlePicked(result)
            }
            .onAppear {
                if let pre = preselectedCardStableId { cardStableId = pre }
                else if let first = cards.first { cardStableId = first.stableId }
            }
        }
    }

    // MARK: Mapping picker binding

    private var mappingBinding: Binding<ColumnMapping> {
        Binding(
            get: {
                mapping ?? {
                    let m = StatementParser.suggestedMapping(headers: csvResult?.headers ?? [])
                    return ColumnMapping(date: m.date, description: m.description,
                                         amount: m.amount, debit: m.debit, credit: m.credit,
                                         negativeIsCharge: negativeIsCharge)
                }()
            },
            set: { mapping = $0 }
        )
    }

    private func remap() {
        guard let headers = csvResult?.headers, !headers.isEmpty,
              let data = lastCSVText
        else { return }
        var m = mappingBinding.wrappedValue
        m.negativeIsCharge = negativeIsCharge
        mapping = m
        csvResult = StatementParser.parseCSV(data, mapping: m)
    }

    // MARK: File handling

    @State private var lastCSVText: String?

    private func handlePicked(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                parseError = "Couldn't access the file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            if ext == "pdf" {
                source = .pdf
                let data = try Data(contentsOf: url)
                guard let text = PDFStatementParser.extractText(from: data) else {
                    parseError = "Couldn't read text from this PDF (it may be a scanned image)."
                    return
                }
                pdfResult = PDFStatementParser.parseLineItems(text)
                csvResult = nil
            } else {
                source = .csv
                let text = try String(contentsOf: url, encoding: .utf8)
                lastCSVText = text
                mapping = nil
                csvResult = StatementParser.parseCSV(text)
                pdfResult = nil
            }
            parseError = nil
        } catch {
            parseError = error.localizedDescription
        }
    }

    private func doImport() {
        TransactionStore.importParsed(
            parsed,
            cardStableId: cardStableId,
            periodKey: periodKey,
            fileName: fileName,
            source: source,
            context: context
        )
        dismiss()
    }
}

// MARK: - MonthPicker

/// Simple YYYY-MM picker for choosing the statement period.
struct MonthPicker: View {
    @Binding var periodKey: String

    private static let months: [String] = {
        let cal = Calendar.current
        let now = Date()
        return (0..<12).map { back in
            let d = cal.date(byAdding: .month, value: -back, to: now)!
            return RecurrenceEngine.periodKey(cadence: .monthly, date: d) ?? ""
        }.filter { !$0.isEmpty }
    }()

    private func label(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return key }
        var comps = DateComponents(); comps.year = y; comps.month = m; comps.day = 1
        guard let d = Calendar.current.date(from: comps) else { return key }
        return RecurrenceEngine.periodLabel(cadence: .monthly, date: d) ?? key
    }

    var body: some View {
        Picker("Month", selection: $periodKey) {
            ForEach(Self.months, id: \.self) { key in
                Text(label(key)).tag(key)
            }
        }
    }
}

// MARK: - ColumnMappingPicker

struct ColumnMappingPicker: View {
    var headers: [String]
    @Binding var mapping: ColumnMapping

    private func colName(_ i: Int?) -> String {
        guard let i, i < headers.count else { return "—" }
        return headers[i]
    }

    var body: some View {
        Picker("Date column", selection: $mapping.date) {
            ForEach(headers.indices, id: \.self) { i in Text(headers[i]).tag(i) }
        }
        Picker("Description column", selection: $mapping.description) {
            ForEach(headers.indices, id: \.self) { i in Text(headers[i]).tag(i) }
        }
        Toggle("Single amount column", isOn: Binding(
            get: { mapping.amount != nil },
            set: { on in
                if on { mapping.amount = mapping.debit ?? 0; mapping.debit = nil; mapping.credit = nil }
                else { mapping.amount = nil }
            }
        ))
        if mapping.amount != nil {
            Picker("Amount column", selection: Binding(
                get: { mapping.amount ?? 0 },
                set: { mapping.amount = $0 }
            )) {
                ForEach(headers.indices, id: \.self) { i in Text(headers[i]).tag(i) }
            }
        } else {
            Picker("Debit column", selection: Binding(
                get: { mapping.debit ?? 0 }, set: { mapping.debit = $0 }
            )) {
                ForEach(headers.indices, id: \.self) { i in Text(headers[i]).tag(i) }
            }
            Picker("Credit column", selection: Binding(
                get: { mapping.credit ?? 0 }, set: { mapping.credit = $0 }
            )) {
                ForEach(headers.indices, id: \.self) { i in Text(headers[i]).tag(i) }
            }
        }
    }
}

// MARK: - ParsedRowPreview

private struct ParsedRowPreview: View {
    var tx: ParsedTransaction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tx.description).font(.callout).lineLimit(1)
                Text(tx.date, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(tx.amount, format: .currency(code: "USD"))
                .font(.callout).monospacedDigit()
                .foregroundStyle(tx.amount < 0 ? .primary : .green)
            if tx.confidence < 0.7 {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    .accessibilityLabel("Low confidence")
            }
        }
    }
}

#Preview {
    StatementImportView()
        .modelContainer(for: [
            CardItem.self, BenefitItem.self, TipItem.self,
            CompletionRecord.self, MutedReward.self,
            StatementDocument.self, BankTransaction.self, MerchantCategoryOverride.self,
        ], inMemory: true)
}
