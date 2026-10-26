import Foundation
import Network

/// Offline identities are local nicknames, NOT Microsoft accounts.
/// They do not authenticate to online-mode Minecraft servers.
struct OfflineProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var nickname: String

    init(nickname: String) {
        self.id = UUID()
        self.nickname = nickname
    }

    static func isValid(_ name: String) -> Bool {
        (3...16).contains(name.utf8.count) &&
        name.unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_").contains($0)
        }
    }
}

/// Network reachability probe only. A successful TCP connection does not mean
/// that Minecraft multiplayer, server protocol or authentication is implemented.
enum NovaServerProbe {
    static func check(address: String) async -> String {
        let parts = address.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let host = parts.first.map(String.init),
              !host.isEmpty, !host.contains(" "), !host.contains("/") else {
            return "Nieprawidłowy adres serwera."
        }
        let portValue = parts.count == 2 ? Int(parts[1]) : 25565
        guard let portValue, (1...65535).contains(portValue),
              let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            return "Nieprawidłowy port."
        }
        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            let queue = DispatchQueue(label: "pl.novacraft.serverprobe")
            let lock = NSLock()
            var finished = false
            func finish(_ result: String) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: result)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish("Połączenie TCP działa: \(host):\(portValue). Gra multiplayer nie jest jeszcze dostępna.")
                case .failed: finish("Serwer nieosiągalny przez TCP.")
                case .cancelled: finish("Test anulowany.")
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 6) {
                finish("Upłynął czas oczekiwania na serwer.")
            }
        }
    }
}
