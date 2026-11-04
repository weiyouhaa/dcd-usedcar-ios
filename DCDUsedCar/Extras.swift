import SwiftUI

// MARK: - 我的：收藏 / 浏览记录 / 对比清单
struct MinePage: View {
    @ObservedObject private var store = Store.shared
    @State var tab: Int
    @State private var showCompare = false
    @State private var confirmClear = false
    init(initialTab: Int = 0) { _tab = State(initialValue: initialTab) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("收藏", store.favorites.count, 0)
                tabButton("浏览记录", store.history.count, 1)
                tabButton("对比清单", store.compare.count, 2)
            }
            .padding(.horizontal, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            content
            if tab == 2 && !store.compare.isEmpty {
                HStack {
                    Text("已选 \(store.compare.count)/4 辆，2 辆起可对比").font(.system(size: 13)).foregroundColor(Theme.text2)
                    Spacer()
                    Button { Haptics.tap(); showCompare = true } label: {
                        Text("开始对比").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.onYellow)
                            .padding(.horizontal, 22).frame(height: 40).background(store.compare.count >= 2 ? Theme.yellow : Theme.chipBg).clipShape(Capsule())
                    }
                    .disabled(store.compare.count < 2)
                }
                .padding(.horizontal, 16).padding(.vertical, 8).background(Theme.card)
                .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            }
        }
        .background(Theme.card)
        .navigationTitle("我的").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if currentCount > 0 { Button("清空") { confirmClear = true }.foregroundColor(Theme.text2) }
            }
        }
        .confirmationDialog(clearTitle, isPresented: $confirmClear, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                Haptics.success()
                switch tab { case 0: store.clearFavorites(); case 1: store.clearHistory(); default: store.clearCompare() }
            }
        }
        .navigationDestination(for: Car.self) { c in DetailView(skuId: c.id, city: c.city.isEmpty ? "全国" : c.city, preview: c) }
        .navigationDestination(isPresented: $showCompare) { CompareView(cars: store.compare) }
        .task {
            await store.refreshPrices()
            if LaunchArgs.flag("compare") && store.compare.count >= 2 { tab = 2; showCompare = true }
        }
    }

    var currentCount: Int { [store.favorites.count, store.history.count, store.compare.count][tab] }
    var clearTitle: String { ["清空全部 \(store.favorites.count) 个收藏？", "清空全部浏览记录？", "清空对比清单？"][tab] }

    @ViewBuilder var content: some View {
        if currentCount == 0 {
            emptyState
        } else {
            List {
                switch tab {
                case 0:
                    ForEach(store.favorites, id: \.car.id) { f in
                        row(f.car) { priceChange(f).padding(.leading, 14 + 124 + 12).padding(.bottom, 10).padding(.top, -6) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Haptics.tap(); store.removeFav([f.car.id]) } label: { Label("取消收藏", systemImage: "heart.slash") }
                            }
                            .swipeActions(edge: .leading) { compareAction(f.car) }
                    }
                case 1:
                    ForEach(store.history) { c in
                        row(c) { EmptyView() }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Haptics.tap(); store.removeHistory(c.id) } label: { Label("删除", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) { compareAction(c) }
                    }
                default:
                    ForEach(store.compare) { c in
                        row(c, fav: false) { EmptyView() }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Haptics.tap(); store.removeCompare(c.id) } label: { Label("移出", systemImage: "minus.circle") }
                            }
                    }
                }
                Text(tab == 2 ? "左滑可移出对比清单" : "左滑删除 · 右滑加入对比")
                    .font(.system(size: 11)).foregroundColor(Theme.faint).frame(maxWidth: .infinity).padding(.vertical, 14)
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    func row<Extra: View>(_ c: Car, fav: Bool = true, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            CarRow(car: c, showFav: fav)
            extra()
        }
        .background(NavigationLink(value: c) { EmptyView() }.opacity(0))
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.card)
    }

    @ViewBuilder func compareAction(_ c: Car) -> some View {
        if store.inCompare(c.id) {
            Button { Haptics.tap(); store.removeCompare(c.id) } label: { Label("移出对比", systemImage: "minus.square") }.tint(.gray)
        } else {
            Button {
                if store.addCompare(c) { Haptics.success(); Toast.shared.show("已加入对比（\(store.compare.count)/4）") }
                else { Toast.shared.show("对比清单最多 4 辆") }
            } label: { Label("加入对比", systemImage: "plus.square.on.square") }.tint(Color(hex: 0xFFB300))
        }
    }

    var emptyState: some View {
        let (icon, title, sub) = [
            ("heart", "还没有收藏的车源", "在列表或详情页点 ♡ 即可收藏，降价会在这里提醒"),
            ("clock", "暂无浏览记录", "看过的车源会自动出现在这里"),
            ("square.on.square", "对比清单是空的", "在详情页底部点「对比」，或在收藏里右滑加入"),
        ][tab]
        return VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundColor(Theme.faint)
            Text(title).font(.system(size: 16, weight: .medium)).foregroundColor(Theme.text)
            Text(sub).font(.system(size: 13)).foregroundColor(Theme.gray).multilineTextAlignment(.center)
            Button { AppState.shared.tab = 0 } label: {
                Text("去逛逛").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.onYellow)
                    .padding(.horizontal, 28).frame(height: 40).background(Theme.yellow).clipShape(Capsule())
            }.padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .offset(y: -30)
    }

    func tabButton(_ t: String, _ n: Int, _ i: Int) -> some View {
        Button { if tab != i { Haptics.select(); tab = i } } label: {
            VStack(spacing: 6) {
                HStack(spacing: 3) {
                    Text(t).font(.system(size: 16, weight: tab == i ? .semibold : .regular))
                    if n > 0 { Text("\(n)").font(.system(size: 12, weight: .medium)).foregroundColor(tab == i ? Theme.text2 : Theme.gray) }
                }
                .foregroundColor(tab == i ? Theme.text : Theme.text2)
                Capsule().fill(tab == i ? Theme.yellow : .clear).frame(width: 22, height: 3)
            }
            .frame(maxWidth: .infinity).frame(height: 46).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder func priceChange(_ f: Store.Fav) -> some View {
        let df = DateFormatter(); let _ = df.dateFormat = "M月d日"
        if let now = store.latest[f.car.id] {
            let a = Double(f.savedPrice.replacingOccurrences(of: "万", with: "")) ?? 0
            let b = Double(now.replacingOccurrences(of: "万", with: "")) ?? 0
            if now.isEmpty { tag("已下架", Theme.gray) }
            else if b < a - 0.001 { tag("↓ 比收藏时降 \((a - b).wan)（\(df.string(from: f.savedAt)) \(f.savedPrice) → \(now)）", Theme.green) }
            else if b > a + 0.001 { tag("↑ 比收藏时涨 \((b - a).wan)（\(f.savedPrice) → \(now)）", Theme.price) }
            else { tag("价格未变 · \(df.string(from: f.savedAt))收藏", Theme.gray) }
        } else {
            tag("\(df.string(from: f.savedAt))收藏 · 价格检查中…", Theme.gray)
        }
    }
    func tag(_ t: String, _ c: Color) -> some View { Text(t).font(.system(size: 11)).foregroundColor(c).lineLimit(1) }
}

// MARK: - 车源对比
struct CompareView: View {
    let cars: [Car]
    @State private var details: [CarDetail?] = []
    @State private var cfg: FullConfig?
    @State private var error: String?
    @State private var hideSame = true
    let nameW: CGFloat = 80
    /// Up to 3 cars fit on screen without horizontal scrolling; 4 scroll.
    var colW: CGFloat { max(96, (UIScreen.main.bounds.width - nameW) / CGFloat(min(max(cars.count, 1), 3))) }

    var body: some View {
        ScrollView([.vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("隐藏相同项", isOn: $hideSame).font(.system(size: 14)).tint(Color(hex: 0xFFB300)).padding(.horizontal, 16).padding(.vertical, 8)
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            Text("").frame(width: nameW)
                            ForEach(cars.indices, id: \.self) { i in
                                NavigationLink(value: cars[i]) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        RemoteImage(url: cars[i].image, mode: .fill, maxPoints: 240).frame(width: colW - 12, height: (colW - 12) * 0.68).clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(cars[i].title).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.text).lineLimit(3).multilineTextAlignment(.leading)
                                        Text(cars[i].price).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.price)
                                    }.frame(width: colW - 12, alignment: .leading).padding(.horizontal, 6)
                                }
                            }
                        }.padding(.bottom, 8)
                        section("车源信息", baseRows)
                        if let cfg {
                            ForEach(cfg.groups.indices, id: \.self) { g in section(cfg.groups[g].name, cfg.groups[g].rows.map { ($0.name, $0.values) }) }
                        } else if let error {
                            Text(error).font(.system(size: 13)).foregroundColor(Theme.gray).padding(16)
                        } else {
                            ProgressView().padding(30)
                        }
                    }
                }
            }
        }
        .background(Theme.card)
        .navigationTitle("车源对比").navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    var baseRows: [(String, [String])] {
        func col(_ f: (CarDetail) -> String) -> [String] { cars.indices.map { i in (i < details.count ? details[i] : nil).map(f) ?? "…" } }
        func imp(_ i: Int) -> (CarDetail) -> String { { $0.importantText.count > i ? $0.importantText[i] : "-" } }
        return [
            ("售价", cars.map(\.price)),
            ("新车指导价", col { $0.officialPrice.isEmpty ? "-" : $0.officialPrice }),
            ("上牌", col(imp(0))),
            ("里程", col(imp(1))),
            ("车源地", col(imp(2))),
            ("价格评估", col { $0.priceTips.isEmpty ? "-" : $0.priceTips }),
            ("检测报告", col { $0.hasReport ? "有" : "无" }),
            ("车身颜色", col { $0.bodyColor.isEmpty ? "-" : $0.bodyColor }),
        ] + paramRows
    }
    var paramRows: [(String, [String])] {
        let names = details.compactMap { $0 }.flatMap { $0.params.map(\.name) }
        var seen = Set<String>(); let uniq = names.filter { seen.insert($0).inserted && !["上牌时间", "表显里程", "车身颜色"].contains($0) }
        return uniq.map { n in (n, cars.indices.map { i in (i < details.count ? details[i] : nil)?.params.first { $0.name == n }?.value ?? "-" }) }
    }

    @ViewBuilder func section(_ title: String, _ rows: [(String, [String])]) -> some View {
        let shown = hideSame ? rows.filter { Set($0.1).count > 1 } : rows
        if !shown.isEmpty {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text2)
                .padding(.horizontal, 12).frame(width: nameW + colW * CGFloat(cars.count), height: 30, alignment: .leading).background(Theme.bg)
            ForEach(shown.indices, id: \.self) { r in
                HStack(spacing: 0) {
                    Text(shown[r].0).font(.system(size: 12)).foregroundColor(Theme.gray).frame(width: nameW - 12, alignment: .leading).padding(.leading, 12)
                    ForEach(shown[r].1.indices, id: \.self) { i in
                        Text(shown[r].1[i]).font(.system(size: 12)).foregroundColor(Theme.text).frame(width: colW - 12, alignment: .leading).padding(.horizontal, 6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
            }
        }
    }

    func load() async {
        var ds: [CarDetail?] = []
        for c in cars { ds.append(try? await DetailCache.shared.get(c.id, city: c.city.isEmpty ? "全国" : c.city)) }
        details = ds
        let ids = ds.map { $0?.carId ?? 0 }
        guard ids.allSatisfy({ $0 > 0 }) else { error = "部分车源已下架，无法对比参数配置"; return }
        do { cfg = try await API.fullConfig(ids) } catch { self.error = "参数配置加载失败，请稍后重试" }
    }
}

// MARK: - 全部参数配置
struct FullConfigView: View {
    let carId: Int
    let title: String
    @State private var cfg: FullConfig?
    @State private var error: String?
    @State private var group = 0

    var body: some View {
        VStack(spacing: 0) {
            if let cfg {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(cfg.groups.indices, id: \.self) { i in
                            Button { group = i } label: {
                                Text(cfg.groups[i].name).font(.system(size: 13, weight: group == i ? .semibold : .regular))
                                    .foregroundColor(group == i ? Theme.selText : Theme.text2)
                                    .padding(.horizontal, 10).frame(height: 28).background(group == i ? Theme.selBg : Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            Text(cfg.carNames.first ?? title).font(.system(size: 13)).foregroundColor(Theme.gray).padding(.horizontal, 16).padding(.vertical, 6)
                            ForEach(cfg.groups.indices, id: \.self) { g in
                                    Text(cfg.groups[g].name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                                        .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 34, alignment: .leading).background(Theme.bg).id("h\(g)")
                                    ForEach(cfg.groups[g].rows.indices.map { "\(g)-\($0)" }, id: \.self) { key in
                                        let row = cfg.groups[g].rows[Int(key.split(separator: "-")[1])!]
                                        HStack(alignment: .top) {
                                            Text(row.name).font(.system(size: 14)).foregroundColor(Theme.gray).frame(width: 120, alignment: .leading)
                                            Text(row.values.first ?? "-").font(.system(size: 14)).foregroundColor(row.values.first == "-" ? Theme.faint : Theme.text)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .padding(.horizontal, 16).padding(.vertical, 9)
                                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 16) }
                                    }
                            }
                            Text("● 标配  ○ 选配  - 无 · 数据来自懂车帝").font(.system(size: 11)).foregroundColor(Theme.gray).frame(maxWidth: .infinity).padding(16)
                        }
                    }
                    .onChange(of: group) { g in withAnimation { proxy.scrollTo("h\(g)", anchor: .top) } }
                }
            } else if let error {
                Spacer()
                Text(error).font(.system(size: 14)).foregroundColor(Theme.gray)
                Button("重试") { Task { await load() } }.padding(8)
                Spacer()
            } else { Spacer(); ProgressView(); Spacer() }
        }
        .background(Theme.card)
        .navigationTitle("参数配置").navigationBarTitleDisplayMode(.inline)
        .task { if cfg == nil { await load() } }
    }
    func load() async {
        error = nil
        do { cfg = try await API.fullConfig([carId]) } catch { self.error = "加载失败（可能被限流），请重试" }
    }
}

