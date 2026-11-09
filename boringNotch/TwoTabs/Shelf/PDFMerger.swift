//
//  PDFMerger.swift
//  TwoTabs Notch - Smart Shelf
//
//  Merges PDF files into one document (PDFKit). No app dependencies.
//

import Foundation
import PDFKit

enum PDFMerger {
    struct Merged {
        let data: Data
        let pageCount: Int
        let documentCount: Int
    }

    enum MergeError: LocalizedError {
        case needTwo
        case unreadable(String)
        case locked(String)
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .needTwo: return "Select at least two PDFs to merge."
            case .unreadable(let name): return "\"\(name)\" could not be read as a PDF."
            case .locked(let name): return "\"\(name)\" is password protected."
            case .writeFailed: return "The merged PDF could not be written."
            }
        }
    }

    /// Pages are appended in the order of `urls`.
    static func merge(urls: [URL]) throws -> Merged {
        guard urls.count >= 2 else { throw MergeError.needTwo }
        let output = PDFDocument()
        for url in urls {
            guard let doc = PDFDocument(url: url), doc.pageCount > 0 else {
                throw MergeError.unreadable(url.lastPathComponent)
            }
            if doc.isLocked { throw MergeError.locked(url.lastPathComponent) }
            for index in 0..<doc.pageCount {
                guard let page = doc.page(at: index) else { continue }
                let copy = (page.copy() as? PDFPage) ?? page
                output.insert(copy, at: output.pageCount)
            }
        }
        guard output.pageCount > 0, let data = output.dataRepresentation() else { throw MergeError.writeFailed }
        return Merged(data: data, pageCount: output.pageCount, documentCount: urls.count)
    }
}
