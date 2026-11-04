import Foundation

// MARK: - Models

struct CarTag: Hashable, Codable {
    let text: String
    let textColor: String
    let bgColor: String
}

struct Car: Identifiable, Hashable, Codable {
    let id: Int64
    let title: String
    let image: String
    var price: String          // decoded, e.g. "3.88万"
    let officialPrice: String  // decoded new-car guide price, e.g. "27.80万"
    let sub: String            // decoded, e.g. "2014年 | 7.70万公里"
    var city: String
    let year: Int
    let tags: [CarTag]
    let transferCount: Int
    let sourceType: String
    let isSelfTrade: Bool      // is_self_trade: 懂车帝官方直营
    let hintBar: String        // official_hint_bar
}

struct Brand: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let logo: String
    let pinyin: String
}

struct Series: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let image: String
}

struct Suggestion: Identifiable, Hashable {
    enum Kind: Hashable { case brand(Brand), series(Int, String), text(String) }
    let kind: Kind
    var id: String {
        switch kind {
        case .brand(let b): return "b\(b.id)"
        case .series(let i, _): return "s\(i)"
        case .text(let t): return "t" + t
        }
    }
}

struct KV: Hashable { let name: String; let value: String }

/// 蔚来系电池方案. dongchedi has no structured field or filter for it (checked sh_sku_list params,
/// list items, detail/major fields and the web bundles, 2026-11-04); the only signal is the seller's
/// free-text description (sh_car_desc), e.g. "75度电池租电" / "100度买断电池". Anything not stated
/// explicitly — or stated both ways — is `.unknown` (shown as 未注明), never guessed from price.
enum BatteryPlan: String, Codable {
    case rent, buy, unknown
    var label: String { switch self { case .rent: return "租电"; case .buy: return "买断"; case .unknown: return "未注明" } }

    static let brandIds: Set<Int> = [112, 918, 10363]   // 蔚来, 乐道, firefly萤火虫
    static func supports(brandId: Int, title: String) -> Bool {
        brandIds.contains(brandId) || title.hasPrefix("蔚来") || title.hasPrefix("乐道") || title.lowercased().hasPrefix("firefly") || title.hasPrefix("萤火虫")
    }

    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    private static let negRentRE = re("非租电|不租电|无需租电")
    private static let rentRE = re("租电|电池\\s*租(?:用|赁|电)|租(?:用|赁)\\s*电池|BaaS|电池\\s*月租")
    // "买断" alone is not enough: sellers also write "NIO Pilot全配包买断" / "智驾买断" (software).
    private static let buyRE = re("非租电|不租电|无需租电|电池\\s*(?:已)?\\s*买断|买断\\s*(?:版|电池)|\\d{2,3}\\s*(?:度|°|kwh)\\s*(?:电池)?\\s*买断|电池\\s*(?:已)?\\s*(?:购买|买了)|车电一体")

    static func classify(_ text: String) -> BatteryPlan {
        func has(_ r: NSRegularExpression, _ s: String) -> Bool { r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil }
        let b = has(buyRE, text)
        let stripped = negRentRE.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        let r = has(rentRE, stripped)
        if r == b { return .unknown }   // neither, or contradictory
        return r ? .rent : .buy
    }
}

/// Remembers classified listings (by sku) so lists, cards and favourites can show the badge without refetching.
@MainActor final class BatteryStore: ObservableObject {
    static let shared = BatteryStore()
    @Published private(set) var plans: [Int64: BatteryPlan] = [:]
    private let key = "batteryPlans.v1"
    init() {
        if let d = UserDefaults.standard.data(forKey: key), let m = try? JSONDecoder().decode([String: BatteryPlan].self, from: d) {
            plans = Dictionary(uniqueKeysWithValues: m.compactMap { k, v in Int64(k).map { ($0, v) } })
        }
    }
    func set(_ id: Int64, _ p: BatteryPlan) {
        guard plans[id] != p else { return }
        plans[id] = p
        saveSoon()
    }
    private var saveTask: Task<Void, Never>?
    private func saveSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            let m = Dictionary(uniqueKeysWithValues: self.plans.suffix(3000).map { ("\($0.key)", $0.value) })
            UserDefaults.standard.set(try? JSONEncoder().encode(m), forKey: self.key)
        }
    }
}

struct ReportCate: Hashable { let name: String; let total: Int; let defect: Int }
struct ReportFlaw: Hashable { let name: String; let desc: String; let images: [String] }

