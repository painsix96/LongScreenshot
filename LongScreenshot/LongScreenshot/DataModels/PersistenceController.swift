import CoreData

/// Core Data 持久化控制器
/// 管理 NSPersistentContainer 的创建和生命周期
struct PersistenceController {
    static let shared = PersistenceController()
    
    /// 用于 SwiftUI 预览的内存存储控制器
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        
        // 创建预览数据
        let viewContext = controller.container.viewContext
        for i in 0..<5 {
            let history = StitchHistory(context: viewContext)
            history.id = UUID()
            history.createdAt = Date().addingTimeInterval(-Double(i) * 86400)
            history.updatedAt = history.createdAt
            history.title = "预览长截图 \(i + 1)"
            history.imagePath = "/preview/image\(i).jpg"
            history.thumbnailPath = "/preview/thumb\(i).jpg"
            history.originalImageCount = Int16.random(in: 2...10)
            history.finalImageSize = "{\"width\":1080,\"height\":\(1920 + i * 500)}"
            history.stitchConfig = "{\"overlapRatio\":0.3,\"quality\":0.9}"
        }
        
        do {
            try viewContext.save()
        } catch {
            print("预览数据保存失败: \(error.localizedDescription)")
        }
        
        return controller
    }()
    
    /// NSPersistentContainer 实例
    let container: NSPersistentContainer
    
    /// 主上下文（UI 线程使用）
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }
    
    /// 初始化方法
    /// - Parameter inMemory: 是否使用内存存储（用于预览和测试）
    init(inMemory: Bool = false) {
        // 尝试从 Bundle 加载模型
        guard let modelURL = Bundle.main.url(forResource: "LongScreenshot", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            // 如果找不到编译后的模型，尝试加载 xcdatamodeld
            container = NSPersistentContainer(name: "LongScreenshot")
            
            if inMemory {
                container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
            }
            
            container.loadPersistentStores { description, error in
                if let error = error {
                    fatalError("Core Data 加载失败: \(error.localizedDescription)")
                }
            }
            
            configureContext(container.viewContext)
            return
        }
        
        container = NSPersistentContainer(name: "LongScreenshot", managedObjectModel: model)
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { description, error in
            if let error = error as NSError? {
                /*
                 典型的配置错误包括：
                 - 父目录不存在，无法创建存储文件
                 - 设备没有权限保护存储
                 - 设备存储空间不足
                 - 存储已存在但模型不兼容
                 */
                fatalError("Core Data 存储加载失败: \(error), \(error.userInfo)")
            }
        }
        
        configureContext(container.viewContext)
    }
    
    /// 配置上下文属性
    private func configureContext(_ context: NSManagedObjectContext) {
        // 自动合并来自父上下文的更改
        context.automaticallyMergesChangesFromParent = true
        // 设置合并策略：优先保留内存中的更改
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    /// 创建后台上下文（用于耗时操作）
    /// - Returns: 新的后台 NSManagedObjectContext
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    /// 在后台执行 Core Data 操作
    /// - Parameter block: 在后台上下文中执行的闭包
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        container.performBackgroundTask { context in
            block(context)
        }
    }
    
    /// 保存主上下文
    /// - Throws: 保存失败时抛出错误
    func saveContext() throws {
        let context = container.viewContext
        guard context.hasChanges else { return }
        
        do {
            try context.save()
        } catch {
            throw error
        }
    }
    
    /// 异步保存主上下文
    func saveContextAsync() async throws {
        try await container.viewContext.perform {
            try self.saveContext()
        }
    }
}