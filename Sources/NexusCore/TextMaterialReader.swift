import CryptoKit
import Foundation

enum TextMaterialReadError: Error, Equatable {
    case empty
    case tooLarge
    case binary
    case invalidEncoding
    case changedDuringRead
    case unreadable
}

struct TextMaterialCapture: Equatable {
    let content: String
    let contentHash: String
    let characterCount: Int
    let truncated: Bool
}

enum TextMaterialReader {
    static let maximumFileByteCount: UInt64 = 64 * 1_024 * 1_024

    private static let chunkByteCount = 64 * 1_024
    private static let encodingSampleByteCount = 8 * 1_024
    private static let truncationMarker = "\n\n[... Nexus omitted middle content ...]\n\n"

    static func capture(at url: URL, characterLimit: Int) throws -> TextMaterialCapture {
        guard characterLimit > 0 else { throw TextMaterialReadError.unreadable }
        let before = try fileIdentity(at: url)
        guard before.size > 0 else { throw TextMaterialReadError.empty }
        guard before.size <= maximumFileByteCount else { throw TextMaterialReadError.tooLarge }

        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw TextMaterialReadError.unreadable
        }
        defer { try? handle.close() }

        let sample: Data
        do {
            sample = try handle.read(upToCount: encodingSampleByteCount) ?? Data()
            try handle.seek(toOffset: 0)
        } catch {
            throw TextMaterialReadError.unreadable
        }
        let detected = try detectEncoding(in: sample, fileSize: before.size)
        if detected.bomByteCount > 0 {
            do {
                try handle.seek(toOffset: UInt64(detected.bomByteCount))
            } catch {
                throw TextMaterialReadError.unreadable
            }
        }

        var decoder = StreamingDecoder(encoding: detected.encoding)
        var accumulator = TextCaptureAccumulator(limit: characterLimit, marker: truncationMarker)
        var hasher = SHA256()

        do {
            while let data = try handle.read(upToCount: chunkByteCount), !data.isEmpty {
                let decoded = try decoder.decode(data, isFinal: false)
                if !decoded.isEmpty {
                    hasher.update(data: Data(decoded.utf8))
                    accumulator.append(decoded)
                }
            }
            let final = try decoder.decode(Data(), isFinal: true)
            if !final.isEmpty {
                hasher.update(data: Data(final.utf8))
                accumulator.append(final)
            }
        } catch let error as TextMaterialReadError {
            throw error
        } catch {
            throw TextMaterialReadError.unreadable
        }

        guard accumulator.characterCount > 0 else { throw TextMaterialReadError.empty }
        let after = try fileIdentity(at: url)
        guard before == after else { throw TextMaterialReadError.changedDuringRead }

