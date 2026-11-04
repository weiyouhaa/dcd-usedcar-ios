import Foundation

/// 电池方案 knowledge for 蔚来系 listings, from two sources:
///  1. the daily index built by .github/workflows/battery-index.yml (all nationwide listings,
///     published on the `battery-index` branch), downloaded at most about once a day;
///  2. a per-sku on-device cache of live classifications (24 h TTL, persisted to disk).
/// A detail page is fetched live only for listings neither source knows about.
@MainActor final class BatteryStore: ObservableObject {
    static let shared = BatteryStore()
    static let ttl: TimeInterval = 24 * 3600
    static let indexMaxAge: TimeInterval = 3 * 86400
    static let indexURLs = [
        "https://raw.githubusercontent.com/weiyouhaa/dcd-usedcar-ios/battery-index/battery-index.json",
        "https://fastly.jsdelivr.net/gh/weiyouhaa/dcd-usedcar-ios@battery-index/battery-index.json",
        "https://cdn.jsdelivr.net/gh/weiyouhaa/dcd-usedcar-ios@battery-index/battery-index.json",
    ]

    struct Entry: Codable { let p: BatteryPlan; let t: TimeInterval }
    @Published private(set) var local: [Int64: Entry] = [:]
    @Published private(set) var index: [Int64: BatteryPlan] = [:]
    @Published private(set) var indexDate: Date?
    private(set) var indexBrands: Set<Int> = []
    let useIndex = !LaunchArgs.flag("noindex")

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("battery", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static var localFile: URL { dir.appendingPathComponent("local.json") }
    private static var indexFile: URL { dir.appendingPathComponent("index.json") }
    private let ud = UserDefaults.standard

    init() {
        ud.removeObject(forKey: "batteryPlans.v1")   // v2.6 store (no TTL)
        if LaunchArgs.flag("resetbattery") {
            try? FileManager.default.removeItem(at: Self.localFile)
            try? FileManager.default.removeItem(at: Self.indexFile)
            for k in ["battery.etag", "battery.lastCheck"] { ud.removeObject(forKey: k) }
        }
        if let d = try? Data(contentsOf: Self.localFile), let m = try? JSONDecoder().decode([String: Entry].self, from: d) {
            let cutoff = Date().timeIntervalSince1970 - 7 * 86400
            local = Dictionary(uniqueKeysWithValues: m.compactMap { k, v in v.t > cutoff ? Int64(k).map { ($0, v) } : nil })
        }
        if let d = try? Data(contentsOf: Self.indexFile), let x = Self.parseIndex(d) { apply(x) }
    }

    // MARK: lookups
    var indexFresh: Bool { useIndex && (indexDate.map { Date().timeIntervalSince($0) < Self.indexMaxAge } ?? false) }

    /// Best known plan (fresh local → index → stale local), for filtering and badges.
    func plan(_ id: Int64) -> BatteryPlan? {
        if let e = local[id], Date().timeIntervalSince1970 - e.t < Self.ttl { return e.p }
        if indexFresh, let p = index[id] { return p }
        return local[id]?.p
    }
    /// Only listings that neither the index nor a <24 h local result knows need a live detail fetch.
    func needsFetch(_ id: Int64) -> Bool {
        if let e = local[id], Date().timeIntervalSince1970 - e.t < Self.ttl { return false }
        if indexFresh, index[id] != nil { return false }
        return true
    }
    /// The index lists every nationwide listing of these brands, so list + index is enough to filter.
    func covers(_ f: Filters) -> Bool {
        guard indexFresh, f.supportsBattery else { return false }
        if let b = f.brand { return indexBrands.contains(b.id) }
        return true
    }

    func set(_ id: Int64, _ p: BatteryPlan) {
        local[id] = Entry(p: p, t: Date().timeIntervalSince1970)
        saveSoon()
    }
    private var saveTask: Task<Void, Never>?
    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            let m = Dictionary(uniqueKeysWithValues: self.local.map { ("\($0.key)", $0.value) })
            if let d = try? JSONEncoder().encode(m) { try? d.write(to: Self.localFile, options: .atomic) }
        }
    }

    // MARK: daily index
    struct Parsed { let date: Date; let brands: Set<Int>; let items: [Int64: BatteryPlan] }
    nonisolated static func parseIndex(_ d: Data) -> Parsed? {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let g = j["generated_at"] as? String, let date = ISO8601DateFormatter().date(from: g),
              let items = j["items"] as? [String: String] else { return nil }
        var m: [Int64: BatteryPlan] = [:]; m.reserveCapacity(items.count)
        for (k, v) in items { if let id = Int64(k), let p = BatteryPlan(rawValue: v) { m[id] = p } }
        let brands = Set(((j["brands"] as? [String: Any]) ?? [:]).keys.compactMap(Int.init))
        return Parsed(date: date, brands: brands, items: m)
    }
    private func apply(_ x: Parsed) { index = x.items; indexDate = x.date; indexBrands = x.brands }

    private var indexTask: Task<Void, Never>?
    /// Download the index if due: never more than once per 24 h, except an hourly re-check
    /// once our copy is older than a day (the workflow runs at 03:00 Asia/Shanghai).
    func ensureIndex() async {
        guard useIndex else { return }
        if let t = indexTask { return await t.value }
        let last = ud.double(forKey: "battery.lastCheck")
        let sinceCheck = Date().timeIntervalSince1970 - last
        let age = indexDate.map { Date().timeIntervalSince($0) } ?? .infinity
        guard last == 0 || sinceCheck > 24 * 3600 || (age > 25 * 3600 && sinceCheck > 3600) else { return }
        let t = Task { await self.download() }
        indexTask = t
        await t.value
        indexTask = nil
    }

    private func download() async {
        let etag = indexDate == nil ? nil : ud.string(forKey: "battery.etag")
        let t0 = Date()
        // Race the mirrors (raw.githubusercontent may be slow or blocked on some networks).
        let winner: (Data?, String?, Int)? = await withTaskGroup(of: (Data?, String?, Int)?.self) { g in
            for u in Self.indexURLs {
                g.addTask {
                    var r = URLRequest(url: URL(string: u)!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
                    if let etag { r.setValue(etag, forHTTPHeaderField: "If-None-Match") }
                    guard let res = try? await URLSession.shared.data(for: r), let h = res.1 as? HTTPURLResponse else { return nil }
                    let d = res.0
                    if h.statusCode == 304 { return (nil, etag, 304) }
                    guard h.statusCode == 200 else { return nil }
                    return (d, h.value(forHTTPHeaderField: "ETag"), 200)
                }
            }
            for await r in g { if let r { g.cancelAll(); return r } }
            return nil
        }
        guard let w = winner else { API.log("battery index: all mirrors failed"); return }
        let (data, newTag, code) = w
        ud.set(Date().timeIntervalSince1970, forKey: "battery.lastCheck")
        if code == 304 { API.log("battery index 304 in \(Int(Date().timeIntervalSince(t0) * 1000))ms"); return }
        guard let data, let x = await Task.detached(operation: { Self.parseIndex(data) }).value else { return }
        if let cur = indexDate, x.date <= cur { return }
        apply(x)
        ud.set(newTag, forKey: "battery.etag")
        try? data.write(to: Self.indexFile, options: .atomic)
        API.log("battery index \(x.items.count) items (\(data.count)B) in \(Int(Date().timeIntervalSince(t0) * 1000))ms")
    }

    var updatedText: String? {
        guard indexFresh, let d = indexDate else { return nil }
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm"
        return "电池数据更新于 \(f.string(from: d))"
    }
}