// MARK: - 价格分析报告
struct PriceAnalysisView: View {
    let sku: Int64
    @State private var a: PriceAnalysis?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let a {
                    box {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(a.price.wan).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.price)
                                if !a.tips.isEmpty {
                                    Text(a.tips).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.selText)
                                        .padding(.horizontal, 8).frame(height: 24).background(Theme.selBg).clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            Text([a.carAge, a.mileage].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.gray)
                            if a.max > a.min { rangeBar(a) }
                            if !a.desc.isEmpty { Text(a.desc).font(.system(size: 13)).foregroundColor(Theme.text2).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                    box("同类车源对比") {
                        VStack(spacing: 0) {
                            if a.sameYear.0 > 0 { cmpRow("同车系同年份", a.sameYear) }
                            if a.sameMileage.0 > 0 { cmpRow("同车系相近里程", a.sameMileage) }
                        }
                    }
                    if a.views + a.favs + a.clues > 0 {
                        box("车源热度") {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    stat("\(a.views)", "浏览"); stat("\(a.favs)", "收藏"); stat("\(a.clues)", "咨询")
                                }
                                if !a.heatText.isEmpty { Text(a.heatText).font(.system(size: 12)).foregroundColor(Theme.gray) }
                            }
                        }
                    }
                    ForEach(a.tables.indices, id: \.self) { i in box(a.tables[i].0) { bars(a.tables[i].1) } }
                    Text("数据来自懂车帝价格分析，仅供参考").font(.system(size: 11)).foregroundColor(Theme.gray).padding(.vertical, 12)
                } else if let error {
                    Text(error).font(.system(size: 14)).foregroundColor(Theme.gray).padding(.top, 60)
                    Button("重试") { Task { await load() } }
                } else { ProgressView().padding(.top, 80) }
            }.padding(.top, 10)
        }
        .background(Theme.bg)
        .navigationTitle("价格分析").navigationBarTitleDisplayMode(.inline)
        .task { if a == nil { await load() } }
    }
    func load() async {
        error = nil
        do { a = try await API.priceAnalysis(sku: sku) } catch APIError.empty { error = "该车源暂无价格分析" } catch { self.error = "加载失败（可能被限流），请重试" }
    }

    func box<C: View>(_ title: String? = nil, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text) }
            c()
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 10)).padding(.horizontal, 10)
    }
    func rangeBar(_ a: PriceAnalysis) -> some View {
        let pos = { (v: Double) -> CGFloat in CGFloat(max(0, min(1, (v - a.min) / (a.max - a.min)))) }
        return VStack(spacing: 6) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [Theme.green, Color(hex: 0xFFC933), Theme.price], startPoint: .leading, endPoint: .trailing)).frame(height: 8).offset(y: 14)
                    marker("本车", a.price, Theme.price).offset(x: pos(a.price) * g.size.width - 20)
                    if a.avg > 0 { tick(g.size.width * pos(a.avg)) }
                }
            }.frame(height: 30)
            HStack {
                Text("最低 \(a.min.wan)"); Spacer()
                if a.avg > 0 { Text("均价 \(a.avg.wan)") }; Spacer()
                Text("最高 \(a.max.wan)")
            }.font(.system(size: 11)).foregroundColor(Theme.gray)
        }
    }
    func marker(_ t: String, _ v: Double, _ c: Color) -> some View {
        VStack(spacing: 0) {
            Text(t).font(.system(size: 10, weight: .semibold)).foregroundColor(.white).padding(.horizontal, 4).frame(height: 14).background(c).clipShape(RoundedRectangle(cornerRadius: 3))
            Circle().fill(c).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
        }.frame(width: 40)
    }
    func tick(_ x: CGFloat) -> some View { Rectangle().fill(Theme.text).frame(width: 2, height: 14).offset(x: x - 1, y: 11) }
    func cmpRow(_ t: String, _ v: (Int, Double, Double, Double)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(t).font(.system(size: 14)).foregroundColor(Theme.text)
                Text("共 \(v.0) 辆在售").font(.system(size: 11)).foregroundColor(Theme.gray)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(v.1.wan) - \(v.2.wan)").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                if v.3 > 0 { Text("均价 \(v.3.wan)").font(.system(size: 11)).foregroundColor(Theme.gray) }
            }
        }
        .padding(.vertical, 10).overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }
    func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
            Text(l).font(.system(size: 12)).foregroundColor(Theme.gray)
        }.frame(maxWidth: .infinity)
    }
    func bars(_ b: PriceAnalysis.Bars) -> some View {
        let mx = max(1, b.y.max() ?? 1)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(b.x.indices, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text("\(b.y[i])").font(.system(size: 9)).foregroundColor(Theme.gray)
                        RoundedRectangle(cornerRadius: 3).fill(Color(hex: 0xFFC933)).frame(height: max(2, 90 * CGFloat(b.y[i]) / CGFloat(mx)))
                        Text(b.x[i]).font(.system(size: 9)).foregroundColor(Theme.text2).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(height: 130, alignment: .bottom)
            if !b.unit.isEmpty { Text("单位：\(b.unit)").font(.system(size: 10)).foregroundColor(Theme.gray) }
        }
    }
}

