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

    struct ViewerItem: Identifiable { let images: [String]; let index: Int; var id: String { "\(index)-\(images.count)" } }

    var webURL: URL { URL(string: "https://www.dongchedi.com/usedcar/\(skuId)")! }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: 10) {
                gallery
                if let d {
                    headCard(d)
                    if !d.serviceText.isEmpty { serviceCard(d) }
                    if !d.priceTips.isEmpty || !d.popularity.isEmpty { priceCard(d) }
                    if !d.params.isEmpty { paramsCard(d).id("params") }
                    if !d.config.isEmpty { configCard(d).id("config") }
                    if d.hasReport { reportCard(d).id("report") }
                    if !d.desc.isEmpty { descCard(d).id("desc") }
                    if !d.shopName.isEmpty { shopCard(d).id("shop") }
                    Text("非官方工具，数据来自懂车帝网页，仅供参考\n车源编号 \(d.skuId)")
                        .font(.system(size: 11)).foregroundColor(Theme.gray).multilineTextAlignment(.center).padding(.vertical, 16)
                } else if let error {
                    VStack(spacing: 10) {
                        Text(error).font(.system(size: 14)).foregroundColor(Theme.gray)
                        Button("重新加载") { Task { await load() } }
                            .font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                            .padding(.horizontal, 20).frame(height: 34).background(Theme.yellow).clipShape(Capsule())
                    }.padding(.top, 40)
                } else {
                    if let p = preview { previewHead(p) }
                    ProgressView().padding(30)
                }
            }
        }
        .onChange(of: d?.skuId) { _ in
            if let a = LaunchArgs.value("scroll") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { proxy.scrollTo(a, anchor: .top) }
            }
        }
        }
        .background(Theme.bg)
        .navigationTitle("车源详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: webURL) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .task { if d == nil { await load() } }
        .fullScreenCover(item: $viewer) { v in ImageViewer(images: v.images, index: v.index) }
    }

    func load() async {
        error = nil
        do { d = try await DetailCache.shared.get(skuId, city: city) }
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
        .frame(height: UIScreen.main.bounds.width * 0.75)
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        if !d.downPayment.isEmpty && !d.monthPay.isEmpty {
                            Text("首付\(d.downPayment)万 · 月供\(d.monthPay)元").font(.system(size: 12)).foregroundColor(Theme.text2)
                                .padding(.horizontal, 6).frame(height: 20).background(Theme.chipBg).clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                }
                if d.isSelfTrade {
                    SelfBadge(text: "懂车帝官方直营")
                }
                Text(d.title).font(.system(size: 19, weight: .semibold)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                let tags = d.tags + (preview?.tags ?? []).filter { t in !d.tags.contains { $0.text == t.text } }
                if !tags.isEmpty {
                    HStack(spacing: 6) { ForEach(tags.prefix(4), id: \.self) { TagView(tag: $0) } }
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
                                    .foregroundColor(c.defect == 0 ? Color(hex: 0x1BA35C) : Theme.price)
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

struct ImageViewer: View {
    let images: [String]
    @State var index: Int
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(images.indices, id: \.self) { i in
                    RemoteImage(url: images[i], mode: .fit, maxPoints: 1000).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onTapGesture { dismiss() }
            HStack {
                Text("\(index + 1)/\(images.count)").foregroundColor(.white).font(.system(size: 15, weight: .medium))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundColor(.white) }
            }.padding()
        }
    }
}
