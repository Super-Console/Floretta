import FlorettaCore
import XCTest

final class LayoutTests: XCTestCase {
    func testSingleRootIsCenteredWithCenterStyle() {
        let engine = LayoutEngine()
        let root = MindMapNode(text: "中心")
        let frames = engine.layout(MindMapDocument(title: "one", roots: [root]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0].frame.midX, 0, accuracy: 0.001)
        XCTAssertEqual(frames[0].frame.midY, 0, accuracy: 0.001)
        XCTAssertEqual(frames[0].fontSize, 30)
        XCTAssertEqual(frames[0].fill, .white)
        XCTAssertEqual(frames[0].border, .black)
        XCTAssertEqual(frames[0].textColor, .black)
        XCTAssertNil(frames[0].link)
        XCTAssertFalse(engine.appearance.showsShadows)
    }

    func testMultipleRootsStackWithoutOverlap() {
        let engine = LayoutEngine()
        let first = MindMapNode(text: "一", children: [MindMapNode(text: "甲")])
        let second = MindMapNode(text: "二", children: [MindMapNode(text: "乙")])
        let frames = engine.layout(MindMapDocument(title: "many", roots: [first, second]))
        let top = frames.filter { $0.parentID == nil }
        XCTAssertEqual(top.count, 2)
        XCTAssertEqual(top[0].frame.midX, 0, accuracy: 0.001)
        XCTAssertEqual(top[1].frame.midX, 0, accuracy: 0.001)
        let firstTree = frames.filter { $0.id == first.id || $0.parentID == first.id }
        let secondTree = frames.filter { $0.id == second.id || $0.parentID == second.id }
        let firstBottom = firstTree.map(\.frame.maxY).max()!
        let secondTop = secondTree.map(\.frame.minY).min()!
        XCTAssertGreaterThan(secondTop, firstBottom)
    }

    func testTwoAndThreeLevelsGrowOutward() {
        let grand = MindMapNode(text: "孙")
        let right = MindMapNode(text: "右", children: [grand])
        let left = MindMapNode(text: "左")
        let root = MindMapNode(text: "根", children: [right, left])
        let frames = LayoutEngine().layout(MindMapDocument(title: "levels", roots: [root]))
        let rootFrame = frames.first { $0.id == root.id }!
        let rightFrame = frames.first { $0.id == right.id }!
        let leftFrame = frames.first { $0.id == left.id }!
        let grandFrame = frames.first { $0.id == grand.id }!
        XCTAssertEqual(rootFrame.fontSize, 30)
        XCTAssertEqual(rightFrame.fontSize, 20)
        XCTAssertEqual(grandFrame.fontSize, 18)
        XCTAssertGreaterThan(rightFrame.frame.minX, rootFrame.frame.maxX)
        XCTAssertGreaterThan(grandFrame.frame.minX, rightFrame.frame.maxX)
        XCTAssertLessThan(leftFrame.frame.maxX, rootFrame.frame.minX)
        XCTAssertEqual(rightFrame.frame.minX - rootFrame.frame.maxX, LayoutMetrics().horizontalGap, accuracy: 0.001)
        assertNoOverlap(frames)
    }

    func testBalanceUsesSubtreeHeightInsteadOfOddEven() {
        let tall = MindMapNode(
            text: "高",
            children: (0..<6).map { MindMapNode(text: "孙\($0)") }
        )
        let shortA = MindMapNode(text: "甲")
        let shortB = MindMapNode(text: "乙")
        let root = MindMapNode(text: "根", children: [tall, shortA, shortB])
        let frames = LayoutEngine().layout(MindMapDocument(title: "balance", roots: [root]))
        let rootFrame = frames.first { $0.id == root.id }!
        let tallFrame = frames.first { $0.id == tall.id }!
        let aFrame = frames.first { $0.id == shortA.id }!
        let bFrame = frames.first { $0.id == shortB.id }!
        XCTAssertGreaterThan(tallFrame.frame.minX, rootFrame.frame.maxX)
        XCTAssertLessThan(aFrame.frame.maxX, rootFrame.frame.minX)
        XCTAssertLessThan(bFrame.frame.maxX, rootFrame.frame.minX)
        let union = frames.reduce(rootFrame.frame) { $0.union($1.frame) }
        XCTAssertEqual(rootFrame.frame.midY, union.midY, accuracy: 0.01)
    }

