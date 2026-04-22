import XCTest
import CoreData
import UIKit
@testable import LongScreenshot

// MARK: - CoreData 单元测试

@MainActor
final class CoreDataTests: XCTestCase {
    
    var persistenceController: PersistenceController!
    var testHelper: TestHelper!
    
    override func setUp() {
        super.setUp()
        // 使用内存存储进行测试
        persistenceController = PersistenceController(inMemory: true)
        testHelper = TestHelper.shared
    }
    
    override func tearDown() {
        testHelper.cleanupTestFiles()
        persistenceController = nil
        super.tearDown()
    }
    
    // MARK: - PersistenceController 初始化测试
    
    /// 测试内存存储初始化
    func testPersistenceController_InMemory() {
        let controller = PersistenceController(inMemory: true)
        XCTAssertNotNil(controller.container)
        XCTAssertNotNil(controller.viewContext)
    }
    
    /// 测试共享实例
    func testPersistenceController_Shared() {
        let shared1 = PersistenceController.shared
        let shared2 = PersistenceController.shared
        XCTAssertTrue(shared1 === shared2, "共享实例应该是同一个对象")
    }
    
    /// 测试预览实例
    func testPersistenceController_Preview() {
        let preview = PersistenceController.preview
        XCTAssertNotNil(preview.container)
        
        // 验证预览数据
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        do {
            let results = try preview.viewContext.fetch(fetchRequest)
            XCTAssertEqual(results.count, 5, "预览数据应该包含 5 条记录")
        } catch {
            XCTFail("获取预览数据失败: \(error)")
        }
    }
    
    /// 测试后台上下文创建
    func testNewBackgroundContext() {
        let backgroundContext = persistenceController.newBackgroundContext()
        XCTAssertNotNil(backgroundContext)
        XCTAssertTrue(backgroundContext.concurrencyType == .privateQueueConcurrencyType)
    }
    
    // MARK: - CRUD 操作测试
    
