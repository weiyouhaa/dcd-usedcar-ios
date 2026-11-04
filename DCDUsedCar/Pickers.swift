import SwiftUI

// MARK: - Dropdown filter panel

struct FilterPanel: View {
    let panel: Panel
    @Binding var filters: Filters
    let done: (Bool) -> Void
    @State private var draft = Filters()
    @State private var lo = ""
    @State private var hi = ""

    var body: some View {
        VStack(spacing: 0) {
            switch panel {
            case .sort:
                VStack(spacing: 0) {
                    ForEach(FilterOptions.sort, id: \.self) { o in
                        Button {
                            filters.sort = o.param.isEmpty ? nil : o; done(true)
                        } label: {
                            HStack {
                                Text(o.text).font(.system(size: 14, weight: isSort(o) ? .semibold : .regular))
                                    .foregroundColor(isSort(o) ? Theme.selText : Theme.text)
                                Spacer()
                                if isSort(o) { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.selText) }
                            }
                            .padding(.horizontal, 16).frame(height: 46).contentShape(Rectangle())
                        }
                    }
                }.padding(.bottom, 6)
            case .price:
                section(nil, FilterOptions.price, \.price, single: true)
                HStack(spacing: 8) {
                    Text("自定义").font(.system(size: 13)).foregroundColor(Theme.text2)
                    numField("最低", $lo)
                    Text("—").foregroundColor(Theme.gray)
                    numField("最高", $hi)
                    Text("万").font(.system(size: 13)).foregroundColor(Theme.text2)
                    Spacer(minLength: 4)
                    Button("确定") {
                        let l = Int(lo) ?? 0, h = Int(hi) ?? -1
                        if !(lo.isEmpty && hi.isEmpty) {
                            let t = h < 0 ? "\(l)万以上" : (l == 0 ? "\(h)万以下" : "\(l)-\(h)万")
                            filters.price = Option(text: t, key: "price", param: "\(l),\(h)")
                        }
                        done(true)
                    }
                    .font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                    .padding(.horizontal, 14).frame(height: 32).background(Theme.yellow).clipShape(Capsule())
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            case .age:
                section(nil, FilterOptions.age, \.age, single: true).padding(.bottom, 8)
            case .mileage:
                section(nil, FilterOptions.mileage, \.mileage, single: true).padding(.bottom, 8)
            case .more:
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("服务").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text).padding(.horizontal, 16).padding(.top, 14)
                        HStack(spacing: 10) {
                            toggleChip("透明一口价", $draft.fixedPrice)
                            toggleChip("有检测报告", $draft.testReport)
                        }.padding(.horizontal, 16).padding(.top, 10)
                        Text("车源类型").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text).padding(.horizontal, 16).padding(.top, 16)
                        HStack(spacing: 10) {
                            toggleChip("懂车帝自营", $draft.dcdSelf)
                            toggleChip("4S店专区", $draft.cert4S)
                            toggleChip("视频看车", $draft.video)
                        }.padding(.horizontal, 16).padding(.top, 10)
                        section("级别", FilterOptions.level, \.level, single: false)
                        section("能源类型", FilterOptions.fuel, \.fuel, single: false)
                        section("变速箱", FilterOptions.gearbox, \.gearbox, single: false)
                        section("排放标准", FilterOptions.emission, \.emission, single: false)
                    }
                }
                .frame(maxHeight: 380)
                HStack(spacing: 10) {
                    Button("重置") {
                        draft.level = nil; draft.fuel = nil; draft.gearbox = nil; draft.emission = nil; draft.fixedPrice = false; draft.testReport = false; draft.dcdSelf = false; draft.cert4S = false; draft.video = false
                    }
                    .font(.system(size: 15)).foregroundColor(Theme.text).frame(maxWidth: .infinity).frame(height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 21).stroke(Theme.line))
                    Button("确定") { filters = draft; done(true) }
                        .font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text).frame(maxWidth: .infinity).frame(height: 42)
                        .background(Theme.yellow).clipShape(Capsule())
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            case .brand:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedCorner(radius: 12, corners: [.bottomLeft, .bottomRight]))
        .onAppear { draft = filters }
    }

    func isSort(_ o: Option) -> Bool { (filters.sort?.param ?? "") == o.param }

    func numField(_ p: String, _ b: Binding<String>) -> some View {
        TextField(p, text: b).keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(.system(size: 13)).frame(width: 64, height: 32).background(Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 4))
    }

    func toggleChip(_ t: String, _ b: Binding<Bool>) -> some View {
        Button { b.wrappedValue.toggle() } label: { chip(t, on: b.wrappedValue).frame(width: 104) }
    }

    func chip(_ t: String, on: Bool) -> some View {
        Text(t).font(.system(size: 13, weight: on ? .medium : .regular)).lineLimit(1).minimumScaleFactor(0.8)
            .foregroundColor(on ? Theme.selText : Theme.text)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(on ? Theme.selBg : Theme.chipBg)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.selText.opacity(0.6) : .clear, lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    /// single = apply immediately (dropdown style); otherwise edits the draft (applied with 确定).
    func section(_ title: String?, _ opts: [Option], _ kp: WritableKeyPath<Filters, Option?>, single: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title { Text(title).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                if single {
                    Button { filters[keyPath: kp] = nil; done(true) } label: { chip("不限", on: filters[keyPath: kp] == nil) }
                }
                ForEach(opts, id: \.self) { o in
                    Button {
                        if single { filters[keyPath: kp] = o; done(true) }
                        else { draft[keyPath: kp] = draft[keyPath: kp] == o ? nil : o }
                    } label: { chip(o.text, on: (single ? filters : draft)[keyPath: kp] == o) }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat; var corners: UIRectCorner
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}

// MARK: - City

struct CityPicker: View {
    let current: String
    let pick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(FilterOptions.cities, id: \.self) { c in
                        Button { pick(c); dismiss() } label: {
                            Text(c).font(.system(size: 14, weight: c == current ? .semibold : .regular))
                                .foregroundColor(c == current ? Theme.selText : Theme.text)
                                .frame(maxWidth: .infinity).frame(height: 36)
                                .background(c == current ? Theme.selBg : Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }.padding(16)
            }
            .navigationTitle("选择城市").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}

// MARK: - Brand -> Series

struct BrandPicker: View {
    @ObservedObject var model: ListModel
    let pick: (Brand?, Series?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var path: [Brand] = []

    var groups: [(String, [Brand])] {
        Dictionary(grouping: model.allBrands, by: { $0.pinyin.isEmpty ? "#" : String($0.pinyin.prefix(1)) })
            .sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ZStack(alignment: .trailing) {
                    List {
                        Section {
                            Button { pick(nil, nil); dismiss() } label: { Text("不限品牌").foregroundColor(Theme.text) }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                                ForEach(model.hotBrands.prefix(10)) { b in
                                    Button { path = [b] } label: {
                                        VStack(spacing: 4) {
                                            RemoteImage(url: b.logo, mode: .fit, maxPoints: 40).frame(width: 34, height: 34)
                                            Text(b.name).font(.system(size: 11)).foregroundColor(Theme.text).lineLimit(1)
                                        }
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.vertical, 6)
                        } header: { Text("热门品牌") }
                        if model.allBrands.isEmpty { HStack { Spacer(); ProgressView(); Spacer() } }
                        ForEach(groups, id: \.0) { g in
                            Section {
                                ForEach(g.1) { b in
                                    Button { path = [b] } label: {
                                        HStack(spacing: 12) {
                                            RemoteImage(url: b.logo, mode: .fit, maxPoints: 40).frame(width: 30, height: 30)
                                            Text(b.name).font(.system(size: 15)).foregroundColor(model.filters.brand?.id == b.id ? Theme.selText : Theme.text)
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.gray)
                                        }
                                    }
                                }
                            } header: { Text(g.0) }.id(g.0)
                        }
                    }
                    .listStyle(.plain)
                    VStack(spacing: 1) {
                        ForEach(groups, id: \.0) { g in
                            Text(g.0).font(.system(size: 10, weight: .medium)).foregroundColor(Theme.text2)
                                .frame(width: 18, height: 14)
                                .onTapGesture { proxy.scrollTo(g.0, anchor: .top) }
                        }
                    }.padding(.trailing, 2)
                }
            }
            .navigationTitle("选择品牌").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .navigationDestination(for: Brand.self) { b in
                SeriesList(model: model, brand: b) { s in pick(b, s); dismiss() }
            }
            .task { await model.loadBrands() }
        }
    }
}

/// Full-width series picker for one brand: image, name and live on-sale count for the current city/filters.
struct SeriesList: View {
    @ObservedObject var model: ListModel
    let brand: Brand
    let pick: (Series?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { pick(nil) } label: {
                    HStack(spacing: 10) {
                        RemoteImage(url: brand.logo, mode: .fit, maxPoints: 40).frame(width: 30, height: 30)
                        Text("不限车系（全部\(brand.name)）").font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                        Spacer()
                        if model.filters.brand?.id == brand.id && model.filters.series == nil { Image(systemName: "checkmark").foregroundColor(Theme.selText) }
                    }.padding(.horizontal, 14).frame(height: 52)
                }
                Rectangle().fill(Theme.line).frame(height: 0.5)
                if model.seriesLoading && model.seriesBrand == brand.id {
                    HStack { Spacer(); ProgressView(); Text("加载车系…").font(.system(size: 13)).foregroundColor(Theme.gray); Spacer() }.padding(30)
                } else if model.series.isEmpty {
                    VStack(spacing: 10) {
                        Text("当前城市暂无\(brand.name)的车系数据").font(.system(size: 13)).foregroundColor(Theme.gray)
                        Button("重试") { Task { model.seriesBrand = nil; await model.loadSeries(for: brand) } }
                    }.frame(maxWidth: .infinity).padding(30)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 14) {
                    ForEach(model.seriesBrand == brand.id ? model.series : []) { s in
                        let on = model.filters.series?.id == s.id
                        Button { pick(s) } label: {
                            VStack(spacing: 4) {
                                RemoteImage(url: s.image, mode: .fit, maxPoints: 120).frame(height: 60).frame(maxWidth: .infinity)
                                    .background(Color.white)
                                Text(s.name).font(.system(size: 13, weight: on ? .semibold : .regular)).foregroundColor(on ? Theme.selText : Theme.text).lineLimit(1)
                                Text(count(s)).font(.system(size: 11)).foregroundColor(Theme.gray)
                            }
                            .padding(.vertical, 8).padding(.horizontal, 4)
                            .background(on ? Theme.selBg : Theme.chipBg.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
        }
        .navigationTitle("\(brand.name) · 选择车系").navigationBarTitleDisplayMode(.inline)
        .task(id: brand.id) {
            await model.loadSeries(for: brand)
            await model.loadSeriesCounts()
        }
    }

    func count(_ s: Series) -> String {
        guard let n = model.seriesCounts[s.id] else { return " " }
        return n >= 10000 ? "10000+辆在售" : "\(n)辆在售"
    }
}

// MARK: - Search

struct SearchPage: View {
    @ObservedObject var model: ListModel
    /// Bool: also open the series picker (a brand was chosen).
    let apply: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sugs: [Suggestion] = []
    @FocusState private var focused: Bool
    @AppStorage("history") private var historyRaw = ""

    var history: [String] { historyRaw.split(separator: "\n").map(String.init) }

    var brandMatches: [Brand] {
        let k = text.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return [] }
        return model.allBrands.filter { $0.name.localizedCaseInsensitiveContains(k) || k.localizedCaseInsensitiveContains($0.name) }.prefix(3).map { $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(Theme.text2)
                    TextField("搜索品牌/车系，如 卡罗拉", text: $text).focused($focused).submitLabel(.search)
                        .onSubmit { submit() }
                    if !text.isEmpty { Image(systemName: "xmark.circle.fill").foregroundColor(Color(hex: 0xC5C7CF)).onTapGesture { text = "" } }
                }
                .padding(.horizontal, 12).frame(height: 36).background(Theme.chipBg).clipShape(Capsule())
                Button("取消") { dismiss() }.foregroundColor(Theme.text)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            List {
                if text.isEmpty {
                    if !history.isEmpty {
                        Section {
                            FlowChips(items: history) { h in text = h; submit() }
                                .listRowSeparator(.hidden)
                        } header: {
                            HStack { Text("搜索历史"); Spacer(); Button("清空") { historyRaw = "" }.font(.system(size: 12)) }
                        }
                    }
                    if !model.hotBrands.isEmpty {
                        Section {
                            FlowChips(items: model.hotBrands.prefix(12).map(\.name)) { n in
                                if let b = model.hotBrands.first(where: { $0.name == n }) { choose(.brand(b), label: n) }
                            }.listRowSeparator(.hidden)
                        } header: { Text("热门品牌") }
                    }
                } else {
                    ForEach(brandMatches) { b in
                        row(icon: b.logo, title: b.name, sub: "品牌") { choose(.brand(b), label: b.name) }
                    }
                    ForEach(sugs) { s in
                        if case let .series(id, name) = s.kind {
                            row(icon: nil, title: name, sub: "车系") { choose(s.kind, label: name) }
                        }
                    }
                    row(icon: nil, title: "在已加载车源标题中搜索“\(text)”", sub: "") { choose(.text(text), label: text) }
                }
            }
            .listStyle(.plain)
        }
        .background(Color.white)
        .onAppear { focused = true }
        .task(id: text) {
            let k = text.trimmingCharacters(in: .whitespaces)
            guard !k.isEmpty else { sugs = []; return }
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            sugs = (try? await API.suggest(k)) ?? []
        }
    }

    func row(icon: String?, title: String, sub: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { RemoteImage(url: icon, mode: .fit, maxPoints: 30).frame(width: 24, height: 24) }
                else { Image(systemName: "magnifyingglass").foregroundColor(Theme.gray).frame(width: 24) }
                Text(title).font(.system(size: 15)).foregroundColor(Theme.text).lineLimit(1)
                Spacer()
                if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundColor(Theme.gray) }
            }
        }
    }

    func submit() {
        let k = text.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return }
        if let b = model.allBrands.first(where: { $0.name == k }) { choose(.brand(b), label: k); return }
        Task {
            let s = (try? await API.suggest(k)) ?? sugs
            if let first = s.first, case let .series(_, name) = first.kind, name.localizedCaseInsensitiveContains(k) || k.localizedCaseInsensitiveContains(name) {
                choose(first.kind, label: k)
            } else if let b = brandMatches.first {
                choose(.brand(b), label: k)
            } else {
                choose(.text(k), label: k)
            }
        }
    }

    func choose(_ kind: Suggestion.Kind, label: String) {
        var h = history.filter { $0 != label }; h.insert(label, at: 0)
        historyRaw = h.prefix(12).joined(separator: "\n")
        switch kind {
        case .brand(let b): model.filters.brand = b; model.filters.series = nil; model.filters.keyword = ""
        case .series(let id, let name):
            // suggestions carry no brand id; series_ids alone filters correctly (verified: 卡罗拉 8 = 丰田+卡罗拉 8 in 北京)
            if let b = model.filters.brand, model.seriesBrand == b.id, model.series.contains(where: { $0.id == id }) {} else { model.filters.brand = nil }
            model.filters.series = Series(id: id, name: name, image: ""); model.filters.keyword = ""
        case .text(let t): model.filters.keyword = t
        }
        dismiss()
        switch kind {
        case .text: break
        case .brand: apply(true)
        case .series: apply(false)
        }
    }
}

struct FlowChips: View {
    let items: [String]
    let tap: (String) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { i in
                Button { tap(i) } label: {
                    Text(i).font(.system(size: 13)).foregroundColor(Theme.text).lineLimit(1)
                        .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 30)
                        .background(Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 4))
                }.buttonStyle(.plain)
            }
        }
    }
}
