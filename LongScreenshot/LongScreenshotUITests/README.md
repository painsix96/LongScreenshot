# LongScreenshot UI 测试

本项目包含 LongScreenshot 应用的 UI 测试套件，用于验证应用的用户界面和核心交互流程。

## 目录结构

```
LongScreenshotUITests/
├── MainFlowTests.swift          # 主要用户流程测试
├── BoundaryTests.swift          # 边界情况测试
├── UITestHelper.swift           # 测试辅助工具
├── LongScreenshotUITests.xctestplan  # 测试方案配置
└── README.md                    # 本文档
```

## 测试文件说明

### MainFlowTests.swift
主要用户流程测试，包含以下测试用例：

1. **testAppLaunch** - 应用启动测试
   - 验证主界面元素正确显示
   - 验证导入按钮和 Tab Bar 存在

2. **testTabNavigation** - Tab 导航测试
   - 测试首页、历史、设置三个 Tab 之间的切换
   - 验证页面跳转正确

3. **testImageSelectionFlow** - 图片选择流程测试
   - 验证导入按钮触发相册选择器
   - 验证取消选择行为

4. **testHistoryView** - 历史记录查看测试
   - 验证历史页面正常显示
   - 验证空状态和有数据状态的显示

5. **testSettingsView** - 设置页面测试
   - 验证设置页面结构
   - 验证设置选项存在

6. **testCompleteUserFlow** - 完整流程集成测试
   - 测试从启动到查看历史的完整流程
   - 验证所有 Tab 正常显示

7. **testHomeViewInteractions** - 主界面元素交互测试
   - 验证导入按钮可点击
   - 验证应用图标交互

8. **testDarkModeAppearance** - 深色模式适配测试
   - 验证深色模式下界面正常显示
   - 验证所有 Tab 在深色模式下可用

### BoundaryTests.swift
边界情况测试，包含以下测试用例：

1. **testEmptyPhotoLibraryHandling** - 空相册处理
2. **testMaximumImageCountLimit** - 最大图片数量限制（20张）
3. **testPhotoPermissionDenied** - 权限拒绝处理
4. **testInvalidImageHandling** - 无效图片处理
5. **testCancelOperations** - 取消操作流程
6. **testRapidInteraction** - 快速连续操作测试
7. **testSingleImageSelection** - 单张图片选择处理
8. **testMemoryPressureHandling** - 内存压力测试
9. **testBackgroundResume** - 后台恢复测试
10. **testDeviceRotation** - 设备旋转测试
11. **testErrorAlerts** - 错误提示测试

### UITestHelper.swift
测试辅助工具类，提供以下功能：

#### 等待方法
- `waitFor(seconds:)` - 等待指定时间
- `waitForElement(_:timeout:)` - 等待元素出现
- `waitForElementToDisappear(_:timeout:)` - 等待元素消失
- `waitForAnimations(duration:)` - 等待动画完成

#### 截图方法
- `takeScreenshot(name:)` - 截取屏幕截图
- `takeScreenshot(of:name:)` - 截取特定元素截图

#### 滑动操作
- `swipeUp(on:distance:)` - 向上滑动
- `swipeDown(on:distance:)` - 向下滑动
- `swipeLeft(on:distance:)` - 向左滑动
- `swipeRight(on:distance:)` - 向右滑动

#### 点击操作
- `tapElement(_:timeout:retryCount:)` - 点击元素（带重试）
- `longPressElement(_:duration:)` - 长按元素
- `doubleTapElement(_:)` - 双击元素

#### 文本输入
- `enterText(_:into:clearFirst:)` - 输入文本
- `clearText(in:)` - 清除文本

#### 系统弹窗处理
- `allowSystemAlert(timeout:)` - 允许权限弹窗
- `denySystemAlert(timeout:)` - 拒绝权限弹窗
- `handleSystemAlert(timeout:)` - 自动处理弹窗

## 运行测试

### 在 Xcode 中运行

1. 打开 `LongScreenshot.xcodeproj`
2. 选择目标设备和 iOS 版本
3. 使用快捷键 `Cmd + U` 运行所有测试
4. 或使用 `Cmd + 6` 打开测试导航器，选择特定测试运行

### 使用 xcodebuild 命令行运行