struct CarDetail {
    let skuId: String
    let isSelfTrade: Bool
    let title: String
    let images: [String]
    let price: Double?            // 万
    let officialPrice: String     // 新车指导价
    let taxPrice: String          // 新车含税价
    let importantText: [String]   // ["2014年上牌", "7.70万公里", "北京车源"]
    let params: [KV]              // other_params
    let config: [KV]
    let tags: [CarTag]
    let priceTips: String
    let priceDesc: String
    let popularity: String
    let downPayment: String
    let monthPay: String
    let serviceText: String
    let desc: String
    let hasReport: Bool
    let reportOverview: [KV]
    let reportCates: [ReportCate]
    let reportFlaws: [ReportFlaw]
    let reportTip: String
    let shopName: String
    let shopFullName: String
    let shopLogo: String
    let shopAddress: String
    let shopHours: String
    let shopCity: String
    let shopSalesNum: Int
    let shopRange: String
    let bodyColor: String
    let year: Int
    let carId: Int
    let seriesId: Int
    let seriesName: String
    let finRatio: Int             // financial_info.down_payment_ratio (3 = 30%)
    let finMonths: Int            // financial_info.repayment_cycle
    var brandId: Int = 0          // car_info.brand_id

    /// 租电/买断 as stated in the seller's own description (nil for brands without battery rental).
    var batteryPlan: BatteryPlan? { BatteryPlan.supports(brandId: brandId, title: title) ? BatteryPlan.classify(title + "\n" + desc) : nil }

    /// Summary row for favorites / history when we came from a deep link without a list row.
    func asCar(city: String) -> Car {
        Car(id: Int64(skuId) ?? 0, title: title, image: images.first ?? "", price: price?.wan ?? "", officialPrice: officialPrice,
            sub: importantText.prefix(2).joined(separator: " | "), city: shopCity.isEmpty ? city : shopCity, year: year, tags: tags,
            transferCount: 0, sourceType: "", isSelfTrade: isSelfTrade, hintBar: "")
    }
}

/// /motor/pc/car/get_full_config_info?car_id_list=a,b  (the 参数配置 page of dongchedi.com)
struct FullConfig {
    struct Row: Hashable { let name: String; let values: [String] }
    struct Group: Hashable { let name: String; var rows: [Row] }
    let carNames: [String]
    let groups: [Group]
}

/// /motor/sh_go/api/price_analysis/detail?sku_id=  (价格分析报告)
struct PriceAnalysis {
    struct Bars: Hashable { let unit: String; let x: [String]; let y: [Int] }
    let price: Double, avg: Double, min: Double, max: Double
    let tips: String, desc: String
    let sameYear: (cnt: Int, min: Double, max: Double, avg: Double)
    let sameMileage: (cnt: Int, min: Double, max: Double, avg: Double)
    let views: Int, favs: Int, clues: Int, heatText: String
    let carAge: String, mileage: String
    let tables: [(String, Bars)]
}

// MARK: - Filters

struct Filters: Equatable, Codable {
    var city = "全国"
    var brand: Brand?
    var series: Series?
    var price: Option?
    var age: Option?
    var mileage: Option?
    var sort: Option?
    var gearbox: Option?
    var fuel: Option?
    var level: Option?
    var emission: Option?
    var capacity: Option?
    var driven: Option?
    var origin: Option?
    var subLevel: Option?
    var fixedPrice = false
    var testReport = false
    var dcdSelf = false      // dcd_self_sh=1   懂车帝自营（网页版叫“懂懂二手车”）
    var cert4S = false       // car_source_types=1  4S店专区
    var video = false        // has_related_video=1 视频看车
    var keyword = ""   // local title filter (fallback when keyword is not a brand/series)
    /// 电池方案 (NIO family only): "rent" / "buy" / nil. Client-side — sh_sku_list has no such param.
    var battery: String?

    /// 蔚来 / 乐道 / firefly萤火虫 sell cars with battery rental (BaaS) or bought out.
    var supportsBattery: Bool {
        if let brand { return BatteryPlan.brandIds.contains(brand.id) }
        if let series { return BatteryPlan.supports(brandId: 0, title: series.name) }
        return false
    }
    var batteryWanted: BatteryPlan? { supportsBattery ? battery.flatMap(BatteryPlan.init(rawValue:)) : nil }

    var params: [String: String] {
        var p: [String: String] = ["sh_city_name": city]
        if let brand { p["brand"] = "\(brand.id)" }
        if let series { p["series_ids"] = "\(series.id)" }
        for o in [price, age, mileage, sort, gearbox, fuel, level, emission, capacity, driven, origin, subLevel].compactMap({ $0 }) { p[o.key] = o.param }
        if fixedPrice { p["is_fixed_price"] = "1" }
        if testReport { p["third_party_test_report"] = "1" }
        if dcdSelf { p["dcd_self_sh"] = "1" }
        if cert4S { p["car_source_types"] = "1" }
        if video { p["has_related_video"] = "1" }
        return p
    }

