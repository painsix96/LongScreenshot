import XCTest

/// UI 测试辅助工具类
/// 提供常用的测试操作封装和辅助方法
class UITestHelper {
    
    let app: XCUIApplication
    
    /// 初始化
    /// - Parameter app: XCUIApplication 实例
    init(app: XCUIApplication) {
        self.app = app
    }
    
    // MARK: - 等待方法
    
    /// 等待指定时间
    /// - Parameter seconds: 等待秒数
    func waitFor(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
    
    /// 等待元素出现
    /// - Parameters:
    ///   - element: 要等待的元素
    ///   - timeout: 超时时间（秒）
    /// - Returns: 元素是否在规定时间内出现
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }
    
    /// 等待元素消失
    /// - Parameters:
    ///   - element: 要等待消失的元素
    ///   - timeout: 超时时间（秒）
    /// - Returns: 元素是否在规定时间内消失
    @discardableResult
    func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// 等待元素可点击
    /// - Parameters:
    ///   - element: 要等待的元素
    ///   - timeout: 超时时间（秒）
    /// - Returns: 元素是否在规定时间内可点击
    @discardableResult
    func waitForElementToBeTappable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if element.exists && element.isHittable {
                return true
            }
            waitFor(seconds: 0.1)
        }
        return false
    }
    
    /// 等待动画完成
    /// - Parameter duration: 动画持续时间（默认 0.5 秒）
    func waitForAnimations(duration: TimeInterval = 0.5) {
        waitFor(seconds: duration)
    }
    
    // MARK: - 截图方法
    
    /// 截取屏幕截图
    /// - Parameter name: 截图名称
    /// - Returns: 截图数据
    @discardableResult
    func takeScreenshot(name: String = "screenshot") -> XCUIScreenshot {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.add(attachment)
        return screenshot
    }
    
    /// 截取特定元素的截图
    /// - Parameters:
    ///   - element: 要截图的元素
    ///   - name: 截图名称
    /// - Returns: 截图数据
    @discardableResult
    func takeScreenshot(of element: XCUIElement, name: String) -> XCUIScreenshot {
        let screenshot = element.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.add(attachment)
        return screenshot
    }
    
    // MARK: - 滑动操作
    
    /// 向上滑动
    /// - Parameters:
    ///   - element: 滑动目标元素（默认为整个窗口）
    ///   - distance: 滑动距离比例（0-1）
    func swipeUp(on element: XCUIElement? = nil, distance: CGFloat = 0.5) {
        let target = element ?? app.windows.firstMatch
        target.swipeUp()
    }
    
    /// 向下滑动
    /// - Parameters:
    ///   - element: 滑动目标元素（默认为整个窗口）
    ///   - distance: 滑动距离比例（0-1）
    func swipeDown(on element: XCUIElement? = nil, distance: CGFloat = 0.5) {
        let target = element ?? app.windows.firstMatch
        target.swipeDown()
    }
    
    /// 向左滑动
    /// - Parameters:
    ///   - element: 滑动目标元素（默认为整个窗口）
    ///   - distance: 滑动距离比例（0-1）
    func swipeLeft(on element: XCUIElement? = nil, distance: CGFloat = 0.5) {
        let target = element ?? app.windows.firstMatch
        target.swipeLeft()
    }
    
    /// 向右滑动
    /// - Parameters:
    ///   - element: 滑动目标元素（默认为整个窗口）
    ///   - distance: 滑动距离比例（0-1）
    func swipeRight(on element: XCUIElement? = nil, distance: CGFloat = 0.5) {
        let target = element ?? app.windows.firstMatch
        target.swipeRight()
    }
    
    /// 自定义滑动
    /// - Parameters:
    ///   - element: 滑动目标元素
    ///   - startPoint: 起始点（相对坐标 0-1）
    ///   - endPoint: 结束点（相对坐标 0-1）
    func swipe(from startPoint: CGVector, to endPoint: CGVector, on element: XCUIElement? = nil) {
        let target = element ?? app.windows.firstMatch
        let coordinate1 = target.coordinate(withNormalizedOffset: startPoint)
        let coordinate2 = target.coordinate(withNormalizedOffset: endPoint)
        coordinate1.press(forDuration: 0.1, thenDragTo: coordinate2)
    }
    
    // MARK: - 点击操作
    
    /// 点击元素（带重试机制）
    /// - Parameters:
    ///   - element: 要点击的元素
    ///   - timeout: 超时时间
    ///   - retryCount: 重试次数
    /// - Returns: 点击是否成功
    @discardableResult
    func tapElement(_ element: XCUIElement, timeout: TimeInterval = 5, retryCount: Int = 3) -> Bool {
        for _ in 0..<retryCount {
            if waitForElementToBeTappable(element, timeout: timeout) {
                element.tap()
                return true
            }
        }
        return false
    }
    
    /// 长按元素
    /// - Parameters:
    ///   - element: 要长按的元素
    ///   - duration: 长按持续时间
    func longPressElement(_ element: XCUIElement, duration: TimeInterval = 1.0) {
        if element.waitForExistence(timeout: 5) {
            element.press(forDuration: duration)
        }
    }
    
    /// 双击元素
    /// - Parameter element: 要双击的元素
    func doubleTapElement(_ element: XCUIElement) {
        if element.waitForExistence(timeout: 5) {
            element.doubleTap()
        }
    }
    
    /// 在坐标处点击
    /// - Parameters:
    ///   - point: 点击坐标（相对坐标 0-1）
    ///   - element: 目标元素（默认为整个窗口）
    func tapAt(point: CGVector, on element: XCUIElement? = nil) {
        let target = element ?? app.windows.firstMatch
        let coordinate = target.coordinate(withNormalizedOffset: point)
        coordinate.tap()
    }
    
    // MARK: - 文本输入
    
    /// 在文本框中输入文字
    /// - Parameters:
    ///   - text: 要输入的文字
    ///   - textField: 目标文本框
    func enterText(_ text: String, into textField: XCUIElement, clearFirst: Bool = true) {
        if textField.waitForExistence(timeout: 5) {
            textField.tap()
            
            if clearFirst {
                textField.clearText()
            }
            
            textField.typeText(text)
        }
    }
    
    /// 清除文本框内容
    /// - Parameter textField: 目标文本框
    func clearText(in textField: XCUIElement) {
        textField.clearText()
    }
    
    // MARK: - 键盘操作
    
    /// 关闭键盘
    func dismissKeyboard() {
        if app.keyboards.element.exists {
            // 尝试通过点击 Return 键关闭
            app.keyboards.buttons["return"].tap()
        }
    }
    
    /// 按键盘上的指定按钮
    /// - Parameter buttonName: 按钮名称
    func pressKeyboardButton(_ buttonName: String) {
        if app.keyboards.element.exists {
            let button = app.keyboards.buttons[buttonName]
            if button.exists {
                button.tap()
            }
        }
    }
    
    // MARK: - 断言辅助
    
    /// 验证元素存在
    /// - Parameters:
    ///   - element: 要验证的元素
    ///   - message: 失败时的消息
    func assertElementExists(_ element: XCUIElement, message: String? = nil) {
        XCTAssertTrue(element.exists, message ?? "元素应存在")
    }
    
    /// 验证元素不存在
    /// - Parameters:
    ///   - element: 要验证的元素
    ///   - message: 失败时的消息
    func assertElementNotExists(_ element: XCUIElement, message: String? = nil) {
        XCTAssertFalse(element.exists, message ?? "元素不应存在")
    }
    
    /// 验证元素可点击
    /// - Parameters:
    ///   - element: 要验证的元素
    ///   - message: 失败时的消息
    func assertElementIsTappable(_ element: XCUIElement, message: String? = nil) {
        XCTAssertTrue(element.exists && element.isHittable, 
                     message ?? "元素应存在且可点击")
    }
    
    /// 验证元素文本
    /// - Parameters:
    ///   - element: 要验证的元素
    ///   - expectedText: 期望的文本
    ///   - message: 失败时的消息
    func assertElementText(_ element: XCUIElement, equals expectedText: String, message: String? = nil) {
        XCTAssertEqual(element.label, expectedText, 
                       message ?? "元素文本应匹配")
    }
    
    /// 验证元素包含文本
    /// - Parameters:
    ///   - element: 要验证的元素
    ///   - expectedText: 期望包含的文本
    ///   - message: 失败时的消息
    func assertElementContainsText(_ element: XCUIElement, _ expectedText: String, message: String? = nil) {
        XCTAssertTrue(element.label.contains(expectedText), 
                      message ?? "元素应包含文本 '\(expectedText)'")
    }
    
    // MARK: - 滚动和查找
    
    /// 滚动到找到指定文本的元素
    /// - Parameters:
    ///   - text: 要查找的文本
    ///   - maxSwipes: 最大滑动次数
    /// - Returns: 找到的元素
    @discardableResult
    func scrollTo(text: String, maxSwipes: Int = 10) -> XCUIElement? {
        let element = app.staticTexts[text]
        
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return element
            }
            swipeUp(distance: 0.5)
        }
        
        return nil
    }
    
    /// 滚动到找到指定标识符的元素
    /// - Parameters:
    ///   - identifier: 元素标识符
    ///   - maxSwipes: 最大滑动次数
    /// - Returns: 找到的元素
    @discardableResult
    func scrollTo(identifier: String, maxSwipes: Int = 10) -> XCUIElement? {
        let element = app.descendants(matching: .any)[identifier]
        
        for _ in 0..<maxSwipes {
            if element.exists && element.isHittable {
                return element
            }
            swipeUp(distance: 0.5)
        }
        
        return nil
    }
    
    // MARK: - 设备操作
    
    /// 设置设备方向
    /// - Parameter orientation: 设备方向
    func setDeviceOrientation(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
    }
    
    /// 按 Home 键（仅适用于支持 Home 键的设备）
    func pressHomeButton() {
        XCUIDevice.shared.press(.home)
    }
    
    /// 锁屏
    func lockScreen() {
        XCUIDevice.shared.press(.lockScreen)
    }
    
    /// 摇动设备
    func shakeDevice() {
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
    }
    
    // MARK: - 系统弹窗处理
    
    /// 允许系统权限弹窗
    /// - Parameter timeout: 超时时间
    func allowSystemAlert(timeout: TimeInterval = 5) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["允许"]
        
        if allowButton.waitForExistence(timeout: timeout) {
            allowButton.tap()
        }
    }
    
    /// 拒绝系统权限弹窗
    /// - Parameter timeout: 超时时间
    func denySystemAlert(timeout: TimeInterval = 5) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let dontAllowButton = springboard.buttons["不允许"]
        
        if dontAllowButton.waitForExistence(timeout: timeout) {
            dontAllowButton.tap()
        }
    }
    
    /// 处理系统弹窗（自动点击第一个按钮）
    /// - Parameter timeout: 超时时间
    func handleSystemAlert(timeout: TimeInterval = 5) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        
        if alert.waitForExistence(timeout: timeout) {
            alert.buttons.firstMatch.tap()
        }
    }
    
    // MARK: - 性能测试辅助
    
    /// 测量操作执行时间
    /// - Parameters:
    ///   - name: 测量名称
    ///   - operation: 要测量的操作
    /// - Returns: 执行时间（秒）
    @discardableResult
    func measureTime(name: String, operation: () -> Void) -> TimeInterval {
        let startTime = Date()
        operation()
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        let attachment = XCTAttachment(string: "\(name) 执行时间: \(String(format: "%.3f", duration)) 秒")
        attachment.name = "\(name)_timing"
        XCTContext.add(attachment)
        
        return duration
    }
    
    // MARK: - 调试辅助
    
    /// 打印当前界面元素树
    func printElementTree() {
        print("=== 界面元素树 ===")
        print(app.debugDescription)
    }
    
    /// 获取元素数量统计
    /// - Returns: 各类型元素数量
    func getElementCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        
        let elementTypes: [XCUIElement.ElementType] = [
            .button, .staticText, .textField, .secureTextField,
            .switch, .slider, .picker, .pickerWheel,
            .table, .cell, .collectionView, .other
        ]
        
        for type in elementTypes {
            let query = app.descendants(matching: type)
            counts["\(type)"] = query.count
        }
        
        return counts
    }
    
    /// 验证应用没有崩溃
    /// - Returns: 应用是否正常运行
    func verifyAppNotCrashed() -> Bool {
        return app.state == .runningForeground
    }
}

// MARK: - XCUIElement 扩展

extension XCUIElement {
    /// 清除文本框内容
    func clearText() {
        guard self.exists else { return }
        
        // 选中文本
        self.tap()
        self.press(forDuration: 1.0)
        
        // 点击全选
        if let selectAllButton = self.menuItems["全选"].firstMatch as XCUIElement? {
            if selectAllButton.waitForExistence(timeout: 2) {
                selectAllButton.tap()
            }
        }
        
        // 删除选中文本
        let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: (self.value as? String)?.count ?? 10)
        self.typeText(deleteString)
    }
    
    /// 滚动到元素可见
    func scrollToVisible() {
        while !self.isHittable {
            let window = XCUIApplication().windows.firstMatch
            window.swipeUp()
        }
    }
    
    /// 等待元素变为可点击状态
    @discardableResult
    func waitForTappable(timeout: TimeInterval) -> Bool {
        let startTime = Date()
        while Date().timeIntervalSince(startTime) < timeout {
            if self.isHittable {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return false
    }
}

// MARK: - String 扩展

extension String {
    /// 本地化字符串
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
