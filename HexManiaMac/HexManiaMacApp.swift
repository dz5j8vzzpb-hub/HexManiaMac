import SwiftUI

@main
struct HexManiaMacApp: App {
    @StateObject private var document = ROMDocument()
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.italian.rawValue

    private var appLanguage: AppLanguage {
        AppLanguage.from(appLanguageRaw)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(document)
                .environment(\.appLanguage, appLanguage)
                .frame(minWidth: EditorLayout.windowMinWidth, minHeight: EditorLayout.windowMinHeight)
        }
        .defaultSize(width: EditorLayout.windowDefaultWidth, height: EditorLayout.windowDefaultHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.text("open.rom.menu", language: appLanguage)) { document.isImporterPresented = true }
                    .keyboardShortcut("o")
                Button(L10n.text("open.save.menu", language: appLanguage)) { document.isSaveImporterPresented = true }
                    .keyboardShortcut("o", modifiers: [.command, .option])
                Divider()
                Button(L10n.text("save", language: appLanguage)) { document.saveActiveDocument() }
                    .keyboardShortcut("s")
                    .disabled(!document.canSaveActiveDocument)
                Button(L10n.text("save.as", language: appLanguage)) { document.saveAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(!document.canSaveAsActiveDocument)
                Divider()
                Button(L10n.text("close.document", language: appLanguage)) { document.closeActiveDocument() }
                    .keyboardShortcut("w")
                    .disabled(document.editorMode == .home)
            }
            CommandGroup(replacing: .undoRedo) {
                Button(L10n.text("undo", language: appLanguage)) { document.undo() }
                    .keyboardShortcut("z")
                    .disabled(document.editorMode != .rom || !document.canUndo)
                Button(L10n.text("redo", language: appLanguage)) { document.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(document.editorMode != .rom || !document.canRedo)
            }
        }
    }
}
