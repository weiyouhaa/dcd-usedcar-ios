import Foundation

// MARK: - Models

struct CarTag: Hashable {
    let text: String
    let textColor: String
    let bgColor: String
}

struct Car: Identifiable, Hashable {
    let id: Int64
    let title: String
    let image: String
    let price: String          // decoded, e.g. "3.88万"
    let officialPrice: String  // decoded new-car guide price, e.g. "27.80万"
    let sub: String            // decoded, e.g. "2014年 | 7.70万公里"
    let city: String
    let year: Int
    let tags: [CarTag]
    let transferCount: Int
    let sourceType: String
    let isSelfTrade: Bool      // is_self_trade: 懂车帝官方直营
    let hintBar: String        // official_hint_bar
}

struct Brand: Identifiable, Hashable {
    let id: Int
    let name: String
    let logo: String
    let pinyin: String
}

struct Series: Identifiable, Hashable {
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
}

// MARK: - Filters

struct Filters: Equatable {
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
    var fixedPrice = false
    var testReport = false
    var dcdSelf = false      // dcd_self_sh=1   懂车帝自营（网页版叫“懂懂二手车”）
    var cert4S = false       // car_source_types=1  4S店专区
    var video = false        // has_related_video=1 视频看车
    var keyword = ""   // local title filter (fallback when keyword is not a brand/series)

    var params: [String: String] {
        var p: [String: String] = ["sh_city_name": city]
        if let brand { p["brand"] = "\(brand.id)" }
        if let series { p["series_ids"] = "\(series.id)" }
        for o in [price, age, mileage, sort, gearbox, fuel, level, emission].compactMap({ $0 }) { p[o.key] = o.param }
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
        return r
    }
}

struct Option: Hashable {
    let text: String
    let key: String
    let param: String
}

// Values taken from dongchedi.com /usedcar page filter config (verified against sh_sku_list).
enum FilterOptions {
    static let price: [Option] = [("3万以下", "0,3"), ("3-5万", "3,5"), ("5-8万", "5,8"), ("8-10万", "8,10"), ("10-15万", "10,15"), ("15-20万", "15,20"), ("20-30万", "20,30"), ("30-50万", "30,50"), ("50万以上", "50,-1")].map { Option(text: $0.0, key: "price", param: $0.1) }
    static let age: [Option] = [("1年内", "0,1"), ("1-3年", "1,3"), ("3-5年", "3,5"), ("5-8年", "5,8"), ("8-10年", "8,10"), ("10年以上", "10,-1")].map { Option(text: $0.0, key: "age_range", param: $0.1) }
    static let mileage: [Option] = [("1万公里内", "0,1"), ("3万公里内", "0,3"), ("5万公里内", "0,5"), ("6万公里内", "0,6"), ("10万公里内", "0,10")].map { Option(text: $0.0, key: "mileage_range", param: $0.1) }
    static let sort: [Option] = [("默认排序", ""), ("最新上架", "4"), ("价格最低", "1"), ("价格最高", "2"), ("车龄最短", "5"), ("里程最少", "7")].map { Option(text: $0.0, key: "sort_type", param: $0.1) }
    static let gearbox: [Option] = [("手动", "1"), ("自动", "2")].map { Option(text: $0.0, key: "gearbox_type", param: $0.1) }
    static let fuel: [Option] = [("汽油", "1"), ("柴油", "2"), ("纯电动", "4"), ("油电混合", "3"), ("插电混动", "6"), ("增程式", "5"), ("新能源", "4,5,6")].map { Option(text: $0.0, key: "fuel_form", param: $0.1) }
    static let level: [Option] = [("轿车", "0"), ("SUV", "1"), ("MPV", "2"), ("跑车", "4"), ("皮卡", "3")].map { Option(text: $0.0, key: "series_type", param: $0.1) }
    static let emission: [Option] = [("国四", "2"), ("国五", "5"), ("国六", "7")].map { Option(text: $0.0, key: "environmental_standards", param: $0.1) }
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
            year: info["year"] as? Int ?? 0)
    }
}

extension Double {
    var wan: String {
        let s = String(format: "%.2f", self)
        return (s.hasSuffix(".00") ? String(s.dropLast(3)) : s) + "万"
    }
}