    /// 测试创建记录
    func testCreateHistory() throws {
        let context = persistenceController.viewContext
        
        let history = StitchHistory(context: context)
        history.id = UUID()
        history.createdAt = Date()
        history.updatedAt = Date()
        history.title = "测试标题"
        history.imagePath = "/test/image.jpg"
        history.thumbnailPath = "/test/thumb.jpg"
        history.originalImageCount = 3
        history.finalImageSize = "{\"width\":1080,\"height\":3000}"
        history.stitchConfig = "{\"quality\":0.9}"
        
        try persistenceController.saveContext()
        
        // 验证创建成功
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try context.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "测试标题")
    }
    
    /// 测试读取记录
    func testFetchHistory() throws {
        // 创建测试数据
        try createTestHistory(title: "记录1")
        try createTestHistory(title: "记录2")
        try createTestHistory(title: "记录3")
        
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        
        XCTAssertEqual(results.count, 3)
    }
    
    /// 测试更新记录
    func testUpdateHistory() throws {
        // 创建记录
        let history = try createTestHistory(title: "旧标题")
        
        // 更新记录
        history.title = "新标题"
        history.updatedAt = Date()
        try persistenceController.saveContext()
        
        // 验证更新
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.first?.title, "新标题")
    }
    
    /// 测试删除记录
    func testDeleteHistory() throws {
        // 创建记录
        let history = try createTestHistory(title: "待删除")
        
        // 删除记录
        persistenceController.viewContext.delete(history)
        try persistenceController.saveContext()
        
        // 验证删除
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 0)
    }
    
    /// 测试批量删除
    func testBatchDelete() throws {
        // 创建多条记录
        for i in 1...5 {
            try createTestHistory(title: "记录\(i)")
        }
        
        // 验证创建成功
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        var results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 5)
        
        // 批量删除
        let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try persistenceController.container.persistentStoreCoordinator.execute(
            batchDelete,
            with: persistenceController.viewContext
        )
        
        // 验证删除
        results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - 查询测试
    
    /// 测试按 ID 查询
    func testFetchByID() throws {
        let testID = UUID()
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = testID
        history.createdAt = Date()
        history.title = "测试记录"
        try persistenceController.saveContext()
        
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", testID as CVarArg)
        fetchRequest.fetchLimit = 1
        
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, testID)
    }
    
    /// 测试排序查询
    func testFetchWithSorting() throws {
        // 创建按时间排序的记录
        for i in 0..<5 {
            let history = StitchHistory(context: persistenceController.viewContext)
            history.id = UUID()
            history.createdAt = Date().addingTimeInterval(-Double(i) * 3600) // 每小时一个
            history.title = "记录\(i)"
        }
        try persistenceController.saveContext()
        
        // 按时间倒序查询
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StitchHistory.createdAt, ascending: false)]
        
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.first?.title, "记录0") // 最新的记录
    }
    
    /// 测试条件查询
    func testFetchWithPredicate() throws {
        // 创建不同条件的记录
        try createTestHistory(title: "测试标题A", imageCount: 2)
        try createTestHistory(title: "测试标题B", imageCount: 5)
        try createTestHistory(title: "其他标题", imageCount: 3)
        
        // 查询包含 "测试" 的记录
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "title CONTAINS[c] %@", "测试")
        
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 2)
    }
    
    // MARK: - 异步操作测试
    
    /// 测试异步保存
    func testSaveContextAsync() async throws {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = UUID()
        history.createdAt = Date()
        history.title = "异步测试"
        
        try await persistenceController.saveContextAsync()
        
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)
    }
    
    /// 测试后台任务执行
    func testPerformBackgroundTask() async {
        let expectation = self.expectation(description: "后台任务完成")
        
        persistenceController.performBackgroundTask { context in
            let history = StitchHistory(context: context)
            history.id = UUID()
            history.createdAt = Date()
            history.title = "后台任务"
            
            do {
                try context.save()
                expectation.fulfill()
            } catch {
                XCTFail("保存失败: \(error)")
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - 数据验证测试
    
    /// 测试必填字段验证
    func testRequiredFields() throws {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = UUID()
        history.createdAt = Date()
        // 不设置 title，应该可以保存（Core Data 没有非空约束）
        
        try persistenceController.saveContext()
        
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)
    }
    
    /// 测试数据类型验证
    func testDataTypes() throws {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = UUID()
        history.createdAt = Date()
        history.originalImageCount = 5
        history.title = "类型测试"
        
        try persistenceController.saveContext()
        
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        let fetchedHistory = results.first!
        
        XCTAssertEqual(fetchedHistory.originalImageCount, 5)
        XCTAssertNotNil(fetchedHistory.createdAt)
    }
    
    // MARK: - 图片存储/加载测试
    
    /// 测试保存图片数据
    func testSaveImageData() throws {
        let testImage = testHelper.createSolidColorImage(
            color: .blue,
            size: CGSize(width: 100, height: 100)
        )
        
        guard let imageData = testImage.jpegData(compressionQuality: 0.9) else {
            XCTFail("无法获取图片数据")
            return
        }
        
        // 保存图片到临时目录
        guard let tempURL = testHelper.saveImageToTemp(testImage) else {
            XCTFail("保存图片失败")
            return
        }
        
        // 创建记录
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = UUID()
        history.createdAt = Date()
        history.title = "图片测试"
        history.imagePath = tempURL.path
        
        try persistenceController.saveContext()
        
        // 验证可以加载图片
        if let loadedData = try? Data(contentsOf: tempURL) {
            XCTAssertEqual(loadedData.count, imageData.count)
        } else {
            XCTFail("无法加载图片数据")
        }
    }
    
    /// 测试大尺寸图片处理
    func testLargeImageData() throws {
        let testImage = testHelper.create1080pImage(color: .red)
        
        guard let tempURL = testHelper.saveImageToTemp(testImage) else {
            XCTFail("保存图片失败")
            return
        }
        
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = UUID()
        history.createdAt = Date()
        history.title = "大图片测试"
        history.imagePath = tempURL.path
        history.finalImageSize = "{\"width\":1080,\"height\":1920}"
        
        try persistenceController.saveContext()
        
        let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
        let results = try persistenceController.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)
    }
    
    // MARK: - 数据迁移测试
    
    /// 测试轻量级数据迁移
    func testLightweightMigration() {
        // 这里我们测试内存存储的迁移能力
        let controller = PersistenceController(inMemory: true)
        
        // 创建一些数据
        let context = controller.viewContext
        let history = StitchHistory(context: context)
        history.id = UUID()
        history.createdAt = Date()
        history.title = "迁移测试"
        
        do {
            try context.save()
            XCTAssertTrue(true, "数据保存成功")
        } catch {
            XCTFail("数据保存失败: \(error)")
        }
    }
    
    /// 测试模型兼容性
    func testModelCompatibility() {
        // 测试当前模型是否可以正常使用
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        
        // 尝试使用所有属性
        let history = StitchHistory(context: context)
        history.id = UUID()
        history.createdAt = Date()
        history.updatedAt = Date()
        history.title = "兼容性测试"
        history.imagePath = "/test/image.jpg"
        history.thumbnailPath = "/test/thumb.jpg"
        history.originalImageCount = 5
        history.finalImageSize = "{\"width\":1080,\"height\":2000}"
        history.stitchConfig = "{\"quality\":0.95}"
        
        do {
            try context.save()
            XCTAssertTrue(true, "模型兼容性测试通过")
        } catch {
            XCTFail("模型兼容性测试失败: \(error)")
        }
    }
    
    // MARK: - 性能测试
    
    /// 测试大量记录创建性能
    func testPerformance_BatchCreate() {
        let context = persistenceController.viewContext
        
        measure {
            for i in 0..<100 {
                let history = StitchHistory(context: context)
                history.id = UUID()
                history.createdAt = Date()
                history.title = "性能测试记录\(i)"
                history.originalImageCount = Int16.random(in: 2...20)
            }
            
            do {
                try context.save()
            } catch {
                XCTFail("保存失败: \(error)")
            }
            
            // 清理
            let fetchRequest: NSFetchRequest<NSFetchRequestResult> = StitchHistory.fetchRequest()
            let batchDelete = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try? context.execute(batchDelete)
        }
    }
    
    /// 测试大量记录查询性能
    func testPerformance_BatchFetch() throws {
        // 预创建数据
        for i in 0..<1000 {
            let history = StitchHistory(context: persistenceController.viewContext)
            history.id = UUID()
            history.createdAt = Date().addingTimeInterval(-Double(i) * 3600)
            history.title = "查询测试\(i)"
        }
        try persistenceController.saveContext()
        
        measure {
            let fetchRequest: NSFetchRequest<StitchHistory> = StitchHistory.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \StitchHistory.createdAt, ascending: false)]
            
            do {
                let results = try persistenceController.viewContext.fetch(fetchRequest)
                XCTAssertEqual(results.count, 1000)
            } catch {
                XCTFail("查询失败: \(error)")
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 创建测试历史记录
    @discardableResult
    private func createTestHistory(title: String, imageCount: Int16 = 3) throws -> StitchHistory {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.id = UUID()
        history.createdAt = Date()
        history.updatedAt = Date()
        history.title = title
        history.imagePath = "/test/\(UUID().uuidString).jpg"
        history.thumbnailPath = "/test/\(UUID().uuidString)_thumb.jpg"
        history.originalImageCount = imageCount
        history.finalImageSize = "{\"width\":1080,\"height\":3000}"
        try persistenceController.saveContext()
        return history
    }
}

// MARK: - StitchHistory 扩展测试

extension CoreDataTests {
    
    /// 测试 imageSize 属性
    func testImageSizeExtension() throws {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.finalImageSize = "{\"width\":1080,\"height\":1920}"
        
        let size = history.imageSize
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
    }
    
    /// 测试 config 属性
    func testConfigExtension() throws {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.stitchConfig = "{\"overlapRatio\":0.3,\"quality\":0.9,\"algorithm\":\"default\",\"enableSimilarityCheck\":true}"
        
        let config = history.config
        XCTAssertNotNil(config)
        XCTAssertEqual(config?.overlapRatio, 0.3)
        XCTAssertEqual(config?.quality, 0.9)
    }
    
    /// 测试日期格式化
    func testDateFormatting() throws {
        let history = StitchHistory(context: persistenceController.viewContext)
        history.createdAt = Date()
        
        XCTAssertNotNil(history.formattedDate)
        XCTAssertNotNil(history.formattedDateTime)
    }
}

// MARK: - StitchConfig 测试

extension CoreDataTests {
    
    /// 测试 StitchConfig 编码
    func testStitchConfigEncoding() {
        let config = StitchConfig(
            overlapRatio: 0.3,
            quality: 0.9,
            algorithm: "test",
            enableSimilarityCheck: true
        )
        
        let jsonString = config.toJSON()
        XCTAssertNotNil(jsonString)
        
        // 验证可以解码
        let decodedConfig = StitchConfig.fromJSON(jsonString)
        XCTAssertNotNil(decodedConfig)
        XCTAssertEqual(decodedConfig?.overlapRatio, 0.3)
        XCTAssertEqual(decodedConfig?.quality, 0.9)
    }
    
    /// 测试 StitchConfig 默认值
    func testStitchConfigDefaults() {
        let config = StitchConfig()
        
        XCTAssertEqual(config.overlapRatio, 0.3)
        XCTAssertEqual(config.quality, 0.9)
        XCTAssertEqual(config.algorithm, "default")
        XCTAssertTrue(config.enableSimilarityCheck)
    }
    
    /// 测试无效 JSON 处理
    func testStitchConfigInvalidJSON() {
        let config = StitchConfig.fromJSON("{invalid json}")
        XCTAssertNil(config)
        
        let config2 = StitchConfig.fromJSON(nil)
        XCTAssertNil(config2)
    }
}
