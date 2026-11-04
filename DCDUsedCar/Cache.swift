import Foundation
import CryptoKit
import ImageIO
import UIKit

/// Tiny file cache for API JSON (list pages, brand list, series lists, details).
enum DiskCache {
    static let dir: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("api", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    static func file(_ key: String) -> URL {
        let h = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return dir.appendingPathComponent(h)
    }
    static func get(_ key: String, maxAge: TimeInterval) -> Data? {
        let f = file(key)
        guard let a = try? FileManager.default.attributesOfItem(atPath: f.path),
              let m = a[.modificationDate] as? Date, Date().timeIntervalSince(m) < maxAge else { return nil }
        return try? Data(contentsOf: f)
    }
    static func put(_ key: String, _ data: Data) { try? data.write(to: file(key), options: .atomic) }
}

/// De-duplicates and caches detail fetches so a press-down prefetch is reused by the detail page.
actor DetailCache {
    static let shared = DetailCache()
    private var tasks: [Int64: Task<CarDetail, Error>] = [:]
    func get(_ sku: Int64, city: String) async throws -> CarDetail {
        if let t = tasks[sku] {
            do { return try await t.value } catch { tasks[sku] = nil }
        }
        let t = Task { try await API.detail(sku: sku, city: city) }
        tasks[sku] = t
        do { return try await t.value } catch { tasks[sku] = nil; throw error }
    }
    nonisolated func prefetch(_ sku: Int64, city: String) {
        Task { _ = try? await get(sku, city: city) }
    }
}

/// Image loading: shared session with a 300 MB URLCache on disk, ImageIO downsampling to the
/// displayed pixel size off the main thread, NSCache in memory, in-flight de-duplication.
final class ImageLoader: @unchecked Sendable {
    static let shared = ImageLoader()
    private let mem = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()
    init() {
        mem.totalCostLimit = 80 << 20
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 300 << 20, diskPath: "img")
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.httpAdditionalHeaders = ["Referer": "https://www.dongchedi.com/"]
        session = URLSession(configuration: cfg)
    }
    static func key(_ url: String, _ px: Int) -> NSString { "\(px)|\(url)" as NSString }
    func cached(_ url: String, px: Int) -> UIImage? { mem.object(forKey: Self.key(url, px)) }

    func load(_ url: String, px: Int) async -> UIImage? {
        if let i = cached(url, px: px) { return i }
        let k = Self.key(url, px) as String
        lock.lock()
        if let t = inflight[k] { lock.unlock(); return await t.value }
        let t = Task.detached(priority: .userInitiated) { [session] () -> UIImage? in
            guard let u = URL(string: url), let (data, _) = try? await session.data(from: u) else { return nil }
            return Self.downsample(data, maxPixel: px)
        }
        inflight[k] = t
        lock.unlock()
        let img = await t.value
        lock.lock(); inflight[k] = nil; lock.unlock()
        if let img { mem.setObject(img, forKey: Self.key(url, px), cost: Int(img.size.width * img.size.height * img.scale * img.scale * 4)) }
        return img
    }

    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,      // decode now, on this background thread
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}
