import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Spacebar preview for `.floretta`. Same picture as the Finder thumbnail, at a larger edge.
final class FlorettaPreviewProvider: NSObject, QLPreviewProvider {
    func providePreview(
        for request: QLFilePreviewRequest,
        completionHandler handler: @escaping (QLPreviewReply?, Error?) -> Void
    ) {
        let url = request.fileURL
        let deliver = PreviewReplyBox(handler)
        Task { @MainActor in
            let picture = FlorettaQuickLookRenderer.picture(
                at: url,
                longestPixelEdge: FlorettaQuickLookRenderer.finderPreviewEdge
            )
            let preview = FlorettaQuickLookRenderer.preview(from: picture)
            guard !preview.data.isEmpty else {
                deliver.handler(nil, CocoaError(.fileReadCorruptFile))
                return
            }
            let data = preview.data
            let size = CGSize(
                width: max(preview.contentSize.width, 1),
                height: max(preview.contentSize.height, 1)
            )
            let reply = QLPreviewReply(dataOfContentType: .png, contentSize: size) { _ in
                data
            }
            deliver.handler(reply, nil)
        }
    }
}

/// The Quick Look callback is not `Sendable`. The box crosses onto the main actor with the reply.
private final class PreviewReplyBox: @unchecked Sendable {
    let handler: (QLPreviewReply?, Error?) -> Void

    init(_ handler: @escaping (QLPreviewReply?, Error?) -> Void) {
        self.handler = handler
    }
}
