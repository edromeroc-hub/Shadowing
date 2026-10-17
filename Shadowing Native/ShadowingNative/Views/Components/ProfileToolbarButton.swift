import SwiftUI

/// Ícone de perfil no topo das abas: o perfil abre por cima, sem ocupar uma aba.
struct ProfileToolbarButton: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Button {
            appModel.isProfilePresented = true
        } label: {
            Image(systemName: "person.crop.circle.fill")
        }
        .accessibilityLabel("Perfil")
    }
}