    var activeChips: [(String, WritableKeyPath<Filters, Option?>?)] {
        var r: [(String, WritableKeyPath<Filters, Option?>?)] = []
        if let price { r.append((price.text, \.price)) }
        if let age { r.append((age.text, \.age)) }
        if let mileage { r.append((mileage.text, \.mileage)) }
        if let gearbox { r.append((gearbox.text, \.gearbox)) }
        if let fuel { r.append((fuel.text, \.fuel)) }
        if let level { r.append((level.text, \.level)) }
        if let emission { r.append((emission.text, \.emission)) }
        if let capacity { r.append((capacity.text, \.capacity)) }
        if let driven { r.append((driven.text, \.driven)) }
        if let origin { r.append((origin.text, \.origin)) }
        if let subLevel { r.append((subLevel.text, \.subLevel)) }
        return r
    }
}

struct Option: Hashable, Codable {
    let text: String
    let key: String
    let param: String
}

// Values taken from dongchedi.com /usedcar page filter config (verified against sh_sku_list).
enum FilterOptions {
    static let price: [Option] = [("3万以下", "0,3"), ("3-5万", "3,5"), ("5-8万", "5,8"), ("8-10万", "8,10"), ("10-15万", "10,15"), ("15-20万", "15,20"), ("20-30万", "20,30"), ("30-50万", "30,50"), ("50万以上", "50,-1")].map { Option(text: $0.0, key: "price", param: $0.1) }
    static let age: [Option] = [("1年内", "0,1"), ("1-3年", "1,3"), ("3-5年", "3,5"), ("5-8年", "5,8"), ("8-10年", "8,10"), ("10年以上", "10,-1")].map { Option(text: $0.0, key: "age_range", param: $0.1) }
    static let mileage: [Option] = [("1万公里内", "0,1"), ("3万公里内", "0,3"), ("5万公里内", "0,5"), ("6万公里内", "0,6"), ("10万公里内", "0,10")].map { Option(text: $0.0, key: "mileage_range", param: $0.1) }
    static let sort: [Option] = [("默认排序", ""), ("最新上架", "4"), ("价格最低", "1"), ("价格最高", "2"), ("车龄最短", "5"), ("车龄最长", "6"), ("里程最少", "7"), ("里程最多", "8")].map { Option(text: $0.0, key: "sort_type", param: $0.1) }
    static let gearbox: [Option] = [("手动", "1"), ("自动", "2")].map { Option(text: $0.0, key: "gearbox_type", param: $0.1) }
    static let fuel: [Option] = [("汽油", "1"), ("柴油", "2"), ("纯电动", "4"), ("油电混合", "3"), ("插电混动", "6"), ("增程式", "5"), ("新能源", "4,5,6")].map { Option(text: $0.0, key: "fuel_form", param: $0.1) }
    static let level: [Option] = [("轿车", "0"), ("SUV", "1"), ("MPV", "2"), ("跑车", "4"), ("皮卡", "3")].map { Option(text: $0.0, key: "series_type", param: $0.1) }
    static let emission: [Option] = [("国四", "2"), ("国五", "5"), ("国六", "7")].map { Option(text: $0.0, key: "environmental_standards", param: $0.1) }
    // Verified 2026-11-04: each changes sh_sku_list `total` (北京 7549 → 排量1.1-1.6L 1237, 四驱 3311, 进口 3037, 紧凑型SUV 656).
    // The site's 国别/座椅/安全配置/舒适配置/懂车分/气缸/进气/结构 params are ignored by the API (total unchanged), so they are not offered.
    static let capacity: [Option] = [("1.0L以下", "0,1.0"), ("1.1-1.6L", "1.1,1.6"), ("1.7-2.0L", "1.7,2.0"), ("2.1-2.5L", "2.1,2.5"), ("2.6-3.0L", "2.6,3.0"), ("3.1-4.0L", "3.1,4.0"), ("4.0L以上", "4.0,-1")].map { Option(text: $0.0, key: "capacity_l", param: $0.1) }
    static let driven: [Option] = [("前驱", "1"), ("后驱", "2"), ("四驱", "3")].map { Option(text: $0.0, key: "driven_form", param: $0.1) }
    static let origin: [Option] = [("合资", "1"), ("自主", "2"), ("进口", "4")].map { Option(text: $0.0, key: "expanded_origin", param: $0.1) }
    static let subLevel: [Option] = [("微型车", "0"), ("小型车", "1"), ("紧凑型车", "2"), ("中型车", "3"), ("中大型车", "4"), ("大型车", "5"), ("小型SUV", "10"), ("紧凑型SUV", "11"), ("中型SUV", "12"), ("中大型SUV", "13"), ("大型SUV", "14")].map { Option(text: $0.0, key: "outter_detail_type", param: $0.1) }
    static let cities = ["全国", "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "武汉", "南京", "西安", "天津", "苏州", "郑州", "长沙", "东莞", "青岛", "沈阳", "宁波", "昆明", "合肥", "佛山", "济南", "福州", "厦门", "石家庄", "大连", "哈尔滨", "长春", "太原", "南昌", "南宁", "贵阳", "温州", "无锡", "常州", "徐州", "泉州", "金华", "台州", "嘉兴", "绍兴", "烟台", "潍坊", "临沂", "保定", "唐山", "洛阳", "乌鲁木齐", "兰州", "呼和浩特", "海口", "银川", "西宁", "拉萨"]
}

// MARK: - API (unofficial; endpoints used by the dongchedi.com web site)

enum APIError: Error { case server, empty }

enum API {
    static let ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    static let base = "https://www.dongchedi.com"

