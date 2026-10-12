import SwiftUI

struct VanillaModifiedIndicator: View {
    var body: some View {
        Circle()
            .fill(.orange)
            .frame(width: 7, height: 7)
            .help("Modificato rispetto a Vanilla")
            .accessibilityLabel("Modificato rispetto a Vanilla")
    }
}

struct VanillaModifiedFilterToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Solo modificati", isOn: $isOn)
            .toggleStyle(.checkbox)
            .controlSize(.small)
    }
}
