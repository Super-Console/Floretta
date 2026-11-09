import FlorettaCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// UTType for a picked file. Icon availability is reported separately so a missing
/// system icon can fall back to the generic file symbol.
@MainActor
enum AppleFileTypes {
    static func recognize(filename: String, declaredTypeIdentifier: String?) -> FileTypeFact {
        let fromName = (filename as NSString).pathExtension
        let declared = declaredTypeIdentifier.flatMap { UTType($0) }
        let fromExtension = fromName.isEmpty ? nil : UTType(filenameExtension: fromName)
        let type = resolved(fromExtension: fromExtension, declared: declared)
        let ext = storedExtension(pathExtension: fromName, type: type)
        let available = type.map { hasSystemIcon($0, fileExtension: ext) } ?? false
        return FileTypeFact(
            typeIdentifier: type?.identifier,
            systemIconAvailable: available,
            fileExtension: ext
        )
    }

    static var importableContentTypes: [UTType] {
        var seen = Set<String>()
        var types: [UTType] = []
        func append(_ type: UTType?) {
            guard let type, seen.insert(type.identifier).inserted else { return }
            types.append(type)
        }
        append(.item)
        append(.data)
        append(.pdf)
        append(UTType(filenameExtension: "psd"))
        append(UTType(filenameExtension: "dmg"))
        return types
    }

    private static func resolved(fromExtension: UTType?, declared: UTType?) -> UTType? {
        switch (fromExtension, declared) {
        case let (ext?, declared?):
            if declared.conforms(to: ext) { return declared }
            if ext.conforms(to: declared) { return ext }
            return ext
        case let (ext?, nil):
            return ext
        case let (nil, declared?):
            return declared
        case (nil, nil):
            return nil
        }
    }

    private static func storedExtension(pathExtension: String, type: UTType?) -> String {
        if !pathExtension.isEmpty { return pathExtension }
        return type?.preferredFilenameExtension ?? "bin"
    }

    private static func hasSystemIcon(_ type: UTType, fileExtension: String) -> Bool {
        let identifier = type.identifier
        if identifier.hasPrefix("dyn.") { return false }
        if identifier == UTType.data.identifier
            || identifier == UTType.item.identifier
            || identifier == UTType.content.identifier {
            return false
        }
        return iconDiffersFromGeneric(type, fileExtension: fileExtension)
    }

    #if os(macOS)
    private static func iconDiffersFromGeneric(_ type: UTType, fileExtension: String) -> Bool {
        let icon = NSWorkspace.shared.icon(for: type)
        let generic = NSWorkspace.shared.icon(for: .data)
        let side = NSSize(width: 32, height: 32)
        icon.size = side
        generic.size = side
        guard let left = icon.tiffRepresentation, let right = generic.tiffRepresentation else { return false }
        return left != right
    }
    #else
    private static func iconDiffersFromGeneric(_ type: UTType, fileExtension: String) -> Bool {
        guard let candidate = IOSFileIcons.png(extension: fileExtension),
              let generic = IOSFileIcons.png(extension: "qzxfloretta") else { return false }
        return candidate != generic
    }
    #endif
}

@MainActor
enum AppleFileIcon {
    private static var cache: [String: Image] = [:]

    static func image(for resolution: FileIconResolution) -> Image {
        switch resolution {
        case .system(let identifier):
            return systemImage(identifier: identifier) ?? generic
        case .generic:
            return generic
        }
    }

    static func image(fileExtension: String, filename: String) -> Image {
        if let cached = cache[fileExtension] { return cached }
        let fact = AppleFileTypes.recognize(filename: filename, declaredTypeIdentifier: nil)
        let image = image(for: FileIconPolicy.resolution(for: fact))
        cache[fileExtension] = image
        return image
    }

    static var generic: Image { Image(systemName: "doc") }

    #if os(macOS)
    private static func systemImage(identifier: String) -> Image? {
        guard let type = UTType(identifier) else { return nil }
        let icon = NSWorkspace.shared.icon(for: type)
        icon.size = NSSize(width: 32, height: 32)
        guard icon.tiffRepresentation != nil else { return nil }
        return Image(nsImage: icon)
    }
    #else
    private static func systemImage(identifier: String) -> Image? {
        guard let type = UTType(identifier) else { return nil }
        let ext = type.preferredFilenameExtension ?? "bin"
        guard let icon = IOSFileIcons.uiImage(extension: ext) else { return nil }
        return Image(uiImage: icon)
    }
    #endif
}

@MainActor
final class FileIconCache {
    private var images: [String: Image] = [:]

    func image(for badge: FileBadge) -> Image {
        if let cached = images[badge.fileExtension] { return cached }
        let image = AppleFileIcon.image(fileExtension: badge.fileExtension, filename: badge.filename)
        images[badge.fileExtension] = image
        return image
    }
}

enum PreviewFileProbe {
    /// Nil when the path is gone. Never throws.
    static func urlIfPresent(_ url: URL) -> URL? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return url
    }
}

#if os(iOS)
@MainActor
private enum IOSFileIcons {
    static func uiImage(extension ext: String) -> UIImage? {
        UIDocumentInteractionController(url: probeURL(ext)).icons.first
    }

    static func png(extension ext: String) -> Data? {
        uiImage(extension: ext)?.pngData()
    }

    private static func probeURL(_ ext: String) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("FlorettaIconProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safe = AttachmentNames.normalizeExtension(ext)
        let url = folder.appendingPathComponent("probe.\(safe)")
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        return url
    }
}
#endif
