import Darwin
import Foundation
import OmiyaInput

final class MozcConverter: KanaKanjiConverter {
    private let executable: URL
    private let dictionary: URL
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?

    init?(bundle: Bundle) {
        guard let executable = bundle.url(forAuxiliaryExecutable: "omiya-mozc"),
              let dictionary = bundle.url(forResource: "mozc", withExtension: "data")
        else { return nil }
        self.executable = executable
        self.dictionary = dictionary
    }

    deinit {
        disconnect()
    }

    func convert(_ reading: String, segmentLengths: [Int]?) -> [ConversionSegment]? {
        let sizes = segmentLengths ?? []
        guard !reading.isEmpty, reading.utf8.count <= 1024,
              sizes.count <= 256, sizes.allSatisfy({ (1...255).contains($0) }),
              !reading.unicodeScalars.contains(where: { $0.value < 0x20 })
        else { return nil }
        let request = reading + "\n" + sizes.map(String.init).joined(separator: " ") + "\n"
        do {
            if process?.isRunning != true { try connect() }
            guard let input, let output else { return nil }
            try input.write(contentsOf: Data(request.utf8))
            let response = try readLine(from: output)
            return try JSONDecoder().decode([ConversionSegment]?.self, from: response)
        } catch {
            disconnect()
            return nil
        }
    }

    private func connect() throws {
        disconnect()
        let process = Process()
        let requests = Pipe()
        let replies = Pipe()
        guard fcntl(requests.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw ConnectionError.unavailable
        }
        process.executableURL = executable
        process.arguments = [dictionary.path]
        process.standardInput = requests
        process.standardOutput = replies
        process.standardError = FileHandle.nullDevice
        try process.run()
        input = requests.fileHandleForWriting
        output = replies.fileHandleForReading
        self.process = process
    }

    private func disconnect() {
        if let process, process.isRunning {
            process.terminate()
        }
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
    }

    private func readLine(from handle: FileHandle) throws -> Data {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while response.count < 2_000_000 {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { throw ConnectionError.unavailable }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32((remaining * 1_000).rounded(.up)))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0, descriptor.revents & Int16(POLLIN) != 0 else {
                throw ConnectionError.unavailable
            }
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(handle.fileDescriptor, bytes.baseAddress, bytes.count)
            }
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw ConnectionError.unavailable }
            let chunk = buffer.prefix(count)

            if let newline = chunk.firstIndex(of: 10) {
                response.append(contentsOf: chunk[..<newline])
                return response
            }
            response.append(contentsOf: chunk)
        }
        throw ConnectionError.unavailable
    }

    private enum ConnectionError: Error {
        case unavailable
    }
}
