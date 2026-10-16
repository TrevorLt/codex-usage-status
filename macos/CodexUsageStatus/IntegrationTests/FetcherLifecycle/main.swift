import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FETCHER LIFECYCLE FAIL: \(message)\n", stderr)
        exit(1)
    }
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

let sensitiveError = ResponseBox()
sensitiveError.append(Data((#"{"id":2,"error":{"message":"Bearer sk-secret-token"}}"# + "\n").utf8))
_ = sensitiveError.wait(timeout: .now() + 1)
if case .failure(let error) = sensitiveError.result() {
    expect(!error.localizedDescription.contains("sk-secret-token"), "server error leaked sensitive text")
} else {
    expect(false, "generic server error did not propagate")
}

print("FETCHER LIFECYCLE PASS")
