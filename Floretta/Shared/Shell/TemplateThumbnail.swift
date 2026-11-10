import SwiftUI

/// One drawing per template. Colors are the official theme for the current appearance.
struct TemplateThumbnail: View {
    static let width: CGFloat = 220
    static let height: CGFloat = 132

    var kind: TemplateKind
    @Environment(\.colorScheme) private var colorScheme

    private var theme: LayoutAppearance {
        MapThemeCatalog.appearance(
            themeID: MapThemeCatalog.defaultThemeID,
            scheme: colorScheme == .dark ? .dark : .light,
            fallback: .standard
        )
    }

    private var canvas: Color {
        guard let paper = theme.canvasBackground else { return Color.primary.opacity(0.04) }
        return ink(paper)
    }
    private var nodeFill: Color {
        guard let fill = theme.uniformFill else { return Color.primary.opacity(0.08) }
        return ink(fill)
    }
    private var nodeStroke: Color {
        guard let stroke = theme.uniformStroke else { return Color.primary.opacity(0.45) }
        return ink(stroke)
    }
    private var edge: Color {
        guard let line = theme.edgeColor else { return Color.accentColor.opacity(0.8) }
        return ink(line)
    }
    private var title: Color { ink(theme.centerText) }

    var body: some View {
        ZStack {
            canvas
            content
        }
        .frame(width: Self.width, height: Self.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(nodeStroke.opacity(0.45), lineWidth: 1)
        }
        .accessibilityLabel(kind.name)
    }

    @ViewBuilder
    private var content: some View {
        switch kind {
        case .mindMap:
            mindMap
        case .logic:
            logic
        case .brace:
            brace
        case .org:
            org
        case .timeline:
            timeline
        case .fishbone:
            fishbone
        case .swot:
            swot
        case .compare:
            compare
        case .okr:
            okr
        case .sevenQuestions:
            seven
        case .meeting:
            meeting
        case .reading:
            reading
        }
    }

    private var mindMap: some View {
        ZStack {
            curve(CGPoint(x: 110, y: 66), CGPoint(x: 46, y: 36))
            curve(CGPoint(x: 110, y: 66), CGPoint(x: 46, y: 96))
            curve(CGPoint(x: 110, y: 66), CGPoint(x: 174, y: 36))
            curve(CGPoint(x: 110, y: 66), CGPoint(x: 174, y: 96))
            chip("去程").position(x: 46, y: 36)
            chip("预算").position(x: 46, y: 96)
            chip("行程").position(x: 174, y: 36)
            chip("行装").position(x: 174, y: 96)
            chip("出行", emphasized: true).position(x: 110, y: 66)
        }
    }

