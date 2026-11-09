import Foundation

enum ZipArchiveError: Error, Equatable, Sendable {
    case corrupt(String)
    case overLimit(String)
}

struct ZipLimits: Equatable, Sendable {
    var maxEntries: Int
    var maxDecompressedBytes: Int
    var maxNodes: Int
    var maxAssetBytes: Int

    static let standard = ZipLimits(
        maxEntries: 512,
        maxDecompressedBytes: 32 * 1024 * 1024,
        maxNodes: 100_000,
        maxAssetBytes: 16 * 1024 * 1024
    )
}

struct ZipEntry: Equatable, Sendable {
    var name: String
    var data: Data
}

enum ZipArchive {
    static func write(_ entries: [ZipEntry]) -> Data {
        let sorted = entries.sorted { $0.name < $1.name }
        var local = Data()
        var central = Data()
        var offset: UInt32 = 0
        for entry in sorted {
            let name = Data(entry.name.utf8)
            let crc = zipCRC32(entry.data)
            let size = UInt32(entry.data.count)
            var header = Data()
            appendLE(UInt32(0x04034b50), to: &header)
            appendLE(UInt16(20), to: &header)
            appendLE(UInt16(0), to: &header)
            appendLE(UInt16(0), to: &header)
            appendLE(UInt16(0), to: &header)
            appendLE(UInt16(0), to: &header)
            appendLE(crc, to: &header)
            appendLE(size, to: &header)
            appendLE(size, to: &header)
            appendLE(UInt16(name.count), to: &header)
            appendLE(UInt16(0), to: &header)
            let localStart = offset
            local.append(header)
            local.append(name)
            local.append(entry.data)
            offset += UInt32(header.count + name.count + entry.data.count)

            var record = Data()
            appendLE(UInt32(0x02014b50), to: &record)
            appendLE(UInt16(20), to: &record)
            appendLE(UInt16(20), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(crc, to: &record)
            appendLE(size, to: &record)
            appendLE(size, to: &record)
            appendLE(UInt16(name.count), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt16(0), to: &record)
            appendLE(UInt32(0), to: &record)
            appendLE(localStart, to: &record)
            central.append(record)
            central.append(name)
        }
        let centralStart = UInt32(local.count)
        var end = Data()
        appendLE(UInt32(0x06054b50), to: &end)
        appendLE(UInt16(0), to: &end)
        appendLE(UInt16(0), to: &end)
        appendLE(UInt16(sorted.count), to: &end)
        appendLE(UInt16(sorted.count), to: &end)
        appendLE(UInt32(central.count), to: &end)
        appendLE(centralStart, to: &end)
        appendLE(UInt16(0), to: &end)
        return local + central + end
    }

    static func read(_ data: Data, limits: ZipLimits) throws -> [ZipEntry] {
        guard data.count >= 22 else {
            throw ZipArchiveError.corrupt("Zip is too small.")
        }
        guard let eocd = findEOCD(data) else {
            throw ZipArchiveError.corrupt("Zip directory is missing.")
        }
        let entryCount = Int(readU16(data, eocd + 10))
        if entryCount > limits.maxEntries {
            throw ZipArchiveError.overLimit("Zip has \(entryCount) entries; limit is \(limits.maxEntries).")
        }
        let centralSize = Int(readU32(data, eocd + 12))
        let centralOffset = Int(readU32(data, eocd + 16))
        guard centralOffset >= 0, centralSize >= 0,
              centralOffset <= data.count, centralOffset + centralSize <= data.count else {
            throw ZipArchiveError.corrupt("Zip directory is out of range.")
        }
        var cursor = centralOffset
        let centralEnd = centralOffset + centralSize
        var entries: [ZipEntry] = []
        var decompressed = 0
        for _ in 0..<entryCount {
            guard cursor + 46 <= centralEnd else {
                throw ZipArchiveError.corrupt("Zip directory entry is truncated.")
            }
            guard readU32(data, cursor) == 0x02014b50 else {
                throw ZipArchiveError.corrupt("Zip directory entry is invalid.")
            }
            let flags = Int(readU16(data, cursor + 8))
            let method = Int(readU16(data, cursor + 10))
            let crc = readU32(data, cursor + 16)
            let compressedSize = Int(readU32(data, cursor + 20))
            let uncompressedSize = Int(readU32(data, cursor + 24))
            let nameLength = Int(readU16(data, cursor + 28))
            let extraLength = Int(readU16(data, cursor + 30))
            let commentLength = Int(readU16(data, cursor + 32))
            let localOffset = Int(readU32(data, cursor + 42))
            let nameStart = cursor + 46
            guard nameStart + nameLength + extraLength + commentLength <= centralEnd else {
                throw ZipArchiveError.corrupt("Zip directory name is truncated.")
            }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let name = String(data: nameData, encoding: .utf8) else {
                throw ZipArchiveError.corrupt("Zip entry name is not UTF-8.")
            }
            if flags & 0x1 != 0 || flags & 0x8 != 0 {
                throw ZipArchiveError.corrupt("Unsupported zip entry flags.")
            }
            try validateName(name)
            if uncompressedSize > limits.maxDecompressedBytes || compressedSize > limits.maxDecompressedBytes {
                throw ZipArchiveError.overLimit("Zip entry \(name) exceeds the size limit.")
            }
            if decompressed > limits.maxDecompressedBytes - uncompressedSize {
                throw ZipArchiveError.overLimit("Zip decompressed size exceeds \(limits.maxDecompressedBytes) bytes.")
            }
            let payload = try extract(
                data: data,
                localOffset: localOffset,
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                crc: crc,
                maxOutput: limits.maxDecompressedBytes - decompressed
            )
            decompressed += payload.count
            if !name.hasSuffix("/") {
                entries.append(ZipEntry(name: name, data: payload))
            }
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    private static func extract(
        data: Data,
        localOffset: Int,
        name: String,
        method: Int,
        compressedSize: Int,
        uncompressedSize: Int,
        crc: UInt32,
        maxOutput: Int
    ) throws -> Data {
        guard localOffset >= 0, localOffset + 30 <= data.count else {
            throw ZipArchiveError.corrupt("Zip entry \(name) is out of range.")
        }
        guard readU32(data, localOffset) == 0x04034b50 else {
            throw ZipArchiveError.corrupt("Zip entry \(name) has a bad header.")
        }
        let nameLength = Int(readU16(data, localOffset + 26))
        let extraLength = Int(readU16(data, localOffset + 28))
        let start = localOffset + 30 + nameLength + extraLength
        guard start >= 0, compressedSize >= 0, start <= data.count, compressedSize <= data.count - start else {
            throw ZipArchiveError.corrupt("Zip entry \(name) is truncated.")
        }
        let compressed = data.subdata(in: start..<(start + compressedSize))
        let output: Data
        switch method {
        case 0:
            guard compressedSize == uncompressedSize else {
                throw ZipArchiveError.corrupt("Zip entry \(name) has a bad stored size.")
            }
            output = compressed
        case 8:
            do {
                output = try RawInflate.inflate(compressed, maxOutput: maxOutput)
            } catch InflateError.tooBig {
                throw ZipArchiveError.overLimit("Zip entry \(name) exceeds the size limit.")
            } catch {
                throw ZipArchiveError.corrupt("Zip entry \(name) could not be inflated.")
            }
        default:
            throw ZipArchiveError.corrupt("Zip entry \(name) uses unsupported compression \(method).")
        }
        guard output.count == uncompressedSize else {
            throw ZipArchiveError.corrupt("Zip entry \(name) inflated to an unexpected size.")
        }
        guard zipCRC32(output) == crc else {
            throw ZipArchiveError.corrupt("Zip entry \(name) failed its checksum.")
        }
        return output
    }

    private static func validateName(_ name: String) throws {
        if name.isEmpty || name.hasPrefix("/") || name.contains("\\") || name.contains("..") {
            throw ZipArchiveError.corrupt("Zip entry name is not allowed.")
        }
    }

    private static func findEOCD(_ data: Data) -> Int? {
        let start = max(0, data.count - 22 - 65_535)
        var index = data.count - 22
        while index >= start {
            if readU32(data, index) == 0x06054b50 {
                return index
            }
            index -= 1
        }
        return nil
    }
}

enum InflateError: Error {
    case corrupt
    case tooBig
}

enum RawInflate {
    static func inflate(_ input: Data, maxOutput: Int) throws -> Data {
        var reader = BitReader(input)
        var output: [UInt8] = []
        output.reserveCapacity(min(maxOutput, 65_536))
        var finished = false
        while !finished {
            let bfinal = try reader.bits(1)
            let btype = try reader.bits(2)
            finished = bfinal == 1
            switch btype {
            case 0:
                try storedBlock(&reader, into: &output, max: maxOutput)
            case 1:
                try decodeCodes(
                    lit: try Huffman(lengths: fixedLiteralLengths()),
                    dist: try Huffman(lengths: fixedDistanceLengths()),
                    reader: &reader,
                    into: &output,
                    max: maxOutput
                )
            case 2:
                try dynamicBlock(&reader, into: &output, max: maxOutput)
            default:
                throw InflateError.corrupt
            }
        }
        return Data(output)
    }

    private static func storedBlock(_ reader: inout BitReader, into output: inout [UInt8], max: Int) throws {
        reader.align()
        let length = try reader.byte() | (try reader.byte() << 8)
        let complement = try reader.byte() | (try reader.byte() << 8)
        guard complement == (~length & 0xFFFF) else { throw InflateError.corrupt }
        guard length <= max, output.count <= max - length else { throw InflateError.tooBig }
        for _ in 0..<length {
            output.append(UInt8(try reader.byte()))
        }
    }

    private static func dynamicBlock(_ reader: inout BitReader, into output: inout [UInt8], max: Int) throws {
        let literalCount = try reader.bits(5) + 257
        let distanceCount = try reader.bits(5) + 1
        let codeLengthCount = try reader.bits(4) + 4
        guard literalCount <= 286, distanceCount <= 32, codeLengthCount <= 19 else {
            throw InflateError.corrupt
        }
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        var codeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengths[order[index]] = try reader.bits(3)
        }
        let lengthDecoder = try Huffman(lengths: codeLengths)
        var lengths = [Int](repeating: 0, count: literalCount + distanceCount)
        var cursor = 0
        while cursor < lengths.count {
            let symbol = try lengthDecoder.decode(&reader)
            switch symbol {
            case 0...15:
                lengths[cursor] = symbol
                cursor += 1
            case 16:
                guard cursor > 0 else { throw InflateError.corrupt }
                let repeatCount = try reader.bits(2) + 3
                guard cursor + repeatCount <= lengths.count else { throw InflateError.corrupt }
                let value = lengths[cursor - 1]
                for _ in 0..<repeatCount {
                    lengths[cursor] = value
                    cursor += 1
                }
            case 17:
                let repeatCount = try reader.bits(3) + 3
                guard cursor + repeatCount <= lengths.count else { throw InflateError.corrupt }
                cursor += repeatCount
            case 18:
                let repeatCount = try reader.bits(7) + 11
                guard cursor + repeatCount <= lengths.count else { throw InflateError.corrupt }
                cursor += repeatCount
            default:
                throw InflateError.corrupt
            }
        }
        let lit = try Huffman(lengths: Array(lengths[..<literalCount]))
        let dist = try Huffman(lengths: Array(lengths[literalCount...]))
        try decodeCodes(lit: lit, dist: dist, reader: &reader, into: &output, max: max)
    }

    private static func decodeCodes(
        lit: Huffman,
        dist: Huffman,
        reader: inout BitReader,
        into output: inout [UInt8],
        max: Int
    ) throws {
        while true {
            let symbol = try lit.decode(&reader)
            if symbol < 256 {
                guard output.count < max else { throw InflateError.tooBig }
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else if symbol <= 285 {
                let length = try matchLength(symbol, reader: &reader)
                let distanceSymbol = try dist.decode(&reader)
                let distance = try matchDistance(distanceSymbol, reader: &reader)
                guard distance > 0, distance <= output.count else { throw InflateError.corrupt }
                guard length <= max, output.count <= max - length else { throw InflateError.tooBig }
                for _ in 0..<length {
                    output.append(output[output.count - distance])
                }
            } else {
                throw InflateError.corrupt
            }
        }
    }

    private static func matchLength(_ symbol: Int, reader: inout BitReader) throws -> Int {
        let bases = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258,
        ]
        let extras = [
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
            3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
        ]
        let index = symbol - 257
        guard bases.indices.contains(index) else { throw InflateError.corrupt }
        return bases[index] + (try reader.bits(extras[index]))
    }

    private static func matchDistance(_ symbol: Int, reader: inout BitReader) throws -> Int {
        let bases = [
            1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
            257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
        ]
        let extras = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
            7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
        ]
        guard bases.indices.contains(symbol) else { throw InflateError.corrupt }
        return bases[symbol] + (try reader.bits(extras[symbol]))
    }

    private static func fixedLiteralLengths() -> [Int] {
        var lengths = [Int](repeating: 0, count: 288)
        for index in 0...143 { lengths[index] = 8 }
        for index in 144...255 { lengths[index] = 9 }
        for index in 256...279 { lengths[index] = 7 }
        for index in 280...287 { lengths[index] = 8 }
        return lengths
    }

    private static func fixedDistanceLengths() -> [Int] {
        Array(repeating: 5, count: 32)
    }
}

private struct BitReader {
    let bytes: [UInt8]
    var index = 0
    var bit = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func bitValue() throws -> Int {
        guard index < bytes.count else { throw InflateError.corrupt }
        let value = Int((bytes[index] >> bit) & 1)
        bit += 1
        if bit == 8 {
            bit = 0
            index += 1
        }
        return value
    }

