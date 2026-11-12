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
}