    func testSameLevelSharesHeightAndSiblingGapStaysConstant() {
        let short = MindMapNode(text: "短")
        let long = MindMapNode(text: "这是一段明显更长的一级主题")
        let third = MindMapNode(text: "短")
        let root = MindMapNode(text: "根", children: [short, long, third])
        let frames = LayoutEngine().layout(MindMapDocument(title: "size", roots: [root]))
        let level1 = [short, long, third].map { id in frames.first { $0.id == id.id }! }
        XCTAssertEqual(level1[0].size.height, level1[1].size.height)
        XCTAssertEqual(level1[1].size.height, level1[2].size.height)
        XCTAssertGreaterThan(level1[1].size.width, level1[0].size.width)
        let right = level1.filter { $0.frame.minX > frames[0].frame.maxX }.sorted { $0.frame.minY < $1.frame.minY }
        XCTAssertGreaterThanOrEqual(right.count, 2)
        let gap = right[1].frame.minY - right[0].frame.maxY
        XCTAssertEqual(gap, LayoutMetrics().siblingGap, accuracy: 0.001)
    }

    func testLinksAreEdgeMidpointSCurvesThatThinAndFollowBranchColor() {
        let grand = MindMapNode(text: "孙")
        let first = MindMapNode(text: "一", children: [grand])
        let second = MindMapNode(text: "二")
        let root = MindMapNode(text: "根", children: [first, second])
        let engine = LayoutEngine()
        let frames = engine.layout(MindMapDocument(title: "links", roots: [root]))
        let rootFrame = frames.first { $0.id == root.id }!
        let firstFrame = frames.first { $0.id == first.id }!
        let secondFrame = frames.first { $0.id == second.id }!
        let grandFrame = frames.first { $0.id == grand.id }!
        let firstLink = try! XCTUnwrap(firstFrame.link)
        XCTAssertEqual(firstLink.start.x, rootFrame.frame.maxX, accuracy: 0.001)
        XCTAssertEqual(firstLink.start.y, rootFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(firstLink.end.x, firstFrame.frame.minX, accuracy: 0.001)
        XCTAssertEqual(firstLink.end.y, firstFrame.frame.midY, accuracy: 0.001)
        XCTAssertEqual(firstLink.control1.y, firstLink.start.y, accuracy: 0.001)
        XCTAssertEqual(firstLink.control2.y, firstLink.end.y, accuracy: 0.001)
        XCTAssertNotEqual(firstLink.control1.x, firstLink.start.x)
        XCTAssertGreaterThan(firstLink.lineWidth, grandFrame.link!.lineWidth)
        XCTAssertEqual(firstFrame.fill, firstLink.color)
        XCTAssertEqual(firstFrame.textColor, .white)
        XCTAssertEqual(grandFrame.link?.color, firstLink.color)
        XCTAssertEqual(grandFrame.textColor, .black)
        XCTAssertNotEqual(secondFrame.link?.color, firstLink.color)
        XCTAssertEqual(secondFrame.textColor, .white)
        let light = firstLink.color.lightened(by: engine.appearance.deeperFillMix)
        XCTAssertEqual(grandFrame.fill, light)
    }

    /// Three equal siblings put two on one side, so those midpoints are not level with the parent.
    /// A cubic that has been replaced by a straight segment keeps its controls on the chord and fails here.
    /// t = 0.5 of this symmetric S lies on the chord; the quarter point is the one that bows.
    func testSCurveBendsWhenParentAndChildDifferInY() throws {
        let siblings = [
            MindMapNode(text: "上"),
            MindMapNode(text: "中"),
            MindMapNode(text: "下"),
        ]
        let root = MindMapNode(text: "根", children: siblings)
        let frames = LayoutEngine().layout(MindMapDocument(title: "bend", roots: [root]))
        let rootFrame = try XCTUnwrap(frames.first { $0.id == root.id })
        let children = siblings.compactMap { node in frames.first { $0.id == node.id } }
        XCTAssertEqual(children.count, 3)
        let bent = children.filter { abs($0.frame.midY - rootFrame.frame.midY) > 1 }
        XCTAssertFalse(bent.isEmpty)

        for child in bent {
            let link = try XCTUnwrap(child.link)
            XCTAssertGreaterThan(abs(link.end.y - link.start.y), 1)
            XCTAssertGreaterThan(distanceFromChord(link.control1, link: link), 1)
            XCTAssertGreaterThan(distanceFromChord(link.control2, link: link), 1)
            let quarter = cubicPoint(link, t: 0.25)
            XCTAssertGreaterThan(distanceFromChord(quarter, link: link), 1)
        }
    }

    func testCollapsedSubtreeIsExcluded() {
        let root = MindMapNode(text: "根", isCollapsed: true, children: [MindMapNode(text: "藏")])
        let frames = LayoutEngine().layout(MindMapDocument(title: "fold", roots: [root]))
        XCTAssertEqual(frames.map(\.id), [root.id])
    }

    func testManualPositionSkipsThatBranch() {
        let hidden = MindMapNode(text: "藏")
        let child = MindMapNode(text: "子", children: [hidden])
        let root = MindMapNode(
            text: "根",
            position: MindMapPoint(x: 12, y: 34),
            children: [child]
        )
        let frames = LayoutEngine().layout(MindMapDocument(title: "manual", roots: [root]))
        XCTAssertEqual(frames.map(\.id), [root.id])
        XCTAssertEqual(frames[0].origin.x, 12, accuracy: 0.001)
        XCTAssertEqual(frames[0].origin.y, 34, accuracy: 0.001)
    }

    func testManualChildIsPlacedButItsSubtreeIsNotAutoLaid() {
        let hidden = MindMapNode(text: "藏")
        let child = MindMapNode(
            text: "浮",
            position: MindMapPoint(x: 400, y: 20),
            children: [hidden]
        )
        let root = MindMapNode(text: "根", children: [child])
        let frames = LayoutEngine().layout(MindMapDocument(title: "branch", roots: [root]))
        XCTAssertNotNil(frames.first { $0.id == child.id })
        XCTAssertEqual(frames.first { $0.id == child.id }?.origin.x ?? -1, 400, accuracy: 0.001)
        XCTAssertNil(frames.first { $0.id == hidden.id })
    }

    func testMeasurementCacheKeyIncludesFontSize() {
        let cache = TextMeasurementCache()
        var engine = LayoutEngine(cache: cache)
        let document = MindMapDocument(title: "cache", roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])])
        _ = engine.layout(document)
        let misses = cache.missCount
        XCTAssertGreaterThan(misses, 0)
        _ = engine.layout(document)
        XCTAssertEqual(cache.missCount, misses)
        engine.metrics.centerFontSize = 28
        _ = engine.layout(document)
        XCTAssertGreaterThan(cache.missCount, misses)
    }

    func testInteractionHooksExposeHoverSelectionAndFloatingTopics() {
        var interaction = CanvasInteraction.standard
        var document = MindMapDocument(title: "hooks", roots: [MindMapNode(text: "根")])
        let rootID = document.roots[0].id
        CanvasCommands.apply(.hover(rootID), document: &document, interaction: &interaction)
        XCTAssertEqual(interaction.addDirections, CanvasDirection.allCases)
        XCTAssertEqual(interaction.addDirections.count, 4)
        CanvasCommands.apply(.hover(nil), document: &document, interaction: &interaction)
        XCTAssertTrue(interaction.addDirections.isEmpty)

        CanvasCommands.apply(.select(rootID), document: &document, interaction: &interaction)
        XCTAssertTrue(interaction.showsSelectionChrome)
        XCTAssertEqual(interaction.selectionBorder, .selectionBlue)
        XCTAssertEqual(interaction.selectionBorderWidth, 1.5)
        XCTAssertEqual(interaction.resizeHandles, CanvasDirection.allCases)
        XCTAssertFalse(interaction.showsShadows)

        let before = document.roots[0].children.count
        let childID = CanvasCommands.apply(
            .addChild(parentID: rootID, direction: .right),
            document: &document,
            interaction: &interaction
        )
        XCTAssertNotNil(childID)
        XCTAssertEqual(document.roots[0].children.count, before + 1)

        let point = CGPoint(x: 80, y: -20)
        let floating = CanvasCommands.apply(
            .addFloatingTopic(at: point),
            document: &document,
            interaction: &interaction
        )
        XCTAssertEqual(document.roots.count, 2)
        XCTAssertEqual(document.roots[1].id, floating)
        XCTAssertEqual(document.roots[1].position?.x ?? -1, 80, accuracy: 0.001)
        XCTAssertEqual(document.roots[1].position?.y ?? -1, -20, accuracy: 0.001)
    }

    func testCanvasChromeParamsCoverZoomFitAndSheets() {
        var chrome = CanvasChrome.standard
        XCTAssertTrue(chrome.isInfinite)
        XCTAssertEqual(chrome.zoomPercent, 100)
        XCTAssertTrue(chrome.zoomIsClickable)
        XCTAssertTrue(chrome.fitControlVisible)
        XCTAssertEqual(chrome.sheets.count, 1)
        chrome.addSheet(title: "Page 2")
        chrome.selectSheet(1)
        XCTAssertEqual(chrome.sheets.count, 2)
        XCTAssertEqual(chrome.activeSheetIndex, 1)
        XCTAssertEqual(LayoutEngine().kind, .bilateral)
    }

    func testBranchThemesStayWithinTheCatalogLimitAndDifferInBothSchemes() {
        XCTAssertLessThanOrEqual(MapThemeCatalog.all.count, MapThemeCatalog.limit)
        XCTAssertEqual(MapThemeCatalog.limit, 9)
        XCTAssertEqual(MapThemeCatalog.all.count, 9)
        let ink = MapThemeCatalog.all.first { $0.id == MapThemeCatalog.standardID }
        XCTAssertEqual(ink?.id, MapThemeCatalog.standardID)
        XCTAssertEqual(ink?.light, .standard)
        XCTAssertEqual(ink?.light.palette, .standard)
        let branches = MapThemeCatalog.all.filter { $0.id != MapThemeCatalog.florettaID }
        XCTAssertEqual(branches.count, 8)
        for theme in MapThemeCatalog.all {
            XCTAssertFalse(theme.nameKey.isEmpty)
            XCTAssertGreaterThanOrEqual(theme.light.palette.colors.count, 4)
            XCTAssertLessThanOrEqual(theme.light.palette.colors.count, 8)
            XCTAssertEqual(theme.light.palette.colors.count, theme.dark.palette.colors.count)
            assertDistinct(theme.light.palette.colors)
            assertDistinct(theme.dark.palette.colors)
            XCTAssertNotEqual(theme.light.palette.colors, theme.dark.palette.colors)
            XCTAssertNotEqual(theme.light.centerFill, theme.dark.centerFill)
            XCTAssertLessThan(theme.dark.centerFill.red, 0.35)
            XCTAssertGreaterThan(theme.dark.centerText.red, 0.9)
            if theme.id == MapThemeCatalog.florettaID { continue }
            XCTAssertEqual(theme.light.level1Text, LayoutAppearance.standard.level1Text)
            XCTAssertLessThan(theme.dark.level1Text.red, 0.2)
        }
        for left in MapThemeCatalog.all.indices {
            for right in MapThemeCatalog.all.indices where right > left {
                let a = MapThemeCatalog.all[left]
                let b = MapThemeCatalog.all[right]
                XCTAssertNotEqual(a.id, b.id)
                XCTAssertNotEqual(a.nameKey, b.nameKey)
                XCTAssertNotEqual(a.light.palette.colors, b.light.palette.colors)
                XCTAssertNotEqual(a.dark.palette.colors, b.dark.palette.colors)
                XCTAssertNotEqual(a.dark.centerFill, b.dark.centerFill)
            }
        }
        for theme in MapThemeCatalog.all where theme.id != MapThemeCatalog.florettaID {
            XCTAssertNil(theme.light.canvasBackground)
            XCTAssertNil(theme.dark.canvasBackground)
            XCTAssertNil(theme.light.linkStroke)
            XCTAssertNil(theme.dark.linkStroke)
        }
    }

    func testColorPresetsDefineBranchColorsBackgroundAndLineWidth() {
        let names = ["晨曦", "极简灰", "海盐", "橘叶", "夜紫", "森林"]
        XCTAssertEqual(MapColorPresetCatalog.all.map(\.nameKey), names)
        XCTAssertEqual(Set(MapColorPresetCatalog.all.map(\.id)).count, names.count)
        var papers: [BranchColor] = []
        var widths: [CGFloat] = []
        var palettes: [[BranchColor]] = []
        for preset in MapColorPresetCatalog.all {
            XCTAssertFalse(preset.id.isEmpty)
            XCTAssertGreaterThanOrEqual(preset.branchColors.count, 4)
            XCTAssertGreaterThan(preset.lineWidth, 0)
            XCTAssertEqual(preset.appearance.palette.colors, preset.branchColors)
            XCTAssertEqual(preset.appearance.canvasBackground, preset.canvasBackground)
            XCTAssertEqual(preset.appearance.linkStroke, preset.lineWidth)
            XCTAssertFalse(papers.contains(preset.canvasBackground))
            XCTAssertFalse(widths.contains(preset.lineWidth))
            XCTAssertFalse(palettes.contains(preset.branchColors))
            assertDistinct(preset.branchColors)
            papers.append(preset.canvasBackground)
            widths.append(preset.lineWidth)
            palettes.append(preset.branchColors)
            XCTAssertFalse(MapThemeCatalog.all.contains { $0.id == preset.id })
            let light = MapThemeCatalog.appearance(themeID: preset.id, scheme: .light, fallback: .standard)
            let dark = MapThemeCatalog.appearance(themeID: preset.id, scheme: .dark, fallback: .standard)
            XCTAssertEqual(light, preset.appearance)
            XCTAssertEqual(dark, preset.appearance)
        }
    }

    func testFlorettaThemeTokensMatchTheBrandAndNewMapsUseIt() throws {
        XCTAssertEqual(MapThemeCatalog.defaultThemeID, MapThemeCatalog.florettaID)
        XCTAssertNotEqual(MapThemeCatalog.defaultThemeID, MapThemeCatalog.standardID)
        XCTAssertEqual(MapThemeCatalog.florettaCornerRadius, 12)
        XCTAssertEqual(MapThemeCatalog.florettaStrokeWidth, 1)
        let theme = try XCTUnwrap(MapThemeCatalog.all.first { $0.id == MapThemeCatalog.florettaID })
        XCTAssertEqual(theme.nameKey, "Floretta 主题")
        let light = theme.light
        XCTAssertEqual(light.canvasBackground, BranchColor(hex: "#F5EBDA"))
        XCTAssertEqual(light.uniformFill, BranchColor(hex: "#F7EFE1"))
        XCTAssertEqual(light.uniformStroke, BranchColor(hex: "#C87756"))
        XCTAssertEqual(light.uniformStrokeWidth, 1)
        XCTAssertEqual(light.cornerRadius, 12)
        XCTAssertEqual(light.edgeColor, BranchColor(hex: "#BFA893"))
        XCTAssertEqual(light.edgeStartWidth, MapThemeCatalog.florettaEdgeStartWidth)
        XCTAssertEqual(light.edgeEndWidth, MapThemeCatalog.florettaEdgeEndWidth)
        XCTAssertGreaterThan(light.edgeStartWidth ?? 0, light.edgeEndWidth ?? 0)
        XCTAssertLessThanOrEqual(light.edgeStartWidth ?? 99, 2)
        XCTAssertEqual(light.rootFontDesign, "serif")
        XCTAssertEqual(light.bodyFontDesign, "default")
        XCTAssertEqual(light.childCountBadgeInset, MapThemeCatalog.florettaChildBadgeInset)
        XCTAssertEqual(light.childCountBadgeColor, BranchColor(hex: "#C87756"))
        XCTAssertEqual(light.centerText, BranchColor(hex: MapThemeCatalog.florettaTitleHex))
        XCTAssertEqual(light.level1Text, light.centerText)
        XCTAssertNotEqual(theme.dark.canvasBackground, light.canvasBackground)
        XCTAssertEqual(theme.dark.cornerRadius, light.cornerRadius)
        XCTAssertEqual(theme.dark.uniformStrokeWidth, 1)
        XCTAssertEqual(theme.dark.rootFontDesign, "serif")
        XCTAssertEqual(theme.dark.bodyFontDesign, "default")

        let child = MindMapNode(text: "子")
        let root = MindMapNode(text: "根", children: [child])
        let fresh = MindMapDocument.newMap(title: "品牌", roots: [root])
        XCTAssertEqual(fresh.themeID, "floretta")
        let saved = try XCTUnwrap(String(data: try FlorettaCodec.encode(fresh), encoding: .utf8))
        XCTAssertTrue(saved.contains("themeID"))
        XCTAssertTrue(saved.contains("floretta"))
        let openedFresh = try FlorettaCodec.decode(try FlorettaCodec.encode(fresh))
        XCTAssertEqual(openedFresh.themeID, "floretta")

        let frames = LayoutEngine().layout(openedFresh, scheme: .light)
        let rootFrame = try XCTUnwrap(frames.first { $0.isRoot })
        let childFrame = try XCTUnwrap(frames.first { $0.id == child.id })
        XCTAssertEqual(rootFrame.fill, BranchColor(hex: "#F7EFE1"))
        XCTAssertEqual(childFrame.fill, rootFrame.fill)
        XCTAssertEqual(rootFrame.border, BranchColor(hex: "#C87756"))
        XCTAssertEqual(childFrame.border, rootFrame.border)
        XCTAssertEqual(rootFrame.borderWidth, 1)
        XCTAssertEqual(childFrame.borderWidth, 1)
        XCTAssertEqual(rootFrame.cornerRadius, 12)
        XCTAssertEqual(childFrame.cornerRadius, 12)
        XCTAssertEqual(rootFrame.fontDesign, "serif")
        XCTAssertEqual(childFrame.fontDesign, "default")
        XCTAssertEqual(rootFrame.textColor, BranchColor(hex: "#3A2A22"))
        XCTAssertEqual(childFrame.textColor, rootFrame.textColor)
        XCTAssertEqual(rootFrame.childBadgeInset, 0)
        XCTAssertEqual(childFrame.childBadgeInset, 28)
        XCTAssertFalse(childFrame.childBadgeOnMinX)
        let sided = MindMapDocument.newMap(
            title: "侧",
            roots: [MindMapNode(text: "根", children: [MindMapNode(text: "右"), MindMapNode(text: "左")])]
        )
        let sidedFrames = LayoutEngine().layout(sided)
        let sidedRoot = try XCTUnwrap(sidedFrames.first { $0.isRoot })
        let sidedChildren = sidedFrames.filter { !$0.isRoot }
        XCTAssertEqual(sidedChildren.count, 2)
        XCTAssertTrue(sidedChildren.contains { $0.frame.midX < sidedRoot.frame.midX && $0.childBadgeOnMinX })
        XCTAssertTrue(sidedChildren.contains { $0.frame.midX > sidedRoot.frame.midX && !$0.childBadgeOnMinX })
        let link = try XCTUnwrap(childFrame.link)
        XCTAssertEqual(link.color, BranchColor(hex: "#BFA893"))
        XCTAssertEqual(link.lineWidth, MapThemeCatalog.florettaEdgeStartWidth)
        XCTAssertEqual(link.endWidth, MapThemeCatalog.florettaEdgeEndWidth)
        XCTAssertTrue(link.isTapered)
        XCTAssertEqual(link.point(at: 0), link.start)
        XCTAssertEqual(link.point(at: 1).x, link.end.x, accuracy: 0.001)
        XCTAssertEqual(link.point(at: 1).y, link.end.y, accuracy: 0.001)
        let samples = 8
        let outline = link.taperedOutline(samples: samples)
        XCTAssertEqual(outline.count, samples * 2)
        let startGap = hypot(
            outline[0].x - outline[outline.count - 1].x,
            outline[0].y - outline[outline.count - 1].y
        )
        let endGap = hypot(
            outline[samples - 1].x - outline[samples].x,
            outline[samples - 1].y - outline[samples].y
        )
        XCTAssertEqual(startGap, link.lineWidth, accuracy: 0.05)
        XCTAssertEqual(endGap, link.endWidth, accuracy: 0.05)

        let plainRoot = MindMapNode(text: "根", children: [MindMapNode(text: "子")])
        let plain = LayoutEngine().layout(MindMapDocument(title: "旧", roots: [plainRoot]))
        let plainChild = try XCTUnwrap(plain.first { !$0.isRoot })
        let plainCenter = try XCTUnwrap(plain.first { $0.isRoot })
        XCTAssertEqual(childFrame.size.width - plainChild.size.width, 28, accuracy: 0.001)
        XCTAssertEqual(rootFrame.size.width, plainCenter.size.width, accuracy: 0.001)

        let painted = MindMapNode(
            text: "丙",
            style: MindMapNodeStyle(
                colorHex: "#112233",
                fillHex: "#ED0DB8",
                borderHex: "#010101",
                borderWidth: 4,
                cornerRadius: 3,
                fontDesign: "rounded"
            )
        )
        let custom = MindMapDocument.newMap(title: "品牌", roots: [MindMapNode(text: "根", children: [painted])])
        let customFrame = try XCTUnwrap(LayoutEngine().layout(custom).first { $0.id == painted.id })
        XCTAssertEqual(customFrame.fill, BranchColor(hex: "#ED0DB8"))
        XCTAssertEqual(customFrame.border, BranchColor(hex: "#010101"))
        XCTAssertEqual(customFrame.cornerRadius, 3)
        XCTAssertEqual(customFrame.borderWidth, 4)
        XCTAssertEqual(customFrame.fontDesign, "rounded")
        XCTAssertEqual(custom.roots[0].children[0].style?.colorHex, "#112233")
    }

    func testOpeningADocumentKeepsItsThemeAndNodeStyles() throws {
        let styled = MindMapNode(
            text: "根",
            style: MindMapNodeStyle(
                colorHex: "#112233",
                fillHex: "#ED0DB8",
                cornerRadius: 2,
                fontDesign: "rounded"
            ),
            children: [MindMapNode(text: "子")]
        )
        var grove = MindMapDocument(title: "旧", roots: [styled])
        grove.themeID = "grove"
        let openedGrove = try FlorettaCodec.decode(try FlorettaCodec.encode(grove))
        XCTAssertEqual(openedGrove.themeID, "grove")
        XCTAssertEqual(openedGrove.roots[0].style, styled.style)
        let groveFill = try XCTUnwrap(LayoutEngine().layout(openedGrove).first { $0.isRoot }?.fill)
        XCTAssertNotEqual(groveFill, BranchColor(hex: "#F7EFE1"))
        XCTAssertEqual(
            LayoutEngine().layout(openedGrove).first { $0.text == "根" }?.fill,
            BranchColor(hex: "#ED0DB8")
        )

        let ink = MindMapDocument(title: "旧墨", roots: [MindMapNode(text: "根", children: [MindMapNode(text: "子")])])
        XCTAssertNil(ink.themeID)
        let inkJSON = try XCTUnwrap(String(data: try FlorettaCodec.encode(ink), encoding: .utf8))
        XCTAssertFalse(inkJSON.contains("themeID"))
        let openedInk = try FlorettaCodec.decode(Data(inkJSON.utf8))
        XCTAssertNil(openedInk.themeID)
        let inkRoot = try XCTUnwrap(LayoutEngine().layout(openedInk).first { $0.isRoot })
        XCTAssertEqual(inkRoot.fill, .white)
        XCTAssertEqual(inkRoot.fontDesign, "default")
        XCTAssertEqual(inkRoot.cornerRadius, LayoutAppearance.standard.cornerRadius)
        XCTAssertNotEqual(inkRoot.fill, BranchColor(hex: "#F7EFE1"))

        let blank = """
        {"formatVersion":1,"title":"t","createdAt":"2026-11-09T00:00:00Z","modifiedAt":"2026-11-09T00:00:00Z","roots":[{"id":"11111111-1111-1111-1111-111111111111","text":"根","note":"","collapsed":false,"children":[]}]}
        """
        let decodedBlank = try FlorettaCodec.decode(Data(blank.utf8))
        XCTAssertNil(decodedBlank.themeID)
        XCTAssertEqual(LayoutEngine().layout(decodedBlank).first?.fill, .white)
    }

    func testAutomaticBranchColorsFollowTheThemeAndKeepExplicitFills() throws {
        let first = MindMapNode(text: "甲")
        let grandchild = MindMapNode(text: "孙")
        let second = MindMapNode(text: "乙", children: [grandchild])
        let painted = MindMapNode(
            text: "丙",
            style: MindMapNodeStyle(colorHex: "#112233", fillHex: "#ED0DB8")
        )
        let root = MindMapNode(text: "根", children: [first, second, painted])
        var document = MindMapDocument(title: "色", roots: [root])
        document.themeID = "grove"
        let theme = try XCTUnwrap(MapThemeCatalog.all.first { $0.id == "grove" })
        let light = LayoutEngine().layout(document, scheme: .light)
        let dark = LayoutEngine().layout(document, scheme: .dark)
        XCTAssertEqual(light.map(\.id), dark.map(\.id))
        XCTAssertEqual(light.map(\.origin), dark.map(\.origin))

        let lightFirst = try XCTUnwrap(light.first { $0.id == first.id })
        let lightSecond = try XCTUnwrap(light.first { $0.id == second.id })
        let lightGrand = try XCTUnwrap(light.first { $0.id == grandchild.id })
        let lightPainted = try XCTUnwrap(light.first { $0.id == painted.id })
        XCTAssertEqual(lightFirst.fill, theme.light.palette.color(at: 0))
        XCTAssertEqual(lightFirst.link?.color, lightFirst.fill)
        XCTAssertEqual(lightSecond.fill, theme.light.palette.color(at: 1))
        XCTAssertNotEqual(lightFirst.fill, lightSecond.fill)
        XCTAssertEqual(lightGrand.link?.color, lightSecond.link?.color)
        XCTAssertEqual(lightGrand.fill, lightSecond.fill.lightened(by: theme.light.deeperFillMix))
        XCTAssertEqual(lightPainted.fill, try XCTUnwrap(BranchColor(hex: "#ED0DB8")))
        XCTAssertEqual(document.roots[0].children[2].style?.colorHex, "#112233")
        XCTAssertEqual(document.roots[0].children[2].style?.fillHex, "#ED0DB8")

        let darkFirst = try XCTUnwrap(dark.first { $0.id == first.id })
        let darkCenter = try XCTUnwrap(dark.first { $0.id == root.id })
        XCTAssertEqual(darkFirst.fill, theme.dark.palette.color(at: 0))
        XCTAssertNotEqual(darkFirst.fill, lightFirst.fill)
        XCTAssertEqual(darkCenter.fill, theme.dark.centerFill)
        XCTAssertNotEqual(darkCenter.fill, .white)
        XCTAssertEqual(dark.first { $0.id == painted.id }?.fill, lightPainted.fill)

        let unset = MindMapDocument(title: "色", roots: [root])
        XCTAssertEqual(LayoutEngine().layout(unset), LayoutEngine().layout(unset, scheme: .light))
        let standardFirst = try XCTUnwrap(LayoutEngine().layout(unset).first { $0.id == first.id })
        XCTAssertEqual(standardFirst.fill, BranchPalette.standard.color(at: 0))
        XCTAssertNotEqual(standardFirst.fill, lightFirst.fill)

        var unknown = document
        unknown.themeID = "future-theme"
        let fallback = try XCTUnwrap(LayoutEngine().layout(unknown, scheme: .light).first { $0.id == first.id })
        XCTAssertEqual(fallback.fill, standardFirst.fill)
    }

    func testThousandNodeLayoutPrintsElapsedTime() {
        var children: [MindMapNode] = []
        var count = 1
        for index in 0..<40 {
            let grandchildren = index == 39 ? 23 : 24
            let branch = MindMapNode(
                text: "支\(index)",
                children: (0..<grandchildren).map { MindMapNode(text: "叶\(index)-\($0)") }
            )
            children.append(branch)
            count += 1 + grandchildren
        }
        XCTAssertEqual(count, 1000)
        let document = MindMapDocument(title: "measure", roots: [MindMapNode(text: "根", children: children)])
        let start = Date()
        let frames = LayoutEngine().layout(document)
        let seconds = Date().timeIntervalSince(start)
        print("measure bilateral-layout nodes=\(frames.count) seconds=\(seconds)")
        XCTAssertEqual(frames.count, 1000)
    }

    private func cubicPoint(_ link: LinkCurve, t: CGFloat) -> CGPoint {
        let u = 1 - t
        let uu = u * u
        let tt = t * t
        return CGPoint(
            x: uu * u * link.start.x + 3 * uu * t * link.control1.x + 3 * u * tt * link.control2.x + tt * t * link.end.x,
            y: uu * u * link.start.y + 3 * uu * t * link.control1.y + 3 * u * tt * link.control2.y + tt * t * link.end.y
        )
    }

    private func distanceFromChord(_ point: CGPoint, link: LinkCurve) -> CGFloat {
        let dx = link.end.x - link.start.x
        let dy = link.end.y - link.start.y
        let length = hypot(dx, dy)
        let cross = dx * (point.y - link.start.y) - dy * (point.x - link.start.x)
        return abs(cross) / length
    }

    private func assertDistinct(_ colors: [BranchColor], file: StaticString = #filePath, line: UInt = #line) {
        for left in colors.indices {
            for right in colors.indices where right > left {
                XCTAssertNotEqual(colors[left], colors[right], file: file, line: line)
            }
        }
    }

    private func assertNoOverlap(_ frames: [NodeFrame], file: StaticString = #filePath, line: UInt = #line) {
        for left in frames.indices {
            for right in frames.indices where right > left {
                let hit = frames[left].frame.intersection(frames[right].frame)
                XCTAssertFalse(hit.width > 0.5 && hit.height > 0.5, file: file, line: line)
            }
        }
    }
}