    mutating func bits(_ count: Int) throws -> Int {
        var value = 0
        for shift in 0..<count {
            value |= try bitValue() << shift
        }
        return value
    }

    mutating func align() {
        if bit != 0 {
            bit = 0
            index += 1
        }
    }

    mutating func byte() throws -> Int {
        align()
        guard index < bytes.count else { throw InflateError.corrupt }
        let value = Int(bytes[index])
        index += 1
        return value
    }
}

private struct Huffman {
    private var symbolsByCode: [Int: Int] = [:]
    private var minimumLength = 1
    private var maximumLength = 0

    init(lengths: [Int]) throws {
        var counts = [Int](repeating: 0, count: 16)
        for length in lengths where length > 0 {
            guard length < 16 else { throw InflateError.corrupt }
            counts[length] += 1
        }
        var nextCode = [Int](repeating: 0, count: 16)
        var code = 0
        for length in 1...15 {
            let (sum, sumOverflow) = code.addingReportingOverflow(counts[length - 1])
            let (shifted, shiftOverflow) = sum.multipliedReportingOverflow(by: 2)
            if sumOverflow || shiftOverflow || shifted < 0 || shifted >= 65_536 {
                throw InflateError.corrupt
            }
            code = shifted
            nextCode[length] = code
        }
        var minimum = 16
        var maximum = 0
        for (symbol, length) in lengths.enumerated() where length > 0 {
            let assigned = nextCode[length]
            nextCode[length] = assigned + 1
            symbolsByCode[(length << 16) | assigned] = symbol
            minimum = min(minimum, length)
            maximum = max(maximum, length)
        }
        if maximum > 0 {
            minimumLength = minimum
            maximumLength = maximum
        }
    }

