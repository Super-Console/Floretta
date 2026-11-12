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
        guard let ping = ThemeFontCascade.firstAvailable(ThemeFontCascade.chineseSansNames) else {
            XCTFail("PingFang SC was not found on this Mac")
            return
        }
        let used = ThemeFontCascade.postScriptName(familyID: "system-sans", for: "汉字")
        XCTAssertEqual(used, ping)
        let interCJK = ThemeFontCascade.postScriptName(familyID: "inter", for: "汉字")
        XCTAssertNotEqual(interCJK, "Inter-Regular")
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

    func testSourceHanSerifIsNotBundled() {
        let names = ThemeFontCascade.bundledFontURLs().map(\.lastPathComponent)
        XCTAssertFalse(names.contains { $0.contains("SourceHan") || $0.contains("CJK") })
        XCTAssertEqual(names.filter { $0.hasSuffix(".otf") }.count, 7)
    }
}
