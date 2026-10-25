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

    static func consumeReset(creditID: String?, idempotencyKey: String) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try consumeResetSync(creditID: creditID, idempotencyKey: idempotencyKey)
        }.value
    }

    private static func readRateLimits() throws -> RateLimitsResponse {
        let candidates = CodexPathResolver.candidatePaths()
        guard let codexPath = CodexPathResolver.firstExecutablePath(in: candidates) else {
            throw FetchError.codexNotFound(candidates)
        }

        let responseBox = ResponseBox()
        try exchangeWithAppServer(
            codexPath: codexPath,
            request: try rateLimitsRequest(),
            responseBox: responseBox
        )
        switch responseBox.rateLimitsResult() {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case .none:
            throw FetchError.missingRateLimitResponse
        }
    }

    private static func consumeResetSync(creditID: String?, idempotencyKey: String) throws -> String {
        guard !idempotencyKey.isEmpty else { throw FetchError.invalidOutput }
        let candidates = CodexPathResolver.candidatePaths()
        guard let codexPath = CodexPathResolver.firstExecutablePath(in: candidates) else {
            throw FetchError.codexNotFound(candidates)
        }

        let responseBox = ResponseBox(kind: .resetConsume)
        try exchangeWithAppServer(
            codexPath: codexPath,
            request: try resetConsumeRequest(creditID: creditID, idempotencyKey: idempotencyKey),
            responseBox: responseBox
        )
        switch responseBox.resetConsumeResult() {
        case .success(let response):
            return response.outcome
        case .failure(let error):
            throw error
        case .none:
            throw FetchError.missingRateLimitResponse
        }
    }

    private static func exchangeWithAppServer(codexPath: String, request: String, responseBox: ResponseBox) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexPath)
        process.arguments = ["app-server", "--listen", "stdio://"]

        let standardInput = Pipe()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = standardError

        let diagnostics = ProcessDiagnosticCapture()
        let completion = ProcessCompletion()
        let standardOutputEOF = PipeEndOfFile()
        let standardErrorEOF = PipeEndOfFile()
        process.terminationHandler = { terminatedProcess in
            responseBox.markTerminated(terminatedProcess.terminationStatus)
            completion.markFinished()
        }

        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                standardOutputEOF.markReached()
            } else {
                responseBox.append(data)
            }
        }
        standardError.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                standardErrorEOF.markReached()
            } else {
                diagnostics.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            closePipes(
                standardInput: standardInput,
                standardOutput: standardOutput,
                standardError: standardError
            )
            throw FetchError.appServerLaunchFailed
        }

        let requestLines = [try initializeRequest(), #"{"method":"initialized"}"#, request].joined(separator: "\n") + "\n"

        if process.isRunning {
            do {
                try standardInput.fileHandleForWriting.write(contentsOf: Data(requestLines.utf8))
            } catch {
                finishProcess(
                    process,
                    completion: completion,
                    standardOutputEOF: standardOutputEOF,
                    standardErrorEOF: standardErrorEOF,
                    standardInput: standardInput,
                    standardOutput: standardOutput,
                    standardError: standardError
                )
                throw FetchError.appServerCommunicationFailed
            }
        }

        let timedOut = responseBox.wait(timeout: .now() + AppConfig.appServerTimeout) == .timedOut
        finishProcess(
            process,
            completion: completion,
            standardOutputEOF: standardOutputEOF,
            standardErrorEOF: standardErrorEOF,
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError
        )

        if timedOut {
            throw FetchError.timeout
        }

        if case .failure(let error)? = responseBox.payloadResult() {
            if case .appServerExited(let status, _) = error as? FetchError {
                throw FetchError.appServerExited(status, diagnostics.safeDescription())
            }
            throw error
        }
    }

    private static func initializeRequest() throws -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let value: [String: Any] = [
            "method": "initialize",
            "id": 1,
            "params": [
                "clientInfo": ["name": "codex_usage_status_menubar", "title": "Codex Usage Status", "version": version],
                "capabilities": ["experimentalApi": true]
            ]
        ]
        return try jsonLine(value)
    }

    private static func rateLimitsRequest() throws -> String {
        try jsonLine(["method": "account/rateLimits/read", "id": 2])
    }

    private static func resetConsumeRequest(creditID: String?, idempotencyKey: String) throws -> String {
        var params: [String: String] = ["idempotencyKey": idempotencyKey]
        if let creditID, !creditID.isEmpty { params["creditId"] = creditID }
        return try jsonLine(["method": "account/rateLimitResetCredit/consume", "id": 2, "params": params])
    }

    private static func jsonLine(_ value: [String: Any]) throws -> String {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard let line = String(data: data, encoding: .utf8) else { throw FetchError.invalidOutput }
            return line
        } catch {
            throw FetchError.invalidOutput
        }
    }

    private static func finishProcess(
        _ process: Process,
        completion: ProcessCompletion,
        standardOutputEOF: PipeEndOfFile,
        standardErrorEOF: PipeEndOfFile,
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe
    ) {
        standardInput.fileHandleForWriting.closeFile()
        terminateProcess(process, completion: completion)

        // Process termination closes its pipe writers. Drain final bytes and wait for EOF,
        // but keep cleanup bounded if a descendant inherited either descriptor.
        _ = standardOutputEOF.wait(timeout: .now() + .milliseconds(250))
        _ = standardErrorEOF.wait(timeout: .now() + .milliseconds(250))

        standardOutput.fileHandleForReading.readabilityHandler = nil
        standardError.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil

        closePipes(
            standardInput: standardInput,
            standardOutput: standardOutput,
            standardError: standardError
        )
    }

    private static func closePipes(
        standardInput: Pipe,
        standardOutput: Pipe,
        standardError: Pipe
    ) {
        standardInput.fileHandleForWriting.closeFile()
        standardOutput.fileHandleForReading.closeFile()
        standardError.fileHandleForReading.closeFile()
    }

    private static func terminateProcess(_ process: Process, completion: ProcessCompletion) {
        guard process.isRunning else {
            return
        }

        process.terminate()
        if completion.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
            _ = completion.wait(timeout: .now() + 1)
        }
    }
}

