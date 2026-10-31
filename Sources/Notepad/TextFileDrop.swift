import AppKit
import Foundation

/// Shared validation for Finder drags, SwiftUI item providers, and window drops.
enum TextFileDrop {
    static func supportedURL(_ url: URL) -> URL? {
        guard url.isFileURL, url.pathExtension.lowercased() == "txt" else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return url.standardizedFileURL
    }

    static func urls(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return supportedURLs(objects)
    }

    static func supportedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        return urls.compactMap { url in
            guard let url = supportedURL(url), seen.insert(url).inserted else { return nil }
            return url
        }
    }

    static func fileURL(from item: Any?) -> URL? {
        if let url = item as? URL { return supportedURL(url) }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil) {
            return supportedURL(url)
        }
        if let string = item as? String, let url = URL(string: string) {
            return supportedURL(url)
        }
        return nil
    }
}
