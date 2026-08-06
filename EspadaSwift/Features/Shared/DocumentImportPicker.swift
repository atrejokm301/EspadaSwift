import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Native document picker with unlimited multi-select and optional folders.
/// Filters e-Sword extensions after pick so any directory is allowed.
struct DocumentImportPicker: UIViewControllerRepresentable {
    var onPick: ([URL]) -> Void
    var onCancel: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Broad types so user can open any folder / Files location
        let types: [UTType] = [
            .item,
            .folder,
            .data,
            .content,
            UTType(filenameExtension: "bbli") ?? .data,
            UTType(filenameExtension: "cmti") ?? .data,
            UTType(filenameExtension: "dcti") ?? .data,
            UTType(filenameExtension: "lexi") ?? .data,
            UTType(filenameExtension: "refi") ?? .data,
            UTType(filenameExtension: "bblx") ?? .data,
            UTType(filenameExtension: "cmtx") ?? .data,
            UTType(filenameExtension: "dctx") ?? .data,
            UTType(filenameExtension: "lexx") ?? .data,
        ]
        // asCopy: false streams from source (lower peak RAM than copying into Inbox first).
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        let onCancel: (() -> Void)?

        init(onPick: @escaping ([URL]) -> Void, onCancel: (() -> Void)?) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel?()
        }
    }
}

enum ESwordImportFilter {
    static let allowedExtensions: Set<String> = [
        "bbli", "bblx", "bbl",
        "cmti", "cmtx", "cmt",
        "dcti", "dctx", "dct",
        "lexi", "lexx", "lex",
        "refi", "refx", "ref",
    ]

    /// Expand folders recursively and keep only e-Sword module files.
    static func expandToModuleFiles(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        let fm = FileManager.default

        func addFile(_ url: URL) {
            let ext = url.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return }
            let key = url.lastPathComponent.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            out.append(url)
        }

        func walk(_ url: URL) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                // Still try as file (security-scoped may resolve later)
                addFile(url)
                return
            }
            if isDir.boolValue {
                if let enumerator = fm.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for case let fileURL as URL in enumerator {
                        addFile(fileURL)
                    }
                }
            } else {
                addFile(url)
            }
        }

        for url in urls {
            walk(url)
        }
        return out
    }
}
