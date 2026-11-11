import Foundation

/// Stable limits and formatting shared by the media preview pipeline and its tests.
public enum MediaPreviewPolicy {
    public static let maximumWaveformSamples = 512

    public static func boundedSamples(_ values: [Float], limit: Int = maximumWaveformSamples) -> [Float] {
        let count = max(0, limit)
        guard values.count > count, count > 0 else { return Array(values.prefix(count)) }
        guard count > 1 else { return [values.max() ?? 0] }
        return (0..<count).map { index in
            let start = index * values.count / count
            let end = max(start + 1, (index + 1) * values.count / count)
            return values[start..<min(end, values.count)].map(abs).max() ?? 0
        }
    }

    public static func durationLabel(seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = min(Int(seconds), Int.max)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

public struct MediaPreviewArtifact: Equatable, Sendable {
    public let imageData: Data
    public let duration: Double?

    public init(imageData: Data, duration: Double?) {
        self.imageData = imageData
        self.duration = duration
    }
}

/// The platform target supplies AVFoundation-backed generation; tests inject a fake.
public protocol MediaPreviewGenerating: Sendable {
    func generate(from file: URL, kind: NodeMediaKind) async -> MediaPreviewArtifact?
}

public struct MediaPreviewLoader: Sendable {
    public let cache: ThumbnailFileCache
    public let generator: any MediaPreviewGenerating

    public init(cache: ThumbnailFileCache, generator: any MediaPreviewGenerating) {
        self.cache = cache
        self.generator = generator
    }

    /// Missing files and failed decoders are normal placeholder cases, never fatal errors.
    public func load(file: URL, key: String, kind: NodeMediaKind) async -> MediaPreviewArtifact? {
        guard kind != .other,
              FileManager.default.isReadableFile(atPath: file.path) else { return nil }
        if cache.contains(key), let data = try? Data(contentsOf: cache.fileURL(for: key)) {
            try? cache.touch(key)
            return MediaPreviewArtifact(imageData: data, duration: nil)
        }
        guard let result = await generator.generate(from: file, kind: kind) else { return nil }
        try? cache.store(result.imageData, for: key)
        return result
    }
}
