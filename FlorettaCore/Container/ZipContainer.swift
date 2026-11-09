import Foundation

public struct ZipContainer: DocumentContainer {
    public var limits: ZipLimits

    public init(limits: ZipLimits = .standard) {
        self.limits = limits
    }

    public func read(data: Data) throws -> FlorettaPackage {
        let entries: [ZipEntry]
        do {
            entries = try ZipArchive.read(data, limits: limits)
        } catch let error as ZipArchiveError {
            throw map(error)
        }
        guard let documentEntry = entries.first(where: { $0.name == "document.json" }) else {
            throw DocumentContainerError.missingEntry("document.json")
        }
        guard let metadataEntry = entries.first(where: { $0.name == "metadata.json" }) else {
            throw DocumentContainerError.missingEntry("metadata.json")
        }
        let document: MindMapDocument
        do {
            document = try FlorettaCodec.decode(documentEntry.data)
        } catch let error as FlorettaCodecError {
            throw DocumentContainerError.document(error)
        } catch {
            throw DocumentContainerError.corrupt("document.json could not be read.")
        }
        let nodes = document.topicCount
        if nodes > limits.maxNodes {
            throw DocumentContainerError.overLimit("Document has \(nodes) nodes; limit is \(limits.maxNodes).")
        }
        let metadata: FlorettaMetadata
        do {
            metadata = try JSONDecoder().decode(FlorettaMetadata.self, from: metadataEntry.data)
        } catch let error as DocumentContainerError {
            throw error
        } catch {
            throw DocumentContainerError.corrupt("metadata.json could not be read.")
        }
        var assets: [FlorettaAsset] = []
        for entry in entries where entry.name.hasPrefix("assets/") {
            if entry.data.count > limits.maxAssetBytes {
                throw DocumentContainerError.overLimit("Asset \(entry.name) exceeds the size limit.")
            }
            let fileName = String(entry.name.dropFirst("assets/".count))
            let parts = fileName.split(separator: ".", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].count == 64, parts[0].allSatisfy(\.isHexDigit) else {
                throw DocumentContainerError.corrupt("Asset name \(entry.name) is not assets/<sha256>.<ext>.")
            }
            let hash = parts[0].lowercased()
            guard hash == sha256Hex(entry.data) else {
                throw DocumentContainerError.corrupt("Asset \(entry.name) does not match its content hash.")
            }
            if assets.contains(where: { $0.sha256 == hash }) {
                continue
            }
            assets.append(FlorettaAsset(sha256: hash, fileExtension: parts[1].lowercased(), data: entry.data))
        }
        assets.sort { $0.sha256 < $1.sha256 }
        return FlorettaPackage(document: document, metadata: metadata, assets: assets)
    }

    public func write(_ package: FlorettaPackage) throws -> Data {
        let nodes = package.document.topicCount
        if nodes > limits.maxNodes {
            throw DocumentContainerError.overLimit("Document has \(nodes) nodes; limit is \(limits.maxNodes).")
        }
        let documentData: Data
        do {
            documentData = try FlorettaCodec.encode(package.document)
        } catch let error as FlorettaCodecError {
            throw DocumentContainerError.document(error)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let metadataData = try encoder.encode(package.metadata)
        var entries = [
            ZipEntry(name: "document.json", data: documentData),
            ZipEntry(name: "metadata.json", data: metadataData),
        ]
        var seen: Set<String> = []
        for asset in package.assets {
            if asset.data.count > limits.maxAssetBytes {
                throw DocumentContainerError.overLimit("Asset \(asset.relativePath) exceeds the size limit.")
            }
            if !seen.insert(asset.sha256).inserted {
                continue
            }
            entries.append(ZipEntry(name: asset.relativePath, data: asset.data))
        }
        if entries.count > limits.maxEntries {
            throw DocumentContainerError.overLimit("Package has \(entries.count) entries; limit is \(limits.maxEntries).")
        }
        let total = entries.reduce(0) { $0 + $1.data.count }
        if total > limits.maxDecompressedBytes {
            throw DocumentContainerError.overLimit("Package exceeds \(limits.maxDecompressedBytes) bytes.")
        }
        return ZipArchive.write(entries)
    }

    private func map(_ error: ZipArchiveError) -> DocumentContainerError {
        switch error {
        case .corrupt(let message):
            return .corrupt(message)
        case .overLimit(let message):
            return .overLimit(message)
        }
    }
}