enum ResponsePayloadKind: Sendable {
    case rateLimits
    case resetConsume
}

enum AppServerResponsePayload: Sendable {
    case rateLimits(RateLimitsResponse)
    case resetConsume(ResetCreditConsumeResponse)
}

struct ResetCreditConsumeResponse: Decodable, Sendable {
    let outcome: String
}

final class ResponseBox: @unchecked Sendable {
    static let maximumLineBytes = 1_048_576

    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var lineBuffer = Data()
    private let kind: ResponsePayloadKind
    private var storedResult: Result<AppServerResponsePayload, Error>?
    private var terminationStatus: Int32?

    init(kind: ResponsePayloadKind = .rateLimits) {
        self.kind = kind
    }

    var bufferedByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return lineBuffer.count
    }

    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard storedResult == nil else {
            return
        }

        for byte in data {
            if byte == 0x0A {
                if lineBuffer.last == 0x0D {
                    lineBuffer.removeLast()
                }
                let line = lineBuffer
                lineBuffer.removeAll(keepingCapacity: true)

                do {
                    if let response = try Self.parseLine(line, kind: kind) {
                        storedResult = .success(response)
                        semaphore.signal()
                        return
                    }
                } catch {
                    storedResult = .failure(error)
                    semaphore.signal()
                    return
                }
                continue
            }

            guard lineBuffer.count < Self.maximumLineBytes else {
                storedResult = .failure(FetchError.invalidOutput)
                semaphore.signal()
                return
            }
            lineBuffer.append(byte)
        }
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }

    func result() -> Result<RateLimitsResponse, Error>? {
        mapResult { payload in
            guard case .rateLimits(let response) = payload else { throw FetchError.invalidOutput }
            return response
        }
    }

    func rateLimitsResult() -> Result<RateLimitsResponse, Error>? { result() }

    func resetConsumeResult() -> Result<ResetCreditConsumeResponse, Error>? {
        mapResult { payload in
            guard case .resetConsume(let response) = payload else { throw FetchError.invalidOutput }
            return response
        }
    }

    func payloadResult() -> Result<AppServerResponsePayload, Error>? {
        lock.lock()
        defer { lock.unlock() }
        if let storedResult {
            return storedResult
        }
        if let terminationStatus {
            return .failure(FetchError.appServerExited(Int(terminationStatus), nil))
        }
        return nil
    }

    private func mapResult<Value>(_ transform: (AppServerResponsePayload) throws -> Value) -> Result<Value, Error>? {
        guard let result = payloadResult() else { return nil }
        switch result {
        case .success(let payload):
            do { return .success(try transform(payload)) }
            catch { return .failure(error) }
        case .failure(let error):
            return .failure(error)
        }
    }

    func markTerminated(_ status: Int32) {
        lock.lock()
        defer { lock.unlock() }

        terminationStatus = status
        semaphore.signal()
    }

    private static func parseLine(_ line: Data, kind: ResponsePayloadKind) throws -> AppServerResponsePayload? {
        guard let decodedLine = String(data: line, encoding: .utf8) else {
            throw FetchError.invalidOutput
        }
        let trimmedLine = decodedLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else {
            return nil
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(
                with: Data(trimmedLine.utf8),
                options: [.fragmentsAllowed]
            )
        } catch {
            throw FetchError.invalidOutput
        }

        guard let envelope = object as? [String: Any] else {
            return nil
        }
        guard stringID(envelope["id"]) == "2" else {
            return nil
        }

        if let errorObject = envelope["error"] as? [String: Any] {
            throw FetchError.appServerError(safeServerErrorDescription(errorObject))
        }

        // Restrict the value to a JSON object before passing it to JSONSerialization.
        // Null and scalar results are controlled protocol errors, not Foundation exceptions.
        guard let result = envelope["result"] as? [String: Any] else {
            throw FetchError.invalidOutput
        }

        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            switch kind {
            case .rateLimits:
                return .rateLimits(try JSONDecoder().decode(RateLimitsResponse.self, from: resultData))
            case .resetConsume:
                return .resetConsume(try JSONDecoder().decode(ResetCreditConsumeResponse.self, from: resultData))
            }
        } catch {
            throw FetchError.invalidOutput
        }
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

