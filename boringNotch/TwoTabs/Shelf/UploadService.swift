//
//  UploadService.swift
//  TwoTabs Notch - Smart Shelf
//
//  Anonymous uploads to Litterbox (temporary) / Catbox (permanent).
//  API reference (checked 2026-11-09):
//    https://litterbox.catbox.moe/tools.php  reqtype=fileupload time=1h|12h|24h|72h fileToUpload=<file>
//    https://catbox.moe/tools.php            reqtype=fileupload [userhash] fileToUpload=<file>
//  Both answer with the file URL as plain text.
//  No app dependencies: the multipart body is built here and can be tested offline.
//

import Foundation
import UniformTypeIdentifiers

struct UploadTarget {
    let name: String
    let endpoint: URL
    /// Text fields sent before the file part (order preserved).
    let fields: [(name: String, value: String)]
    let fileFieldName: String
    let maxBytes: Int64
    /// Short human text such as "expires in 72h".
    let lifetimeNote: String

    static func litterbox(expiry: String) -> UploadTarget {
        UploadTarget(
            name: "Litterbox",
            endpoint: URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!,
            fields: [("reqtype", "fileupload"), ("time", expiry)],
            fileFieldName: "fileToUpload",
            maxBytes: 1_000_000_000, // 1 GB (decimal, like Finder shows sizes)
            lifetimeNote: "expires in \(expiry)")
    }

    static let catbox = UploadTarget(
        name: "Catbox",
        endpoint: URL(string: "https://catbox.moe/user/api.php")!,
        fields: [("reqtype", "fileupload")],
        fileFieldName: "fileToUpload",
        maxBytes: 200_000_000, // 200 MB (decimal, like Finder shows sizes)
        lifetimeNote: "permanent")

    /// Throws before any network traffic when the file is over the host's limit.
    func checkSize(_ bytes: Int64, fileName: String) throws {
        if bytes > maxBytes {
            throw UploadError.tooLarge(fileName: fileName, bytes: bytes, limit: maxBytes, host: name)
        }
        if bytes == 0 { throw UploadError.emptyFile(fileName) }
    }
}

enum UploadError: LocalizedError {
    case tooLarge(fileName: String, bytes: Int64, limit: Int64, host: String)
    case emptyFile(String)
    case unreadable(String)
    case badStatus(Int, String)
    case badResponse(String)
    case network(String)

    var errorDescription: String? {
        let fmt = { (b: Int64) in ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
        switch self {
        case .tooLarge(let name, let bytes, let limit, let host):
            return "\(name) is \(fmt(bytes)); \(host) accepts up to \(fmt(limit))."
        case .emptyFile(let name): return "\(name) is empty."
        case .unreadable(let name): return "\(name) could not be read."
        case .badStatus(let code, let body):
            return "Upload failed (HTTP \(code))" + (body.isEmpty ? "." : ": \(body)")
        case .badResponse(let body):
            return "Unexpected answer from the host" + (body.isEmpty ? "." : ": \(body)")
        case .network(let message): return "Network error: \(message)"
        }
    }
}

enum MultipartBuilder {
    static func makeBoundary() -> String { "TwoTabsNotch-\(UUID().uuidString)" }

    /// Escapes a file name for a Content-Disposition header.
    static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\"", with: "_")
        return cleaned.isEmpty ? "file" : cleaned
    }

    static func mimeType(for url: URL) -> String {
        UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType ?? "application/octet-stream"
    }

    /// Everything before the file bytes.
    static func preamble(boundary: String, fields: [(name: String, value: String)],
                         fileField: String, fileName: String, mimeType: String) -> Data {
        var text = ""
        for field in fields {
            text += "--\(boundary)\r\n"
            text += "Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n"
            text += "\(field.value)\r\n"
        }
        text += "--\(boundary)\r\n"
        text += "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(safeFileName(fileName))\"\r\n"
        text += "Content-Type: \(mimeType)\r\n\r\n"
        return Data(text.utf8)
    }

    static func epilogue(boundary: String) -> Data { Data("\r\n--\(boundary)--\r\n".utf8) }

    /// Streams preamble + file + epilogue into `bodyURL` without loading the file into memory.
    static func writeBody(to bodyURL: URL, boundary: String, target: UploadTarget, fileURL: URL) throws {
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil)
        let out = try FileHandle(forWritingTo: bodyURL)
        defer { try? out.close() }
        let name = fileURL.lastPathComponent
        try out.write(contentsOf: preamble(boundary: boundary, fields: target.fields,
                                           fileField: target.fileFieldName, fileName: name,
                                           mimeType: mimeType(for: fileURL)))
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }
        try out.write(contentsOf: epilogue(boundary: boundary))
    }
}

enum UploadService {

    private final class ProgressDelegate: NSObject, URLSessionTaskDelegate {
        let onProgress: @Sendable (Double) -> Void
        init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }
        func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                        totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
            guard totalBytesExpectedToSend > 0 else { return }
            onProgress(Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        }
    }

    /// Uploads one file and returns the public URL the host answered with.
    static func upload(fileURL: URL, target: UploadTarget,
                       onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let name = fileURL.lastPathComponent
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) }
        guard let size else { throw UploadError.unreadable(name) }
        try target.checkSize(size, fileName: name)

        let boundary = MultipartBuilder.makeBoundary()
        let bodyURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("upload-\(UUID().uuidString).body")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        do {
            try MultipartBuilder.writeBody(to: bodyURL, boundary: boundary, target: target, fileURL: fileURL)
        } catch {
            throw UploadError.unreadable(name)
        }

        var request = URLRequest(url: target.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("TwoTabsNotch/1.0", forHTTPHeaderField: "User-Agent")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 3600
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.upload(for: request, fromFile: bodyURL,
                                                        delegate: ProgressDelegate(onProgress: onProgress))
        } catch {
            throw UploadError.network(error.localizedDescription)
        }

        let body = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(body.prefix(200))
        guard let http = response as? HTTPURLResponse else { throw UploadError.badResponse(snippet) }
        guard (200..<300).contains(http.statusCode) else { throw UploadError.badStatus(http.statusCode, snippet) }
        return try parseLink(from: body)
    }

    /// Hosts answer with the bare URL on success and with an error sentence otherwise.
    static func parseLink(from body: String) throws -> URL {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http", url.host != nil, !trimmed.contains(" ") {
            return url
        }
        throw UploadError.badResponse(String(trimmed.prefix(200)))
    }
}
