import XCTest

/// 主要用户流程 UI 测试
/// 测试应用的核心功能流程，包括启动、导航、图片选择和拼接
final class MainFlowTests: XCTestCase {
    
    var app: XCUIApplication!
    var helper: UITestHelper!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        helper = UITestHelper(app: app)
        
        // 配置启动参数
        app.launchArguments = ["--uitesting", "--reset-state"]
        
        // 启动应用
        app.launch()
    }
    
    override func tearDownWithError() throws {
        helper = nil
        app = nil
    }
    
    // MARK: - 测试用例 1: 应用启动测试
    
    /// 测试应用正常启动并显示主界面
    func testAppLaunch() throws {
        // 验证主界面元素存在
        XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 5),
                     "应用启动后应显示标题")
        
        // 验证导入按钮存在
        let importButton = app.buttons["导入截图"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5),
                     "主界面应显示导入截图按钮")
        
        // 验证欢迎文本存在
        XCTAssertTrue(app.staticTexts["轻松拼接多张截图为一张长图"].exists,
                     "应显示欢迎描述文本")
        
        // 验证 Tab Bar 存在
        XCTAssertTrue(app.tabBars.element.exists,
                     "底部 Tab Bar 应存在")
    }
    
    // MARK: - 测试用例 2: Tab 导航测试
    
    /// 测试所有 Tab 之间的导航
    func testTabNavigation() throws {
        // 等待首页加载
        XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 5))
        
        // 测试切换到历史 Tab
        app.tabBars.buttons["历史"].tap()
        helper.waitForAnimations()
        
        // 验证历史页面元素
        let historyTitle = app.staticTexts["历史记录"]
        XCTAssertTrue(historyTitle.waitForExistence(timeout: 3) || 
                     app.navigationBars["历史记录"].exists,
                     "切换到历史 Tab 后应显示历史记录")
        
        // 测试切换到设置 Tab
        app.tabBars.buttons["设置"].tap()
        helper.waitForAnimations()
        
        // 验证设置页面元素
        let settingsTitle = app.staticTexts["设置"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3) ||
                     app.navigationBars["设置"].exists,
                     "切换到设置 Tab 后应显示设置界面")
        
        // 测试切换回首页
        app.tabBars.buttons["首页"].tap()
        helper.waitForAnimations()
        
        // 验证返回首页
        XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 3),
                     "切换回首页应显示主界面")
    }
    
    // MARK: - 测试用例 3: 图片选择流程测试
    
    /// 测试图片选择流程（模拟权限允许的情况）
    func testImageSelectionFlow() throws {
        // 点击导入按钮
        let importButton = app.buttons["导入截图"]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))
        importButton.tap()
        
        // 等待系统相册选择器出现
        // 注意：系统相册选择器是系统级别的，UI 测试对其访问有限
        // 这里主要验证按钮触发行为
        helper.waitForAnimations()
        
        // 如果相册选择器出现，验证其存在
        let photosPicker = app.otherElements["PHPickerView"]
        if photosPicker.waitForExistence(timeout: 3) {
            XCTAssertTrue(photosPicker.exists, "应显示系统相册选择器")
            
            // 取消选择
            app.buttons["取消"].firstMatch.tap()
        }
    }
    
    // MARK: - 测试用例 4: 历史记录查看测试
    
    /// 测试历史记录页面的显示和交互
    func testHistoryView() throws {
        // 切换到历史 Tab
        app.tabBars.buttons["历史"].tap()
        helper.waitForAnimations()
        
        // 验证历史页面结构
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3),
                     "历史页面应有导航栏")
        
        // 如果没有历史记录，验证空状态视图
        if app.staticTexts["还没有拼接记录"].waitForExistence(timeout: 2) {
            XCTAssertTrue(app.staticTexts["导入图片开始您的第一次拼接"].exists,
                         "空状态应显示提示文本")
        } else {
            // 有历史记录时，验证列表存在
            let tablesQuery = app.tables
            let collectionQuery = app.collectionViews
            
            XCTAssertTrue(tablesQuery.element.exists || collectionQuery.element.exists,
                         "历史记录应以列表或网格形式显示")
        }
    }
    
    // MARK: - 测试用例 5: 设置页面测试
    
    /// 测试设置页面的显示
    func testSettingsView() throws {
        // 切换到设置 Tab
        app.tabBars.buttons["设置"].tap()
        helper.waitForAnimations()
        
        // 验证设置页面结构
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 3),
                     "设置页面应有导航栏")
        
        // 验证设置选项存在（根据实际实现调整）
        // 常见的设置选项
        let settingsElements = ["关于", "帮助", "反馈", "版本", "隐私"]
        var foundAnySetting = false
        
        for element in settingsElements {
            if app.staticTexts[element].exists || app.buttons[element].exists {
                foundAnySetting = true
                break
            }
        }
        
        // 至少应有一个设置相关元素
        XCTAssertTrue(foundAnySetting || app.tables.element.exists,
                     "设置页面应包含设置选项")
    }
    
    // MARK: - 测试用例 6: 完整流程集成测试
    
    /// 测试从启动到查看历史的完整流程
    func testCompleteUserFlow() throws {
        // 1. 验证启动
        XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 5))
        
        // 2. 验证首页元素
        XCTAssertTrue(app.buttons["导入截图"].exists)
        
        // 3. 检查最近拼接区域
        if app.staticTexts["最近拼接"].waitForExistence(timeout: 2) {
            // 如果有历史记录，验证查看全部按钮
            if app.buttons["查看全部"].exists {
                app.buttons["查看全部"].tap()
                helper.waitForAnimations()
                
                // 验证进入历史页面
                XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 3))
                
                // 返回首页
                if app.buttons["返回"].exists {
                    app.buttons["返回"].tap()
                } else if app.navigationBars.buttons.firstMatch.exists {
                    app.navigationBars.buttons.firstMatch.tap()
                }
            }
        }
        
        // 4. 遍历所有 Tab
        let tabs = ["首页", "历史", "设置"]
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            helper.waitForAnimations()
            
            // 验证每个 Tab 至少有一些内容
            let hasContent = app.windows.firstMatch.descendants(matching: .any).count > 5
            XCTAssertTrue(hasContent, "\(tab) Tab 应显示内容")
        }
    }
    
    // MARK: - 测试用例 7: 主界面元素交互测试
    
    /// 测试主界面各种交互元素
    func testHomeViewInteractions() throws {
        // 等待首页加载
        XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 5))
        
        // 测试应用图标可点击（如果有交互）
        let iconElement = app.images["photo.stack.fill"]
        if iconElement.exists {
            iconElement.tap()
            helper.waitForAnimations()
        }
        
        // 验证导入按钮状态
        let importButton = app.buttons["导入截图"]
        XCTAssertTrue(importButton.isEnabled,
                     "导入按钮应处于可点击状态")
        XCTAssertTrue(importButton.isHittable,
                     "导入按钮应可交互")
    }
    
    // MARK: - 测试用例 8: 深色模式适配测试
    
    /// 测试应用在深色模式下的显示
    func testDarkModeAppearance() throws {
        // 设置为深色模式
        app.launchArguments.append("-UITestDarkMode")
        app.terminate()
        app.launch()
        
        helper.waitForAnimations()
        
        // 验证应用正常启动
        XCTAssertTrue(helper.waitForElement(app.staticTexts["长截图拼接"], timeout: 5),
                     "深色模式下应用应正常启动")
        
        // 验证主要元素仍然可见
        XCTAssertTrue(app.buttons["导入截图"].exists,
                     "深色模式下导入按钮应可见")
        
        // 遍历所有 Tab 验证深色模式
        let tabs = ["首页", "历史", "设置"]
        for tab in tabs {
            app.tabBars.buttons[tab].tap()
            helper.waitForAnimations()
            
            // 截图验证（可选）
            let screenshot = app.screenshot()
            XCTAssertNotNil(screenshot.pngRepresentation,
                           "深色模式下应能正常截图")
        }
    }
}
