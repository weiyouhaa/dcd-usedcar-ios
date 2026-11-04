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
    var keyword = ""   // local title filter (fallback when keyword is not a brand/series)

    var params: [String: String] {
        var p: [String: String] = ["sh_city_name": city]
        if let brand { p["brand"] = "\(brand.id)" }
        if let series { p["series_ids"] = "\(series.id)" }
        for o in [price, age, mileage, sort, gearbox, fuel, level, emission].compactMap({ $0 }) { p[o.key] = o.param }
        if fixedPrice { p["is_fixed_price"] = "1" }
        if testReport { p["third_party_test_report"] = "1" }
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

    static func request(_ path: String, query: [String: String] = [:], form: [String: String]? = nil) async throws -> [String: Any] {
        var c = URLComponents(string: base + path)!
        var q = [URLQueryItem(name: "aid", value: "1839"), URLQueryItem(name: "app_name", value: "auto_web_pc")]
        q += query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        c.queryItems = q
        var req = URLRequest(url: c.url!, timeoutInterval: 20)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.dongchedi.com/usedcar", forHTTPHeaderField: "Referer")
        if let form {
            req.httpMethod = "POST"
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var fc = URLComponents()
            fc.queryItems = form.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            req.httpBody = fc.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        }
        var lastError: Error = APIError.server
        for attempt in 0..<4 {   // the server sometimes answers 403 (rate limit); back off and retry
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if (resp as? HTTPURLResponse)?.statusCode == 200,
                   let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return j
                }
            } catch { lastError = error }
            try await Task.sleep(nanoseconds: UInt64(1_500_000_000) * UInt64(attempt + 1))
        }
        throw lastError
    }

    static func tags(_ any: Any?) -> [CarTag] {
        (any as? [[String: Any]] ?? []).compactMap { t in
            guard let text = t["text"] as? String, !text.isEmpty else { return nil }
            return CarTag(text: text, textColor: t["text_color"] as? String ?? "", bgColor: t["background_color"] as? String ?? "")
        }
    }

    static func search(_ f: Filters, page: Int) async throws -> (cars: [Car], hasMore: Bool, total: Int) {
        var form = f.params
        form["page"] = "\(page)"
        form["limit"] = "40"
        let j = try await request("/motor/pc/sh/sh_sku_list", form: form)
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
                sourceType: x["car_source_type"] as? String ?? "")
        }
        return (cars, d["has_more"] as? Bool ?? false, d["total"] as? Int ?? 0)
    }

    static var brandCache: (all: [Brand], hot: [Brand])?
    static func brands() async throws -> (all: [Brand], hot: [Brand]) {
        if let brandCache { return brandCache }
        let j = try await request("/motor/pc/car/brand/all_brand")
        guard let d = j["data"] as? [String: Any] else { throw APIError.server }
        func parse(_ a: Any?) -> [Brand] {
            (a as? [[String: Any]] ?? []).compactMap { e in
                guard let i = e["info"] as? [String: Any], let id = i["brand_id"] as? Int, let n = i["brand_name"] as? String else { return nil }
                return Brand(id: id, name: n, logo: https(i["image_url"] as? String ?? ""), pinyin: i["pinyin"] as? String ?? "#")
            }
        }
        let r = (parse(d["brand"]), parse(d["hot_brand"]))
        brandCache = r
        return r
    }

    static func series(brand: Int, city: String) async throws -> [Series] {
        let j = try await request("/motor/pc/sh/sh_series_list", query: ["brand_id": "\(brand)", "sh_city_name": city])
        return (j["data"] as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["series_id"] as? Int, let n = s["series_name"] as? String else { return nil }
            return Series(id: id, name: n, image: https(s["image_url"] as? String ?? ""))
        }
    }

    static func suggest(_ kw: String) async throws -> [Suggestion] {
        var c = URLComponents(string: base + "/motor/searchacl/complete")!
        c.queryItems = [URLQueryItem(name: "motor_source", value: "pc_new"), URLQueryItem(name: "keyword", value: kw)]
        var req = URLRequest(url: c.url!, timeoutInterval: 10)
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
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
