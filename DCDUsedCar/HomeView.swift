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
    @Published var error: String?
    @Published var hotBrands: [Brand] = []
    @Published var allBrands: [Brand] = []
    private var page = 1
    private var generation = 0

    var shown: [Car] {
        let k = filters.keyword.trimmingCharacters(in: .whitespaces)
        return k.isEmpty ? cars : cars.filter { $0.title.localizedCaseInsensitiveContains(k) }
    }

    func reload() {
        generation += 1
        cars = []; page = 1; hasMore = false; total = 0
        loadMore(force: true)
    }

    func loadMore(force: Bool = false) {
        if loading && !force { return }
        loading = true; error = nil
        let gen = generation, p = page, f = filters
        Task {
            do {
                let r = try await API.search(f, page: p)
                guard gen == generation else { return }
                let existing = Set(cars.map(\.id))
                cars += r.cars.filter { !existing.contains($0.id) }
                hasMore = r.hasMore && !r.cars.isEmpty
                total = r.total
                page = p + 1
            } catch {
                guard gen == generation else { return }
                self.error = "网络开小差了（可能被限流），请稍后重试"
            }
            loading = false
        }
    }

    func loadBrands() async {
        guard allBrands.isEmpty, let b = try? await API.brands() else { return }
        allBrands = b.all; hotBrands = b.hot
    }
}

struct HomeView: View {
    @StateObject private var m = ListModel()
    @State private var panel: Panel?
    @State private var showCity = false
    @State private var showSearch = false
    @State private var showBrands = false
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
            SearchPage(model: m) { m.reload() }
        }
        .sheet(isPresented: $showBrands) {
            BrandPicker(model: m) { b, s in
                m.filters.brand = b; m.filters.series = s; m.reload()
            }
        }
        .task {
            if let c = LaunchArgs.value("city") { m.filters.city = c }
            if m.cars.isEmpty { m.reload() }
            await m.loadBrands()
            if let d = LaunchArgs.value("detail"), let id = Int64(d) { path.append(id) }
            if let p = LaunchArgs.value("panel"), let pp = Panel(rawValue: p) {
                if pp == .brand { showBrands = true } else { panel = pp }
            }
            if LaunchArgs.flag("search") { showSearch = true }
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
                        if m.filters.brand?.id == b.id { m.filters.brand = nil } else { m.filters.brand = b }
                        m.filters.series = nil; m.filters.keyword = ""; m.reload()
                    } label: {
                        VStack(spacing: 4) {
                            RemoteImage(url: b.logo, mode: .fit).frame(width: 32, height: 32)
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
            filterButton(.brand, m.filters.series?.name ?? m.filters.brand?.name ?? "品牌", active: m.filters.brand != nil || m.filters.series != nil)
            filterButton(.price, m.filters.price?.text ?? "价格", active: m.filters.price != nil)
            filterButton(.age, m.filters.age?.text ?? "车龄", active: m.filters.age != nil)
            filterButton(.mileage, m.filters.mileage?.text ?? "里程", active: m.filters.mileage != nil)
            filterButton(.more, "更多", active: moreCount > 0)
        }
        .frame(height: 40)
    }

    var moreCount: Int { [m.filters.gearbox, m.filters.fuel, m.filters.level, m.filters.emission].compactMap { $0 }.count + (m.filters.fixedPrice ? 1 : 0) + (m.filters.testReport ? 1 : 0) }

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
                        NavigationLink(value: c) { CarRow(car: c) }.buttonStyle(.plain)
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
        return m.total >= 10000 ? "共找到 10000+ 辆车" : "共找到 \(m.total) 辆车"
    }

    var quickRow: some View {
        let chips = m.filters.activeChips
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                quickToggle("透明一口价", on: m.filters.fixedPrice) { m.filters.fixedPrice.toggle() }
                quickToggle("有检测报告", on: m.filters.testReport) { m.filters.testReport.toggle() }
                quickToggle("准新车", on: m.filters.age?.param == "0,1") { m.filters.age = m.filters.age?.param == "0,1" ? nil : FilterOptions.age[0] }
                quickToggle("新能源", on: m.filters.fuel?.param == "4,5,6") { m.filters.fuel = m.filters.fuel?.param == "4,5,6" ? nil : FilterOptions.fuel.last }
                quickToggle("SUV", on: m.filters.level?.param == "1") { m.filters.level = m.filters.level?.param == "1" ? nil : FilterOptions.level[1] }
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

    func quickToggle(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { action(); m.reload() } label: {
            Text(t).font(.system(size: 12, weight: on ? .medium : .regular))
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

struct CarRow: View {
    let car: Car
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: car.image)
                .frame(width: 128, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 5) {
                Text(car.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subLine).font(.system(size: 12)).foregroundColor(Theme.gray).lineLimit(1)
                if !car.tags.isEmpty {
                    HStack(spacing: 4) { ForEach(car.tags.prefix(3), id: \.self) { TagView(tag: $0) } }
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
