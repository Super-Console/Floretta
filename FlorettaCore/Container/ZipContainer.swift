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
            if let inventory = inventoryError(for: error) {
                throw inventory
            }
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
        var failures: [AssetCorruption] = []
        var stored: Set<String> = []
        for entry in entries where entry.name.hasPrefix("assets/") {
            if entry.data.count > limits.maxAssetBytes {
                throw DocumentContainerError.overLimit("Asset \(entry.name) exceeds the size limit.")
            }
            guard let parsed = AttachmentNames.parseAsset(entry.name) else {
                failures.append(AssetCorruption(
                    filename: String(entry.name.dropFirst("assets/".count)),
                    sha256: "",
                    entryName: entry.name,
                    reason: .malformedName
                ))
                continue
            }
            stored.insert(parsed.sha256)
            let actual = sha256Hex(entry.data)
            if actual != parsed.sha256 {
                failures.append(AssetCorruption(
                    filename: AssetInventory.filenames(for: parsed.sha256, in: document),
                    sha256: parsed.sha256,
                    entryName: entry.name,
                    reason: .hashMismatch(actual: actual)
                ))
                continue
            }
            if assets.contains(where: { $0.sha256 == parsed.sha256 }) {
                continue
            }
            assets.append(FlorettaAsset(sha256: parsed.sha256, fileExtension: parsed.fileExtension, data: entry.data))
        }
        failures.append(contentsOf: AssetInventory.missingReferences(in: document, stored: stored))
        if let error = AssetInventory.error(from: failures) {
            throw error
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

    /// In-memory reads reject a bad CRC before the bytes can be hashed. Name that asset anyway.
    private func inventoryError(for error: ZipArchiveError) -> AssetInventoryError? {
        guard case .corrupt(let message) = error else { return nil }
        let prefix = "Zip entry "
        let suffix = " failed its checksum."
        guard message.hasPrefix(prefix), message.hasSuffix(suffix) else { return nil }
        let name = String(message.dropFirst(prefix.count).dropLast(suffix.count))
        guard name.hasPrefix("assets/") else { return nil }
        let parsed = AttachmentNames.parseAsset(name)
        return AssetInventoryError(failures: [
            AssetCorruption(
                filename: parsed.map { "\($0.sha256.prefix(8)).\($0.fileExtension)" } ?? name,
                sha256: parsed?.sha256 ?? "",
                entryName: name,
                reason: .declaredChecksumMismatch
            ),
        ])
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