#### 运行所有 UI 测试
```bash
cd /Users/chenhanzhong/Documents/trae_projects/Long-Screenshot/LongScreenshot

xcodebuild test \
  -project LongScreenshot.xcodeproj \
  -scheme LongScreenshot \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest' \
  -testPlan LongScreenshotUITests
```

#### 运行特定测试类
```bash
xcodebuild test \
  -project LongScreenshot.xcodeproj \
  -scheme LongScreenshot \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest' \
  -only-testing:LongScreenshotUITests/MainFlowTests
```

#### 运行特定测试方法
```bash
xcodebuild test \
  -project LongScreenshot.xcodeproj \
  -scheme LongScreenshot \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest' \
  -only-testing:LongScreenshotUITests/MainFlowTests/testAppLaunch
```

### 支持的设备和 iOS 版本

#### 设备支持
- iPhone 15 Pro
- iPhone 15
- iPhone 14 Pro
- iPhone 14
- iPhone SE (3rd generation)
- iPhone 13 mini

#### iOS 版本
- iOS 17.0+
- iOS 16.0+

### 测试方案配置

测试方案配置文件 `LongScreenshotUITests.xctestplan` 定义了以下测试配置：

1. **iPhone 15 Pro - Light Mode**
   - 浅色模式下的完整测试

2. **iPhone 15 Pro - Dark Mode**
   - 深色模式下的完整测试

3. **iPhone SE - Light Mode**
   - 小屏幕设备浅色模式测试

4. **iPhone SE - Dark Mode**
   - 小屏幕设备深色模式测试

## 测试最佳实践

### 1. 编写新测试

```swift
func testNewFeature() throws {
    // 等待首页加载
    XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 5))
    
    // 执行操作
    app.buttons["新功能按钮"].tap()
    helper.waitForAnimations()
    
    // 验证结果
    XCTAssertTrue(app.staticTexts["预期文本"].exists)
    
    // 截图记录
    helper.takeScreenshot(name: "new_feature_result")
}
```

### 2. 使用辅助方法

```swift
// 等待元素
try helper.waitForElement(app.buttons["导入截图"], timeout: 5)

// 截图
helper.takeScreenshot(name: "screenshot_name")

// 滚动查找
helper.scrollTo(text: "目标文本", maxSwipes: 10)

// 处理系统弹窗
helper.allowSystemAlert(timeout: 5)
```

### 3. 调试测试

```swift
// 打印元素树
helper.printElementTree()

// 测量操作时间
helper.measureTime(name: "操作名称") {
    // 执行操作
}

// 验证应用状态
XCTAssertTrue(helper.verifyAppNotCrashed())
```

## 注意事项

1. **相册访问**：系统相册选择器是系统级别的，UI 测试对其访问有限，部分测试可能需要在真机上运行

2. **权限弹窗**：首次运行测试时可能需要处理权限弹窗，可以使用 `allowSystemAlert()` 辅助方法

3. **动画等待**：界面切换和动画需要适当等待，使用 `waitForAnimations()` 确保元素可交互

4. **设备旋转**：部分测试会改变设备方向，测试完成后会恢复默认方向

5. **测试隔离**：每个测试用例独立运行，测试之间不会相互影响

## 故障排除

### 测试失败常见问题

1. **元素未找到**
   - 增加等待时间
   - 检查元素标识符是否正确
   - 使用 `printElementTree()` 查看可用元素

2. **点击无效**
   - 确保元素已出现且可点击
   - 使用 `waitForElementToBeTappable()` 等待元素可交互

3. **系统弹窗未处理**
   - 确保在主线程处理弹窗
   - 增加超时时间

4. **设备方向问题**
   - 测试完成后手动恢复方向
   - 检查是否支持横屏

## 持续集成

可以在 CI/CD 流程中集成 UI 测试：

```bash
# 示例 GitHub Actions 配置
name: UI Tests

on: [push, pull_request]

jobs:
  ui-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Run UI Tests
        run: |
          xcodebuild test \
            -project LongScreenshot.xcodeproj \
            -scheme LongScreenshot \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=latest' \
            -testPlan LongScreenshotUITests
```

## 更新日志

### 2024-04-20
- 创建 UI 测试套件
- 添加 MainFlowTests 主流程测试
- 添加 BoundaryTests 边界测试
- 添加 UITestHelper 辅助工具
- 配置多设备和主题测试方案
