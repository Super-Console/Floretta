import Foundation
import QuickLookThumbnailing

/// Finder icon for `.floretta`. The picture comes from `FlorettaQuickLookRenderer`.
final class FlorettaThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let edge = FlorettaQuickLookRenderer.pixelEdge(points: request.maximumSize, scale: request.scale)
        let deliver = ThumbnailReplyBox(handler)
        Task { @MainActor in
            let picture = FlorettaQuickLookRenderer.picture(at: url, longestPixelEdge: edge)
            do {
                let file = try FlorettaQuickLookRenderer.writePNG(picture, in: FileManager.default.temporaryDirectory)
                deliver.handler(QLThumbnailReply(imageFileURL: file), nil)
            } catch {
                deliver.handler(nil, error)
            }
        }
    }
}

/// The Quick Look callback is not `Sendable`. The box crosses onto the main actor with the reply.
private final class ThumbnailReplyBox: @unchecked Sendable {
    let handler: (QLThumbnailReply?, Error?) -> Void

    init(_ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        self.handler = handler
    }
}