    private var logic: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let y = CGFloat(28 + index * 26)
                curve(CGPoint(x: 52, y: 66), CGPoint(x: 150, y: y))
                chip(["读者", "论点", "结论", "删空话"][index]).position(x: 168, y: y)
            }
            chip("写清楚", emphasized: true).position(x: 52, y: 66)
        }
    }

    private var brace: some View {
        ZStack {
            BraceShape()
                .stroke(edge, lineWidth: 1.5)
                .frame(width: 18, height: 90)
                .position(x: 108, y: 66)
            chip("叶菜").position(x: 48, y: 36)
            chip("根茎").position(x: 48, y: 96)
            chip("菠菜").position(x: 168, y: 28)
            chip("生菜").position(x: 168, y: 52)
            chip("萝卜").position(x: 168, y: 84)
            chip("土豆").position(x: 168, y: 108)
        }
    }

    private var org: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 110, y: 40))
                path.addLine(to: CGPoint(x: 110, y: 62))
                path.addLine(to: CGPoint(x: 40, y: 62))
                path.addLine(to: CGPoint(x: 180, y: 62))
                path.move(to: CGPoint(x: 40, y: 62))
                path.addLine(to: CGPoint(x: 40, y: 86))
                path.move(to: CGPoint(x: 110, y: 62))
                path.addLine(to: CGPoint(x: 110, y: 86))
                path.move(to: CGPoint(x: 180, y: 62))
                path.addLine(to: CGPoint(x: 180, y: 86))
            }
            .stroke(edge, lineWidth: 1)
            chip("食堂", emphasized: true).position(x: 110, y: 28)
            chip("前厅").position(x: 40, y: 100)
            chip("厨房").position(x: 110, y: 100)
            chip("采购").position(x: 180, y: 100)
        }
    }

    private var timeline: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 20, y: 78))
                path.addLine(to: CGPoint(x: 200, y: 78))
            }
            .stroke(edge, lineWidth: 1.5)
            ForEach(Array(["立项", "设计", "开发", "上架"].enumerated()), id: \.offset) { index, title in
                let x = CGFloat(36 + index * 48)
                Circle()
                    .fill(nodeStroke)
                    .frame(width: 8, height: 8)
                    .position(x: x, y: 78)
                chip(title).position(x: x, y: index.isMultiple(of: 2) ? 48 : 104)
            }
        }
    }

    private var fishbone: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 24, y: 66))
                path.addLine(to: CGPoint(x: 196, y: 66))
                path.move(to: CGPoint(x: 60, y: 66))
                path.addLine(to: CGPoint(x: 36, y: 36))
                path.move(to: CGPoint(x: 100, y: 66))
                path.addLine(to: CGPoint(x: 76, y: 96))
                path.move(to: CGPoint(x: 140, y: 66))
                path.addLine(to: CGPoint(x: 164, y: 36))
                path.move(to: CGPoint(x: 170, y: 66))
                path.addLine(to: CGPoint(x: 194, y: 96))
            }
            .stroke(edge, lineWidth: 1.25)
            chip("延误", emphasized: true).position(x: 110, y: 66)
            chip("人员").position(x: 36, y: 28)
            chip("设备").position(x: 70, y: 108)
            chip("材料").position(x: 164, y: 28)
            chip("环境").position(x: 188, y: 108)
        }
    }

    private var swot: some View {
        let titles = ["优势", "劣势", "机会", "威胁"]
        return VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(0..<2, id: \.self) { column in
                        Text(titles[row * 2 + column])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(title)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(nodeFill, in: RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8).strokeBorder(nodeStroke, lineWidth: 1)
                            }
                    }
                }
            }
        }
        .padding(16)
    }

    private var compare: some View {
        HStack(spacing: 16) {
            column("旧楼", rows: ["月租", "通勤", "装修"])
            column("园区", rows: ["月租", "通勤", "装修"])
        }
        .padding(.horizontal, 28)
    }

    private var okr: some View {
        VStack(spacing: 8) {
            chip("复购三成", emphasized: true)
            HStack(spacing: 8) {
                chip("回头客")
                chip("客诉")
                chip("新品")
            }
        }
    }

    private var seven: some View {
        let titles = ["人", "事", "时", "地", "因", "何", "价"]
        return HStack(spacing: 4) {
            ForEach(titles, id: \.self) { title in
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(self.title)
                    .frame(width: 22, height: 22)
                    .background(nodeFill, in: Circle())
                    .overlay { Circle().strokeBorder(nodeStroke, lineWidth: 1) }
            }
        }
    }

    private var meeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            chip("店务会", emphasized: true)
            chip("议题")
            chip("决定")
            chip("待办")
            chip("未决")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 28)
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 6) {
            chip("书名", emphasized: true)
            chip("人物").padding(.leading, 16)
            chip("情节").padding(.leading, 16)
            chip("摘句").padding(.leading, 28)
            chip("看法").padding(.leading, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 24)
    }

    private func column(_ title: String, rows: [String]) -> some View {
        VStack(spacing: 6) {
            chip(title, emphasized: true)
            ForEach(rows, id: \.self) { row in
                chip(row)
            }
        }
    }

    private func chip(_ text: String, emphasized: Bool = false) -> some View {
        Text(text)
            .font(emphasized
                ? FlorettaTitleFont.font(design: theme.rootFontDesign, size: 11)
                : FlorettaTitleFont.font(design: theme.bodyFontDesign, size: 9))
            .foregroundStyle(title)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(nodeFill, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).strokeBorder(nodeStroke, lineWidth: 1)
            }
    }

    private func curve(_ start: CGPoint, _ end: CGPoint) -> some View {
        Path { path in
            path.move(to: start)
            let mid = (start.x + end.x) / 2
            path.addCurve(to: end, control1: CGPoint(x: mid, y: start.y), control2: CGPoint(x: mid, y: end.y))
        }
        .stroke(edge, lineWidth: 1.25)
    }

    private func ink(_ color: BranchColor) -> Color {
        Color(red: color.red, green: color.green, blue: color.blue)
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
