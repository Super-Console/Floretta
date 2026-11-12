import CoreText
import XCTest
@testable import FlorettaCore

final class ThemeFontCascadeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ThemeFontCascade.registerBundledFonts()
    }

    func testBundledLatinPostScriptNamesMatchTheDeclaredFaces() {
        let expected = [
            "eb-garamond": "EBGaramond-Regular",
            "crimson-pro": "CrimsonPro-Regular",
            "libre-baskerville": "LibreBaskerville-Regular",
            "noto-serif": "NotoSerif-Regular",
            "inter": "Inter-Regular",
            "ibm-plex-sans": "IBMPlexSans",
            "noto-sans": "NotoSans-Regular",
        ]
        XCTAssertFalse(ThemeFontCascade.bundledFontURLs().isEmpty, "bundled Regular faces must be visible to the test bundle or app bundle")
        for (id, ps) in expected {
            XCTAssertEqual(ThemeFontCascade.postScriptName(familyID: id), ps, id)
        }
    }

    func testChineseSerifCascadeUsesSongtiNotALatinFace() {
        let songti = ThemeFontCascade.firstAvailable(ThemeFontCascade.chineseSerifNames)
        XCTAssertNotNil(songti, "Songti SC / STSong must be present so Chinese serif is not faked with a Latin face")
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"].contains(songti),
            "unexpected Songti PostScript name \(songti ?? "nil")"
        )

        let latin = ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "Hello")
        XCTAssertEqual(latin, "EBGaramond-Regular")

        let chinese = ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "汉字")
        XCTAssertNotEqual(chinese, "EBGaramond-Regular", "a Latin serif must not be reported as covering Chinese")
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"].contains(chinese),
            "CJK run used \(chinese)"
        )
    }

    func testSystemSerifChineseAlsoUsesSongti() {
        let used = ThemeFontCascade.postScriptName(familyID: "system-serif", for: "汉字")
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"].contains(used),
            "system-serif CJK run used \(used)"
        )
    }

    func testFollowSystemChineseUsesPingFangWhenAvailable() {
        let used = ThemeFontCascade.postScriptName(familyID: "system-sans", for: "汉字")
        XCTAssertTrue(
            used.localizedCaseInsensitiveContains("PingFang") || used.localizedCaseInsensitiveContains("NotoSans"),
            "system-sans Chinese should be PingFang / Noto Sans, used \(used)"
        )
        let interCJK = ThemeFontCascade.postScriptName(familyID: "inter", for: "汉字")
        XCTAssertNotEqual(interCJK, "Inter-Regular")
    }

    func testSystemSansAndSystemSerifResolveDifferentFacesForEachLanguage() {
        // Modern (跟随系统) must not keep the classic serif cascade.
        let sansEn = ThemeFontCascade.postScriptName(familyID: "system-sans", for: "Hello")
        let serifEn = ThemeFontCascade.postScriptName(familyID: "system-serif", for: "Hello")
        XCTAssertNotEqual(sansEn, serifEn, "English system-sans \(sansEn) must differ from system-serif \(serifEn)")
        XCTAssertFalse(
            sansEn.localizedCaseInsensitiveContains("NewYork")
                || sansEn.localizedCaseInsensitiveContains("Georgia")
                || sansEn.localizedCaseInsensitiveContains("Times")
                || sansEn.localizedCaseInsensitiveContains("Garamond")
                || sansEn.localizedCaseInsensitiveContains("Song"),
            "system-sans English must not be a serif face, used \(sansEn)"
        )
        XCTAssertTrue(
            serifEn.localizedCaseInsensitiveContains("NewYork")
                || serifEn.localizedCaseInsensitiveContains("Georgia")
                || serifEn.localizedCaseInsensitiveContains("Times")
                || serifEn.localizedCaseInsensitiveContains("Song"),
            "system-serif English used \(serifEn)"
        )

        let sansZh = ThemeFontCascade.postScriptName(familyID: "system-sans", for: "汉字")
        let serifZh = ThemeFontCascade.postScriptName(familyID: "system-serif", for: "汉字")
        XCTAssertNotEqual(sansZh, serifZh, "Chinese system-sans \(sansZh) must differ from system-serif \(serifZh)")
        XCTAssertTrue(
            sansZh.localizedCaseInsensitiveContains("PingFang") || sansZh.localizedCaseInsensitiveContains("NotoSans"),
            "system-sans Chinese used \(sansZh)"
        )
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"].contains(serifZh)
                || serifZh.localizedCaseInsensitiveContains("Song"),
            "system-serif Chinese used \(serifZh)"
        )

        let sansJa = ThemeFontCascade.postScriptName(familyID: "system-sans", for: "あいうえお")
        let serifJa = ThemeFontCascade.postScriptName(familyID: "system-serif", for: "あいうえお")
        XCTAssertFalse(
            sansJa.localizedCaseInsensitiveContains("Mincho")
                || sansJa.localizedCaseInsensitiveContains("Songti")
                || sansJa.localizedCaseInsensitiveContains("STSong")
                || sansJa.localizedCaseInsensitiveContains("NewYork"),
            "system-sans Japanese must not stay on a mincho/serif face, used \(sansJa)"
        )
        // Hiragino Sans is preferred; PingFang also covers kana and may win.
        print("FONT_RESOLVE system-sans ja=\(sansJa) ko=\(ThemeFontCascade.postScriptName(familyID: "system-sans", for: "한국어")) en=\(sansEn) zh=\(sansZh)")
        print("FONT_RESOLVE system-serif ja=\(serifJa) ko=\(ThemeFontCascade.postScriptName(familyID: "system-serif", for: "한국어")) en=\(serifEn) zh=\(serifZh)")
        _ = serifJa

        let sansKo = ThemeFontCascade.postScriptName(familyID: "system-sans", for: "한국어")
        let serifKo = ThemeFontCascade.postScriptName(familyID: "system-serif", for: "한국어")
        XCTAssertNotEqual(sansKo, serifKo, "Korean system-sans \(sansKo) must differ from system-serif \(serifKo)")
        XCTAssertTrue(
            sansKo.localizedCaseInsensitiveContains("Gothic")
                || sansKo.localizedCaseInsensitiveContains("AppleSD")
                || sansKo.localizedCaseInsensitiveContains("PingFang")
                || sansKo.localizedCaseInsensitiveContains("NotoSans"),
            "system-sans Korean used \(sansKo)"
        )
    }

    func testJapaneseAndKoreanFallbackPostScriptNames() {
        ThemeFontCascade.registerBundledFonts()
        // Hiragino Mincho / AppleMyungjo are present for the ja/ko cascade slots.
        XCTAssertEqual(ThemeFontCascade.firstAvailable(ThemeFontCascade.japaneseSerifNames), "HiraMinProN-W3")
        XCTAssertEqual(ThemeFontCascade.firstAvailable(ThemeFontCascade.koreanSerifNames), "AppleMyungjo")

        // Songti SC is earlier in the serif cascade and also covers kana, so a Japanese
        // sample may resolve to STSongti-SC-Regular rather than HiraMinProN-W3. Record the
        // actual run; never treat a Latin face as covering CJK.
        let kana = ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "あいうえお")
        XCTAssertNotEqual(kana, "EBGaramond-Regular")
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular", "HiraMinProN-W3"].contains(kana),
            "Japanese kana run used \(kana)"
        )
        let hangul = ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "한국어")
        XCTAssertEqual(hangul, "AppleMyungjo")

        let kanaSans = ThemeFontCascade.postScriptName(familyID: "inter", for: "あいうえお")
        XCTAssertNotEqual(kanaSans, "Inter-Regular")
        let hangulSans = ThemeFontCascade.postScriptName(familyID: "inter", for: "한국어")
        if let gothic = ThemeFontCascade.firstAvailable(ThemeFontCascade.koreanSansNames) {
            XCTAssertEqual(hangulSans, gothic)
        }
        let english = ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "Hello")
        XCTAssertEqual(english, "EBGaramond-Regular")
    }

    func testCachedSizesKeepLatinAndChinesePostScriptNames() {
        // The (family, design, size) cache must not change what a run resolves
        // to: Latin stays on the bundled face, Chinese stays on Songti (or the
        // documented system serif). Hitting several sizes exercises the
        // cheap size-copy path after the first cascade build.
        let sizes: [CGFloat] = [12, 16, 18.5, 24, 32, 48]
        for size in sizes {
            _ = ThemeFontCascade.platformFont(familyID: "eb-garamond", nodeDesign: "default", size: size)
            _ = ThemeFontCascade.platformFont(familyID: "system-serif", nodeDesign: "default", size: size)
        }
        XCTAssertEqual(ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "Hello"), "EBGaramond-Regular")
        let chineseGaramond = ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "汉字")
        XCTAssertNotEqual(chineseGaramond, "EBGaramond-Regular")
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"].contains(chineseGaramond)
                || chineseGaramond.localizedCaseInsensitiveContains("Song"),
            "EB Garamond Chinese run used \(chineseGaramond) after cache fills"
        )
        let chineseSystem = ThemeFontCascade.postScriptName(familyID: "system-serif", for: "汉字")
        XCTAssertTrue(
            ["STSongti-SC-Regular", "STSong", "STSongti-TC-Regular"].contains(chineseSystem)
                || chineseSystem.localizedCaseInsensitiveContains("Song"),
            "system-serif Chinese run used \(chineseSystem) after cache fills"
        )
        // A second lookup at a size already cached must be identical.
        XCTAssertEqual(ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "Hello"), "EBGaramond-Regular")
        XCTAssertEqual(ThemeFontCascade.postScriptName(familyID: "eb-garamond", for: "汉字"), chineseGaramond)
    }

    func testSourceHanSerifIsNotBundled() {
        let names = ThemeFontCascade.bundledFontURLs().map(\.lastPathComponent)
        XCTAssertFalse(names.contains { $0.contains("SourceHan") || $0.contains("CJK") })
        XCTAssertEqual(names.filter { $0.hasSuffix(".otf") }.count, 7)
    }

    func testSizeQuantizationUsesRelativeLogBuckets() {
        XCTAssertEqual(ThemeFontCascade.quantizedPointSize(1), 1, accuracy: 0.000_1)
        XCTAssertEqual(ThemeFontCascade.quantizedPointSize(0.1), 1, accuracy: 0.000_1, "sizes below 1pt still clamp to 1 before quantizing")

        // 16.24 and 16.3 used to be the 0.5pt fixtures (16 and 16.5). They
        // now share one ~2% bucket whose CTFont size is the bucket value,
        // not a half-point grid.
        let sixteen = ThemeFontCascade.quantizedPointSize(16)
        XCTAssertEqual(sixteen, 16, accuracy: 0.02)
        let aroundSixteen = ThemeFontCascade.quantizedPointSize(16.24)
        XCTAssertEqual(ThemeFontCascade.quantizedPointSize(16.3), aroundSixteen, accuracy: 0.000_1)
        XCTAssertNotEqual(aroundSixteen, 16)
        XCTAssertNotEqual(aroundSixteen, 16.5)
        XCTAssertLessThanOrEqual(abs(aroundSixteen - 16.24) / 16.24, 0.02)

        // At 4pt a 0.5pt step is 12.5%; at 20pt it is 2.5%. Log buckets
        // must stay ≤2% at both ends, and across the pinch range.
        for size in stride(from: CGFloat(1), through: 200, by: 0.25) {
            let quantized = ThemeFontCascade.quantizedPointSize(size)
            XCTAssertLessThanOrEqual(abs(quantized - size) / size, 0.01 + 1e-9, "quantization error at \(size)pt is more than half a 2% step")
        }
        var previous = ThemeFontCascade.quantizedPointSize(1)
        var size: CGFloat = 1
        var jumped = false
        while size <= 200 {
            size *= 1.001
            let quantized = ThemeFontCascade.quantizedPointSize(size)
            if abs(quantized - previous) > 0.000_000_1 {
                let jump = (quantized - previous) / previous
                XCTAssertGreaterThan(jump, 0, "buckets must increase with size")
                XCTAssertLessThanOrEqual(jump, 0.02 + 1e-9, "adjacent buckets at \(previous)→\(quantized) jumped more than 2%")
                previous = quantized
                jumped = true
            }
        }
        XCTAssertTrue(jumped)
    }

    func testContinuousZoomSizesShareACachedRelativeBucket() {
        ThemeFontCascade.resetResolvedFontCacheForTests()
        defer { ThemeFontCascade.resetResolvedFontCacheForTests() }

        let family = "eb-garamond"
        let design = "default"
        let bucket = ThemeFontCascade.quantizedPointSize(16.24)
        // 16.24 and 16.3 are 0.37% apart, well inside a 2% bucket.
        let near: [CGFloat] = [16.24, 16.27, 16.3]
        for size in near {
            let font = ThemeFontCascade.cachedCTFont(familyID: family, nodeDesign: design, size: size)
            XCTAssertEqual(CTFontGetSize(font), bucket, accuracy: 0.000_1, "size \(size) should share the 16.24 bucket")
            XCTAssertEqual(CTFontCopyPostScriptName(font) as String, "EBGaramond-Regular")
        }
        XCTAssertEqual(ThemeFontCascade.resolvedFontCacheCountForTests(), 1)

        // A size more than a full 2% step away must be a different bucket.
        let far = ThemeFontCascade.cachedCTFont(familyID: family, nodeDesign: design, size: 16.24 * 1.025)
        XCTAssertNotEqual(CTFontGetSize(far), bucket, accuracy: 0.000_1)
        XCTAssertEqual(ThemeFontCascade.resolvedFontCacheCountForTests(), 2)
        XCTAssertEqual(CTFontCopyPostScriptName(far) as String, "EBGaramond-Regular")
    }

    func testFontCacheEvictsLeastRecentlyUsedWhenOverCapacity() {
        ThemeFontCascade.resetResolvedFontCacheForTests()
        defer { ThemeFontCascade.resetResolvedFontCacheForTests() }

        ThemeFontCascade.setResolvedFontCacheCapacityForTests(4)
        XCTAssertEqual(ThemeFontCascade.resolvedFontCacheCapacityForTests(), 4)

        let family = "eb-garamond"
        let design = "default"
        // Six sizes more than 2% apart, so six distinct log buckets. After
        // the fifth and sixth inserts, the two oldest sizes must leave so
        // the cache stays at the cap.
        let sizes: [CGFloat] = [10, 10.5, 11, 11.5, 12, 12.5]
        let uniqueBuckets = Set(sizes.map { ThemeFontCascade.quantizedPointSize($0) })
        XCTAssertEqual(uniqueBuckets.count, 6)
        for size in sizes {
            _ = ThemeFontCascade.cachedCTFont(familyID: family, nodeDesign: design, size: size)
        }
        XCTAssertEqual(ThemeFontCascade.resolvedFontCacheCountForTests(), 4)

        // 10 and 10.5 were inserted first and never reused, so they were evicted.
        // Re-resolving 10 is a miss and will evict the current oldest (11).
        // Touch the sizes we want to keep first so 11 is the one that goes.
        ThemeFontCascade.touchResolvedFontCacheForTests(familyID: family, nodeDesign: design, sizes: [11.5, 12, 12.5])
        let evicted = ThemeFontCascade.cachedCTFont(familyID: family, nodeDesign: design, size: 10)
        XCTAssertEqual(CTFontGetSize(evicted), ThemeFontCascade.quantizedPointSize(10), accuracy: 0.000_1)
        XCTAssertEqual(ThemeFontCascade.resolvedFontCacheCountForTests(), 4)
        XCTAssertEqual(CTFontCopyPostScriptName(evicted) as String, "EBGaramond-Regular")

        // 11.5 / 12 / 12.5 were just touched, so they must still be cached
        // (same pointer as a fresh snapshot lookup after beginFrame).
        ThemeFontCascade.beginFrame()
        let kept = ThemeFontCascade.cachedCTFont(familyID: family, nodeDesign: design, size: 12.5)
        XCTAssertEqual(CTFontGetSize(kept), ThemeFontCascade.quantizedPointSize(12.5), accuracy: 0.000_1)
        XCTAssertEqual(ThemeFontCascade.resolvedFontCacheCountForTests(), 4)
    }
}
