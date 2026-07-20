import Foundation
import PDFKit

/// Enforces the permissions embedded in an encrypted PDF before deriving or
/// mutating content. Unencrypted documents report every permission as allowed.
enum PDFPermissionPolicy {
    enum Requirement {
        case copyContent
        case changeDocument
        case assembleDocument
    }

    static func require(
        _ requirements: Requirement...,
        for document: PDFDocument
    ) throws {
        if document.isLocked { throw PDFwringerError.documentIsLocked }

        for requirement in requirements {
            let allowed = switch requirement {
            case .copyContent: document.allowsCopying
            case .changeDocument: document.allowsDocumentChanges
            case .assembleDocument: document.allowsDocumentAssembly
            }
            guard allowed else {
                throw PDFwringerError.documentPermissionsDenied
            }
        }
    }
}
