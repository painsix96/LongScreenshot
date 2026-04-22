# LongScreenshot 单元测试

本文档包含 LongScreenshot 项目的单元测试说明。

## 测试目录结构

```
LongScreenshotTests/
├── Utils/
│   └── TestHelper.swift           # 测试工具类
├── ServicesTests/
│   ├── ImageSimilarityTests.swift  # 图像相似度测试
│   ├── OverlapDetectorTests.swift  # 重叠检测测试
│   └── ImageStitcherTests.swift    # 图像拼接测试
├── ModelsTests/
│   └── CoreDataTests.swift        # Core Data 测试
└── ViewModelsTests/               # ViewModel 测试（预留）
```

## 测试文件说明

### 1. TestHelper.swift

测试工具类，提供以下功能：

#### 图片创建方法
- `createSolidColorImage(color:size:scale:)` - 创建纯色测试图片
- `createScreenshotMockImage(size:baseColor:gradientHeight:)` - 创建模拟截图测试图片
- `createStitchableImagePair(width:height:overlapHeight:)` - 创建可拼接的图片对
- `createStitchableImages(count:width:height:overlapHeight:)` - 创建多张可拼接图片
- `create1080pImage(color:)` - 创建 1080p 测试图片
- `create4KImage(color:)` - 创建 4K 测试图片

#### 图片比较方法
- `areImagesEqual(_:_:tolerance:)` - 比较两张图片是否相同

#### 测试数据清理
- `registerTestFile(_:)` - 注册测试文件路径
- `cleanupTestFiles()` - 清理所有测试文件
- `cleanupCoreData(container:)` - 清理 Core Data 内存存储
- `createTempDirectory()` - 创建临时目录
- `saveImageToTemp(_:filename:)` - 保存图片到临时文件

#### XCTest 扩展
- `waitAsync(timeout:)` - 异步等待
- `measureAsync(_:operation:)` - 测量异步操作执行时间
- `assertPerformance(operation:maxDuration:message:)` - 断言操作在指定时间内完成
- `XCTAssertImagesEqual(_:_:tolerance:file:line:)` - 断言两张图片相等
- `XCTAssertImageSize(_:width:height:file:line:)` - 断言图片尺寸

### 2. ImageSimilarityTests.swift

测试图像相似度计算模块，包含：

#### 感知哈希算法测试 (10 个测试)
- 相同图片应该返回相似度 1.0
- 完全不同图片应该返回低相似度
- 相似图片应该有较高相似度
- 不同尺寸图片应该能正确处理

#### 像素差异计算测试 (3 个测试)
- 相同图片应该返回相似度 1.0
- 轻微颜色变化的图片
- 完全不同颜色应该返回低相似度

#### 特征点匹配测试 (2 个测试)
- 相同图片的特征匹配
- 有内容的图片特征匹配

#### 综合算法测试 (2 个测试)
- 相同图片的综合相似度
- 可拼接的截图相似度

#### 性能测试 (4 个测试)
- 1080p 图片感知哈希计算（< 1秒）
- 1080p 图片像素差异计算（< 1秒）
- 1080p 图片特征匹配计算（< 1秒）
- 1080p 图片综合算法计算（< 3秒）

#### 边界条件测试 (3 个测试)
- 小尺寸图片处理
- 长宽比例极端的图片
- 透明图片处理

#### 扩展测试 (2 个测试)
- 相似度等级计算
- 相似度描述

**总计：26 个测试用例**

### 3. OverlapDetectorTests.swift

测试重叠区域检测模块，包含：

#### 垂直方向重叠检测测试 (5 个测试)
- 有重叠的图片
- 完全相同的图片
- 无重叠的图片
- 大面积重叠
- 小面积重叠

#### 水平方向重叠检测测试 (2 个测试)
- 水平方向重叠检测
- 水平方向与垂直方向的对比

#### 无重叠情况处理测试 (2 个测试)
- 无重叠时的空结果
- 拼接质量等级

#### 批量检测功能测试 (4 个测试)
- 批量重叠检测（5 张图片）
- 图片数量不足
- 两张图片
- 计算总重叠高度

#### 性能测试 (2 个测试)
- 1080p 图片重叠检测（< 5秒）
- 5 张图片批量检测（< 30秒）

#### 边界条件测试 (3 个测试)
- 小尺寸图片的重叠检测
- 不同尺寸图片的重叠检测
- 极端长宽比的图片

**总计：18 个测试用例**

### 4. ImageStitcherTests.swift

测试图像拼接功能模块，包含：

#### 基本拼接功能测试 (3 个测试)
- 两张有重叠的图片
- 相同图片
- 拼接结果的尺寸

#### 多张图片拼接测试 (5 个测试)
- 3 张图片拼接
- 5 张图片拼接
- 10 张图片拼接
- 快速拼接模式
- 静态快速拼接方法

#### 错误处理测试 (4 个测试)
- 图片数量不足错误
- 空数组错误
- 超出最大图片数限制
- 无效图片数据

#### 不同配置测试 (3 个测试)
- 高性能配置
- 高质量配置
- 自定义配置

#### 内存管理测试 (3 个测试)
- 大图片拼接时的内存使用
- 多张 1080p 图片拼接
- 拼接结果的信息完整性