        return TextMaterialCapture(
            content: accumulator.content,
            contentHash: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            characterCount: accumulator.characterCount,
            truncated: accumulator.truncated
        )
    }

    private struct FileIdentity: Equatable {
        let size: UInt64
        let modificationDate: Date?
    }

    private enum Encoding {
        case utf8
        case utf16LittleEndian
        case utf16BigEndian
    }

    private struct DetectedEncoding {
        let encoding: Encoding
        let bomByteCount: Int
    }

    private static func fileIdentity(at url: URL) throws -> FileIdentity {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                throw TextMaterialReadError.unreadable
            }
            return FileIdentity(size: UInt64(fileSize), modificationDate: values.contentModificationDate)
        } catch let error as TextMaterialReadError {
            throw error
        } catch {
            throw TextMaterialReadError.unreadable
        }
    }

    private static func detectEncoding(in sample: Data, fileSize: UInt64) throws -> DetectedEncoding {
        guard fileSize > 0, !sample.isEmpty else { throw TextMaterialReadError.empty }
        if sample.starts(with: [0xEF, 0xBB, 0xBF]) {
            return DetectedEncoding(encoding: .utf8, bomByteCount: 3)
        }
        if sample.starts(with: [0xFF, 0xFE]) {
            return DetectedEncoding(encoding: .utf16LittleEndian, bomByteCount: 2)
        }
        if sample.starts(with: [0xFE, 0xFF]) {
            return DetectedEncoding(encoding: .utf16BigEndian, bomByteCount: 2)
        }

        if let inferred = inferredUTF16Encoding(from: sample) {
            return DetectedEncoding(encoding: inferred, bomByteCount: 0)
        }
        if sample.contains(0) {
            throw TextMaterialReadError.binary
        }
        if String(data: sample, encoding: .utf8) != nil || mayEndWithIncompleteUTF8(sample) {
            return DetectedEncoding(encoding: .utf8, bomByteCount: 0)
        }
        throw TextMaterialReadError.invalidEncoding
    }

    private static func inferredUTF16Encoding(from sample: Data) -> Encoding? {
        let evenLength = sample.count - (sample.count % 2)
        guard evenLength >= 8 else { return nil }
        var evenZeros = 0
        var oddZeros = 0
        var pairCount = 0
        var index = 0
        while index < evenLength {
            if sample[index] == 0 { evenZeros += 1 }
            if sample[index + 1] == 0 { oddZeros += 1 }
            pairCount += 1
            index += 2
        }
        let threshold = max(1, pairCount / 5)
        if oddZeros >= threshold, evenZeros * 4 < oddZeros {
            let value = String(data: sample.prefix(evenLength), encoding: .utf16LittleEndian)
            if value.map(printableScore) ?? 0 >= 0.85 {
                return .utf16LittleEndian
            }
            return nil
        }
        if evenZeros >= threshold, oddZeros * 4 < evenZeros {
            let value = String(data: sample.prefix(evenLength), encoding: .utf16BigEndian)
            if value.map(printableScore) ?? 0 >= 0.85 {
                return .utf16BigEndian
            }
            return nil
        }

        let prefix = sample.prefix(evenLength)
        let little = String(data: prefix, encoding: .utf16LittleEndian)
        let big = String(data: prefix, encoding: .utf16BigEndian)
        let littleScore = little.map(printableScore) ?? 0
        let bigScore = big.map(printableScore) ?? 0
        guard max(littleScore, bigScore) >= 0.85, abs(littleScore - bigScore) >= 0.1 else { return nil }
        return littleScore > bigScore ? .utf16LittleEndian : .utf16BigEndian
    }

    private static func printableScore(_ value: String) -> Double {
        guard !value.unicodeScalars.isEmpty else { return 0 }
        let printable = value.unicodeScalars.reduce(into: 0) { count, scalar in
            if scalar == "\n" || scalar == "\r" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar) {
                count += 1
            }
        }
        return Double(printable) / Double(value.unicodeScalars.count)
    }

    private static func mayEndWithIncompleteUTF8(_ data: Data) -> Bool {
        guard !data.isEmpty else { return false }
        for retainedByteCount in 1...min(3, data.count) {
            let prefix = data.dropLast(retainedByteCount)
            if String(data: prefix, encoding: .utf8) != nil {
                return true
            }
        }
        return false
    }

    private struct StreamingDecoder {
        let encoding: Encoding
        var carry = Data()

        mutating func decode(_ data: Data, isFinal: Bool) throws -> String {
            var combined = carry
            combined.append(data)
            carry.removeAll(keepingCapacity: true)
            if combined.isEmpty { return "" }

            let maximumCarry = encoding == .utf8 ? 3 : 4
            if isFinal {
                guard let value = string(from: combined) else { throw TextMaterialReadError.invalidEncoding }
                return value
            }
            for retainedByteCount in 0...min(maximumCarry, combined.count) {
                let prefix = combined.dropLast(retainedByteCount)
                guard let value = string(from: prefix) else { continue }
                if retainedByteCount > 0 {
                    carry = Data(combined.suffix(retainedByteCount))
                }
                return value
            }
            throw TextMaterialReadError.invalidEncoding
        }

        private func string(from data: Data.SubSequence) -> String? {
            switch encoding {
            case .utf8:
                return String(data: data, encoding: .utf8)
            case .utf16LittleEndian:
                guard data.count.isMultiple(of: 2) else { return nil }
                return String(data: data, encoding: .utf16LittleEndian)
            case .utf16BigEndian:
                guard data.count.isMultiple(of: 2) else { return nil }
                return String(data: data, encoding: .utf16BigEndian)
            }
        }
    }

    private struct TextCaptureAccumulator {
        let limit: Int
        let marker: String
        let headLimit: Int
        let tailLimit: Int
        var characterCount = 0
        var completeContent = ""
        var head = ""
        var tail = ""
        var truncated = false

        init(limit: Int, marker: String) {
            self.limit = limit
            self.marker = marker
            let available = max(0, limit - marker.count)
            let preferredTail = limit >= ContextMaterialExtractor.perSourceCharacterLimit ? 10_000 : available / 4
            self.tailLimit = min(preferredTail, available)
            self.headLimit = max(0, available - tailLimit)
        }

        mutating func append(_ value: String) {
            characterCount += value.count
            if !truncated {
                completeContent.append(value)
                if completeContent.count <= limit { return }
                truncated = true
                head = String(completeContent.prefix(headLimit))
                tail = String(completeContent.suffix(tailLimit))
                completeContent.removeAll(keepingCapacity: false)
                return
            }
            if head.count < headLimit {
                head.append(contentsOf: value.prefix(headLimit - head.count))
            }
            if tailLimit > 0 {
                tail = String((tail + value).suffix(tailLimit))
            }
        }

        var content: String {
            truncated ? head + marker + tail : completeContent
        }
    }
}