    func decode(_ reader: inout BitReader) throws -> Int {
        guard maximumLength > 0 else { throw InflateError.corrupt }
        var code = 0
        for length in 1...maximumLength {
            code = (code << 1) | (try reader.bitValue())
            if length >= minimumLength, let symbol = symbolsByCode[(length << 16) | code] {
                return symbol
            }
        }
        throw InflateError.corrupt
    }
}

func zipCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        var mixed = (crc ^ UInt32(byte)) & 0xFF
        for _ in 0..<8 {
            if mixed & 1 == 1 {
                mixed = 0xEDB8_8320 ^ (mixed >> 1)
            } else {
                mixed >>= 1
            }
        }
        crc = (crc >> 8) ^ mixed
    }
    return crc ^ 0xFFFF_FFFF
}

private func appendLE(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
}

private func appendLE(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
}

private func readU16(_ data: Data, _ offset: Int) -> UInt16 {
    guard offset >= 0, offset + 1 < data.count else { return 0 }
    return UInt16(data[data.startIndex + offset])
        | (UInt16(data[data.startIndex + offset + 1]) << 8)
}

private func readU32(_ data: Data, _ offset: Int) -> UInt32 {
    guard offset >= 0, offset + 3 < data.count else { return 0 }
    return UInt32(data[data.startIndex + offset])
        | (UInt32(data[data.startIndex + offset + 1]) << 8)
        | (UInt32(data[data.startIndex + offset + 2]) << 16)
        | (UInt32(data[data.startIndex + offset + 3]) << 24)
}
