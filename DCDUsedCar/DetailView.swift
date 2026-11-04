import SwiftUI

struct DetailView: View {
    let skuId: Int64
    let city: String
    let preview: Car?
    @State private var d: CarDetail?
    @State private var error: String?
    @State private var page = 0
    @State private var viewer: ViewerItem?
    @State private var descExpanded = false
    @State private var showAllFlaws = false
    @State private var showLoan = false
    @State private var openConfig = false
    @State private var openAnalysis = false
    @State private var similar: [Car] = []
    @State private var similarTotal = 0
    @ObservedObject private var store = Store.shared

    struct ViewerItem: Identifiable { let images: [String]; let index: Int; var id: String { "\(index)-\(images.count)" } }

    var webURL: URL { URL(string: "https://www.dongchedi.com/usedcar/\(skuId)")! }

    @State private var scrollY: CGFloat = 0
    @State private var openCompare = false
    @State private var section = ""
    @State private var jumping = false
    var navH: CGFloat { topInset + 44 + 36 + 8 }
    /// Lands a section's 1pt marker just below the sticky nav + tabs instead of under them.
    var sectionAnchorPoint: UnitPoint { UnitPoint(x: 0.5, y: navH / max(UIScreen.main.bounds.height, 1)) }
    var topInset: CGFloat { (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.safeAreaInsets.top ?? 47 }
    @Environment(\.dismiss) private var dismiss

    var galleryH: CGFloat { UIScreen.main.bounds.width * 0.75 }
    /// 0 while the gallery is fully visible, 1 once it has scrolled under the nav bar.
    var navProgress: CGFloat { min(1, max(0, (-scrollY - galleryH * 0.45) / (galleryH * 0.3))) }

    var anchors: [(String, String)] {
        guard let d else { return [] }
        var a: [(String, String)] = [("head", "概览")]
        if !d.params.isEmpty { a.append(("params", "基本信息")) }
        if !d.config.isEmpty || d.carId > 0 { a.append(("config", "配置")) }
        if d.hasReport { a.append(("report", "检测")) }
        if !d.desc.isEmpty { a.append(("desc", "车况")) }
        if !d.shopName.isEmpty { a.append(("shop", "商家")) }
        if !similar.isEmpty { a.append(("similar", "相似")) }
        return a
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 10) {
                gallery
                    .background(GeometryReader { g in Color.clear.preference(key: ScrollTopKey.self, value: g.frame(in: .named("detail")).minY) })
                if let d {
                    headCard(d).sectionAnchor("head", navH)
                    if !d.serviceText.isEmpty { serviceCard(d) }
                    if d.price != nil { priceCard(d) }
                    if !d.params.isEmpty { paramsCard(d).sectionAnchor("params", navH) }
                    if !d.config.isEmpty || d.carId > 0 { configCard(d).sectionAnchor("config", navH) }
                    if d.hasReport { reportCard(d).sectionAnchor("report", navH) }
                    if !d.desc.isEmpty { descCard(d).sectionAnchor("desc", navH) }
                    if !d.shopName.isEmpty { shopCard(d).sectionAnchor("shop", navH) }
                    if !similar.isEmpty { similarCard.sectionAnchor("similar", navH) }
                    Text("非官方工具，数据来自懂车帝网页，仅供参考\n车源编号 \(d.skuId)")
                        .font(.system(size: 11)).foregroundColor(Theme.gray).multilineTextAlignment(.center).padding(.vertical, 16)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 36, weight: .light)).foregroundColor(Theme.faint)
                        Text(error).font(.system(size: 14)).foregroundColor(Theme.gray)
                        Button("重新加载") { Task { await load() } }
                            .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.onYellow)
                            .padding(.horizontal, 22).frame(height: 38).background(Theme.yellow).clipShape(Capsule())
                    }.padding(.top, 40)
                } else {
                    if let p = preview { previewHead(p) }
                    skeletonCards
                }
            }
        }
        .coordinateSpace(name: "detail")
        .ignoresSafeArea(edges: .top)
        .trackScrollTop()
        .onPreferenceChange(ScrollTopKey.self) { scrollY = $0 }
        .onPreferenceChange(SectionPosKey.self) { pos in
            // Highlight the section whose card has scrolled under the sticky nav + tabs.
            guard !jumping, navProgress >= 1 else { return }
            let line = navH + 16
            let cur = anchors.last { (pos[$0.0] ?? .infinity) <= line }?.0 ?? anchors.first?.0 ?? ""
            if cur != section { section = cur }
        }
        .overlay(alignment: .top) { topBar(proxy) }
        .onChange(of: d?.skuId) { _ in
            if let a = LaunchArgs.value("scroll") {
                section = a
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(a, anchor: sectionAnchorPoint) }
            }
        }
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { if d != nil { bottomBar } }
        .task { if d == nil { await load() } }
        .fullScreenCover(item: $viewer) { v in ImageViewer(images: v.images, index: v.index) }
        .navigationDestination(isPresented: $openConfig) { if let d { FullConfigView(carId: d.carId, title: d.title) } }
        .navigationDestination(isPresented: $openAnalysis) { PriceAnalysisView(sku: skuId) }
        .navigationDestination(isPresented: $openCompare) { CompareView(cars: store.compare) }
        .sheet(isPresented: $showLoan) {
            if let d, let p = d.price {
                LoanSheet(price: p, ratio: d.finRatio, months: d.finMonths, officialMonthPay: Double(d.monthPay) ?? 0, officialDown: Double(d.downPayment) ?? 0)
            }
        }
    }

    // MARK: custom nav bar — transparent over the photo, fades to solid with title + section tabs
    func topBar(_ proxy: ScrollViewProxy) -> some View {
        let p = navProgress
        return VStack(spacing: 0) {
            HStack(spacing: 4) {
                circleButton("chevron.left", p) { dismiss() }
                Text(d?.title ?? preview?.title ?? "车源详情").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                    .lineLimit(1).opacity(p).frame(maxWidth: .infinity)
                ShareLink(item: webURL) { circleIcon("square.and.arrow.up", p) }
            }
            .padding(.horizontal, 8).frame(height: 44)
            if p >= 1 && anchors.count > 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(anchors, id: \.0) { a in
                            Button {
                                Haptics.select(); section = a.0; jumping = true
                                withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(a.0, anchor: sectionAnchorPoint) }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { jumping = false }
                            } label: {
                                VStack(spacing: 5) {
                                    Text(a.1).font(.system(size: 14, weight: section == a.0 ? .semibold : .regular))
                                        .foregroundColor(section == a.0 ? Theme.text : Theme.text2)
                                    Capsule().fill(section == a.0 ? Theme.yellow : .clear).frame(width: 18, height: 3)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 36)
                .transition(.opacity)
            }
        }
        .background(Theme.card.opacity(p).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5).opacity(p) }
        .animation(.easeOut(duration: 0.18), value: p >= 1)
    }

    func circleIcon(_ name: String, _ p: CGFloat) -> some View {
        Image(systemName: name).font(.system(size: 17, weight: .semibold))
            .foregroundColor(p > 0.5 ? Theme.text : .white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.black.opacity(0.32 * (1 - p))))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }
    func circleButton(_ name: String, _ p: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { circleIcon(name, p) }
    }

    // MARK: sticky bottom action bar
    var bottomBar: some View {
        let fav = store.isFav(skuId), cmp = store.inCompare(skuId)
        return HStack(spacing: 0) {
            barItem(fav ? "heart.fill" : "heart", fav ? "已收藏" : "收藏", tint: fav ? Theme.heart : Theme.text) {
                guard let d else { return }
                store.toggleFav(favCar(d))
                if fav { Haptics.tap(); Toast.shared.show("已取消收藏") } else { Haptics.success(); Toast.shared.show("已收藏，降价会在「我的」提醒") }
            }
            barItem(cmp ? "checkmark.square.fill" : "plus.square.on.square", cmp ? "对比 \(store.compare.count)" : "加入对比", tint: cmp ? Color(hex: 0xFFB300) : Theme.text) {
                guard let d else { return }
                if cmp {
                    if store.compare.count >= 2 { Haptics.tap(); openCompare = true }
                    else { Toast.shared.show("再加 1 辆即可对比") }
                } else if store.addCompare(favCar(d)) {
                    Haptics.success()
                    Toast.shared.show(store.compare.count >= 2 ? "已加入对比，再点「对比」查看" : "已加入对比（\(store.compare.count)/4）")
                } else { Toast.shared.show("对比清单最多 4 辆，请先在「我的」移出") }
            }
            ShareLink(item: webURL) {
                VStack(spacing: 3) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18))
                    Text("分享").font(.system(size: 10))
                }
                .foregroundColor(Theme.text).frame(width: 58, height: 48)
            }
            Spacer(minLength: 8)
            if d?.price != nil {
                Button { Haptics.tap(); showLoan = true } label: {
                    VStack(spacing: 1) {
                        Text("算月供").font(.system(size: 15, weight: .semibold))
                        if let d, !d.monthPay.isEmpty { Text("月供约\(d.monthPay)元").font(.system(size: 10)) }
                    }
                    .foregroundColor(Theme.onYellow).frame(minWidth: 128).frame(height: 44)
                    .background(Theme.yellow).clipShape(Capsule())
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.leading, 6).padding(.trailing, 14).padding(.vertical, 6)
        .background(Theme.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 0.5) }
    }

    func barItem(_ icon: String, _ text: String, tint: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18)).foregroundColor(tint)
                Text(text).font(.system(size: 10)).foregroundColor(Theme.text).lineLimit(1).fixedSize()
            }
            .frame(minWidth: 58).frame(height: 48).contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    var skeletonCards: some View {
        VStack(spacing: 10) {
            card { VStack(alignment: .leading, spacing: 10) { Bone(w: 120, h: 26); Bone(h: 18); Bone(w: 200, h: 18); Bone(h: 56, r: 8) } }
            card { VStack(alignment: .leading, spacing: 12) { Bone(w: 80, h: 17); HStack(spacing: 20) { ForEach(0..<3, id: \.self) { _ in VStack(alignment: .leading, spacing: 6) { Bone(w: 60, h: 15); Bone(w: 40, h: 11) } } } } }
            card { VStack(alignment: .leading, spacing: 10) { Bone(w: 80, h: 17); ForEach(0..<4, id: \.self) { _ in Bone(h: 14) } } }
        }
        .modifier(Shimmer())
    }

    /// Keep the list row (with its tags / sub line) when we have one; otherwise build from detail.
    func favCar(_ d: CarDetail) -> Car {
        var c = preview ?? d.asCar(city: city)
        if let p = d.price { c.price = p.wan }
        if c.city.isEmpty { c.city = city }
        return c
    }

    var similarCard: some View {
        card("相似车源") {
            VStack(spacing: 0) {
                ForEach(similar.prefix(8)) { c in
                    NavigationLink(value: c) { CarRow(car: c).padding(.horizontal, -14) }
                        .buttonStyle(PrefetchPress { DetailCache.shared.prefetch(c.id, city: c.city.isEmpty ? city : c.city) })
                }
                if similarTotal > 8 {
                    Text("同价位同级别共 \(similarTotal) 辆在售").font(.system(size: 12)).foregroundColor(Theme.gray).padding(.top, 8)
                }
            }
        }
    }

    func load() async {
        error = nil
        do {
            let x = try await DetailCache.shared.get(skuId, city: city)
            d = x
            store.visit(favCar(x))
            if let p = x.batteryPlan { BatteryStore.shared.set(skuId, p) }
            if LaunchArgs.flag("loan") { showLoan = true }
            if LaunchArgs.flag("viewer"), !x.images.isEmpty { viewer = ViewerItem(images: x.images, index: 0) }
            if LaunchArgs.flag("fullconfig") { openConfig = true }
            if LaunchArgs.flag("analysis") { openAnalysis = true }
            if LaunchArgs.flag("fav") && !store.isFav(skuId) { store.toggleFav(favCar(x)) }
            if x.seriesId > 0, let list = try? await API.similar(series: x.seriesId, city: city, exclude: skuId) {
                similar = list; similarTotal = list.count
            }
        }
        catch APIError.empty { error = "该车源已下架或不存在" }
        catch { self.error = "加载失败（可能被限流），请重试" }
    }

    // MARK: gallery
    var images: [String] { d?.images.isEmpty == false ? d!.images : (preview.map { [$0.image] } ?? []) }

    var gallery: some View {
        ZStack(alignment: .bottomTrailing) {
            if images.isEmpty {
                Theme.chipBg
            } else {
                TabView(selection: $page) {
                    ForEach(images.indices, id: \.self) { i in
                        RemoteImage(url: images[i], maxPoints: 440).frame(maxWidth: .infinity).clipped()
                            .contentShape(Rectangle())
                            .onTapGesture { viewer = ViewerItem(images: images, index: i) }
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            if images.count > 1 {
                Text("\(page + 1)/\(images.count)").font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                    .padding(.horizontal, 10).frame(height: 22).background(Color.black.opacity(0.5)).clipShape(Capsule()).padding(12)
            }
        }
        .frame(height: galleryH)
    }

    func previewHead(_ p: Car) -> some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Text(p.price).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.price)
                Text(p.title).font(.system(size: 18, weight: .semibold)).foregroundColor(Theme.text)
            }
        }
    }

    // MARK: cards
    func card<C: View>(_ title: String? = nil, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text) }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.rCard, style: .continuous))
        .padding(.horizontal, 10)
    }

    func headCard(_ d: CarDetail) -> some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(d.price?.wan ?? preview?.price ?? "").font(.system(size: 28, weight: .bold)).foregroundColor(Theme.price)
                    if !d.taxPrice.isEmpty {
                        Text("新车含税价 \(d.taxPrice)").font(.system(size: 12)).foregroundColor(Theme.gray)
                    }
                    Spacer()
                }
                if !d.officialPrice.isEmpty || !d.downPayment.isEmpty {
                    HStack(spacing: 10) {
                        if !d.officialPrice.isEmpty { Text("指导价 \(d.officialPrice)").font(.system(size: 12)).foregroundColor(Theme.gray) }
                        if d.price != nil {
                            Button { showLoan = true } label: {
                                HStack(spacing: 2) {
                                    Text(!d.downPayment.isEmpty && !d.monthPay.isEmpty ? "首付\(d.downPayment)万 · 月供\(d.monthPay)元" : "贷款计算")
                                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                                }
                                .font(.system(size: 12)).foregroundColor(Theme.text2)
                                .padding(.horizontal, 6).frame(height: 20).background(Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                }
                if d.isSelfTrade {
                    SelfBadge(text: "懂车帝官方直营")
                }
                Text(d.title).font(.system(size: 19, weight: .semibold)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                let tags = d.tags + (preview?.tags ?? []).filter { t in !d.tags.contains { $0.text == t.text } }
                let plan = d.batteryPlan
                if !tags.isEmpty || plan != nil {
                    HStack(spacing: 6) {
                        if let plan { BatteryBadge(plan: plan, long: true) }
                        ForEach(tags.prefix(plan == nil ? 4 : 3), id: \.self) { TagView(tag: $0) }
                    }
                }
                if plan != nil {
                    Text(plan == .unknown ? "懂车帝未提供电池方案字段，卖家描述中也未写明租电或买断，请向车商确认" : "依据：卖家车况描述中写明“\(plan!.label)”，以实际合同为准")
                        .font(.system(size: 11)).foregroundColor(Theme.faint).fixedSize(horizontal: false, vertical: true)
                }
                if !d.importantText.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(d.importantText.indices, id: \.self) { i in
                            let (v, l) = splitImportant(d.importantText[i])
                            VStack(spacing: 4) {
                                Text(v).font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                                Text(l).font(.system(size: 12)).foregroundColor(Theme.gray)
                            }.frame(maxWidth: .infinity)
                            if i < d.importantText.count - 1 { Rectangle().fill(Theme.line).frame(width: 0.5, height: 28) }
                        }
                    }
                    .padding(.vertical, 12).background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    /// "2014年上牌" -> ("2014年", "上牌"); "7.70万公里" -> ("7.70万公里", "表显里程"); "北京车源" -> ("北京", "车源地")
    func splitImportant(_ s: String) -> (String, String) {
        if s.hasSuffix("上牌") { return (String(s.dropLast(2)), "上牌时间") }
        if s.hasSuffix("公里") { return (s, "表显里程") }
        if s.hasSuffix("车源") { return (String(s.dropLast(2)), "车源地") }
        return (s, "")
    }

    func serviceCard(_ d: CarDetail) -> some View {
        card {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.shield.fill").foregroundColor(Theme.selText)
                Text(d.serviceText.replacingOccurrences(of: "·", with: "  ·  ")).font(.system(size: 13)).foregroundColor(Theme.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func priceCard(_ d: CarDetail) -> some View {
        card("价格分析") {
            VStack(alignment: .leading, spacing: 8) {
                if !d.priceTips.isEmpty {
                    Text(d.priceTips).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.selText)
                        .padding(.horizontal, 8).frame(height: 26).background(Theme.selBg).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if !d.popularity.isEmpty { Label(d.popularity, systemImage: "flame").font(.system(size: 13)).foregroundColor(Theme.text2) }
                if !d.priceDesc.isEmpty { Text(d.priceDesc).font(.system(size: 13)).foregroundColor(Theme.gray).fixedSize(horizontal: false, vertical: true) }
                Button { openAnalysis = true } label: { moreLink("查看价格分析报告") }
            }
        }
    }

    func grid(_ items: [KV]) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
            ForEach(items, id: \.self) { kv in
                VStack(alignment: .leading, spacing: 4) {
                    Text(kv.value).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text).lineLimit(2).minimumScaleFactor(0.8)
                    Text(kv.name).font(.system(size: 12)).foregroundColor(Theme.gray)
                }
            }
        }
    }

    func paramsCard(_ d: CarDetail) -> some View {
        card("基本信息") { grid(d.params) }
    }

    func moreLink(_ t: String) -> some View {
        HStack(spacing: 3) {
            Text(t); Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
        }
        .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
        .frame(maxWidth: .infinity).frame(height: 38).background(Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 6)).padding(.top, 4)
    }

    func configCard(_ d: CarDetail) -> some View {
        card("配置参数") {
            VStack(spacing: 0) {
                ForEach(d.config, id: \.self) { kv in
                    HStack {
                        Text(kv.name).font(.system(size: 14)).foregroundColor(Theme.gray)
                        Spacer()
                        Text(kv.value).font(.system(size: 14)).foregroundColor(Theme.text)
                    }
                    .padding(.vertical, 9)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 0.5) }
                }
                if d.carId > 0 { Button { openConfig = true } label: { moreLink("查看全部参数配置") } }
            }
        }
    }

    func reportCard(_ d: CarDetail) -> some View {
        card("检测报告") {
            VStack(alignment: .leading, spacing: 12) {
                if !d.reportCates.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(d.reportCates, id: \.self) { c in
                            VStack(spacing: 4) {
                                Text(c.defect == 0 ? "无异常" : "\(c.defect)项异常").font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(c.defect == 0 ? Theme.green : Theme.price)
                                Text("\(c.name) · \(c.total)项").font(.system(size: 11)).foregroundColor(Theme.gray)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 10).background(Theme.bg).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                ForEach(d.reportOverview, id: \.self) { kv in
                    HStack(alignment: .top, spacing: 10) {
                        Text(kv.name).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text).frame(width: 70, alignment: .leading)
                        Text(kv.value).font(.system(size: 13)).foregroundColor(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !d.reportFlaws.isEmpty {
                    Text("瑕疵记录（\(d.reportFlaws.count)）").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text).padding(.top, 4)
                    ForEach(Array((showAllFlaws ? d.reportFlaws : Array(d.reportFlaws.prefix(3))).enumerated()), id: \.offset) { _, f in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(f.name).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                                Text(f.desc).font(.system(size: 13)).foregroundColor(Theme.text2).fixedSize(horizontal: false, vertical: true)
                            }
                            if !f.images.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(f.images.indices, id: \.self) { i in
                                            RemoteImage(url: f.images[i], maxPoints: 100).frame(width: 96, height: 72).clipShape(RoundedRectangle(cornerRadius: 4))
                                                .onTapGesture { viewer = ViewerItem(images: f.images, index: i) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    if d.reportFlaws.count > 3 {
                        Button(showAllFlaws ? "收起" : "查看全部 \(d.reportFlaws.count) 项") { showAllFlaws.toggle() }
                            .font(.system(size: 13)).foregroundColor(Theme.text2).frame(maxWidth: .infinity)
                    }
                }
                if !d.reportTip.isEmpty {
                    Text(d.reportTip).font(.system(size: 11)).foregroundColor(Theme.gray).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func descCard(_ d: CarDetail) -> some View {
        card("车况描述") {
            VStack(alignment: .leading, spacing: 8) {
                Text(d.desc).font(.system(size: 14)).foregroundColor(Theme.text2).lineSpacing(4)
                    .lineLimit(descExpanded ? nil : 5).fixedSize(horizontal: false, vertical: true)
                Button(descExpanded ? "收起" : "展开全部") { descExpanded.toggle() }
                    .font(.system(size: 13)).foregroundColor(Theme.selText)
            }
        }
    }

    func shopCard(_ d: CarDetail) -> some View {
        card("商家信息") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if !d.shopLogo.isEmpty { RemoteImage(url: d.shopLogo, maxPoints: 44).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(d.shopName).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                        Text([d.shopSalesNum > 0 ? "在售\(d.shopSalesNum)辆" : "", d.shopRange, d.shopHours.isEmpty ? "" : "营业 \(d.shopHours)"].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundColor(Theme.gray)
                    }
                }
                if !d.shopAddress.isEmpty {
                    Label(d.shopAddress, systemImage: "mappin.and.ellipse").font(.system(size: 12)).foregroundColor(Theme.text2)
                }
                if d.shopFullName != d.shopName && !d.shopFullName.isEmpty {
                    Text(d.shopFullName).font(.system(size: 11)).foregroundColor(Theme.gray)
                }
            }
        }
    }
}

struct SectionPosKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

extension View {
    /// Reports the card's top (in the detail scroll space) for section-tab tracking.
    /// 1pt scroll marker at the card's top edge plus its position for section-tab tracking.
    func sectionAnchor(_ id: String, _ navH: CGFloat) -> some View {
        background(GeometryReader { g in Color.clear.preference(key: SectionPosKey.self, value: [id: g.frame(in: .named("detail")).minY]) })
            .background(alignment: .top) { Color.clear.frame(height: 1).allowsHitTesting(false).id(id) }
    }
}

struct ImageViewer: View {
    let images: [String]
    @State var index: Int
    @State private var drag: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(1 - min(drag / 500, 0.85)).ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    ZoomableImage(url: images[i], onTap: { dismiss() }, onDrag: { drag = $0 }).tag(i).ignoresSafeArea()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            HStack {
                Text("\(index + 1)/\(images.count)").foregroundColor(.white).font(.system(size: 15, weight: .medium))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                        .frame(width: 36, height: 36).background(Circle().fill(Color.white.opacity(0.15)))
                }
            }.padding(.horizontal, 16).padding(.top, 8).opacity(drag > 10 ? 0 : 1)
            VStack { Spacer(); Text("双指或双击放大 · 下滑或单击关闭").font(.system(size: 11)).foregroundColor(.white.opacity(0.5)).padding(.bottom, 12) }
        }
        .statusBarHidden()
        .modifier(ClearCoverBackground())
        .onChange(of: index) { _ in Haptics.select() }
    }
}

/// Lets the page underneath show through while the viewer is dragged down (iOS 16.4+).
struct ClearCoverBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) { content.presentationBackground(.clear) } else { content }
    }
}

