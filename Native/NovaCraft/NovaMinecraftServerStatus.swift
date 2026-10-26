import Foundation
import Network

/// Minecraft Java Edition server-list status protocol (handshake -> status request).
/// This does not implement joining a world or account authentication.
enum NovaMinecraftServerStatus {
    static func query(address: String) async -> String {
        let fields = address.split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(fields.count), let first = fields.first,
              !first.isEmpty, !first.contains(" "), !first.contains("/") else {
            return "Nieprawidłowy adres serwera."
        }
        let host = String(first)
        let portNumber = fields.count == 2 ? Int(fields[1]) : 25565
        guard let portNumber, (1...65535).contains(portNumber),
              let port = NWEndpoint.Port(rawValue: UInt16(portNumber)) else {
            return "Nieprawidłowy port serwera."
        }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "pl.novacraft.minecraft-status")
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            var completed = false
            var received = Data()

            func finish(_ result: String) {
                guard !completed else { return }
                completed = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: result)
            }

            func receiveMore() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, isComplete, error in
                    queue.async {
                        guard !completed else { return }
                        if let data { received.append(data) }
                        if received.count > 1_048_576 {
                            finish("Odpowiedź serwera jest za duża.")
                            return
                        }
                        if let result = parseResponse(received) {
                            finish(result)
                        } else if isComplete || error != nil {
                            finish("Serwer nie zwrócił poprawnego statusu Minecraft Java.")
                        } else {
                            receiveMore()
                        }
                    }
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    var payload = Data([0x00]) // Handshake packet ID
                    payload.append(varInt(767)) // 1.21.x status protocol; server may still respond to status
                    let hostData = Data(host.utf8)
                    payload.append(varInt(hostData.count))
                    payload.append(hostData)
                    payload.append(UInt8((portNumber >> 8) & 0xff))
                    payload.append(UInt8(portNumber & 0xff))
                    payload.append(varInt(1)) // next state: status
                    var request = varInt(payload.count)
                    request.append(payload)
                    request.append(contentsOf: [0x01, 0x00]) // status request
                    connection.send(content: request, completion: .contentProcessed { error in
                        queue.async {
                            if error != nil { finish("Nie udało się wysłać zapytania statusu.") }
                            else { receiveMore() }
                        }
                    })
                case .failed:
                    finish("Nie można połączyć się z serwerem.")
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 8) {
                finish("Serwer nie odpowiedział w ciągu 8 sekund.")
            }
        }
    }

    private static func varInt(_ value: Int) -> Data {
        var value = value
        var bytes = Data()
        repeat {
            var byte = UInt8(value & 0x7f)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    private static func readVarInt(_ data: Data, at offset: Int) -> (Int, Int)? {
        var result = 0
        for index in 0..<5 {
            guard offset + index < data.count else { return nil }
            let byte = Int(data[offset + index])
            result |= (byte & 0x7f) << (7 * index)
            if byte & 0x80 == 0 { return (result, offset + index + 1) }
        }
        return nil
    }

    private static func parseResponse(_ bytes: Data) -> String? {
        guard let (packetSize, start) = readVarInt(bytes, at: 0) else { return nil }
        guard packetSize > 0, packetSize < 1_048_576 else { return "Nieprawidłowy rozmiar odpowiedzi." }
        guard bytes.count >= start + packetSize else { return nil }
        guard let (packetID, next) = readVarInt(bytes, at: start), packetID == 0,
              let (jsonLength, jsonStart) = readVarInt(bytes, at: next),
              jsonLength >= 0, jsonLength <= packetSize,
              jsonStart + jsonLength <= start + packetSize else {
            return "Serwer zwrócił nieprawidłowy pakiet statusu."
        }
        let jsonData = bytes.subdata(in: jsonStart..<(jsonStart + jsonLength))
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return "Serwer zwrócił nieprawidłowy JSON statusu."
        }
        let version = (object["version"] as? [String: Any])?["name"] as? String ?? "nieznana"
        let players = object["players"] as? [String: Any] ?? [:]
        let online = players["online"] as? Int ?? 0
        let maximum = players["max"] as? Int ?? 0
        let description = object["description"]
        let motd: String
        if let plain = description as? String {
            motd = plain
        } else if let structured = description as? [String: Any] {
            motd = structured["text"] as? String ?? "Brak opisu"
        } else {
            motd = "Brak opisu"
        }
        let cleanVersion = String(version.prefix(80)).replacingOccurrences(of: "\n", with: " ")
        let cleanMOTD = String(motd.prefix(120)).replacingOccurrences(of: "\n", with: " ")
        return "Minecraft Java • \(cleanVersion) • Gracze: \(online)/\(maximum) • \(cleanMOTD). Status działa; dołączenie do gry nie jest jeszcze dostępne."
    }
}