// MARK: - 贷款计算器（基于本车真实售价；默认首付比例/期数来自懂车帝分期方案）
struct LoanSheet: View {
    let price: Double          // 万
    let defaultRatio: Int      // 0-10 (3 = 30%)
    let defaultMonths: Int
    let officialMonthPay: Double
    let officialDown: Double
    @Environment(\.dismiss) private var dismiss
    @State private var ratio: Int
    @State private var months: Int
    @State private var rateText: String

    init(price: Double, ratio: Int, months: Int, officialMonthPay: Double, officialDown: Double) {
        self.price = price; defaultRatio = ratio; defaultMonths = months; self.officialMonthPay = officialMonthPay; self.officialDown = officialDown
        let r = ratio > 0 ? ratio : 3, n = months > 0 ? months : 36
        _ratio = State(initialValue: r); _months = State(initialValue: n)
        let loan = (price - (officialDown > 0 ? officialDown : price * Double(r) / 10)) * 10000
        let apr = LoanSheet.impliedAPR(loan: loan, months: n, pay: officialMonthPay)
        _rateText = State(initialValue: String(format: "%.1f", apr ?? 6.0))
    }

    static func monthly(_ loan: Double, _ n: Int, _ apr: Double) -> Double {
        let r = apr / 100 / 12
        return r == 0 ? loan / Double(n) : loan * r * pow(1 + r, Double(n)) / (pow(1 + r, Double(n)) - 1)
    }
    /// Back-solve the annual rate implied by 懂车帝's own 方案 (down payment + month pay + cycle).
    static func impliedAPR(loan: Double, months: Int, pay: Double) -> Double? {
        guard loan > 0, pay > 0, months > 0, pay * Double(months) > loan else { return nil }
        var lo = 0.0, hi = 60.0
        for _ in 0..<60 { let mid = (lo + hi) / 2; if monthly(loan, months, mid) > pay { hi = mid } else { lo = mid } }
        return (lo + hi) / 2
    }

