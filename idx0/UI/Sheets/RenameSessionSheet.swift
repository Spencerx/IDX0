import SwiftUI

struct RenameSessionSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Session")
                .font(.title3.weight(.semibold))

            TextField("Session title", text: $coordinator.renameDraftTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    coordinator.commitRenameSession()
                }

            HStack {
                Spacer()
                Button("Cancel") {
                    coordinator.cancelRenameSession()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    coordinator.commitRenameSession()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.renameDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
