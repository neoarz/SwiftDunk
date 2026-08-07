import Darwin
package import Foundation

package enum SecureAtomicFileWriter {
    package static func write(_ data: Data, to destinationURL: URL) throws {
        let temporaryURL =
            destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp",
                isDirectory: false
            )
        // the temp file must share the destination filesystem for an atomic rename
        var descriptor = try openPrivateFile(at: temporaryURL)
        var shouldRemoveTemporaryFile = true

        defer {
            if descriptor >= 0 {
                Darwin.close(descriptor)
            }
            if shouldRemoveTemporaryFile {
                temporaryURL.path.withCString { path in
                    _ = Darwin.unlink(path)
                }
            }
        }

        try writeAll(data, to: descriptor, path: temporaryURL.path)
        // flush the contents before exposing the new name
        guard Darwin.fsync(descriptor) == 0 else {
            throw posixError(code: errno, path: temporaryURL.path)
        }

        let closeResult = Darwin.close(descriptor)
        let closeError = errno
        descriptor = -1
        guard closeResult == 0 else {
            throw posixError(code: closeError, path: temporaryURL.path)
        }

        let renameResult = temporaryURL.path.withCString { sourcePath in
            destinationURL.path.withCString { destinationPath in
                Darwin.rename(sourcePath, destinationPath)
            }
        }
        guard renameResult == 0 else {
            throw posixError(code: errno, path: destinationURL.path)
        }
        shouldRemoveTemporaryFile = false
    }

    private static func openPrivateFile(at url: URL) throws -> Int32 {
        let descriptor = url.path.withCString { path in
            Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                mode_t(S_IRUSR | S_IWUSR)
            )
        }
        guard descriptor >= 0 else {
            throw posixError(code: errno, path: url.path)
        }
        return descriptor
    }

    private static func writeAll(_ data: Data, to descriptor: Int32, path: String) throws {
        try data.withUnsafeBytes { buffer in
            var bytesRemaining = buffer.count
            var address = buffer.baseAddress

            while bytesRemaining > 0 {
                let written = Darwin.write(descriptor, address, bytesRemaining)
                if written < 0 {
                    let writeError = errno
                    if writeError == EINTR {
                        continue
                    }
                    throw posixError(code: writeError, path: path)
                }
                guard written > 0 else {
                    throw posixError(code: EIO, path: path)
                }
                bytesRemaining -= written
                address = address?.advanced(by: written)
            }
        }
    }

    private static func posixError(code: Int32, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}
