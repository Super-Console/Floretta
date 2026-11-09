import SwiftUI

/// Style preview for a new-map card. Drawn with system shapes, not an empty frame.
struct TemplateThumbnail: View {
    static let width: CGFloat = 220
    static let height: CGFloat = 132

    var name: String

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
    }

    private var background: Color {
        switch name {
        case "组织结构图":
            return Color(red: 0.85, green: 0.95, blue: 0.90)
        case "树形图":
            return Color(red: 0.08, green: 0.36, blue: 0.38)
        default:
            if basic.contains(name) { return .white }
            return stableIndex(name, modulo: 2) == 0
                ? .white
                : Color(red: 0.93, green: 0.95, blue: 0.98)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch name {
        case "思维导图":
            mindMap
        case "逻辑图":
            logicMap
        case "括号图":
            braceMap
        case "组织结构图":
            orgChart(ink: Color(red: 0.12, green: 0.35, blue: 0.32), node: .white)
        case "树形图":
            orgChart(ink: .white, node: Color(red: 0.55, green: 0.82, blue: 0.78))
        case "时间轴":
            timeline
        default:
            mindMapColored(title: shortened(name), palette: palette(for: name))
        }
    }

    private var basic: Set<String> {
        ["思维导图", "逻辑图", "括号图", "组织结构图", "树形图", "时间轴"]
    }

    private var mindMap: some View {
        mindMapColored(
            title: "中心主题",
            palette: [
                Color(red: 0.45, green: 0.75, blue: 0.55),
                Color(red: 0.35, green: 0.62, blue: 0.86),
                Color(red: 0.86, green: 0.42, blue: 0.38),
                Color(red: 0.90, green: 0.58, blue: 0.32),
            ]
        )
    }

    private func mindMapColored(title: String, palette: [Color]) -> some View {
        let left = Array(palette.prefix(2))
        let right = Array(palette.dropFirst(min(2, palette.count)))
        return ZStack {
            link(from: CGPoint(x: 110, y: 66), to: CGPoint(x: 48, y: 36), color: left.first ?? .gray)
            link(from: CGPoint(x: 110, y: 66), to: CGPoint(x: 48, y: 96), color: left.dropFirst().first ?? .gray)
            link(from: CGPoint(x: 110, y: 66), to: CGPoint(x: 172, y: 36), color: right.first ?? .gray)
            link(from: CGPoint(x: 110, y: 66), to: CGPoint(x: 172, y: 96), color: right.dropFirst().first ?? .gray)
            pill("分支", fill: left.first ?? .gray).position(x: 48, y: 36)
            pill("分支", fill: left.dropFirst().first ?? .gray).position(x: 48, y: 96)
            pill("分支", fill: right.first ?? .gray).position(x: 172, y: 36)
            pill("分支", fill: right.dropFirst().first ?? .gray).position(x: 172, y: 96)
            pill(title, fill: .white, ink: Color(red: 0.15, green: 0.35, blue: 0.7), border: Color(red: 0.25, green: 0.5, blue: 0.9))
                .position(x: 110, y: 66)
        }
    }

    private var logicMap: some View {
        let colors = [
            Color(red: 0.45, green: 0.42, blue: 0.78),
            Color(red: 0.30, green: 0.58, blue: 0.82),
            Color(red: 0.35, green: 0.70, blue: 0.48),
            Color(red: 0.90, green: 0.55, blue: 0.28),
        ]
        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                let y = CGFloat(28 + index * 26)
                link(from: CGPoint(x: 58, y: 66), to: CGPoint(x: 150, y: y), color: colors[index])
                pill("分支", fill: colors[index]).position(x: 168, y: y)
            }
            pill("中心主题", fill: .white, ink: .black, border: Color(red: 0.25, green: 0.45, blue: 0.85))
                .position(x: 58, y: 66)
        }
    }

    private var braceMap: some View {
        ZStack {
            BraceShape()
                .stroke(Color.black.opacity(0.35), lineWidth: 1.5)
                .frame(width: 18, height: 88)
                .position(x: 110, y: 66)
            pill("主题", fill: Color(red: 0.93, green: 0.94, blue: 0.96), ink: .black).position(x: 48, y: 40)
            pill("主题", fill: Color(red: 0.93, green: 0.94, blue: 0.96), ink: .black).position(x: 48, y: 92)
            pill("分组", fill: Color(red: 0.86, green: 0.91, blue: 0.98), ink: .black).position(x: 168, y: 40)
            pill("分组", fill: Color(red: 0.86, green: 0.91, blue: 0.98), ink: .black).position(x: 168, y: 92)
        }
    }

    private func orgChart(ink: Color, node: Color) -> some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 110, y: 42))
                path.addLine(to: CGPoint(x: 110, y: 68))
                path.addLine(to: CGPoint(x: 40, y: 68))
                path.addLine(to: CGPoint(x: 180, y: 68))
                path.move(to: CGPoint(x: 40, y: 68))
                path.addLine(to: CGPoint(x: 40, y: 84))
                path.move(to: CGPoint(x: 110, y: 68))
                path.addLine(to: CGPoint(x: 110, y: 84))
                path.move(to: CGPoint(x: 180, y: 68))
                path.addLine(to: CGPoint(x: 180, y: 84))
            }
            .stroke(ink.opacity(0.45), lineWidth: 1)
            pill("中心", fill: node, ink: ink).position(x: 110, y: 32)
            pill("分支", fill: node, ink: ink).position(x: 40, y: 98)
            pill("分支", fill: node, ink: ink).position(x: 110, y: 98)
            pill("分支", fill: node, ink: ink).position(x: 180, y: 98)
        }
    }

    private var timeline: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 16, y: 66))
                path.addLine(to: CGPoint(x: 204, y: 66))
            }
            .stroke(Color.black.opacity(0.25), lineWidth: 1.5)
            Circle().fill(Color(red: 0.25, green: 0.5, blue: 0.9)).frame(width: 10, height: 10).position(x: 50, y: 66)
            Circle().fill(Color(red: 0.90, green: 0.45, blue: 0.35)).frame(width: 10, height: 10).position(x: 170, y: 66)
            pill("中心主题", fill: .white, ink: .black, border: Color(red: 0.25, green: 0.5, blue: 0.9))
                .position(x: 110, y: 66)
            pill("事件", fill: Color(red: 0.93, green: 0.95, blue: 0.98), ink: .black).position(x: 50, y: 40)
            pill("事件", fill: Color(red: 0.98, green: 0.93, blue: 0.90), ink: .black).position(x: 170, y: 92)
        }
    }

    private func pill(_ text: String, fill: Color, ink: Color = .white, border: Color? = nil) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
            .overlay {
                if let border {
                    Capsule().strokeBorder(border, lineWidth: 1)
                }
            }
    }

    private func link(from start: CGPoint, to end: CGPoint, color: Color) -> some View {
        Path { path in
            path.move(to: start)
            let mid = (start.x + end.x) / 2
            path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y))
        }
        .stroke(color.opacity(0.85), lineWidth: 1.25)
    }

    private func shortened(_ name: String) -> String {
        if name.count <= 4 { return name }
        return String(name.prefix(4))
    }

    private func palette(for name: String) -> [Color] {
        let palettes: [[Color]] = [
            [
                Color(red: 0.86, green: 0.42, blue: 0.38),
                Color(red: 0.45, green: 0.75, blue: 0.55),
                Color(red: 0.35, green: 0.62, blue: 0.86),
                Color(red: 0.90, green: 0.58, blue: 0.32),
            ],
            [
                Color(red: 0.40, green: 0.45, blue: 0.75),
                Color(red: 0.30, green: 0.65, blue: 0.70),
                Color(red: 0.75, green: 0.45, blue: 0.55),
                Color(red: 0.55, green: 0.70, blue: 0.40),
            ],
            [
                Color(red: 0.20, green: 0.45, blue: 0.55),
                Color(red: 0.85, green: 0.55, blue: 0.25),
                Color(red: 0.45, green: 0.55, blue: 0.75),
                Color(red: 0.55, green: 0.72, blue: 0.62),
            ],
        ]
        return palettes[stableIndex(name, modulo: palettes.count)]
    }

    private func stableIndex(_ name: String, modulo: Int) -> Int {
        var sum = 0
        for scalar in name.unicodeScalars {
            sum = (sum * 33 + Int(scalar.value)) % 10007
        }
        return sum % modulo
    }
}

private struct BraceShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: midY),
            control: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.2)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.2)
        )
        return path
    }
}
