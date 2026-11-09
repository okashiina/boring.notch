//
//  ClaudePetSocketServer.swift
//  TwoTabs Notch - Claude Code pet
//
//  Unix domain socket listener for the hook script. Sandbox safe: the socket lives inside the app container
//  (Data/tmp), which a sandboxed app may create files in and which the unsandboxed hook can connect to.
//  Structure follows Notchi's SocketServer (sk-ruban/notchi, GPL-3.0), simplified: one JSON message per
//  connection, no response channel. See NOTICE.md.
//

import Darwin
import Foundation

final class ClaudePetSocketServer: @unchecked Sendable {
    enum ServerError: Error, CustomStringConvertible {
        case pathTooLong(Int)
        case alreadyListening(String)
        case posix(String, Int32)

        var description: String {
            switch self {
            case .pathTooLong(let n): return "socket path is \(n) bytes, over the 103 byte limit"
            case .alreadyListening(let p): return "another process is already listening on \(p)"
            case .posix(let what, let code): return "\(what) failed: \(String(cString: strerror(code))) (\(code))"
            }
        }
    }

    static let socketFileName = "twotabs-claude-pet.sock"
    static let maxPathBytes = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    /// Container tmp when sandboxed, the same container path computed by hand otherwise (dev builds), so the
    /// hook script always looks in one place:  ~/Library/Containers/<bundle id>/Data/tmp/twotabs-claude-pet.sock
    static func defaultSocketPath(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.okashiina.twotabsnotch") -> String {
        let home = NSHomeDirectory()
        let dataDir = home.hasSuffix("/Data") ? home : "\(home)/Library/Containers/\(bundleIdentifier)/Data"
        return "\(dataDir)/tmp/\(socketFileName)"
    }

    let path: String
    private let clientReadTimeout: TimeInterval
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var onEvent: (@Sendable (ClaudePetEvent) -> Void)?
    private let serverQueue = DispatchQueue(label: "twotabs.claudepet.socket.server")
    private let clientQueue = DispatchQueue(label: "twotabs.claudepet.socket.client", attributes: .concurrent)

    init(path: String = ClaudePetSocketServer.defaultSocketPath(), clientReadTimeout: TimeInterval = 0.5) {
        self.path = path
        self.clientReadTimeout = clientReadTimeout
    }

    deinit { stop() }

    /// Binds and starts accepting. Throws if the socket cannot be set up (the app keeps running without the pet).
    func start(onEvent: @escaping @Sendable (ClaudePetEvent) -> Void) throws {
        try serverQueue.sync {
            guard listenFD < 0 else { return }
            guard path.utf8.count <= Self.maxPathBytes else { throw ServerError.pathTooLong(path.utf8.count) }

            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

            if FileManager.default.fileExists(atPath: path) {
                if Self.hasLiveListener(at: path) { throw ServerError.alreadyListening(path) }
                unlink(path) // stale file from a previous run
            }

            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw ServerError.posix("socket", errno) }

            var addr = Self.makeAddress(path)
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard bound == 0 else {
                let code = errno
                close(fd)
                throw ServerError.posix("bind", code)
            }
            chmod(path, 0o600)
            guard listen(fd, 16) == 0 else {
                let code = errno
                close(fd)
                unlink(path)
                throw ServerError.posix("listen", code)
            }
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

            self.listenFD = fd
            self.onEvent = onEvent
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: serverQueue)
            source.setEventHandler { [weak self] in self?.acceptPending() }
            source.resume()
            self.acceptSource = source
        }
    }

    func stop() {
        serverQueue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 {
                close(listenFD)
                listenFD = -1
                unlink(path)
            }
            onEvent = nil
        }
    }

    // MARK: Internals

    private func acceptPending() {
        while true {
            let client = accept(listenFD, nil, nil)
            if client < 0 { return } // EAGAIN: drained
            guard let handler = onEvent else { close(client); continue }
            clientQueue.async { [clientReadTimeout] in
                Self.serve(client: client, timeout: clientReadTimeout, handler: handler)
            }
        }
    }

    private static func serve(client: Int32, timeout: TimeInterval, handler: @Sendable (ClaudePetEvent) -> Void) {
        defer { close(client) }
        // accept() can hand back a non-blocking fd on BSD; make it blocking with a read timeout.
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while buffer.count < ClaudePetEvent.maxMessageBytes {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break } // EOF, timeout or error
            buffer.append(chunk, count: n)
            if ClaudePetEvent.isComplete(buffer) { break } // answer without waiting for the sender to close
        }
        if let event = ClaudePetEvent.decode(buffer) { handler(event) }
    }

    private static func makeAddress(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: maxPathBytes + 1) { dst in
                _ = path.withCString { strncpy(dst, $0, maxPathBytes) }
            }
        }
        return addr
    }

    private static func hasLiveListener(at path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = makeAddress(path)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        return result == 0
    }
}
