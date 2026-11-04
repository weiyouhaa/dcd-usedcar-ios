import SwiftUI

@main struct DCDUsedCarApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

@MainActor final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var tab = LaunchArgs.flag("mine") ? 1 : 0
}

/// 首页 / 我的 tab bar. Each tab owns its navigation stack; detail pages hide the tab bar.
struct RootView: View {
    @ObservedObject private var app = AppState.shared
    @ObservedObject private var store = Store.shared
    var body: some View {
        TabView(selection: $app.tab) {
            HomeView()
                .tabItem { Label("二手车", systemImage: app.tab == 0 ? "car.fill" : "car") }
                .tag(0)
            NavigationStack { MinePage(initialTab: LaunchArgs.flag("history") ? 1 : 0) }
                .tint(Theme.text)
                .tabItem { Label("我的", systemImage: app.tab == 1 ? "person.fill" : "person") }
                .badge(store.compare.count > 0 ? store.compare.count : 0)
                .tag(1)
        }
        .tint(Theme.text)
        .onChange(of: app.tab) { _ in Haptics.select() }
        .modifier(ToastHost())
    }
}

/// Debug launch arguments (used for screenshots / testing):
///   -city 北京        start city (also skips restoring the last saved filters)
///   -detail <sku_id>  open a listing detail right away
///   -panel price|brand|age|mileage|sort|more   open a filter panel
///   -search           open the search page
///   -mine / -history  open the 我的 tab (favorites / history)
///   -seed N           favorite + add-to-compare the first N listed cars (for screenshots)
///   -firstdetail      open the first listed car once the list loads
///   -scrolled         scroll the home list down a bit (collapsed header)
enum LaunchArgs {
    static func value(_ k: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-" + k), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static func flag(_ k: String) -> Bool { ProcessInfo.processInfo.arguments.contains("-" + k) }
}
