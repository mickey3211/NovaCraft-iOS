import SwiftUI

struct TouchButton: Identifiable, Codable {
    var id: String
    var label: String
    var x: Double
    var y: Double
}

struct TouchOverlayView: View {
    @StateObject private var input = InputRouter.shared
    @State private var editMode = true
    @State private var dragOrigins: [String: CGPoint] = [:]
    @State private var controls: [TouchButton] = Self.defaults

    static let defaults: [TouchButton] = [
        .init(id: "forward", label: "↑", x: 0.20, y: 0.55),
        .init(id: "left", label: "←", x: 0.10, y: 0.72),
        .init(id: "back", label: "↓", x: 0.20, y: 0.85),
        .init(id: "right", label: "→", x: 0.30, y: 0.72),
        .init(id: "jump", label: "SKOK", x: 0.82, y: 0.68),
        .init(id: "attack", label: "ATAK", x: 0.72, y: 0.85),
        .init(id: "use", label: "UŻYJ", x: 0.83, y: 0.38)
    ]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Edytuj układ", isOn: $editMode)
                Button("Reset") { controls = Self.defaults; persist() }
                    .buttonStyle(.bordered)
            }
            GeometryReader { geo in
                ZStack {
                    ForEach(controls.indices, id: \.self) { index in
                        Text(controls[index].label)
                            .font(.caption.bold())
                            .frame(width: 55, height: 55)
                            .background(editMode ? Color.orange.opacity(0.3) : Color.cyan.opacity(0.25),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(editMode ? .orange : .cyan))
                            .position(x: controls[index].x * geo.size.width,
                                      y: controls[index].y * geo.size.height)
                            .gesture(DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let id = controls[index].id
                                    if editMode {
                                        if dragOrigins[id] == nil {
                                            dragOrigins[id] = CGPoint(x: controls[index].x, y: controls[index].y)
                                        }
                                        guard let origin = dragOrigins[id] else { return }
                                        controls[index].x = min(0.92, max(0.08, origin.x + value.translation.width / max(1, geo.size.width)))
                                        controls[index].y = min(0.92, max(0.08, origin.y + value.translation.height / max(1, geo.size.height)))
                                    } else if !input.isHeld(id) {
                                        input.send(id, pressed: true)
                                    }
                                }
                                .onEnded { _ in
                                    let id = controls[index].id
                                    if editMode {
                                        dragOrigins.removeValue(forKey: id)
                                        persist()
                                    } else {
                                        input.send(id, pressed: false)
                                    }
                                })
                    }
                }
            }
            Text(input.lastEvent).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            if let data = UserDefaults.standard.data(forKey: "touch-controls"),
               let stored = try? JSONDecoder().decode([TouchButton].self, from: data),
               !stored.isEmpty { controls = stored }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(controls) {
            UserDefaults.standard.set(data, forKey: "touch-controls")
        }
    }
}
