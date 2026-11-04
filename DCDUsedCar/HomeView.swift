import SwiftUI

enum Panel: String, CaseIterable, Identifiable {
    case sort, brand, price, age, mileage, more
    var id: String { rawValue }
}

@MainActor final class ListModel: ObservableObject {
    @Published var filters = Filters()
    @Published var cars: [Car] = []
    @Published var total = 0
    @Published var hasMore = false
    @Published var loading = false
    @Published var fromCache = false
    @Published var error: String?
    @Published var hotBrands: [Brand] = []
    @Published var allBrands: [Brand] = []
    /// Series of the selected brand (sh_series_list) and their live listing counts.
    @Published var series: [Series] = []
    @Published var seriesBrand: Int?
    @Published var seriesLoading = false
    @Published var seriesCounts: [Int: Int] = [:]
    private var countsKey = ""
    private var page = 1
    private var generation = 0
    private var prefetched: (gen: Int, page: Int, task: Task<(cars: [Car], hasMore: Bool, total: Int), Error>)?
    private var loadTask: Task<Void, Never>?

    var shown: [Car] {
        let k = filters.keyword.trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? cars : cars.filter { $0.title.localizedCaseInsensitiveContains(k) }
    }

    func reload() {
        generation += 1
        loadTask?.cancel(); prefetched?.task.cancel(); prefetched = nil
        page = 1; hasMore = false; fromCache = false
        // Paint the last cached first page for these filters instantly, then refresh.
        if let c = API.cachedSearch(filters) {
            cars = c.cars; total = c.total; hasMore = false; fromCache = true
            API.log("list painted from disk cache (\(c.cars.count) cars)")
        } else {
            cars = []; total = 0
        }
        loadMore(force: true)
    }

    func loadMore(force: Bool = false) {
        if loading && !force { return }
        loading = true; error = nil
        let gen = generation, p = page, f = filters
        let t0 = Date()
        loadTask = Task {
            do {
                let r: (cars: [Car], hasMore: Bool, total: Int)
                if let pf = prefetched, pf.gen == gen, pf.page == p { r = try await pf.task.value; prefetched = nil }
                else { r = try await API.search(f, page: p) }
                guard gen == generation else { return }
                if p == 1 { cars = [] ; fromCache = false }
                let existing = Set(cars.map(\.id))
                cars += r.cars.filter { !existing.contains($0.id) }
                hasMore = r.hasMore && !r.cars.isEmpty
                total = r.total
                page = p + 1
                API.log("page \(p) shown after \(Int(Date().timeIntervalSince(t0) * 1000))ms")
                loading = false
                if hasMore { prefetch(gen: gen, page: p + 1, f: f) }
            } catch {
                guard gen == generation, !(error is CancellationError) else { return }
                if !fromCache { self.error = "网络开小差了（可能被限流），请稍后重试" }
                loading = false
            }
        }
    }

    /// Fetch the next page in the background so scrolling to the bottom appends instantly.
    private func prefetch(gen: Int, page: Int, f: Filters) {
        prefetched = (gen, page, Task { try await API.search(f, page: page) })
    }

    func rowAppeared(_ c: Car) {
        guard hasMore, !loading, let i = cars.lastIndex(where: { $0.id == c.id }), i >= cars.count - 6 else { return }
        loadMore()
    }

    func loadBrands() async {
        guard allBrands.isEmpty, let b = try? await API.brands() else { return }
        allBrands = b.all; hotBrands = b.hot
    }

    func loadSeries(for brand: Brand) async {
        if seriesBrand == brand.id && !series.isEmpty { return }
        seriesBrand = brand.id; series = []; seriesLoading = true
        let r = (try? await API.series(brand: brand.id, city: filters.city)) ?? []
        guard seriesBrand == brand.id else { return }
        series = r; seriesLoading = false
    }

    /// Real on-sale counts per series (limit=1 list queries, 3 at a time, cached 30 min).
    func loadSeriesCounts() async {
        var base = filters; base.series = nil; base.keyword = ""
        let key = "\(base.params)"
        if key != countsKey { seriesCounts = [:]; countsKey = key }
        let todo = series.prefix(40).map(\.id).filter { seriesCounts[$0] == nil }
        await withTaskGroup(of: (Int, Int?).self) { g in
            var it = todo.makeIterator()
            for _ in 0..<3 { if let id = it.next() { g.addTask { (id, await API.seriesCount(base, series: id)) } } }
            for await (id, n) in g {
                if Task.isCancelled { break }
                if let n, key == countsKey { seriesCounts[id] = n }
                if let next = it.next() { g.addTask { (next, await API.seriesCount(base, series: next)) } }
            }
        }
    }
}

