import Foundation
import SwiftUI

struct HexWorkspaceView: View {
    @EnvironmentObject private var document: ROMDocument
    @Environment(\.appLanguage) private var language
    @State private var editedHex = ""

    private let hexColumns = Array(repeating: GridItem(.fixed(30), spacing: 5), count: ROMDocument.bytesPerRow)

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(alignment: .top, spacing: 0) {
                hexGrid
                Divider()
                inspector
                    .frame(width: 230)
            }
        }
        .navigationTitle(document.fileURL?.lastPathComponent ?? "ROM")
        .onChange(of: document.selectedOffset) { _ in refreshEditor() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("\(L10n.text("offset", language: language)) (hex)", text: $document.gotoText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
                .onSubmit { document.goToOffset() }
            Button(L10n.text("go", language: language)) { document.goToOffset() }
            Divider().frame(height: 20)
            TextField(L10n.text("search.hex.placeholder", language: language), text: $document.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
                .onSubmit { document.searchNext() }
            Button(L10n.text("find.next", language: language)) { document.searchNext() }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Spacer()
            Button { document.page = max(0, document.page - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(document.page == 0)
            Text("\(L10n.text("page", language: language)) \(document.page + 1) / \(document.pageCount)")
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 145)
            Button { document.page = min(document.pageCount - 1, document.page + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(document.page + 1 >= document.pageCount)
        }
        .padding(10)
    }

    private var hexGrid: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("OFFSET").frame(width: 86, alignment: .leading)
                    ForEach(0..<16, id: \.self) { value in
                        Text(String(format: "%X", value)).frame(width: 35)
                    }
                    Text("ASCII").padding(.leading, 14)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                Divider().frame(width: 760)

                ForEach(rowStarts, id: \.self) { rowStart in
                    HStack(spacing: 0) {
                        Text(String(format: "%08X", rowStart))
                            .foregroundStyle(.secondary)
                            .frame(width: 86, alignment: .leading)
                        LazyVGrid(columns: hexColumns, spacing: 2) {
                            ForEach(rowStart..<min(rowStart + 16, document.data.count), id: \.self) { offset in
                                byteButton(offset)
                            }
                        }
                        .frame(width: 560)
                        asciiText(rowStart)
                            .frame(width: 150, alignment: .leading)
                            .padding(.leading, 12)
                    }
                    .font(.system(size: 12, design: .monospaced))
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rowStarts: [Int] {
        guard document.pageStart < document.pageEnd else { return [] }
        return Array(stride(from: document.pageStart, to: document.pageEnd, by: ROMDocument.bytesPerRow))
    }

    private func byteButton(_ offset: Int) -> some View {
        Button {
            document.select(offset)
        } label: {
            Text(String(format: "%02X", document.data[offset]))
                .frame(width: 30, height: 19)
                .background(document.selectedOffset == offset ? Color.accentColor : Color.clear)
                .foregroundColor(document.selectedOffset == offset ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
    }

    private func asciiText(_ rowStart: Int) -> some View {
        let end = min(rowStart + 16, document.data.count)
        let string = document.data[rowStart..<end].map { byte -> Character in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
        }
        return Text(String(string))
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.text("byte.inspector", language: language)).font(.headline)
            if let offset = document.selectedOffset, let byte = document.byte(at: offset) {
                LabeledContent(L10n.text("offset", language: language), value: String(format: "0x%08X", offset))
                LabeledContent(L10n.text("decimal", language: language), value: "\(byte)")
                LabeledContent(L10n.text("binary", language: language), value: String(byte, radix: 2).leftPadded(to: 8, with: "0"))
                TextField("00–FF", text: $editedHex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { document.editSelectedByte(hex: editedHex); refreshEditor() }
                Button(L10n.text("apply.byte", language: language)) {
                    document.editSelectedByte(hex: editedHex)
                    refreshEditor()
                }
                .buttonStyle(.borderedProminent)
                Divider()
                Text(L10n.text("hex.memory.warning", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.text("select.byte", language: language)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    private func refreshEditor() {
        if let offset = document.selectedOffset, let byte = document.byte(at: offset) {
            editedHex = String(format: "%02X", byte)
        }
    }
}

private extension String {
    func leftPadded(to length: Int, with character: Character) -> String {
        String(repeating: String(character), count: max(0, length - count)) + self
    }
}
