import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FETCHER LIFECYCLE FAIL: \(message)\n", stderr)
        exit(1)
    }
}

func isInvalidOutput(_ result: Result<RateLimitsResponse, Error>?) -> Bool {
    guard case .failure(let error) = result, let fetchError = error as? FetchError else {
        return false
    }
    if case .invalidOutput = fetchError {
        return true
    }
    return false
}

let terminated = ResponseBox()
terminated.markTerminated(7)
_ = terminated.wait(timeout: .now() + 1)
if case .failure(let error) = terminated.result(), let fetchError = error as? FetchError {
    if case .appServerExited(let status, _) = fetchError {
        expect(status == 7, "early process exit status was not preserved")
    } else {
        expect(false, "early process exit was classified incorrectly")
    }
} else {
    expect(false, "early process exit did not wake the response wait")
}

let authError = ResponseBox()
authError.append(Data((#"{"id":2,"error":{"message":"user is not signed in"}}"# + "\n").utf8))
_ = authError.wait(timeout: .now() + 1)
if case .failure(let error) = authError.result(), let fetchError = error as? FetchError {
    expect(fetchError.localizedDescription.contains("not signed in"), "authentication error was not actionable")
} else {
    expect(false, "authentication error did not propagate")
}

let resetConsumed = ResponseBox(kind: .resetConsume)
resetConsumed.append(Data((#"{"id":2,"result":{"outcome":"reset"}}"# + "\n").utf8))
_ = resetConsumed.wait(timeout: .now() + 1)
if case .success(let outcome) = resetConsumed.resetConsumeResult() {
    expect(outcome.outcome == "reset", "earned reset response outcome was not decoded")
} else {
    expect(false, "earned reset response did not propagate")
}

let resetNoCredit = ResponseBox(kind: .resetConsume)
resetNoCredit.append(Data((#"{"id":2,"result":{"outcome":"noCredit"}}"# + "\n").utf8))
_ = resetNoCredit.wait(timeout: .now() + 1)
if case .success(let outcome) = resetNoCredit.resetConsumeResult() {
    expect(outcome.outcome == "noCredit", "no-credit response outcome was not preserved")
} else {
    expect(false, "no-credit response did not propagate")
}

let sensitiveError = ResponseBox()
sensitiveError.append(Data((#"{"id":2,"error":{"message":"Bearer sk-secret-token"}}"# + "\n").utf8))
_ = sensitiveError.wait(timeout: .now() + 1)
if case .failure(let error) = sensitiveError.result() {
    expect(!error.localizedDescription.contains("sk-secret-token"), "server error leaked sensitive text")
} else {
    expect(false, "generic server error did not propagate")
}

for resultJSON in ["null", "42"] {
    let malformed = ResponseBox()
    malformed.append(Data((#"{"id":2,"result":\#(resultJSON)}"# + "\n").utf8))
    _ = malformed.wait(timeout: .now() + 1)
    expect(isInvalidOutput(malformed.result()), "result \(resultJSON) was not rejected as controlled invalid output")
}

let unicodeResponse = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","planType":"模型"}}}"# + "\n"
let unicodeBytes = Array(unicodeResponse.utf8)
for split in 0...unicodeBytes.count {
    let fragmented = ResponseBox()
    fragmented.append(Data(unicodeBytes[..<split]))
    fragmented.append(Data(unicodeBytes[split...]))
    expect(fragmented.result() != nil, "Unicode response split at byte \(split) was dropped")
}

let oversized = ResponseBox()
oversized.append(Data(repeating: 0x78, count: ResponseBox.maximumLineBytes + 4096))
expect(oversized.bufferedByteCount <= ResponseBox.maximumLineBytes, "stdout line buffer exceeded its bound")
expect(isInvalidOutput(oversized.result()), "oversized stdout line did not produce controlled invalid output")

let diagnostics = ProcessDiagnosticCapture()
diagnostics.append(Data(repeating: 0x78, count: 2 * 1024 * 1024))
expect(diagnostics.retainedByteCount <= ProcessDiagnosticCapture.maximumRetainedBytes, "stderr diagnostic buffer exceeded its bound")
expect(diagnostics.safeDescription() == nil, "unclassified stderr text produced a diagnostic")

let splitDiagnostic = ProcessDiagnosticCapture()
splitDiagnostic.append(Data("not sign".utf8))
splitDiagnostic.append(Data("ed in; token=SYNTHETIC_SECRET_SENTINEL".utf8))
expect(splitDiagnostic.safeDescription()?.contains("not signed in") == true, "split authentication category was not recognized")
expect(splitDiagnostic.safeDescription()?.contains("SYNTHETIC_SECRET_SENTINEL") == false, "raw stderr leaked into the diagnostic")

print("FETCHER LIFECYCLE PASS")
