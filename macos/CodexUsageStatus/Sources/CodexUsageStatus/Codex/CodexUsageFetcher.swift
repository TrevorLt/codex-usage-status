import Darwin
import Foundation

enum CodexUsageFetcher {
    static func fetch() async throws -> UsageSummary {
        try await Task.detached(priority: .utility) {
            try fetchSync()
        }.value
    }

    static func fetchSync() throws -> UsageSummary {
        let response = try readRateLimits()
        return try UsageSummary(response: response)
    }

    private static func readRateLimits() throws -> RateLimitsResponse {
        let candidates = CodexPathResolver.candidatePaths()
        guard let codexPath = CodexPathResolver.firstExecutablePath(in: candidates) else {
            throw FetchError.codexNotFound(candidates)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()

        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let responseBox = ResponseBox()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { process in
            responseBox.markTerminated(process.terminationStatus)
            finished.signal()
        }

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            responseBox.append(handle.availableData)
        }

        do {
            try process.run()
        } catch {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            throw FetchError.appServerLaunchFailed
        }

        let requestLines = [
            #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"codex_usage_status_menubar","title":"Codex Usage Status","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#,
            #"{"method":"initialized"}"#,
            #"{"method":"account/rateLimits/read","id":2}"#
        ].joined(separator: "\n") + "\n"

        standardInput.fileHandleForWriting.write(Data(requestLines.utf8))

        if responseBox.wait(timeout: .now() + AppConfig.appServerTimeout) == .timedOut {
            standardOutput.fileHandleForReading.readabilityHandler = nil
            standardInput.fileHandleForWriting.closeFile()
            terminateProcess(process, finished: finished)
            throw FetchError.timeout
        }

        standardOutput.fileHandleForReading.readabilityHandler = nil
        if !process.isRunning {
            responseBox.append(standardOutput.fileHandleForReading.readDataToEndOfFile())
        }
        standardInput.fileHandleForWriting.closeFile()
        terminateProcess(process, finished: finished)
        let standardErrorData = standardError.fileHandleForReading.readDataToEndOfFile()

        switch responseBox.result() {
        case .success(let response):
            return response
        case .failure(let error):
            if case .appServerExited(let status, _) = error as? FetchError {
                throw FetchError.appServerExited(status, safeProcessErrorDescription(standardErrorData))
            }
            throw error
        case .none:
            throw FetchError.missingRateLimitResponse
        }
    }

    private static func terminateProcess(_ process: Process, finished: DispatchSemaphore) {
        guard process.isRunning else {
            return
        }
        process.terminate()
        if finished.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = finished.wait(timeout: .now() + 1)
        }
    }

    private static func safeProcessErrorDescription(_ data: Data) -> String? {
        guard let message = String(data: data, encoding: .utf8), !message.isEmpty else {
            return nil
        }

        let normalized = message.lowercased()
        if normalized.contains("not signed") || normalized.contains("sign in") ||
            normalized.contains("unauthorized") || normalized.contains("authentication") {
            return "Codex is not signed in. Open Codex and sign in, then refresh."
        }

        if normalized.contains("permission") || normalized.contains("operation not permitted") ||
            normalized.contains("could not initialize") || normalized.contains("failed to initialize") {
            return "Codex could not initialize its local runtime. Open Codex once, then refresh."
        }

        return nil
    }
}

final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var buffer = ""
    private var storedResult: Result<RateLimitsResponse, Error>?
    private var terminationStatus: Int32?

    func append(_ data: Data) {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        if storedResult != nil {
            return
        }

        buffer.append(text)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline])
            buffer.removeSubrange(...newline)

            do {
                if let response = try Self.parseRateLimitsLine(line) {
                    storedResult = .success(response)
                    semaphore.signal()
                    return
                }
            } catch {
                storedResult = .failure(error)
                semaphore.signal()
                return
            }
        }
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }

    func result() -> Result<RateLimitsResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        if let storedResult {
            return storedResult
        }
        if let terminationStatus {
            return .failure(FetchError.appServerExited(Int(terminationStatus), nil))
        }
        return storedResult
    }

    func markTerminated(_ status: Int32) {
        lock.lock()
        defer { lock.unlock() }

        terminationStatus = status
        semaphore.signal()
    }

    private static func parseRateLimitsLine(_ line: String) throws -> RateLimitsResponse? {
        guard let lineData = line.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }

        guard stringID(object["id"]) == "2" else {
            return nil
        }

        if let errorObject = object["error"] as? [String: Any] {
            throw FetchError.appServerError(safeServerErrorDescription(errorObject))
        }

        guard let result = object["result"] else {
            throw FetchError.invalidOutput
        }

        let resultData = try JSONSerialization.data(withJSONObject: result)
        return try JSONDecoder().decode(RateLimitsResponse.self, from: resultData)
    }

    private static func safeServerErrorDescription(_ errorObject: [String: Any]) -> String? {
        guard let message = errorObject["message"] as? String else {
            return nil
        }

        let normalized = message.lowercased()
        if normalized.contains("login") || normalized.contains("sign in") ||
            normalized.contains("signed in") || normalized.contains("unauthorized") ||
            normalized.contains("authentication") {
            return "Codex is not signed in. Open Codex and sign in, then refresh."
        }

        if normalized.contains("method") && (normalized.contains("not found") || normalized.contains("unknown")) {
            return "This Codex version does not support the usage API yet. Update Codex and try again."
        }

        return nil
    }

    private static func stringID(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

enum FetchError: LocalizedError {
    case codexNotFound([String])
    case appServerLaunchFailed
    case timeout
    case appServerExited(Int, String?)
    case appServerError(String?)
    case invalidOutput
    case missingRateLimitResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound(let candidates):
            let checkedPaths = candidates.isEmpty ? "no known locations" : candidates.joined(separator: ", ")
            return "Codex app-server executable was not found. Checked: \(checkedPaths). Open Codex once or set CODEX_BIN for a custom install."
        case .appServerLaunchFailed:
            return "Codex app-server could not be launched. Check the Codex installation and try again."
        case .timeout:
            return "Codex app-server did not respond within 20 seconds. Open Codex and check that it is signed in and online."
        case .appServerExited(let status, let detail):
            return detail ?? "Codex app-server exited before returning usage data (status \(status)). Update or open Codex, then refresh."
        case .appServerError(let detail):
            return detail ?? "Codex app-server returned an error. Open Codex, confirm you are signed in, and refresh."
        case .invalidOutput:
            return "Codex app-server returned an unsupported usage response. Update Codex and try again."
        case .missingRateLimitResponse:
            return "Codex app-server did not return usage data. Confirm Codex is signed in and up to date."
        }
    }
}