/// Pinch / double-tap zoom (1–4x) backed by UIScrollView; single tap closes.
struct ZoomableImage: UIViewRepresentable {
    let url: String
    let onTap: () -> Void
    var onDrag: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coord { Coord(onTap: onTap, onDrag: onDrag) }

    func makeUIView(context: Context) -> UIScrollView {
        let sv = UIScrollView()
        sv.minimumZoomScale = 1; sv.maximumZoomScale = 4
        sv.showsVerticalScrollIndicator = false; sv.showsHorizontalScrollIndicator = false
        sv.contentInsetAdjustmentBehavior = .never
        sv.delegate = context.coordinator
        sv.backgroundColor = .clear
        let iv = UIImageView(); iv.contentMode = .scaleAspectFit
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        iv.frame = sv.bounds
        sv.addSubview(iv)
        context.coordinator.imageView = iv
        context.coordinator.scroll = sv
        let dbl = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.doubleTap(_:)))
        dbl.numberOfTapsRequired = 2
        let one = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coord.singleTap))
        one.require(toFail: dbl)
        sv.addGestureRecognizer(dbl); sv.addGestureRecognizer(one)
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coord.pan(_:)))
        pan.delegate = context.coordinator
        context.coordinator.dismissPan = pan
        sv.addGestureRecognizer(pan)
        if let img = ImageLoader.shared.cached(url, px: 2000) { iv.image = img } else {
            let spinner = UIActivityIndicatorView(style: .medium); spinner.color = .white; spinner.startAnimating()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            sv.addSubview(spinner)
            NSLayoutConstraint.activate([spinner.centerXAnchor.constraint(equalTo: sv.frameLayoutGuide.centerXAnchor), spinner.centerYAnchor.constraint(equalTo: sv.frameLayoutGuide.centerYAnchor)])
            Task { @MainActor in
                let img = await ImageLoader.shared.load(url, px: 2000)
                spinner.removeFromSuperview()
                UIView.transition(with: iv, duration: 0.2, options: .transitionCrossDissolve) { iv.image = img }
            }
        }
        return sv
    }

    func updateUIView(_ sv: UIScrollView, context: Context) {
        if sv.zoomScale == 1, let iv = context.coordinator.imageView, iv.frame.size != sv.bounds.size { iv.frame = sv.bounds }
    }

    final class Coord: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let onTap: () -> Void
        let onDrag: (CGFloat) -> Void
        weak var imageView: UIImageView?
        weak var scroll: UIScrollView?
        weak var dismissPan: UIPanGestureRecognizer?
        init(onTap: @escaping () -> Void, onDrag: @escaping (CGFloat) -> Void) { self.onTap = onTap; self.onDrag = onDrag }

        /// Swipe-down-to-close only at 1x and only for mostly-vertical downward drags (horizontal = paging).
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard g === dismissPan, let p = g as? UIPanGestureRecognizer, let sv = scroll else { return true }
            let v = p.velocity(in: sv)
            return sv.zoomScale <= 1.01 && v.y > 0 && v.y > abs(v.x) * 1.3
        }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            guard let iv = imageView else { return }
            let t = g.translation(in: g.view?.superview)
            switch g.state {
            case .changed:
                let dy = max(0, t.y), s = 1 - min(dy / 1600, 0.2)
                iv.transform = CGAffineTransform(translationX: t.x * 0.6, y: dy).scaledBy(x: s, y: s)
                onDrag(dy)
            case .ended, .cancelled, .failed:
                if t.y > 110 || g.velocity(in: g.view).y > 900 { onTap() }
                else {
                    UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) { iv.transform = .identity }
                    onDrag(0)
                }
            default: break
            }
        }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func singleTap() { onTap() }
        @objc func doubleTap(_ g: UITapGestureRecognizer) {
            guard let sv = scroll, let iv = imageView else { return }
            if sv.zoomScale > 1 { sv.setZoomScale(1, animated: true); return }
            let p = g.location(in: iv), s: CGFloat = 2.5
            let w = sv.bounds.width / s, h = sv.bounds.height / s
            sv.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
        }
    }
}

/// Keep the edge swipe-back gesture when a page hides the system navigation bar.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
