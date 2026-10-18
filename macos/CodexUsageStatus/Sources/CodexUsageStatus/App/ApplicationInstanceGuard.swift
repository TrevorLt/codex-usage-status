import Darwin
import Foundation

@_silgen_name("flock")
private func codexUsageStatusFlock(_ fileDescriptor: Int32, _ operation: Int32) -> Int32

enum ApplicationInstanceGuardError: LocalizedError {
    case createDirectory(String, Int32)
    case openLockFile(String, Int32)
    case secureLockFile(String, Int32)
    case inspectLockFile(String, Int32)
    case unexpectedLockFile(String)
    case acquireLock(String, Int32)

    var errorDescription: String? {
        switch self {
        case let .createDirectory(path, code):
            return "Could not create the per-user application support directory at \(path): \(String(cString: strerror(code)))"
        case let .openLockFile(path, code):
            return "Could not open the per-user application lock at \(path): \(String(cString: strerror(code)))"
        case let .secureLockFile(path, code):
            return "Could not secure the per-user application lock at \(path): \(String(cString: strerror(code)))"
        case let .inspectLockFile(path, code):
            return "Could not inspect the per-user application lock at \(path): \(String(cString: strerror(code)))"
        case let .unexpectedLockFile(path):
            return "The per-user application lock is not a regular file owned by this user: \(path)"
        case let .acquireLock(path, code):
            return "Could not acquire the per-user application lock at \(path): \(String(cString: strerror(code)))"
        }
    }
}

/// Holds an advisory per-user lock for as long as the menu-bar app is running.
/// The stable location is independent of the app bundle path, so launching a
/// migrated copy and launching the legacy bundle contend on the same lock.
final class ApplicationInstanceGuard {
    private let fileDescriptor: Int32

    private init(fileDescriptor: Int32) {
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        _ = codexUsageStatusFlock(fileDescriptor, LOCK_UN)
        _ = Darwin.close(fileDescriptor)
    }

    /// Returns nil when another instance already owns this user's lock.
    static func acquireForCurrentUser() throws -> ApplicationInstanceGuard? {
        let supportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Codex Usage Status", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: supportDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw ApplicationInstanceGuardError.createDirectory(supportDirectory.path, errno)
        }

        return try acquire(lockFileURL: supportDirectory.appendingPathComponent("instance.lock"))
    }

    /// The URL-taking form keeps lock contention testable without using the
    /// user's Library directory.
    static func acquire(lockFileURL: URL) throws -> ApplicationInstanceGuard? {
        let lockPath = lockFileURL.path
        let flags = O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW
        let descriptor = lockPath.withCString { open($0, flags, mode_t(S_IRUSR | S_IWUSR)) }
        guard descriptor >= 0 else {
            throw ApplicationInstanceGuardError.openLockFile(lockPath, errno)
        }

        guard fchmod(descriptor, mode_t(S_IRUSR | S_IWUSR)) == 0 else {
            let code = errno
            _ = close(descriptor)
            throw ApplicationInstanceGuardError.secureLockFile(lockPath, code)
        }

        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0 else {
            let code = errno
            _ = close(descriptor)
            throw ApplicationInstanceGuardError.inspectLockFile(lockPath, code)
        }
        guard (fileInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), fileInfo.st_uid == getuid() else {
            _ = close(descriptor)
            throw ApplicationInstanceGuardError.unexpectedLockFile(lockPath)
        }

        guard codexUsageStatusFlock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = close(descriptor)
            if code == EWOULDBLOCK || code == EAGAIN {
                return nil
            }
            throw ApplicationInstanceGuardError.acquireLock(lockPath, code)
        }

        return ApplicationInstanceGuard(fileDescriptor: descriptor)
    }
}
