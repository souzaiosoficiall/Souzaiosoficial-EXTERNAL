import Foundation
import Combine

final class LicenseManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var statusMessage: String = "Ative sua licença"

    private let key = "souzakeys_license_active"
    private let baseURL = "https://souzakeys.duckdns.org"

    init() {
        isActive = UserDefaults.standard.bool(forKey: key)
    }

    func beginLaunchSession() {
        // Pode colocar validação remota aqui depois
        isActive = UserDefaults.standard.bool(forKey: key)
    }

    func activate(code: String) {
        // Validação simples por enquanto
        if code.count >= 8 {
            UserDefaults.standard.set(true, forKey: key)
            isActive = true
            statusMessage = "Licença ativada"
        } else {
            statusMessage = "Código inválido"
        }
    }

    func deactivate() {
        UserDefaults.standard.set(false, forKey: key)
        isActive = false
        statusMessage = "Licença desativada"
    }
}
