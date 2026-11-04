import SwiftUI
import CoreLocation

/// Local favorites + browsing history (UserDefaults, JSON). Nothing leaves the device.
@MainActor final class Store: ObservableObject {
    static let shared = Store()
    struct Fav: Codable, Hashable { var car: Car; var savedPrice: String; var savedAt: Date }
    @Published private(set) var favorites: [Fav] = []
    @Published private(set) var history: [Car] = []
    /// 对比清单 (max 4), shared by detail page and 我的.
    @Published private(set) var compare: [Car] = []
    /// Latest price per favorite, re-read from detail/major when the 收藏 page opens (nil = not checked, "" = 已下架).
    @Published var latest: [Int64: String] = [:]

    private init() {
        let d = UserDefaults.standard
        if let x = d.data(forKey: "fav"), let v = try? JSONDecoder().decode([Fav].self, from: x) { favorites = v }
        if let x = d.data(forKey: "hist"), let v = try? JSONDecoder().decode([Car].self, from: x) { history = v }
        if let x = d.data(forKey: "cmp"), let v = try? JSONDecoder().decode([Car].self, from: x) { compare = v }
    }
    private func save() {
        let d = UserDefaults.standard
        d.set(try? JSONEncoder().encode(favorites), forKey: "fav")
        d.set(try? JSONEncoder().encode(history), forKey: "hist")
        d.set(try? JSONEncoder().encode(compare), forKey: "cmp")
    }
    func inCompare(_ id: Int64) -> Bool { compare.contains { $0.id == id } }
    /// Returns false when the list is full.
    @discardableResult func addCompare(_ c: Car) -> Bool {
        if inCompare(c.id) { return true }
        guard compare.count < 4 else { return false }
        compare.append(c); save(); return true
    }
    func removeCompare(_ id: Int64) { compare.removeAll { $0.id == id }; save() }
    func clearCompare() { compare = []; save() }
    func clearFavorites() { favorites = []; save() }
    func removeHistory(_ id: Int64) { history.removeAll { $0.id == id }; save() }

    // Last used city + filters, restored on launch.
    static func savedFilters() -> Filters? {
        guard let x = UserDefaults.standard.data(forKey: "filters") else { return nil }
        return try? JSONDecoder().decode(Filters.self, from: x)
    }
    static func saveFilters(_ f: Filters) {
        var f = f; f.keyword = ""
        UserDefaults.standard.set(try? JSONEncoder().encode(f), forKey: "filters")
    }
    func isFav(_ id: Int64) -> Bool { favorites.contains { $0.car.id == id } }
    func toggleFav(_ c: Car) {
        if let i = favorites.firstIndex(where: { $0.car.id == c.id }) { favorites.remove(at: i) }
        else { favorites.insert(Fav(car: c, savedPrice: c.price, savedAt: Date()), at: 0) }
        save()
    }
    func removeFav(_ ids: Set<Int64>) { favorites.removeAll { ids.contains($0.car.id) }; save() }
    func visit(_ c: Car) {
        history.removeAll { $0.id == c.id }
        history.insert(c, at: 0)
        if history.count > 200 { history.removeLast(history.count - 200) }
        save()
    }
    func clearHistory() { history = []; save() }

    /// Re-check current price of each favorite (3 at a time).
    func refreshPrices() async {
        let favs = favorites.map(\.car)
        await withTaskGroup(of: (Int64, String?).self) { g in
            var it = favs.makeIterator()
            func add() { if let c = it.next() { g.addTask { await (c.id, Self.price(c)) } } }
            for _ in 0..<3 { add() }
            for await (id, p) in g { if let p { latest[id] = p }; add() }
        }
    }
    nonisolated static func price(_ c: Car) async -> String? {
        do { return try await DetailCache.shared.get(c.id, city: c.city.isEmpty ? "全国" : c.city).price?.wan ?? "" }
        catch APIError.empty { return "" }
        catch { return nil }
    }
}

/// When-in-use location → city name via reverse geocoding (CLGeocoder).
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()
    private let m = CLLocationManager()
    private var cont: CheckedContinuation<CLLocation?, Never>?

    func city() async -> String? {
        guard let loc = await location() else { return nil }
        let p = try? await CLGeocoder().reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "zh_CN")).first
        guard var c = p?.locality ?? p?.administrativeArea else { return nil }
        for suf in ["市", "地区", "盟"] where c.hasSuffix(suf) && c.count > 2 { c = String(c.dropLast(suf.count)) }
        return c
    }
    @MainActor private func location() async -> CLLocation? {
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { c in
            cont?.resume(returning: nil); cont = c
            if m.authorizationStatus == .notDetermined { m.requestWhenInUseAuthorization() } else { m.requestLocation() }
        }
    }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: cont?.resume(returning: nil); cont = nil
        default: break
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) { cont?.resume(returning: l.last); cont = nil }
    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) { cont?.resume(returning: nil); cont = nil }
}
