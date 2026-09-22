import AuthenticationServices
import CryptoKit
import LastroKit
import SwiftUI

/// Entrar com Apple → Supabase Auth (signInWithIdToken).
struct SignInView: View {
    @Environment(AppStore.self) private var store
    @State private var nonce = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            Backdrop()
            VStack(alignment: .leading, spacing: 18) {
                Spacer()
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(LinearGradient.accentFab, in: .rect(cornerRadius: 20, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lastro").textStyle(34, .bold, tracking: -0.04)
                    Text("Seu mês inteiro, confirmado com o banco.").textStyle(15).foregroundStyle(.inkSecondary)
                }
                Spacer()
                SignInWithAppleButton(.continue) { request in
                    nonce = Self.randomNonce()
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = Self.sha256(nonce)
                } onCompletion: { result in
                    Task { await handle(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .clipShape(.capsule)
                if let error {
                    Text(error).textStyle(13).foregroundStyle(.negative)
                }
            }
            .foregroundStyle(.ink)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        do {
            let auth = try result.get()
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken, let token = String(data: tokenData, encoding: .utf8) else {
                error = "A Apple não devolveu o token."
                return
            }
            try await store.remote?.signInWithApple(idToken: token, nonce: nonce)
            await store.didSignIn()
        } catch {
            self.error = "Não deu para entrar: \(error.localizedDescription)"
        }
    }

    static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var g = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(g.next() % UInt64(chars.count))] })
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
