import SwiftUI

@main struct DCDUsedCarApp: App {
    var body: some Scene { WindowGroup { SearchView() } }
}

// MARK: - API (unofficial; endpoint used by dongchedi.com web)
struct Car: Identifiable, Hashable {
    let id: Int64; let title: String; let image: String; let price: String
    let sub: String; let city: String; let year: Int
    var url: URL { URL(string: "https://m.dongchedi.com/usedcar/\(id)")! }
}

enum API {
    // Custom-font digit obfuscation (PUA codepoints). May change; verify if prices look wrong.
    static let map: [UInt32: String] = [58425:"0",58700:"1",58467:"2",58525:"3",58397:"4",58385:"5",58676:"6",58347:"7",58595:"8",58461:"9",58378:"万",58661:"年",58514:"公",58536:"里",58618:"日"]
    static func dec(_ s: String?) -> String {
        (s ?? "").unicodeScalars.map { map[$0.value] ?? String($0) }.joined()
    }
    static func search(city: String, brand: Int?, price: String?, sort: Int, page: Int) async throws -> (cars: [Car], hasMore: Bool) {
        var req = URLRequest(url: URL(string: "https://www.dongchedi.com/motor/pc/sh/sh_sku_list?aid=1839&app_name=auto_web_pc")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36", forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.dongchedi.com/usedcar", forHTTPHeaderField: "Referer")
        var p = ["sh_city_name": city, "page": "\(page)", "limit": "60", "sort_type": "\(sort)"]
        if let brand { p["brand"] = "\(brand)" }
        if let price { p["price"] = price }
        var c = URLComponents(); c.queryItems = p.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = c.percentEncodedQuery?.data(using: .utf8)
        for attempt in 0..<4 {   // server sometimes returns 403 (rate limit); back off and retry
            let (data, resp) = try await URLSession.shared.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200,
               let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let d = j["data"] as? [String: Any] {
                let list = d["search_sh_sku_info_list"] as? [[String: Any]] ?? []
                let cars = list.map { x in Car(
                    id: (x["sku_id"] as? NSNumber)?.int64Value ?? 0,
                    title: x["title"] as? String ?? "",
                    image: x["image"] as? String ?? "",
                    price: dec(x["sh_price"] as? String),
                    sub: dec(x["sub_title"] as? String),
                    city: x["car_source_city_name"] as? String ?? "",
                    year: x["car_year"] as? Int ?? 0) }
                return (cars, d["has_more"] as? Bool ?? false)
            }
            try await Task.sleep(nanoseconds: UInt64(2 + attempt * 2) * 1_000_000_000)
        }
        throw URLError(.badServerResponse)
    }
}
