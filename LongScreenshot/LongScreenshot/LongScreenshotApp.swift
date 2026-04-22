import SwiftUI
import CoreData

@main
struct LongScreenshotApp: App {
    // 共享的 Core Data 持久化控制器
    let persistenceController = PersistenceController.shared
    
    init() {
        // 配置 Core Data 调试输出（仅在 DEBUG 模式）
        #if DEBUG
        if CommandLine.arguments.contains("-com.apple.CoreData.SQLDebug") {
            print("Core Data SQL 调试已启用")
        }
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // 注入 Core Data 环境
                .environment(\.managedObjectContext, persistenceController.viewContext)
        }
    }
}

// MARK: - Environment Keys

/// 用于在 SwiftUI 环境中访问 PersistentController 的 Key
private struct PersistenceControllerKey: EnvironmentKey {
    static let defaultValue = PersistenceController.shared
}

extension EnvironmentValues {
    var persistenceController: PersistenceController {
        get { self[PersistenceControllerKey.self] }
        set { self[PersistenceControllerKey.self] = newValue }
    }
}