import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

struct MinecraftAccount {
    let username: String
    let uuid: String
    /// Token is held in memory only. Production app should use Keychain for persistent sessions.
    let minecraftAccessToken: String
}

enum AuthError: LocalizedError {
    case clientIDMissing
    case loginCancelled
    case missingCode
    case invalidResponse
    case noJavaEntitlement
    case apiError(String)
    var errorDescription: String? {
        switch self {
        case .clientIDMissing: return "Brak Microsoft Client ID w konfiguracji aplikacji"
        case .loginCancelled: return "Anulowano logowanie"
        case .missingCode: return "Brak kodu autoryzacji"
        case .invalidResponse: return "Nieprawidłowa odpowiedź usługi uwierzytelniania"
        case .noJavaEntitlement: return "Konto nie ma potwierdzonego uprawnienia Minecraft Java Edition"
        case .apiError(let detail): return detail
        }
    }
}

private struct OAuthToken: Decodable {
    let access_token: String
}
private struct XboxResponse: Decodable {
    let Token: String
    let DisplayClaims: Claims?
    struct Claims: Decodable { let xui: [XboxUser]? }
    struct XboxUser: Decodable { let uhs: String }
}
private struct MinecraftToken: Decodable { let access_token: String }
private struct Entitlements: Decodable {
    let items: [Item]
    struct Item: Decodable { let name: String }
}
private struct MinecraftProfile: Decodable {
    let id: String
    let name: String
}

/// Native authorization-code PKCE flow + Xbox Live / XSTS / Minecraft ownership verification.
/// Register a public/native Microsoft Entra app and configure the redirect URI novacraft://auth.
/// This is source code only: requires a valid Microsoft app registration and device testing.
@MainActor
final class MicrosoftMinecraftAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    // Register your own public client in Microsoft Entra; never put a client secret in an iOS app.
    private let clientID = "d48f4c8a-8925-445d-b6c9-0c1049373f78" // NovaCraft Launcher public client
    private let redirect = "novacraft://auth"
    private var webSession: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? UIWindow()
    }

    func signIn() async throws -> MinecraftAccount {
        guard !clientID.isEmpty else { throw AuthError.clientIDMissing }
        let verifier = Self.randomBase64URL(bytes: 32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomBase64URL(bytes: 20)
        var parts = URLComponents(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize")!
        parts.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: "XboxLive.signin offline_access"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state)
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: parts.url!, callbackURLScheme: "novacraft") { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: AuthError.loginCancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = true
            webSession = session
            if !session.start() { continuation.resume(throwing: AuthError.loginCancelled) }
        }
        let result = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        if let errorCode = result?.queryItems?.first(where: { $0.name == "error" })?.value {
            let detail = result?.queryItems?.first(where: { $0.name == "error_description" })?.value ?? errorCode
            throw AuthError.apiError("Microsoft: \(detail)")
        }
        guard result?.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = result?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingCode
        }
        let token = try await exchangeCode(code, verifier: verifier)
        let xbox = try await xboxLive(token: token)
        guard let uhs = xbox.DisplayClaims?.xui?.first?.uhs else { throw AuthError.invalidResponse }
        let xsts = try await xboxSecurity(xbox.Token)
        guard xsts.DisplayClaims?.xui?.first?.uhs == uhs else { throw AuthError.invalidResponse }
        let minecraft = try await minecraftToken(uhs: uhs, xsts: xsts.Token)
        let headers = ["Authorization": "Bearer \(minecraft.access_token)"]
        let entitlements: Entitlements = try await requestJSON(
            "https://api.minecraftservices.com/entitlements/mcstore", headers: headers)
        guard entitlements.items.contains(where: { ["game_minecraft", "product_minecraft"].contains($0.name) }) else {
            throw AuthError.noJavaEntitlement
        }
        let profile: MinecraftProfile = try await requestJSON(
            "https://api.minecraftservices.com/minecraft/profile", headers: headers)
        return MinecraftAccount(username: profile.name, uuid: profile.id, minecraftAccessToken: minecraft.access_token)
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let values = ["client_id": clientID, "grant_type": "authorization_code", "code": code,
                      "redirect_uri": redirect, "code_verifier": verifier, "scope": "XboxLive.signin offline_access"]
        req.httpBody = values.map { key, value in
            "\(Self.encode(key))=\(Self.encode(value))"
        }.joined(separator: "&").data(using: .utf8)
        let token: OAuthToken = try await send(req)
        return token.access_token
    }

    private func xboxLive(token: String) async throws -> XboxResponse {
        let body: [String: Any] = [
            "Properties": ["AuthMethod": "RPS", "SiteName": "user.auth.xboxlive.com", "RpsTicket": "d=\(token)"],
            "RelyingParty": "http://auth.xboxlive.com", "TokenType": "JWT"
        ]
        return try await postJSON("https://user.auth.xboxlive.com/user/authenticate", body: body)
    }

    private func xboxSecurity(_ token: String) async throws -> XboxResponse {
        let body: [String: Any] = [
            "Properties": ["SandboxId": "RETAIL", "UserTokens": [token]],
            "RelyingParty": "rp://api.minecraftservices.com/", "TokenType": "JWT"
        ]
        return try await postJSON("https://xsts.auth.xboxlive.com/xsts/authorize", body: body)
    }

    private func minecraftToken(uhs: String, xsts: String) async throws -> MinecraftToken {
        return try await postJSON("https://api.minecraftservices.com/authentication/login_with_xbox",
            body: ["identityToken": "XBL3.0 x=\(uhs);\(xsts)"])
    }

    private func postJSON<T: Decodable>(_ endpoint: String, body: [String: Any]) async throws -> T {
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }

    private func requestJSON<T: Decodable>(_ endpoint: String, headers: [String: String]) async throws -> T {
        var req = URLRequest(url: URL(string: endpoint)!)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await send(req)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AuthError.apiError("Serwer uwierzytelniania odrzucił żądanie (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func randomBase64URL(bytes: Int) -> String {
        var data = [UInt8](repeating: 0, count: bytes)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes, &data)
        precondition(result == errSecSuccess)
        return base64URL(Data(data))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .init(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? s
    }
}
