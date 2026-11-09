import Foundation

/// SHA-256 for asset names. Foundation has no digest API that is present on every
/// toolchain, and Core does not import CryptoKit. `SHA256Streaming` updates a
/// fixed-size block so a multi-gigabyte file never sits in one buffer.
public struct SHA256Streaming: Sendable {
    private var hash: [UInt32] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ]
    private var block = [UInt8](repeating: 0, count: 64)
    private var blockCount = 0
    private var totalBytes: UInt64 = 0

    public init() {}

    public mutating func update(_ buffer: UnsafeRawBufferPointer) {
        guard let base = buffer.baseAddress, buffer.count > 0 else { return }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var index = 0
        while index < buffer.count {
            let space = 64 - blockCount
            let take = min(space, buffer.count - index)
            for offset in 0..<take {
                block[blockCount + offset] = bytes[index + offset]
            }
            blockCount += take
            index += take
            totalBytes &+= UInt64(take)
            if blockCount == 64 {
                SHA256Hash.compress(&block, into: &hash)
                blockCount = 0
            }
        }
    }

    public mutating func finalize() -> [UInt8] {
        let bitLength = totalBytes &* 8
        block[blockCount] = 0x80
        blockCount += 1
        if blockCount > 56 {
            while blockCount < 64 {
                block[blockCount] = 0
                blockCount += 1
            }
            SHA256Hash.compress(&block, into: &hash)
            blockCount = 0
        }
        while blockCount < 56 {
            block[blockCount] = 0
            blockCount += 1
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            block[blockCount] = UInt8((bitLength >> UInt64(shift)) & 0xff)
            blockCount += 1
        }
        SHA256Hash.compress(&block, into: &hash)
        var out = [UInt8]()
        out.reserveCapacity(32)
        for value in hash {
            out.append(UInt8((value >> 24) & 0xff))
            out.append(UInt8((value >> 16) & 0xff))
            out.append(UInt8((value >> 8) & 0xff))
            out.append(UInt8(value & 0xff))
        }
        return out
    }
}

enum SHA256Hash {
    static func digest(_ message: Data) -> [UInt8] {
        var streaming = SHA256Streaming()
        message.withUnsafeBytes { streaming.update($0) }
        return streaming.finalize()
    }

    fileprivate static func compress(_ block: inout [UInt8], into hash: inout [UInt32]) {
        var words = [UInt32](repeating: 0, count: 64)
        for index in 0..<16 {
            let start = index * 4
            words[index] = (UInt32(block[start]) << 24)
                | (UInt32(block[start + 1]) << 16)
                | (UInt32(block[start + 2]) << 8)
                | UInt32(block[start + 3])
        }
        for index in 16..<64 {
            let s0 = rotate(words[index - 15], 7) ^ rotate(words[index - 15], 18) ^ (words[index - 15] >> 3)
            let s1 = rotate(words[index - 2], 17) ^ rotate(words[index - 2], 19) ^ (words[index - 2] >> 10)
            words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
        }
        var a = hash[0]
        var b = hash[1]
        var c = hash[2]
        var d = hash[3]
        var e = hash[4]
        var f = hash[5]
        var g = hash[6]
        var h = hash[7]
        for index in 0..<64 {
            let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
            let choice = (e & f) ^ (~e & g)
            let temp1 = h &+ s1 &+ choice &+ k[index] &+ words[index]
            let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
            let majority = (a & b) ^ (a & c) ^ (b & c)
            let temp2 = s0 &+ majority
            h = g
            g = f
            f = e
            e = d &+ temp1
            d = c
            c = b
            b = a
            a = temp1 &+ temp2
        }
        hash[0] = hash[0] &+ a
        hash[1] = hash[1] &+ b
        hash[2] = hash[2] &+ c
        hash[3] = hash[3] &+ d
        hash[4] = hash[4] &+ e
        hash[5] = hash[5] &+ f
        hash[6] = hash[6] &+ g
        hash[7] = hash[7] &+ h
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        (value >> count) | (value << (32 - count))
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]
}