struct HomeView: View {
    @StateObject private var m = ListModel()
    @State private var panel: Panel?
    @State private var showCity = false
    @State private var showSearch = false
    @State private var showBrands = false
    @State private var showSeries = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        list
                    }
                    if let panel {
                        Color.black.opacity(0.35).ignoresSafeArea().onTapGesture { withAnimation(.easeOut(duration: 0.15)) { self.panel = nil } }
                        FilterPanel(panel: panel, filters: $m.filters) { apply in
                            withAnimation(.easeOut(duration: 0.15)) { self.panel = nil }
                            if apply { m.reload() }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .clipped()
            }
            .background(Color.white)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Car.self) { DetailView(skuId: $0.id, city: $0.city.isEmpty ? m.filters.city : $0.city, preview: $0) }
            .navigationDestination(for: Int64.self) { DetailView(skuId: $0, city: m.filters.city, preview: nil) }
        }
        .tint(Theme.text)
        .sheet(isPresented: $showCity) {
            CityPicker(current: m.filters.city) { c in m.filters.city = c; m.filters.series = nil; m.reload() }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchPage(model: m) { openSeries in
                m.reload()
                if openSeries { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showSeries = true } }
            }
        }
        .sheet(isPresented: $showBrands) {
            BrandPicker(model: m) { b, s in
                m.filters.brand = b; m.filters.series = s; m.filters.keyword = ""; m.reload()
            }
        }
        .sheet(isPresented: $showSeries) {
            if let b = m.filters.brand {
                NavigationStack {
                    SeriesList(model: m, brand: b) { s in
                        m.filters.series = s; m.filters.keyword = ""; m.reload(); showSeries = false
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showSeries = false } } }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .task {
            if let c = LaunchArgs.value("city") { m.filters.city = c }
            if LaunchArgs.flag("self") { m.filters.dcdSelf = true }
            if let b = LaunchArgs.value("brand"), let id = Int(b) {
                await m.loadBrands()
                m.filters.brand = m.allBrands.first { $0.id == id }
                if let sid = LaunchArgs.value("series").flatMap(Int.init), let br = m.filters.brand {
                    await m.loadSeries(for: br)
                    m.filters.series = m.series.first { $0.id == sid }
                }
            }
            // list and brand requests run in parallel
            if m.cars.isEmpty { m.reload() }
            async let brands: Void = m.loadBrands()
            if LaunchArgs.flag("seriespicker") { showSeries = true }
            if let d = LaunchArgs.value("detail"), let id = Int64(d) { path.append(id) }
            if let p = LaunchArgs.value("panel"), let pp = Panel(rawValue: p) {
                if pp == .brand { showBrands = true } else { panel = pp }
            }
            if LaunchArgs.flag("search") { showSearch = true }
            await brands
        }
    }

    // MARK: header
    var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { showCity = true } label: {
                    HStack(spacing: 2) {
                        Text(m.filters.city).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }.foregroundColor(Theme.text)
                }
                Button { showSearch = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text2)
                        Text(searchLabel).font(.system(size: 14)).foregroundColor(searchLabelActive ? Theme.text : Theme.gray).lineLimit(1)
                        Spacer()
                        if searchLabelActive {
                            Image(systemName: "xmark.circle.fill").foregroundColor(Color(hex: 0xC5C7CF))
                                .onTapGesture { m.filters.keyword = ""; m.filters.series = nil; m.filters.brand = nil; m.reload() }
                        }
                    }
                    .padding(.horizontal, 12).frame(height: 36)
                    .background(Theme.chipBg).clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 10)

            brandRow
            filterBar
            Rectangle().fill(Theme.line).frame(height: 0.5)
        }
        .background(Color.white)
    }

    var searchLabelActive: Bool { m.filters.series != nil || m.filters.brand != nil || !m.filters.keyword.isEmpty }
    var searchLabel: String {
        if !m.filters.keyword.isEmpty { return m.filters.keyword }
        if let s = m.filters.series { return s.name }
        if let b = m.filters.brand { return b.name }
        return "搜索品牌/车系，如 卡罗拉"
    }

    var brandRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(m.hotBrands.prefix(15)) { b in
                    Button {
                        if m.filters.brand?.id == b.id { m.filters.brand = nil } else { m.filters.brand = b; showSeries = true }
                        m.filters.series = nil; m.filters.keyword = ""; m.reload()
                    } label: {
                        VStack(spacing: 4) {
                            RemoteImage(url: b.logo, mode: .fit, maxPoints: 40).frame(width: 32, height: 32)
                            Text(b.name).font(.system(size: 11)).foregroundColor(m.filters.brand?.id == b.id ? Theme.text : Theme.text2)
                                .fontWeight(m.filters.brand?.id == b.id ? .semibold : .regular).lineLimit(1)
                        }
                        .frame(width: 56, height: 62)
                        .background(m.filters.brand?.id == b.id ? Theme.selBg : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                Button { showBrands = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2").font(.system(size: 20)).foregroundColor(Theme.text2).frame(width: 32, height: 32)
                        Text("全部品牌").font(.system(size: 11)).foregroundColor(Theme.text2)
                    }.frame(width: 56, height: 62)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(height: m.hotBrands.isEmpty ? 0 : 66)
        .padding(.bottom, 4)
    }

    var filterBar: some View {
        HStack(spacing: 0) {
            filterButton(.sort, m.filters.sort.map { $0.param.isEmpty ? "排序" : $0.text } ?? "排序", active: !(m.filters.sort?.param.isEmpty ?? true))
            filterButton(.brand, m.filters.brand?.name ?? "品牌", active: m.filters.brand != nil)
            seriesButton
            filterButton(.price, m.filters.price?.text ?? "价格", active: m.filters.price != nil)
            filterButton(.age, m.filters.age?.text ?? "车龄", active: m.filters.age != nil)
            filterButton(.mileage, m.filters.mileage?.text ?? "里程", active: m.filters.mileage != nil)
            filterButton(.more, "更多", active: moreCount > 0)
        }
        .frame(height: 40)
    }

    var seriesButton: some View {
        Button {
            panel = nil
            if m.filters.brand != nil { showSeries = true } else { showBrands = true }
        } label: {
            HStack(spacing: 2) {
                Text(m.filters.series?.name ?? "车系").font(.system(size: 13, weight: m.filters.series != nil ? .semibold : .regular)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(m.filters.series != nil ? Theme.selText : Theme.text)
            .frame(maxWidth: .infinity)
        }
    }

    var moreCount: Int { [m.filters.gearbox, m.filters.fuel, m.filters.level, m.filters.emission].compactMap { $0 }.count + (m.filters.fixedPrice ? 1 : 0) + (m.filters.testReport ? 1 : 0) + [m.filters.dcdSelf, m.filters.cert4S, m.filters.video].filter { $0 }.count }

    func filterButton(_ p: Panel, _ title: String, active: Bool) -> some View {
        Button {
            if p == .brand { panel = nil; showBrands = true; return }
            withAnimation(.easeOut(duration: 0.15)) { panel = panel == p ? nil : p }
        } label: {
            HStack(spacing: 2) {
                Text(p == .more && moreCount > 0 ? "更多(\(moreCount))" : title)
                    .font(.system(size: 13, weight: active || panel == p ? .semibold : .regular)).lineLimit(1)
                Image(systemName: panel == p ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(active ? Theme.selText : Theme.text)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: list
    var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                quickRow
                if !m.filters.keyword.isEmpty || m.total > 0 || !m.cars.isEmpty {
                    HStack {
                        Text(countText).font(.system(size: 12)).foregroundColor(Theme.gray)
                        Spacer()
                        Text("非官方工具 · 数据来自懂车帝网页").font(.system(size: 10)).foregroundColor(Color(hex: 0xC0C2CA))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                }
                if m.cars.isEmpty && m.loading {
                    ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                } else if m.shown.isEmpty && !m.loading {
                    emptyState
                } else {
                    ForEach(m.shown) { c in
                        NavigationLink(value: c) { CarRow(car: c) }
                            .buttonStyle(PrefetchPress { DetailCache.shared.prefetch(c.id, city: c.city.isEmpty ? m.filters.city : c.city) })
                            .onAppear { m.rowAppeared(c) }
                    }
                    footer
                }
            }
        }
        .background(Color.white)
        .refreshable { m.reload() }
    }

    var countText: String {
        if !m.filters.keyword.isEmpty { return "已加载车源中匹配“\(m.filters.keyword)” \(m.shown.count) 辆" }
        let t = m.total >= 10000 ? "共找到 10000+ 辆车" : "共找到 \(m.total) 辆车"
        return m.fromCache && m.loading ? t + " · 更新中…" : t
    }

    var quickRow: some View {
        let chips = m.filters.activeChips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickToggle("懂车帝自营", on: m.filters.dcdSelf, badge: true) { m.filters.dcdSelf.toggle() }
                quickToggle("4S店专区", on: m.filters.cert4S) { m.filters.cert4S.toggle() }
                quickToggle("透明一口价", on: m.filters.fixedPrice) { m.filters.fixedPrice.toggle() }
                quickToggle("有检测报告", on: m.filters.testReport) { m.filters.testReport.toggle() }
                quickToggle("准新车", on: m.filters.age?.param == "0,1") { m.filters.age = m.filters.age?.param == "0,1" ? nil : FilterOptions.age[0] }
                quickToggle("新能源", on: m.filters.fuel?.param == "4,5,6") { m.filters.fuel = m.filters.fuel?.param == "4,5,6" ? nil : FilterOptions.fuel.last }
                quickToggle("SUV", on: m.filters.level?.param == "1") { m.filters.level = m.filters.level?.param == "1" ? nil : FilterOptions.level[1] }
                quickToggle("视频看车", on: m.filters.video) { m.filters.video.toggle() }
                ForEach(chips.indices, id: \.self) { i in
                    if let kp = chips[i].1, !quickCovered(chips[i].0) {
                        Button { m.filters[keyPath: kp] = nil; m.reload() } label: {
                            HStack(spacing: 3) { Text(chips[i].0); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                .font(.system(size: 12)).foregroundColor(Theme.selText)
                                .padding(.horizontal, 10).frame(height: 28).background(Theme.selBg).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 10)
    }

    func quickCovered(_ text: String) -> Bool {
        [FilterOptions.age[0].text, FilterOptions.fuel.last!.text, FilterOptions.level[1].text].contains(text)
    }

    func quickToggle(_ t: String, on: Bool, badge: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button { action(); m.reload() } label: {
            HStack(spacing: 3) {
                if badge { Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundColor(on ? Theme.selText : Color(hex: 0xD18700)) }
                Text(t)
            }
            .font(.system(size: 12, weight: on || badge ? .medium : .regular))
                .foregroundColor(on ? Theme.selText : Theme.text2)
                .padding(.horizontal, 10).frame(height: 28)
                .background(on ? Theme.selBg : Theme.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    @ViewBuilder var footer: some View {
        if let e = m.error {
            VStack(spacing: 8) {
                Text(e).font(.system(size: 12)).foregroundColor(Theme.gray)
                Button("重新加载") { m.loadMore() }.font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                    .padding(.horizontal, 16).frame(height: 30).overlay(Capsule().stroke(Theme.line))
            }.padding(20)
        } else if m.hasMore {
            HStack(spacing: 6) { ProgressView(); Text("加载中…").font(.system(size: 12)).foregroundColor(Theme.gray) }
                .frame(height: 50).frame(maxWidth: .infinity)
                .onAppear { m.loadMore() }
        } else if !m.cars.isEmpty {
            Text("— 没有更多车源了 —").font(.system(size: 12)).foregroundColor(Color(hex: 0xC0C2CA)).frame(height: 50)
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: m.error != nil ? "wifi.exclamationmark" : "car.2").font(.system(size: 44)).foregroundColor(Color(hex: 0xD5D7DD))
            Text(m.error ?? (m.filters.keyword.isEmpty ? "暂无符合条件的车源" : "已加载车源中没有“\(m.filters.keyword)”"))
                .font(.system(size: 14)).foregroundColor(Theme.gray).multilineTextAlignment(.center)
            Button(m.error != nil ? "重新加载" : "清空筛选条件") {
                if m.error == nil { let c = m.filters.city; m.filters = Filters(); m.filters.city = c }
                m.reload()
            }
            .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
            .padding(.horizontal, 20).frame(height: 34).background(Theme.yellow).clipShape(Capsule())
        }
        .padding(.top, 80).frame(maxWidth: .infinity)
    }
}

/// Plain button style that starts fetching the detail as soon as the finger goes down
/// (~100–300 ms before the tap completes and the page pushes).
struct PrefetchPress: ButtonStyle {
    let onPress: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .onChange(of: configuration.isPressed) { if $0 { onPress() } }
    }
}

struct CarRow: View {
    let car: Car
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: car.image, maxPoints: 130)
                .frame(width: 128, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                Text(car.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subLine).font(.system(size: 12)).foregroundColor(Theme.gray).lineLimit(1)
                let tags = car.isSelfTrade ? car.tags.filter { $0.text != "直营" } : car.tags
                if car.isSelfTrade || !tags.isEmpty {
                    HStack(spacing: 4) {
                        if car.isSelfTrade { SelfBadge() }
                        ForEach(tags.prefix(car.isSelfTrade ? 2 : 3), id: \.self) { TagView(tag: $0) }
                    }
                }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(car.price).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.price)
                    if !car.officialPrice.isEmpty {
                        Text("新车\(car.officialPrice)").font(.system(size: 11)).foregroundColor(Theme.gray).strikethrough()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 96)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 154) }
    }
    var subLine: String {
        var parts = car.sub.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !car.city.isEmpty { parts.append(car.city) }
        return parts.joined(separator: " / ")
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 6).fill(Theme.chipBg).frame(width: 128, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.chipBg).frame(height: 14)
                RoundedRectangle(cornerRadius: 3).fill(Theme.chipBg).frame(width: 140, height: 14)
                RoundedRectangle(cornerRadius: 3).fill(Theme.chipBg).frame(width: 100, height: 10)
                Spacer()
                RoundedRectangle(cornerRadius: 3).fill(Theme.chipBg).frame(width: 70, height: 16)
            }
        }
        .frame(height: 96).padding(.horizontal, 14).padding(.vertical, 12)
        .modifier(Shimmer())
    }
}