    // Custom-font digit obfuscation used by sh_sku_list (Private Use Area codepoints).
    // Verified against plain-number fields of /motor/pc/sh/detail/major. May change.
    static let map: [UInt32: String] = [58425: "0", 58700: "1", 58467: "2", 58525: "3", 58397: "4", 58385: "5", 58676: "6", 58347: "7", 58595: "8", 58461: "9", 58378: "万", 58661: "年", 58514: "公", 58536: "里", 58618: "日"]
    static func dec(_ s: String?) -> String {
        (s ?? "").unicodeScalars.map { sc -> String in
            if let m = map[sc.value] { return m }
            if (0xE000...0xF8FF).contains(sc.value) { return "" }  // unknown glyph: drop rather than show garbage
            return String(sc)
        }.joined()
    }

    static func https(_ s: String) -> String { s.hasPrefix("http://") ? "https://" + s.dropFirst(7) : s }

    /// Unsigned p*-dcd.byteimg.com images accept a `~tplv-resize:W:0.webp` template.
    /// The URLs returned by sh_series_list ("~tplv-f042mdwyw7-original:tplv-resize:640:0.image")
    /// fail with HTTP 400 over https (measured), so rewrite them to a small webp (≈5 KB vs 196 KB).
    /// Signed (p*-dcd-sign) URLs can't be changed — the signature covers the size (403).
    static func thumb(_ s: String, _ w: Int) -> String {
        let u = https(s)
        guard !u.contains("-sign."), let r = u.range(of: "~") else { return u }
        return String(u[..<r.lowerBound]) + "~tplv-resize:\(w):0.webp"
    }

    // One shared session: keep-alive connections + cookie jar, consistent browser-like headers.
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpShouldSetCookies = true
        c.httpMaximumConnectionsPerHost = 4
        c.timeoutIntervalForRequest = 12
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpAdditionalHeaders = [
            "User-Agent": ua,
            "Referer": "https://www.dongchedi.com/usedcar",
            "Origin": "https://www.dongchedi.com",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
        ]
        return URLSession(configuration: c)
    }()

    /// Last request stats, for the debug timing overlay / logs.
    static func log(_ s: String) { if LaunchArgs.flag("timing") { print("[timing]", s) } }

    static func makeRequest(_ path: String, query: [String: String], form: [String: String]?) -> URLRequest {
        var c = URLComponents(string: base + path)!
        var q = [URLQueryItem(name: "aid", value: "1839"), URLQueryItem(name: "app_name", value: "auto_web_pc")]
        q += query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        c.queryItems = q
        var req = URLRequest(url: c.url!, timeoutInterval: 12)
        if let form {
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var fc = URLComponents()
            fc.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            req.httpBody = fc.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        }
        return req
    }

    static func cacheKey(_ req: URLRequest) -> String {
        (req.url?.absoluteString ?? "") + "|" + String(data: req.httpBody ?? Data(), encoding: .utf8)!
    }

    /// Fetch JSON. The server randomly answers 403 to ~40% of requests (measured); the 403 is
    /// instant and an immediate retry usually succeeds, so retry fast with short jittered backoff.
    static func request(_ path: String, query: [String: String] = [:], form: [String: String]? = nil, ttl: TimeInterval = 0) async throws -> [String: Any] {
        try await requestData(path, query: query, form: form, ttl: ttl).json
    }