#### 静态方法测试 (3 个测试)
- 静态快速拼接方法
- 静态高质量拼接方法
- 静态方法图片数量不足

#### 性能测试 (2 个测试)
- 两张 1080p 图片拼接（< 30秒）
- 5 张图片拼接（< 60秒）

#### 边界条件测试 (4 个测试)
- 小尺寸图片拼接
- 极端长宽比图片拼接
- 不同宽度图片拼接
- 不同高度图片拼接

#### 扩展测试 (1 个测试)
- OverlapInfo 结构测试

**总计：28 个测试用例**

### 5. CoreDataTests.swift

测试 Core Data 持久化模块，包含：

#### PersistenceController 初始化测试 (4 个测试)
- 内存存储初始化
- 共享实例
- 预览实例
- 后台上下文创建

#### CRUD 操作测试 (4 个测试)
- 创建记录
- 读取记录
- 更新记录
- 删除记录
- 批量删除

#### 查询测试 (3 个测试)
- 按 ID 查询
- 排序查询
- 条件查询

#### 异步操作测试 (2 个测试)
- 异步保存
- 后台任务执行

#### 数据验证测试 (2 个测试)
- 必填字段验证
- 数据类型验证

#### 图片存储/加载测试 (2 个测试)
- 保存图片数据
- 大尺寸图片处理

#### 数据迁移测试 (2 个测试)
- 轻量级数据迁移
- 模型兼容性

#### 性能测试 (2 个测试)
- 批量创建 100 条记录
- 批量查询 1000 条记录

#### StitchHistory 扩展测试 (3 个测试)
- imageSize 属性
- config 属性
- 日期格式化

#### StitchConfig 测试 (3 个测试)
- 编码测试
- 默认值测试
- 无效 JSON 处理

**总计：29 个测试用例**

## 测试覆盖统计

| 模块 | 测试文件 | 测试用例数 | 主要测试内容 |
|------|----------|------------|--------------|
| 工具类 | TestHelper.swift | - | 测试辅助功能 |
| 图像相似度 | ImageSimilarityTests.swift | 26 | 感知哈希、像素差异、特征匹配、性能 |
| 重叠检测 | OverlapDetectorTests.swift | 18 | 重叠区域检测、批量检测、性能 |
| 图像拼接 | ImageStitcherTests.swift | 28 | 拼接功能、错误处理、内存管理 |
| Core Data | CoreDataTests.swift | 29 | CRUD、查询、数据迁移 |
| **总计** | **5 个文件** | **101+** | **全面覆盖核心业务逻辑** |

## 运行测试

### 在 Xcode 中运行

1. 打开项目 `LongScreenshot.xcodeproj`
2. 选择测试目标（Product > Destination）
3. 使用快捷键 `Cmd + U` 运行所有测试
4. 或使用 `Cmd + 6` 打开测试导航器，选择特定测试运行

### 命令行运行

```bash
# 进入项目目录
cd /Users/chenhanzhong/Documents/trae_projects/Long-Screenshot/LongScreenshot

# 运行所有测试
xcodebuild test -project LongScreenshot.xcodeproj -scheme LongScreenshot -destination 'platform=iOS Simulator,name=iPhone 15'

# 运行特定测试类
xcodebuild test -project LongScreenshot.xcodeproj -scheme LongScreenshot -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:LongScreenshotTests/ImageSimilarityTests
```

### 生成测试报告

```bash
# 运行测试并生成 XML 报告
xcodebuild test -project LongScreenshot.xcodeproj -scheme LongScreenshot -destination 'platform=iOS Simulator,name=iPhone 15' -resultBundlePath TestResults.xcresult

# 查看测试结果
xcrun xcresulttool get --path TestResults.xcresult --format json
```

## 测试配置

### 性能测试基准

| 测试项 | 期望时间 | 说明 |
|--------|----------|------|
| 感知哈希（1080p）| < 1秒 | 单张图片相似度计算 |
| 像素差异（1080p）| < 1秒 | 像素级差异计算 |
| 特征匹配（1080p）| < 1秒 | 特征点匹配计算 |
| 综合算法（1080p）| < 3秒 | 综合相似度计算 |
| 重叠检测（1080p）| < 5秒 | 两张图片重叠区域检测 |
| 批量检测（5张）| < 30秒 | 多张图片批量检测 |
| 图片拼接（1080p）| < 30秒 | 两张 1080p 图片拼接 |
| 批量拼接（5张）| < 60秒 | 5 张图片拼接 |
| CoreData 查询 | < 0.5秒 | 1000 条记录排序查询 |
| CoreData 创建 | < 1秒 | 100 条记录批量创建 |

## 注意事项

1. **测试数据清理**：每个测试用例在 `tearDown` 中都会清理测试数据，确保测试之间互不影响
2. **异步测试**：所有异步操作使用 `await` 或 `expectation` 等待完成
3. **内存测试**：大图片测试会打印内存使用情况，用于监控内存泄漏
4. **性能测试**：性能测试使用 `measure` 方法，可以在 Xcode 中查看基准线

## 扩展测试

如需添加新的测试，请遵循以下规范：

1. 按照功能分类放在对应的测试目录中
2. 测试类名以 `Tests` 结尾
3. 测试方法名以 `test` 开头
4. 使用 `@MainActor` 标记 UI 相关的测试类
5. 使用 `///` 添加测试说明注释