final class ProcessDiagnosticCapture: @unchecked Sendable {
    private enum Category {
        case authentication
        case initialization
    }

    private static let patterns: [(category: Category, text: String)] = [
        (.authentication, "not signed"),
        (.authentication, "sign in"),
        (.authentication, "unauthorized"),
        (.authentication, "authentication"),
        (.initialization, "permission"),
        (.initialization, "operation not permitted"),
        (.initialization, "could not initialize"),
        (.initialization, "failed to initialize")
    ]

    static let maximumRetainedBytes = max(
        0,
        (patterns.map { $0.text.utf8.count }.max() ?? 1) - 1
    )

    private let lock = NSLock()
    private var overlap: [UInt8] = []
    private var foundAuthentication = false
    private var foundInitialization = false

    var retainedByteCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return overlap.count
    }

    func append(_ data: Data) {
        guard !data.isEmpty else {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        var searchable = overlap
        searchable.reserveCapacity(overlap.count + data.count)
        searchable.append(contentsOf: data)
        let searchableText = String(decoding: searchable, as: UTF8.self).lowercased()

        for pattern in Self.patterns where searchableText.contains(pattern.text) {
            switch pattern.category {
            case .authentication:
                foundAuthentication = true
            case .initialization:
                foundInitialization = true
            }
        }

        overlap = Array(searchable.suffix(Self.maximumRetainedBytes))
    }

    func safeDescription() -> String? {
        lock.lock()
        defer { lock.unlock() }

        if foundAuthentication {
            return "Codex is not signed in. Open Codex and sign in, then refresh."
        }
        if foundInitialization {
            return "Codex could not initialize its local runtime. Open Codex once, then refresh."
        }
        return nil
    }

}

private final class ProcessCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var finished = false

    func markFinished() {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }
}

private final class PipeEndOfFile: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var reached = false

    func markReached() {
        lock.lock()
        guard !reached else {
            lock.unlock()
            return
        }
        reached = true
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: DispatchTime) -> DispatchTimeoutResult {
        semaphore.wait(timeout: timeout)
    }
}

enum FetchError: LocalizedError {
    case codexNotFound([String])
    case appServerLaunchFailed
    case appServerCommunicationFailed
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
        case .appServerCommunicationFailed:
            return "Codex app-server communication failed. Open Codex and try again."
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
