import SwiftUI

@main struct DCDUsedCarApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}

/// Debug launch arguments (used for screenshots / testing):
///   -city 北京        start city
///   -detail <sku_id>  open a listing detail right away
///   -panel price|brand|age|mileage|sort|more   open a filter panel
///   -search           open the search page
enum LaunchArgs {
    static func value(_ k: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-" + k), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static func flag(_ k: String) -> Bool { ProcessInfo.processInfo.arguments.contains("-" + k) }
}
