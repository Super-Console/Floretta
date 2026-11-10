import FlorettaCore
import Foundation

/// A share reduced to a draft. `fileURL` is our copy of a photo or file.
/// The system deletes the provider's temporary file when its callback returns,
/// so the copy happens inside that callback. The copy is a file-system copy.
struct ShareLoadedItem: Equatable, Sendable {
    var draft: ShareDraft
    var fileURL: URL?
}

enum ShareItemLoader {
    static func load(_ items: [NSExtensionItem]) async throws -> ShareLoadedItem {
        let providers = items.flatMap { $0.attachments ?? [] }
        let title = items.compactMap { item -> String? in
            if let text = item.attributedTitle?.string, !text.isEmpty { return text }
            return item.attributedContentText?.string
        }.first
        guard let plan = ShareTypeChoice.plan(registeredTypeIdentifiers: providers.map(\.registeredTypeIdentifiers)) else {
            throw ShareIngressError.emptyPayload
        }
        switch plan {
        case .webPage:
            let url = try await firstWebURL(in: providers)
            let draft = try ShareDraftBuilder.make(origin: .safari, url: url, title: title)
            return ShareLoadedItem(draft: draft, fileURL: nil)
        case .plainText:
            let text = try await firstText(in: providers)
            let draft = try ShareDraftBuilder.make(origin: .safari, text: text)
            return ShareLoadedItem(draft: draft, fileURL: nil)
        case .file(let typeIdentifier):
            let loaded = try await firstFile(in: providers, typeIdentifier: typeIdentifier)
            do {
                let draft = try ShareDraftBuilder.make(origin: .photos, file: loaded.fact)
                return ShareLoadedItem(draft: draft, fileURL: loaded.url)
            } catch {
                try? FileManager.default.removeItem(at: loaded.url)
                throw error
            }
        }
    }

    private static func firstWebURL(in providers: [NSItemProvider]) async throws -> String {
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.url") {
            switch try await loadItem(provider, type: "public.url") {
            case .url(let url):
                if let web = ShareLinks.webURL(url.absoluteString) { return web }
            case .text(let text):
                if let web = ShareLinks.webURL(text) { return web }
            case .bytes(let data):
                if let text = String(data: data, encoding: .utf8), let web = ShareLinks.webURL(text) { return web }
            case .none:
                break
            }
        }
        throw ShareIngressError.emptyPayload
    }

    private static func firstText(in providers: [NSItemProvider]) async throws -> String {
        for provider in providers {
            let type: String?
            if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                type = "public.plain-text"
            } else if provider.hasItemConformingToTypeIdentifier("public.text") {
                type = "public.text"
            } else {
                type = nil
            }
            guard let type else { continue }
            let text: String?
            switch try await loadItem(provider, type: type) {
            case .text(let string):
                text = string
            case .bytes(let data):
                text = String(data: data, encoding: .utf8)
            case .url, .none:
                text = nil
            }
            if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        throw ShareIngressError.emptyPayload
    }

    private static func firstFile(
        in providers: [NSItemProvider],
        typeIdentifier: String
    ) async throws -> (fact: ShareFileFact, url: URL) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(typeIdentifier) {
            let filename = ShareTypeChoice.filename(suggested: provider.suggestedName, typeIdentifier: typeIdentifier)
            let url = try await copyFile(provider, typeIdentifier: typeIdentifier, filename: filename)
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
            let fact = ShareFileFact(
                filename: filename,
                byteCount: Int64(values.fileSize ?? 0),
                isDirectory: values.isDirectory ?? false
            )
            return (fact, url)
        }
        throw ShareIngressError.missingFile
    }

    /// Copies before the provider deletes `url`. Does not read the file into `Data`.
    private static func copyFile(
        _ provider: NSItemProvider,
        typeIdentifier: String,
        filename: String
    ) async throws -> URL {
        let ext = (filename as NSString).pathExtension
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(ext)
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    if let error {
                        let message = error.localizedDescription
                        continuation.resume(throwing: ShareProviderError(message: message))
                        return
                    }
                    guard let url else {
                        continuation.resume(throwing: ShareIngressError.missingFile)
                        return
                    }
                    do {
                        try FileManager.default.copyItem(at: url, to: destination)
                        continuation.resume()
                    } catch {
                        let message = error.localizedDescription
                        continuation.resume(throwing: ShareProviderError(message: message))
                    }
                }
            }
            return destination
        } catch {
            guard typeIdentifier == "public.file-url" || typeIdentifier == "public.data" else { throw error }
            let value = try await loadItem(provider, type: typeIdentifier)
            guard case .url(let url) = value else { throw error }
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        }
    }

    /// Copies the provider object into a value before leaving the callback.
    /// `NSSecureCoding` is not `Sendable`, so the original `item` stays in the callback.
    private static func loadItem(_ provider: NSItemProvider, type: String) async throws -> LoadedShareValue {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    let message = error.localizedDescription
                    continuation.resume(throwing: ShareProviderError(message: message))
                    return
                }
                // Copy here. `item` is not Sendable and must not be the resumed value.
                let value: LoadedShareValue
                if let found = item as? URL, let copy = URL(string: found.absoluteString) {
                    value = .url(copy)
                } else if let text = item as? String {
                    value = .text(String(text))
                } else if let data = item as? Data {
                    value = .bytes(Data(data))
                } else {
                    value = .none
                }
                continuation.resume(returning: value)
            }
        }
    }
}

/// Value copied out of an `NSItemProvider` callback. The provider object itself is not sent across the continuation.
private enum LoadedShareValue: Sendable {
    case url(URL)
    case text(String)
    case bytes(Data)
    case none
}

private struct ShareProviderError: Error, LocalizedError, Sendable {
    var message: String
    var errorDescription: String? { message }
}
