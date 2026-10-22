import SwiftUI

struct TouchButton: Identifiable, Codable {
    var id: String
    var label: String
    var x: Double
    var y: Double
}

struct TouchOverlayView: View {
    @State private var controls: [TouchButton] = {
        if let data = UserDefaults.standard.data(forKey: "touch-controls"),
           let saved = try? JSONDecoder().decode([TouchButton].self, from: data) { return saved }
        return [
            .init(id: "forward", label: "↑", x: 0.20, y: 0.55),
            .init(id: "left", label: "←", x: 0.10, y: 0.72),
            .init(id: "back", label: "↓", x: 0.20, y: 0.85),
            .init(id: "right", label: "→", x: 0.30, y: 0.72),
            .init(id: "jump", label: "SKOK", x: 0.82, y: 0.68),
            .init(id: "attack", label: "ATAK", x: 0.72, y: 0.85)
        ]
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(controls.indices, id: \.self) { index in
                    Text(controls[index].label)
                        .font(.caption.bold())
                        .frame(width: 58, height: 58)
                        .background(.cyan.opacity(0.25), in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.cyan))
                        .position(x: controls[index].x * geo.size.width, y: controls[index].y * geo.size.height)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            controls[index].x = min(0.92, max(0.08, value.location.x / geo.size.width))
                            controls[index].y = min(0.92, max(0.08, value.location.y / geo.size.height))
                        }.onEnded { _ in
                            if let data = try? JSONEncoder().encode(controls) {
                                UserDefaults.standard.set(data, forKey: "touch-controls")
                            }
                        })
                }
            }
        }
    }
}