    static func requestData(_ path: String, query: [String: String] = [:], form: [String: String]? = nil, ttl: TimeInterval = 0) async throws -> (json: [String: Any], data: Data) {
        let req = makeRequest(path, query: query, form: form)
        let key = cacheKey(req)
        if ttl > 0, let d = DiskCache.get(key, maxAge: ttl), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            log("\(path) disk-cache hit"); return (j, d)
        }
        let t0 = Date()
        var lastError: Error = APIError.server
        for attempt in 0..<7 {
            if Task.isCancelled { throw CancellationError() }
            do {
                let (data, resp) = try await session.data(for: req)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                if code == 200, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    log("\(path) 200 in \(Int(Date().timeIntervalSince(t0) * 1000))ms, attempts \(attempt + 1), \(data.count)B")
                    DiskCache.put(key, data)
                    return (j, data)
                }
                log("\(path) HTTP \(code) attempt \(attempt + 1)")
            } catch { lastError = error; if error is CancellationError { throw error } }
            // 0.2, 0.4, 0.8, 1.2, 1.2 … s with ±25% jitter
            let base = min(0.2 * pow(2, Double(attempt)), 1.2)
            try await Task.sleep(nanoseconds: UInt64(base * Double.random(in: 0.75...1.25) * 1e9))
        }
        throw lastError
    }

    /// Any cached copy (regardless of age) — used to paint instantly before the network answers.
    static func cachedJSON(_ path: String, query: [String: String] = [:], form: [String: String]? = nil, maxAge: TimeInterval) -> [String: Any]? {
        let key = cacheKey(makeRequest(path, query: query, form: form))
        guard let d = DiskCache.get(key, maxAge: maxAge) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    static func tags(_ any: Any?) -> [CarTag] {
        (any as? [[String: Any]] ?? []).compactMap { t in
            guard let text = t["text"] as? String, !text.isEmpty else { return nil }
            return CarTag(text: text, textColor: t["text_color"] as? String ?? "", bgColor: t["background_color"] as? String ?? "")
        }
    }

    static let pageSize = 20

    static func searchForm(_ f: Filters, page: Int) -> [String: String] {
        var form = f.params
        form["page"] = "\(page)"
        form["limit"] = "\(pageSize)"
        return form
    }

    static func search(_ f: Filters, page: Int) async throws -> (cars: [Car], hasMore: Bool, total: Int) {
        try parseList(await request("/motor/pc/sh/sh_sku_list", form: searchForm(f, page: page)))
    }

    /// Cached first page (up to 1 day old) for instant paint.
    static func cachedSearch(_ f: Filters) -> (cars: [Car], hasMore: Bool, total: Int)? {
        guard let j = cachedJSON("/motor/pc/sh/sh_sku_list", form: searchForm(f, page: 1), maxAge: 86400) else { return nil }
        return try? parseList(j)
    }

    static func parseList(_ j: [String: Any]) throws -> (cars: [Car], hasMore: Bool, total: Int) {
        guard let d = j["data"] as? [String: Any] else { throw APIError.server }
        let list = d["search_sh_sku_info_list"] as? [[String: Any]] ?? []
        let cars = list.map { x in
            Car(id: (x["sku_id"] as? NSNumber)?.int64Value ?? 0,
                title: x["title"] as? String ?? "",
                image: https(x["image"] as? String ?? ""),
                price: dec(x["sh_price"] as? String),
                officialPrice: dec(x["official_price"] as? String),
                sub: dec(x["sub_title"] as? String),
                // car_source_city_name is font-obfuscated; brand_source_city_name is plain text
                city: x["brand_source_city_name"] as? String ?? "",
                year: x["car_year"] as? Int ?? 0,
                tags: tags(x["tags"]),
                transferCount: x["transfer_cnt"] as? Int ?? 0,
                sourceType: x["car_source_type"] as? String ?? "",
                isSelfTrade: x["is_self_trade"] as? Bool ?? false,
                hintBar: x["official_hint_bar"] as? String ?? "")
        }
        return (cars, d["has_more"] as? Bool ?? false, d["total"] as? Int ?? 0)
    }

    /// Number of listings for a series in a city (limit=1 query, real `total`).
    /// Total listings for a filter set (limit=1 query, cached 10 min) — used for "查看 N 辆" buttons.
    static func count(_ f: Filters) async -> Int? {
        var form = f.params; form["page"] = "1"; form["limit"] = "1"
        guard let j = try? await request("/motor/pc/sh/sh_sku_list", form: form, ttl: 600),
              let d = j["data"] as? [String: Any] else { return nil }
        return d["total"] as? Int
    }

    static func seriesCount(_ f: Filters, series: Int) async -> Int? {
        var form = f.params
        form["series_ids"] = "\(series)"; form["page"] = "1"; form["limit"] = "1"
        guard let j = try? await request("/motor/pc/sh/sh_sku_list", form: form, ttl: 1800),
              let d = j["data"] as? [String: Any] else { return nil }
        return d["total"] as? Int
    }

    static var brandCache: (all: [Brand], hot: [Brand])?
    static func brands() async throws -> (all: [Brand], hot: [Brand]) {
        if let brandCache { return brandCache }
        let j = try await request("/motor/pc/car/brand/all_brand", ttl: 7 * 86400)
        guard let d = j["data"] as? [String: Any] else { throw APIError.server }
        func parse(_ a: Any?) -> [Brand] {
            (a as? [[String: Any]] ?? []).compactMap { e in
                guard let i = e["info"] as? [String: Any], let id = i["brand_id"] as? Int, let n = i["brand_name"] as? String else { return nil }
                return Brand(id: id, name: n, logo: thumb(i["image_url"] as? String ?? "", 96), pinyin: i["pinyin"] as? String ?? "#")
            }
        }
        let r = (parse(d["brand"]), parse(d["hot_brand"]))
        brandCache = r
        return r
    }

    static func series(brand: Int, city: String) async throws -> [Series] {
        let j = try await request("/motor/pc/sh/sh_series_list", query: ["brand_id": "\(brand)", "sh_city_name": city], ttl: 86400)
        return (j["data"] as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["series_id"] as? Int, let n = s["series_name"] as? String else { return nil }
            return Series(id: id, name: n, image: thumb(s["image_url"] as? String ?? "", 240))
        }
    }

    static func suggest(_ kw: String) async throws -> [Suggestion] {
        var c = URLComponents(string: base + "/motor/searchacl/complete")!
        c.queryItems = [URLQueryItem(name: "motor_source", value: "pc_new"), URLQueryItem(name: "keyword", value: kw)]
        let req = URLRequest(url: c.url!, timeoutInterval: 10)
        let (data, _) = try await session.data(for: req)
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        var out: [Suggestion] = []
        for x in j?["data"] as? [[String: Any]] ?? [] {
            if let b = x["buried_point_info"] as? [String: Any], let sid = b["series_id"] as? Int, let sn = b["series_name"] as? String {
                if !out.contains(where: { $0.id == "s\(sid)" }) { out.append(Suggestion(kind: .series(sid, sn))) }
            }
        }
        return out
    }

    static func detail(sku: Int64, city: String) async throws -> CarDetail {
        let j = try await request("/motor/pc/sh/detail/major", query: ["sku_id": "\(sku)", "city_name": city])
        guard let d = j["data"] as? [String: Any], let info = d["car_info"] as? [String: Any], info["car_id"] != nil else { throw APIError.empty }
        func s(_ o: [String: Any]?, _ k: String) -> String { (o?[k] as? String) ?? ((o?[k] as? NSNumber)?.stringValue ?? "") }
        func kvs(_ a: Any?) -> [KV] {
            (a as? [[String: Any]] ?? []).compactMap { p in
                let n = s(p, "name"), v = s(p, "value")
                // skip anything still font-obfuscated (detail uses a different font than the list)
                if n.isEmpty || v.isEmpty || (n + v).unicodeScalars.contains(where: { (0xE000...0xF8FF).contains($0.value) }) { return nil }
                return KV(name: n, value: v)
            }
        }
        let cfg = d["car_config_overview"] as? [String: Any]
        let power = cfg?["power"] as? [String: Any]
        let man = cfg?["manipulation"] as? [String: Any]
        let space = cfg?["space"] as? [String: Any]
        let ne = cfg?["new_energy_power"] as? [String: Any]
        var config: [KV] = []
        func add(_ n: String, _ v: String) { if !v.isEmpty && v != "-" { config.append(KV(name: n, value: v)) } }
        add("排量", s(power, "capacity")); add("能源类型", s(power, "fuel_form")); add("变速箱", s(power, "gearbox_description"))
        add("最大马力", s(power, "horsepower")); add("百公里加速", s(power, "acceleration_time"))
        if let ne { for (k, v) in ne.sorted(by: { $0.key < $1.key }) { if let v = v as? String, !v.isEmpty, k.contains("range") || k.contains("battery") { add(k == "battery_capacity" ? "电池容量" : (k.contains("range") ? "续航里程" : k), v) } } }
        add("驱动方式", s(man, "driver_form")); add("前悬挂", s(man, "front_suspension_form")); add("后悬挂", s(man, "rear_suspension_form"))
        let l = s(space, "length"), w = s(space, "width"), h = s(space, "height")
        if !l.isEmpty && !w.isEmpty && !h.isEmpty { add("长×宽×高", "\(l)×\(w)×\(h)mm") }
        add("轴距", s(space, "wheelbase").isEmpty ? "" : s(space, "wheelbase") + "mm")

        let report = d["report"] as? [String: Any]
        let cates = (report?["cate_list"] as? [[String: Any]] ?? []).map {
            ReportCate(name: s($0, "cate_name"), total: $0["total"] as? Int ?? 0, defect: $0["defect"] as? Int ?? 0)
        }
        var flaws: [ReportFlaw] = []
        for c in report?["cate_list"] as? [[String: Any]] ?? [] {
            for df in c["defect_list"] as? [[String: Any]] ?? [] {
                let fd = df["flaw_detail"] as? [[String: Any]] ?? []
                let desc = fd.map { s($0, "description") }.filter { !$0.isEmpty }.joined(separator: "；")
                let imgs = fd.flatMap { $0["picture"] as? [String] ?? [] }.map(https)
                flaws.append(ReportFlaw(name: s(df, "name"), desc: desc.isEmpty ? s(df, "description") : desc, images: imgs))
            }
        }
        let shop = d["shop_info"] as? [String: Any]
        let fin = d["financial_info"] as? [String: Any]
        let pa = d["price_analysis_entry"] as? [String: Any]
        let pc = d["price_compare"] as? [String: Any]
        let tips = report?["tips"] as? [String: Any]
        let src = (d["source_sh_price"] as? NSNumber)?.doubleValue
        return CarDetail(
            skuId: s(d, "sku_id"),
            isSelfTrade: d["is_self_trade"] as? Bool ?? false,
            title: s(d, "title"),
            images: (d["head_images"] as? [String] ?? []).map(https),
            price: src.map { $0 / 1_000_000 },
            officialPrice: s(d, "offical_price"),
            taxPrice: s(d, "include_tax_price"),
            importantText: s(d, "important_text").components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
            params: kvs(d["other_params"]),
            config: config,
            tags: tags(d["tags"]),
            priceTips: s(pc, "tips"),
            priceDesc: s(pc, "desc"),
            popularity: s(pa, "popularity").replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression),
            downPayment: s(fin, "down_payment"),
            monthPay: s(fin, "month_pay"),
            serviceText: s(d, "self_core_value_text"),
            desc: s(d, "sh_car_desc"),
            hasReport: report?["has_report"] as? Bool ?? false,
            reportOverview: (report?["overview"] as? [[String: Any]] ?? []).map { KV(name: s($0, "name"), value: s($0, "overview")) },
            reportCates: cates,
            reportFlaws: flaws,
            reportTip: s(tips, "desc"),
            shopName: s(shop, "shop_short_name").isEmpty ? s(shop, "shop_name") : s(shop, "shop_short_name"),
            shopFullName: s(shop, "shop_name"),
            shopLogo: https(s(shop, "shop_logo")),
            shopAddress: s(shop, "shop_address"),
            shopHours: s(shop, "business_time"),
            shopCity: s(shop, "city_name"),
            shopSalesNum: shop?["sales_car_num"] as? Int ?? 0,
            shopRange: s(shop, "sales_range"),
            bodyColor: s(info, "body_color"),
            year: info["year"] as? Int ?? 0,
            carId: info["car_id"] as? Int ?? 0,
            seriesId: (info["series_id"] as? Int) ?? (cfg?["series_id"] as? Int ?? 0),
            seriesName: s(info, "series_name"),
            finRatio: Int(s(fin, "down_payment_ratio")) ?? 0,
            finMonths: fin?["repayment_cycle"] as? Int ?? 0,
            brandId: info["brand_id"] as? Int ?? 0)
    }

    /// 相似车源: /motor/pc/sh/sh_single_list?sku_type=similar (used by the web detail page).
    static func similar(series: Int, city: String, exclude: Int64) async throws -> [Car] {
        let j = try await request("/motor/pc/sh/sh_single_list", query: ["sh_city_name": city, "series_id": "\(series)", "page": "1", "count": "20", "sku_type": "similar"], ttl: 1800)
        let list = (j["data"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
        return list.compactMap { e -> Car? in
            guard let info = e["info"] as? [String: Any], let c = info["card_info"] as? [String: Any], let b = info["base_info"] as? [String: Any],
                  let id = (b["sku_id"] as? NSNumber)?.int64Value, id != exclude else { return nil }
            let op = (b["official_price"] as? NSNumber)?.doubleValue ?? 0
            return Car(id: id, title: c["title"] as? String ?? "", image: https(c["image"] as? String ?? ""), price: dec(c["price"] as? String),
                       officialPrice: op > 0 ? op.wan : "", sub: dec(c["sub_title"] as? String), city: b["brand_source_city_name"] as? String ?? "",
                       year: b["year"] as? Int ?? 0, tags: tags(c["tags"]), transferCount: 0, sourceType: b["source_type_name"] as? String ?? "",
                       isSelfTrade: ((c["card_expend"] as? [String: Any])?["is_self_trade_car"] as? String) == "true", hintBar: "")
        }
    }

    /// 参数配置: /motor/pc/car/get_full_config_info?car_id_list=a,b (multiple car_ids → side-by-side values).
    static func fullConfig(_ carIds: [Int]) async throws -> FullConfig {
        let j = try await request("/motor/pc/car/get_full_config_info", query: ["car_id_list": carIds.map(String.init).joined(separator: ",")], ttl: 7 * 86400)
        guard let d = j["data"] as? [String: Any], let props = d["properties"] as? [[String: Any]] else { throw APIError.empty }
        let cars = d["car_info"] as? [[String: Any]] ?? []
        // keep cars in the requested order
        let byId = Dictionary(cars.map { (Int("\($0["car_id"] ?? "")") ?? 0, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = carIds.compactMap { byId[$0] }
        let infos = ordered.map { $0["info"] as? [String: Any] ?? [:] }
        var groups: [FullConfig.Group] = []
        for p in props {
            let t = p["type"] as? Int ?? 0, name = p["text"] as? String ?? ""
            if t == 0 || t == 2 { groups.append(.init(name: name, rows: [])); continue }
            guard let key = p["key"] as? String, !groups.isEmpty else { continue }
            let vals = infos.map { info -> String in
                guard let v = info[key] as? [String: Any] else { return "-" }
                let text = (v["value"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                switch v["icon_type"] as? Int ?? 0 {
                case 1: return text.isEmpty || text == "标配" ? "●" : "● " + text
                case 2: return text.isEmpty || text == "选装" ? "○" : "○ " + text
                case 3: return "-"
                default: return text.isEmpty ? "-" : text
                }
            }
            if vals.allSatisfy({ $0 == "-" }) && infos.count == 1 { continue }   // hide rows with no data
            groups[groups.count - 1].rows.append(.init(name: name, values: vals))
        }
        return FullConfig(carNames: ordered.map { "\($0["car_year"] ?? "")款 \($0["car_name"] ?? "")" }, groups: groups.filter { !$0.rows.isEmpty })
    }

    static func priceAnalysis(sku: Int64) async throws -> PriceAnalysis {
        let j = try await request("/motor/sh_go/api/price_analysis/detail", query: ["sku_id": "\(sku)"], ttl: 3600)
        guard let d = j["data"] as? [String: Any], d["source_sh_price"] != nil else { throw APIError.empty }
        func w(_ o: [String: Any]?, _ k: String) -> Double { ((o?[k] as? NSNumber)?.doubleValue ?? 0) / 1_000_000 }
        func n(_ o: [String: Any]?, _ k: String) -> Int { (o?[k] as? NSNumber)?.intValue ?? 0 }
        let pc = d["price_compare"] as? [String: Any], heat = d["heat_table"] as? [String: Any]
        var tables: [(String, PriceAnalysis.Bars)] = []
        for (k, t) in [("car_age_table", "同车系车龄分布"), ("mileage_table", "同车系里程分布"), ("condition_table", "同车系车况分布")] {
            if let o = d[k] as? [String: Any], let x = o["x_axis"] as? [String], let y = o["y_axis"] as? [NSNumber], x.count == y.count, !x.isEmpty {
                tables.append((t, .init(unit: o["unit"] as? String ?? "", x: x, y: y.map(\.intValue))))
            }
        }
        return PriceAnalysis(price: w(d, "source_sh_price"), avg: w(d, "avg_price"), min: w(d, "min_price"), max: w(d, "max_price"),
                             tips: pc?["tips"] as? String ?? "", desc: pc?["desc"] as? String ?? "",
                             sameYear: (n(pc, "similar_year_sku_cnt"), w(pc, "similar_year_sku_min_price"), w(pc, "similar_year_sku_max_price"), w(pc, "similar_year_sku_avg_price")),
                             sameMileage: (n(pc, "similar_mileage_sku_cnt"), w(pc, "similar_mileage_sku_min_price"), w(pc, "similar_mileage_sku_max_price"), w(pc, "similar_mileage_sku_avg_price")),
                             views: n(heat, "display_pv"), favs: n(heat, "favourite_pv"), clues: n(heat, "clues_num"), heatText: heat?["annotation"] as? String ?? "",
                             carAge: d["car_age"] as? String ?? "", mileage: d["mileage"] as? String ?? "", tables: tables)
    }

    static func aroundCities(_ city: String) async -> [String] {
        guard city != "全国", let j = try? await request("/motor/pc/sh/around_city_list", query: ["sh_city_name": city], ttl: 7 * 86400) else { return [] }
        return j["data"] as? [String] ?? []
    }
}

extension Double {
    var wan: String {
        let s = String(format: "%.2f", self)
        return (s.hasSuffix(".00") ? String(s.dropLast(3)) : s) + "万"
    }
}