    var body: some View {
        let down = price * Double(ratio) / 10
        let loan = (price - down) * 10000
        let apr = Double(rateText) ?? 0
        let m = LoanSheet.monthly(loan, months, apr)
        NavigationStack {
            Form {
                Section {
                    HStack { Text("车辆售价"); Spacer(); Text(price.wan).foregroundColor(Theme.price).bold() }
                    Picker("首付比例", selection: $ratio) { ForEach(1..<10) { Text("\($0 * 10)%").tag($0) } }
                    Picker("贷款期限", selection: $months) { ForEach([12, 24, 36, 48, 60], id: \.self) { Text("\($0)期（\($0 / 12)年）").tag($0) } }
                    HStack { Text("年利率"); Spacer(); TextField("", text: $rateText).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70); Text("%") }
                }
                Section("测算结果") {
                    row("首付", down.wan)
                    row("贷款金额", (loan / 10000).wan)
                    row("月供", loan > 0 ? String(format: "%.0f 元", m) : "-", strong: true)
                    row("总利息", loan > 0 ? String(format: "%.0f 元", m * Double(months) - loan) : "-")
                }
                Section {
                    if officialMonthPay > 0 {
                        Text("懂车帝常规方案：首付 \(officialDown > 0 ? officialDown.wan : "-")，\(defaultMonths)期，月供 \(Int(officialMonthPay)) 元。默认年利率按该方案反推，可自行修改。实际方案以金融机构审批为准。")
                    } else {
                        Text("该车源无懂车帝分期方案，默认年利率 6%，可自行修改。仅供参考。")
                    }
                }.font(.system(size: 12)).foregroundColor(Theme.gray)
            }
            .navigationTitle("贷款计算器").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
    func row(_ k: String, _ v: String, strong: Bool = false) -> some View {
        HStack { Text(k); Spacer(); Text(v).foregroundColor(strong ? Theme.price : Theme.text).fontWeight(strong ? .bold : .regular) }
    }
}
