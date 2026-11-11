import SwiftUI

struct LicenseActivationView: View {
    @ObservedObject var manager: LicenseManager
    @State private var code = ""

    var body: some View {
        VStack(spacing: 20) {
            Text("Ative sua licença")
                .font(.title2.bold())

            TextField("Código de ativação", text: $code)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            Button("Ativar") {
                manager.activate(code: code)
            }
            .buttonStyle(.borderedProminent)

            Text(manager.statusMessage)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
