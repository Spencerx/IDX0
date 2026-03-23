import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunnerError: LocalizedError, Sendable {
    case executableNotFound(String)
    case executionFailed(executable: String, arguments: [String], exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let executable):
            return "Executable not found: \(executable)"
        case .executionFailed(let executable, let arguments, let exitCode, let stderr):
            let joined = ([executable] + arguments).joined(separator: " ")
            return "Command failed (\(exitCode)): \(joined)\n\(stderr)"
        }
    }
}

protocol ProcessRunnerProtocol: Sendable {
    func run(executable: String, arguments: [String], currentDirectory: String?) async throws -> ProcessResult
}

struct ProcessRunner: ProcessRunnerProtocol, Sendable {
    func run(executable: String, arguments: [String], currentDirectory: String? = nil) async throws -> ProcessResult {
        guard FileManager.default.fileExists(atPath: executable) else {
            throw ProcessRunnerError.executableNotFound(executable)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.terminationHandler = { process in
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(decoding: stdoutData, as: UTF8.self)
                    .trimmingCharacters(in: .newlines)
                let stderr = String(decoding: stderrData, as: UTF8.self)
                    .trimmingCharacters(in: .newlines)

                continuation.resume(returning: ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
