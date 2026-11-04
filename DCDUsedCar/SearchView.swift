import SwiftUI

let dcdRed = Color(red: 1, green: 0.27, blue: 0.2)
let dcdYellow = Color(red: 1, green: 0.85, blue: 0.0)

struct SearchView: View {
    @State private var keyword = ""
    @State private var city = "北京"
    @State private var brand: (String, Int?) = ("品牌", nil)
    @State private var price: (String, String?) = ("价格", nil)
    @State private var sort: (String, Int) = ("排序", 0)
    @State private var cars: [Car] = []
    @State private var page = 1
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?

    // brand ids verified against API: 2 奥迪, 3 奔驰, 5 丰田
    let brands: [(String, Int?)] = [("不限", nil), ("奥迪", 2), ("奔驰", 3), ("丰田", 5)]
    let prices: [(String, String?)] = [("不限", nil), ("5万内", "0,5"), ("5-10万", "5,10"), ("10-15万", "10,15"), ("15-20万", "15,20"), ("20-30万", "20,30"), ("30-50万", "30,50"), ("50万以上", "50,10000")]
    let sorts: [(String, Int)] = [("默认排序", 0), ("价格最高", 2), ("推荐", 3)]
    let cities = ["全国", "北京", "上海", "广州", "深圳", "杭州", "成都", "重庆", "武汉", "南京", "西安", "天津", "苏州", "郑州", "长沙"]

    var shown: [Car] {
        let k = keyword.trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? cars : cars.filter { $0.title.localizedCaseInsensitiveContains(k) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // top search bar
                HStack(spacing: 10) {
                    Menu { ForEach(cities, id: \.self) { c in Button(c) { city = c; reload() } } } label: {
                        HStack(spacing: 2) { Text(city).font(.system(size: 15, weight: .medium)); Image(systemName: "chevron.down").font(.system(size: 10)) }.foregroundColor(.black)
                    }
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("搜索车系，如 卡罗拉", text: $keyword).submitLabel(.search).onSubmit(reload)
                    }.padding(.horizontal, 12).frame(height: 34).background(Color(white: 0.95)).clipShape(Capsule())
                }.padding(.horizontal, 12).padding(.vertical, 8)

                // filter bar
                HStack {
                    filter(brand.0) { ForEach(brands, id: \.0) { b in Button(b.0) { brand = (b.1 == nil ? "品牌" : b.0, b.1); reload() } } }
                    filter(price.0) { ForEach(prices, id: \.0) { p in Button(p.0) { price = (p.1 == nil ? "价格" : p.0, p.1); reload() } } }
                    filter(sort.0) { ForEach(sorts, id: \.0) { s in Button(s.0) { sort = (s.1 == 0 ? "排序" : s.0, s.1); reload() } } }
                }.padding(.vertical, 10).background(Color.white)
                Divider()
                Text("非官方个人工具 · 数据来自懂车帝网页").font(.system(size: 11)).foregroundColor(.gray).padding(4)

                List {
                    ForEach(shown) { c in
                        Link(destination: c.url) { CarRow(car: c) }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                    if hasMore {
                        HStack { Spacer(); if loading { ProgressView() } else { Text("加载更多").foregroundColor(.gray) }; Spacer() }
                            .onAppear { if !loading { load() } }
                    }
                    if let error { Text(error).foregroundColor(.red).font(.footnote) }
                    if !loading && shown.isEmpty && !cars.isEmpty { Text("当前已加载车源中没有“\(keyword)”，可选择品牌或下拉加载更多").font(.footnote).foregroundColor(.gray) }
                }.listStyle(.plain).refreshable { reload() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(.black)
        .onAppear { if cars.isEmpty { reload() } }
    }

    func filter<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        Menu(content: content) {
            HStack(spacing: 3) { Text(title).font(.system(size: 14)); Image(systemName: "arrowtriangle.down.fill").font(.system(size: 7)) }
                .foregroundColor(.black).frame(maxWidth: .infinity)
        }
    }

    func reload() { cars = []; page = 1; hasMore = false; load() }
    func load() {
        loading = true; error = nil
        let p = page
        Task {
            do {
                let r = try await API.search(city: city, brand: brand.1, price: price.1, sort: sort.1, page: p)
                cars += r.cars; hasMore = r.hasMore; page = p + 1
            } catch { self.error = "加载失败（可能被限流），请稍后下拉刷新" }
            loading = false
        }
    }
}

struct CarRow: View {
    let car: Car
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: URL(string: car.image)) { $0.resizable().scaledToFill() } placeholder: { Color(white: 0.93) }
                .frame(width: 120, height: 84).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 6) {
                Text(car.title).font(.system(size: 15, weight: .medium)).foregroundColor(.black).lineLimit(2)
                Text([car.sub.replacingOccurrences(of: " | ", with: " · "), car.city].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundColor(.gray)
                Text(car.price).font(.system(size: 17, weight: .semibold)).foregroundColor(dcdRed)
            }
            Spacer(minLength: 0)
        }
    }
}
