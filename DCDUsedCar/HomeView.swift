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
        Store.saveFilters(filters)
        // Paint the last cached first page for these filters instantly, then refresh.
        if let c = API.cachedSearch(filters) {
            cars = c.cars; total = c.total; hasMore = false; fromCache = true
            API.log("list painted from disk cache (\(c.cars.count) cars)")
        } else {
            cars = []; total = 0
        }
        loadMore(force: true)
    }

    /// Pull-to-refresh: keep the spinner until the first page actually arrives.
    func refresh() async {
        reload()
        await loadTask?.value
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

struct ScrollTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct HomeView: View {
    @StateObject private var m = ListModel()
    @ObservedObject private var store = Store.shared
    @State private var panel: Panel?
    @State private var showCity = false
    @State private var showSearch = false
    @State private var showBrands = false
    @State private var brandStart: Brand?
    @State private var showSeries = false
    @State private var showTop = false
    @State private var didAutoScroll = false
    @State private var path = NavigationPath()
    private let barH: CGFloat = 44
    private let panelAnim = Animation.spring(response: 0.32, dampingFraction: 0.88)

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                searchHeader
                ScrollViewReader { proxy in
                    ZStack(alignment: .top) {
                        list(proxy)
                        if let panel {
                            Color.black.opacity(0.35).ignoresSafeArea().padding(.top, barH)
                                .onTapGesture { closePanel() }
                                .transition(.opacity)
                            VStack(spacing: 0) {
                                filterBar
                                FilterPanel(panel: panel, filters: $m.filters) { apply in
                                    closePanel()
                                    if apply { Haptics.select(); m.reload() }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            .clipped()
                        }
                    }
                    .clipped()
                    .overlay(alignment: .bottomTrailing) {
                        if showTop && panel == nil {
                            Button {
                                Haptics.tap()
                                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                            } label: {
                                Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                                    .frame(width: 44, height: 44).background(Theme.card).clipShape(Circle())
                                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                            }
                            .padding(.trailing, 16).padding(.bottom, 16)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .onChange(of: panel) { p in
                        if p != nil { withAnimation(panelAnim) { proxy.scrollTo("bar", anchor: .top) } }
                    }
                    .onChange(of: m.cars.count) { n in
                        if LaunchArgs.flag("scrolled") && !didAutoScroll && n > 6 {
                            didAutoScroll = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { proxy.scrollTo(m.cars[3].id, anchor: .top) }
                        }
                    }
                }
            }
            .background(Theme.card)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Car.self) { DetailView(skuId: $0.id, city: $0.city.isEmpty ? m.filters.city : $0.city, preview: $0) }
            .navigationDestination(for: Int64.self) { DetailView(skuId: $0, city: m.filters.city, preview: nil) }
        }
        .tint(Theme.text)
        .sheet(isPresented: $showCity) {
            CityPicker(current: m.filters.city) { c in Haptics.select(); m.filters.city = c; m.filters.series = nil; m.reload() }
        }
        .fullScreenCover(isPresented: $showSearch) {
            SearchPage(model: m) { openSeries in
                m.reload()
                if openSeries { DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showSeries = true } }
            }
        }
        .sheet(isPresented: $showBrands) {
            BrandPicker(model: m, start: brandStart) { b, s in
                Haptics.select()
                m.filters.brand = b; m.filters.series = s; m.filters.keyword = ""; m.reload()
            }
        }
        .sheet(isPresented: $showSeries) {
            if let b = m.filters.brand {
                NavigationStack {
                    SeriesList(model: m, brand: b) { s in
                        Haptics.select()
                        m.filters.series = s; m.filters.keyword = ""; m.reload(); showSeries = false
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showSeries = false } } }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .task {
            if let c = LaunchArgs.value("city") { m.filters.city = c }
            else if let saved = Store.savedFilters() { m.filters = saved }
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
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if pp == .brand { showBrands = true } else { withAnimation(panelAnim) { panel = pp } }
            }
            if LaunchArgs.flag("search") { showSearch = true }
            if LaunchArgs.flag("citypicker") { showCity = true }
            if let n = LaunchArgs.value("seed").flatMap(Int.init) {
                for _ in 0..<40 where m.cars.count < n { try? await Task.sleep(nanoseconds: 250_000_000) }
                for c in m.cars.prefix(n) {
                    if !store.isFav(c.id) { store.toggleFav(c) }
                    store.addCompare(c)
                }
            }
            await brands
        }
    }

    func closePanel() { withAnimation(panelAnim) { panel = nil } }

    // MARK: header (stays put; tiles and brands scroll away under it)
    var searchHeader: some View {
        HStack(spacing: 10) {
            Button { showCity = true } label: {
                HStack(spacing: 2) {
                    Image(systemName: "location.fill").font(.system(size: 11))
                    Text(m.filters.city).font(.system(size: 16, weight: .semibold)).lineLimit(1).fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(Theme.text).frame(minHeight: 44)
            }
            Button { showSearch = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text2)
                    Text(searchLabel).font(.system(size: 14)).foregroundColor(searchLabelActive ? Theme.text : Theme.gray).lineLimit(1)
                    Spacer(minLength: 0)
                    if searchLabelActive {
                        Image(systemName: "xmark.circle.fill").foregroundColor(Theme.faint)
                            .frame(width: 30, height: 36).contentShape(Rectangle())
                            .onTapGesture { Haptics.tap(); m.filters.keyword = ""; m.filters.series = nil; m.filters.brand = nil; m.reload() }
                    }
                }
                .padding(.leading, 12).padding(.trailing, searchLabelActive ? 4 : 12).frame(height: 36)
                .background(Theme.chipBg).clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 6)
        .background(Theme.card)
    }

    var searchLabelActive: Bool { m.filters.series != nil || m.filters.brand != nil || !m.filters.keyword.isEmpty }
    var searchLabel: String {
        if !m.filters.keyword.isEmpty { return m.filters.keyword }
        if let s = m.filters.series { return [m.filters.brand?.name, s.name].compactMap { $0 }.joined(separator: " · ") }
        if let b = m.filters.brand { return b.name }
        return "搜索品牌/车系，如 卡罗拉"
    }

    @ViewBuilder var brandRow: some View {
        if !m.hotBrands.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(m.hotBrands.prefix(15)) { b in
                        let on = m.filters.brand?.id == b.id
                        Button {
                            Haptics.select()
                            if on { m.filters.brand = nil } else { m.filters.brand = b; showSeries = true }
                            m.filters.series = nil; m.filters.keyword = ""; m.reload()
                        } label: {
                            VStack(spacing: 4) {
                                RemoteImage(url: b.logo, mode: .fit, maxPoints: 40).frame(width: 30, height: 30)
                                Text(b.name).font(.system(size: 11, weight: on ? .semibold : .regular)).foregroundColor(on ? Theme.text : Theme.text2).lineLimit(1)
                            }
                            .frame(width: 58, height: 60)
                            .background(on ? Theme.selBg : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.rImage))
                        }
                        .buttonStyle(PressStyle())
                    }
                    Button { brandStart = nil; showBrands = true } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2").font(.system(size: 18)).foregroundColor(Theme.text2).frame(width: 30, height: 30)
                            Text("全部品牌").font(.system(size: 11)).foregroundColor(Theme.text2)
                        }.frame(width: 58, height: 60)
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.horizontal, 8)
            }
            .padding(.top, 4)
        }
    }

    /// 6 evenly-sized buttons (brand+series merged) so labels fit on a 375pt iPhone SE.
    var filterBar: some View {
        HStack(spacing: 0) {
            filterButton(.sort, m.filters.sort.map { $0.param.isEmpty ? "排序" : $0.text } ?? "排序", active: !(m.filters.sort?.param.isEmpty ?? true))
            filterButton(.brand, m.filters.series?.name ?? m.filters.brand?.name ?? "品牌", active: m.filters.brand != nil || m.filters.series != nil)
            filterButton(.price, m.filters.price?.text ?? "价格", active: m.filters.price != nil)
            filterButton(.age, m.filters.age?.text ?? "车龄", active: m.filters.age != nil)
            filterButton(.mileage, m.filters.mileage.map { $0.text.replacingOccurrences(of: "公里内", with: "km内") } ?? "里程", active: m.filters.mileage != nil)
            filterButton(.more, moreCount > 0 ? "筛选·\(moreCount)" : "筛选", active: moreCount > 0, icon: "line.3.horizontal.decrease")
        }
        .padding(.horizontal, 4)
        .frame(height: barH)
        .background(Theme.card)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }

    var moreCount: Int { [m.filters.gearbox, m.filters.fuel, m.filters.level, m.filters.emission, m.filters.subLevel, m.filters.origin, m.filters.driven, m.filters.capacity].compactMap { $0 }.count + (m.filters.fixedPrice ? 1 : 0) + (m.filters.testReport ? 1 : 0) + [m.filters.dcdSelf, m.filters.cert4S, m.filters.video].filter { $0 }.count }

    func filterButton(_ p: Panel, _ title: String, active: Bool, icon: String? = nil) -> some View {
        let open = panel == p
        return Button {
            Haptics.tap()
            if p == .brand {
                closePanel(); brandStart = m.filters.brand; showBrands = true; return
            }
            withAnimation(panelAnim) { panel = open ? nil : p }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: active || open ? .semibold : .regular))
                    .lineLimit(1).minimumScaleFactor(0.75)
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                } else {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
            }
            .foregroundColor(active || open ? Theme.selText : Theme.text)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, minHeight: barH)
            .contentShape(Rectangle())
        }
    }

    // MARK: list
    func list(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Color.clear.frame(height: 0).id("top")
                    .background(GeometryReader { g in Color.clear.preference(key: ScrollTopKey.self, value: g.frame(in: .named("homeScroll")).minY) })
                brandRow
                tiles
                Section {
                    quickRow
                    countRow
                    if m.cars.isEmpty && m.loading {
                        ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                    } else if m.shown.isEmpty && !m.loading {
                        emptyState
                    } else {
                        ForEach(m.shown) { c in
                            NavigationLink(value: c) { CarRow(car: c) }
                                .buttonStyle(PrefetchPress { DetailCache.shared.prefetch(c.id, city: c.city.isEmpty ? m.filters.city : c.city) })
                                .onAppear { m.rowAppeared(c) }
                                .id(c.id)
                        }
                        footer
                    }
                } header: {
                    filterBar.id("bar")
                }
            }
            .frame(minHeight: UIScreen.main.bounds.height, alignment: .top)
        }
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(ScrollTopKey.self) { y in
            let show = y < -900
            if show != showTop { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showTop = show } }
        }
        .background(Theme.card)
        .refreshable { await m.refresh(); Haptics.success() }
    }

    @ViewBuilder var countRow: some View {
        if !m.filters.keyword.isEmpty || m.total > 0 || !m.cars.isEmpty {
            HStack(spacing: 4) {
                Text(countText).font(.system(size: 12)).foregroundColor(Theme.gray)
                if m.fromCache && m.loading { ProgressView().scaleEffect(0.6).frame(width: 14, height: 14) }
                Spacer()
                Text("数据来自懂车帝").font(.system(size: 10)).foregroundColor(Theme.faint)
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
        }
    }

    var countText: String {
        if !m.filters.keyword.isEmpty { return "已加载车源中匹配“\(m.filters.keyword)” \(m.shown.count) 辆" }
        return m.total >= 10000 ? "共找到 10000+ 辆车" : "共找到 \(m.total) 辆车"
    }

    var quickRow: some View {
        let chips = m.filters.activeChips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips.indices, id: \.self) { i in
                    if let kp = chips[i].1, !quickCovered(chips[i].0) {
                        Button { Haptics.tap(); m.filters[keyPath: kp] = nil; m.reload() } label: {
                            HStack(spacing: 3) { Text(chips[i].0); Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                .font(.system(size: 12, weight: .medium)).foregroundColor(Theme.selText)
                                .padding(.horizontal, 10).frame(height: 28).background(Theme.selBg).clipShape(RoundedRectangle(cornerRadius: Theme.rChip))
                        }
                    }
                }
                quickToggle("透明一口价", on: m.filters.fixedPrice) { m.filters.fixedPrice.toggle() }
                quickToggle("有检测报告", on: m.filters.testReport) { m.filters.testReport.toggle() }
                quickToggle("合资", on: m.filters.origin?.param == "1") { m.filters.origin = m.filters.origin?.param == "1" ? nil : FilterOptions.origin[0] }
                quickToggle("四驱", on: m.filters.driven?.param == "3") { m.filters.driven = m.filters.driven?.param == "3" ? nil : FilterOptions.driven[2] }
                quickToggle("视频看车", on: m.filters.video) { m.filters.video.toggle() }
                if hasAnyFilter {
                    Button { Haptics.tap(); let c = m.filters.city; m.filters = Filters(); m.filters.city = c; m.reload() } label: {
                        HStack(spacing: 3) { Image(systemName: "arrow.counterclockwise").font(.system(size: 10, weight: .semibold)); Text("重置") }
                            .font(.system(size: 12)).foregroundColor(Theme.text2).padding(.horizontal, 10).frame(height: 28)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 10)
    }

    var hasAnyFilter: Bool { var f = Filters(); f.city = m.filters.city; return f != m.filters }

    func quickCovered(_ text: String) -> Bool {
        [FilterOptions.age[0].text, FilterOptions.fuel.last!.text, FilterOptions.level[1].text, FilterOptions.price[0].text, FilterOptions.price[2].text, FilterOptions.origin[0].text, FilterOptions.driven[2].text].contains(text)
    }

    /// 金刚位 entry tiles — every tile is a real, verified filter.
    var tiles: some View {
        let f = m.filters
        let newest = FilterOptions.sort.first { $0.param == "4" }
        let items: [(String, String, Color, Bool, () -> Void)] = [
            ("懂车帝自营", "checkmark.seal.fill", Color(hex: 0xFFB300), f.dcdSelf, { m.filters.dcdSelf.toggle() }),
            ("4S店专区", "building.2.fill", Color(hex: 0x3D7BFF), f.cert4S, { m.filters.cert4S.toggle() }),
            ("准新车", "sparkles", Color(hex: 0xFF6A3D), f.age?.param == "0,1", { m.filters.age = f.age?.param == "0,1" ? nil : FilterOptions.age[0] }),
            ("新能源", "bolt.car.fill", Theme.green, f.fuel?.param == "4,5,6", { m.filters.fuel = f.fuel?.param == "4,5,6" ? nil : FilterOptions.fuel.last }),
            ("3万以下", "yensign.circle.fill", Color(hex: 0xFF4F14), f.price?.param == "0,3", { m.filters.price = f.price?.param == "0,3" ? nil : FilterOptions.price[0] }),
            ("5-8万", "car.fill", Color(hex: 0x7A5CFF), f.price?.param == "5,8", { m.filters.price = f.price?.param == "5,8" ? nil : FilterOptions.price[2] }),
            ("SUV", "car.side.fill", Color(hex: 0x00A6C8), f.level?.param == "1", { m.filters.level = f.level?.param == "1" ? nil : FilterOptions.level[1] }),
            ("最新上架", "clock.fill", Color(hex: 0xFF4D6A), f.sort?.param == "4", { m.filters.sort = f.sort?.param == "4" ? nil : newest }),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 4), spacing: 4) {
            ForEach(items.indices, id: \.self) { i in
                let it = items[i]
                Button { Haptics.select(); it.4(); m.reload() } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(it.3 ? Theme.yellow : it.2.opacity(0.12)).frame(width: 44, height: 44)
                            Image(systemName: it.1).font(.system(size: 19, weight: .medium)).foregroundColor(it.3 ? Theme.onYellow : it.2)
                        }
                        Text(it.0).font(.system(size: 12, weight: it.3 ? .semibold : .regular)).foregroundColor(Theme.text).lineLimit(1)
                    }.frame(maxWidth: .infinity).padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 6)
    }

    func quickToggle(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.select(); action(); m.reload() } label: {
            HStack(spacing: 3) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(t)
            }
            .font(.system(size: 12, weight: on ? .medium : .regular))
            .foregroundColor(on ? Theme.selText : Theme.text2)
            .padding(.horizontal, 10).frame(height: 28)
            .background(on ? Theme.selBg : Theme.chipBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.rChip))
        }
    }

    @ViewBuilder var footer: some View {
        if let e = m.error {
            VStack(spacing: 8) {
                Text(e).font(.system(size: 12)).foregroundColor(Theme.gray)
                Button("重新加载") { m.loadMore() }.font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                    .padding(.horizontal, 16).frame(height: 32).overlay(Capsule().stroke(Theme.line))
            }.padding(20)
        } else if m.hasMore {
            HStack(spacing: 6) { ProgressView(); Text("加载中…").font(.system(size: 12)).foregroundColor(Theme.gray) }
                .frame(height: 50).frame(maxWidth: .infinity)
                .onAppear { m.loadMore() }
        } else if !m.cars.isEmpty {
            Text("— 没有更多车源了 —").font(.system(size: 12)).foregroundColor(Theme.faint).frame(height: 60)
        }
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: m.error != nil ? "wifi.exclamationmark" : "car.2").font(.system(size: 44)).foregroundColor(Theme.faint)
            Text(m.error ?? (m.filters.keyword.isEmpty ? "暂无符合条件的车源\n试试放宽价格、车龄或筛选条件" : "已加载车源中没有“\(m.filters.keyword)”"))
                .font(.system(size: 14)).foregroundColor(Theme.gray).multilineTextAlignment(.center)
            Button(m.error != nil ? "重新加载" : "清空筛选条件") {
                Haptics.tap()
                if m.error == nil { let c = m.filters.city; m.filters = Filters(); m.filters.city = c }
                m.reload()
            }
            .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.onYellow)
            .padding(.horizontal, 20).frame(height: 38).background(Theme.yellow).clipShape(Capsule())
        }
        .padding(.top, 60).padding(.bottom, 40).frame(maxWidth: .infinity)
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
    var showFav = true
    @ObservedObject private var store = Store.shared
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: car.image, maxPoints: 124)
                .frame(width: 124, height: 93)
                .clipShape(RoundedRectangle(cornerRadius: Theme.rImage, style: .continuous))
                .overlay(alignment: .topLeading) { if car.isSelfTrade { SelfBadge().padding(4) } }
            VStack(alignment: .leading, spacing: 4) {
                Text(car.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text).lineLimit(2)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Text(subLine).font(.system(size: 12)).foregroundColor(Theme.gray).lineLimit(1)
                let tags = car.tags.filter { $0.text != "直营" }
                if !tags.isEmpty {
                    HStack(spacing: 4) { ForEach(tags.prefix(3), id: \.self) { TagView(tag: $0) } }
                }
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(car.price).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.price)
                    if !car.officialPrice.isEmpty {
                        Text("新车\(car.officialPrice)").font(.system(size: 11)).foregroundColor(Theme.gray).strikethrough().lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .overlay(alignment: .trailing) {
                    if showFav {
                        let on = store.isFav(car.id)
                        Button {
                            store.toggleFav(car)
                            if on { Haptics.tap() } else { Haptics.success(); Toast.shared.show("已收藏") }
                        } label: {
                            Image(systemName: on ? "heart.fill" : "heart").font(.system(size: 16))
                                .foregroundColor(on ? Theme.heart : Theme.faint)
                                .frame(width: 40, height: 40).contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .padding(.trailing, -10)
                    }
                }
            }
            .frame(minHeight: 93)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5).padding(.leading, 150) }
    }
    var subLine: String {
        var parts = car.sub.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !car.city.isEmpty { parts.append(car.city) }
        return parts.joined(separator: " · ")
    }
}

/// Same geometry as CarRow so nothing jumps when real rows replace it.
struct SkeletonRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Bone(w: 124, h: 93, r: Theme.rImage)
            VStack(alignment: .leading, spacing: 6) {
                Bone(h: 15); Bone(w: 120, h: 15)
                Bone(w: 140, h: 11)
                HStack(spacing: 4) { Bone(w: 40, h: 16); Bone(w: 48, h: 16) }
                Spacer(minLength: 0)
                Bone(w: 70, h: 18)
            }
        }
        .frame(height: 93).padding(.horizontal, 14).padding(.vertical, 12)
        .modifier(Shimmer())
    }
}
