# 长图拼接 - App Store 发布检查清单

**项目名称**：LongScreenshot  
**Bundle ID**：com.longscreenshot.app  
**版本**：1.0.0  
**更新日期**：2026-04-20

---

## 一、开发配置检查

### 1.1 Info.plist 配置 ✅
- [x] CFBundleDisplayName 设置为 "长图拼接"
- [x] CFBundleShortVersionString 设置为 "1.0.0"
- [x] CFBundleVersion 设置为 "1"
- [x] 添加 NSPhotoLibraryUsageDescription 权限描述
- [x] 添加 NSPhotoLibraryAddUsageDescription 权限描述
- [x] 添加 NSCameraUsageDescription 权限描述
- [x] 添加 NSUserTrackingUsageDescription 权限描述
- [x] 配置 LSApplicationCategoryType 为 productivity
- [x] 设置 CFBundleDevelopmentRegion 为 zh_CN
- [x] 配置 ITSAppUsesNonExemptEncryption 为 false
- [x] 添加 CFBundleDocumentTypes 文档类型支持
- [x] 添加 CFBundleURLTypes URL 类型配置

### 1.2 项目配置 ✅
- [x] Release 模式编译优化已配置
  - GCC_OPTIMIZATION_LEVEL = s
  - SWIFT_OPTIMIZATION_LEVEL = "-O"
  - SWIFT_COMPILATION_MODE = wholemodule
  - STRIP_INSTALLED_PRODUCT = YES
  - DEPLOYMENT_POSTPROCESSING = YES
- [x] Debug 信息格式设置为 dwarf-with-dsym
- [x] ENABLE_NS_ASSERTIONS = NO
- [x] ENABLE_BITCODE = NO
- [x] IPHONEOS_DEPLOYMENT_TARGET = 16.0

### 1.3 签名配置 ⚠️
- [ ] **需配置**：DEVELOPMENT_TEAM = YOUR_TEAM_ID_HERE
  - 在 project.pbxproj 中替换为实际 Team ID
  - 或在 Xcode 中登录开发者账号自动配置
- [ ] **需配置**：Provisioning Profile
  - 确保有有效的 Distribution 证书
  - 创建 App Store 发布的 Provisioning Profile

---

## 二、资源文件检查

### 2.1 应用图标
- [ ] AppIcon.appiconset 包含所有必需尺寸：
  - [ ] iPhone Notification: 20pt@2x, 20pt@3x
  - [ ] iPhone Settings: 29pt@2x, 29pt@3x
  - [ ] iPhone Spotlight: 40pt@2x, 40pt@3x
  - [ ] iPhone App: 60pt@2x, 60pt@3x
  - [ ] iPad Notification: 20pt@1x, 20pt@2x
  - [ ] iPad Settings: 29pt@1x, 29pt@2x
  - [ ] iPad Spotlight: 40pt@1x, 40pt@2x
  - [ ] iPad App: 76pt@1x, 76pt@2x
  - [ ] iPad Pro App: 83.5pt@2x
  - [ ] App Store: 1024pt@1x

### 2.2 启动图
- [ ] 启动屏幕配置完成
- [ ] 适配不同屏幕尺寸
- [ ] 支持深色模式（如需要）

### 2.3 截图准备
- [ ] iPhone 6.7英寸 (1290×2796) - 5张
- [ ] iPhone 6.5英寸 (1242×2688) - 5张（可选）
- [ ] iPhone 5.5英寸 (1242×2208) - 5张
- [ ] iPad 12.9英寸 (2048×2732) - 5张（可选）
- [ ] 预览视频 15-30秒（可选）

**截图内容**：
1. 首页/核心功能展示
2. 智能拼接过程
3. 手动调整功能
4. 标注编辑功能
5. 导出与分享/历史记录

---

## 三、App Store Connect 配置

### 3.1 应用信息
- [ ] 应用名称：长图拼接
- [ ] 副标题：智能拼接聊天记录，一键生成长截图
- [ ] 类别：主要-效率，次要-摄影与录像
- [ ] Bundle ID：com.longscreenshot.app
- [ ] SKU：com.longscreenshot.app.1.0.0

### 3.2 定价与供货范围
- [ ] 价格：免费
- [ ] 供货范围：中国大陆、中国香港、中国台湾、美国等
- [ ] 预订：如需设置预订请提前配置

### 3.3 版本信息
- [ ] 版本号：1.0.0
- [ ] 更新说明（首次发布可留空或填写首次发布说明）
- [ ] 此版本的新增内容（参照 AppStoreMetadata.md）

### 3.4 上传构建版本
- [ ] 使用 Xcode Archive 导出 Release 版本
- [ ] 上传到 App Store Connect
- [ ] 等待处理完成（通常 10-30 分钟）
- [ ] 选择正确的构建版本

---

## 四、元数据提交

### 4.1 应用描述
- [ ] 促销文本（170字符以内）
- [ ] 关键词（100字符以内）
- [ ] 描述（完整版）
- [ ] 技术支持网址
- [ ] 营销网址
- [ ] 隐私政策网址

### 4.2 联系信息
- [ ] 姓氏/名字
- [ ] 电话号码
- [ ] 电子邮件
- [ ] 审核备注（说明应用功能特点，帮助审核）

### 4.3 分级
- [ ] 年龄分级：4+
- [ ] 内容分级：无限制内容

---

## 五、隐私政策配置

### 5.1 App Store 隐私标签
- [ ] 数据类型声明：
  - [ ] 照片/视频：选择文件、保存到相册
  - [ ] 使用数据：崩溃日志（可选）
- [ ] 数据使用目的声明
- [ ] 数据是否链接到用户：否
- [ ] 数据是否用于追踪：否

### 5.2 隐私政策文档
- [x] 已创建 PrivacyPolicy.md
- [ ] 上传到服务器并提供 URL
- [ ] 在 App Store Connect 中填写隐私政策链接

---

## 六、构建与上传

### 6.1 本地构建测试
```bash
# 清理构建目录
xcodebuild clean -project LongScreenshot.xcodeproj -scheme LongScreenshot

# 构建 Release 版本
xcodebuild -project LongScreenshot.xcodeproj \
  -scheme LongScreenshot \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  build
```

### 6.2 Archive 并上传
1. Xcode 中选择 Release Scheme
2. Product → Archive
3. Distribute App → App Store Connect
4. 选择 Upload
5. 等待上传完成

### 6.3 验证清单
- [ ] 在真机上测试 Release 版本
- [ ] 检查所有功能正常工作
- [ ] 验证隐私权限提示正常显示
- [ ] 确认无崩溃或严重 bug
- [ ] 检查内存使用合理

---

## 七、提交审核前检查

### 7.1 功能完整性
- [ ] 智能拼接功能正常
- [ ] 手动调整功能正常
- [ ] 标注工具全部可用
- [ ] 导出功能正常
- [ ] 历史记录功能正常
- [ ] 设置页面完整

### 7.2 界面检查
- [ ] 无占位符文本或测试数据
- [ ] 所有图片资源正常加载
- [ ] 深色模式支持正常（如实现）
- [ ] iPad 适配正常（如支持）
- [ ] 横竖屏切换正常

### 7.3 权限检查
- [ ] 相册权限提示正常
- [ ] 相机权限提示正常（如使用）
- [ ] 权限被拒绝时有适当的降级处理

### 7.4 性能检查
- [ ] 启动时间 < 3秒
- [ ] 大图处理不卡顿
- [ ] 内存占用合理（< 500MB）
- [ ] 电池消耗合理

---

## 八、审核准备

### 8.1 审核账号
- [ ] 本应用无需登录，无需提供测试账号

### 8.2 审核备注模板
```
这是一个长截图拼接工具，主要功能包括：
1. 从相册选择多张截图
2. 自动识别重叠区域进行拼接
3. 支持手动调整拼接位置
4. 提供标注编辑功能
5. 保存拼接结果到相册

所有处理都在本地完成，不上传任何数据到服务器。
隐私权限仅用于访问相册和保存图片。

感谢审核！
```

### 8.3 可能的审核问题准备
- **问题**：应用功能简单，有价值吗？
  - **回答**：长截图是用户高频需求场景，我们的产品提供智能算法自动拼接和精细的手动调整，解决了传统方式需要手动对齐的痛点。

- **问题**：与系统功能重复？
  - **回答**：iOS 系统不提供长截图拼接功能，现有竞品要么收费要么功能不完善。

---

## 九、发布后事项

### 9.1 立即检查
- [ ] 应用在 App Store 正常显示
- [ ] 下载安装正常
- [ ] 首次启动正常
- [ ] 所有功能正常

### 9.2 监控指标
- [ ] 下载量
- [ ] 用户评分和评论
- [ ] 崩溃报告
- [ ] 用户反馈

### 9.3 后续优化
- [ ] 根据用户反馈优化功能
- [ ] 定期更新版本
- [ ] 回复用户评论
- [ ] 维护隐私政策页面

---

## 十、文件清单

已创建的发布相关文件：

| 文件名 | 路径 | 状态 |
|--------|------|------|
| Info.plist | /LongScreenshot/LongScreenshot/Info.plist | ✅ 已更新 |
| PrivacyPolicy.md | /LongScreenshot/PrivacyPolicy.md | ✅ 已创建 |
| AppStoreMetadata.md | /LongScreenshot/AppStoreMetadata.md | ✅ 已创建 |
| AppStoreScreenshots.md | /LongScreenshot/AppStoreScreenshots.md | ✅ 已创建 |
| project.pbxproj | /LongScreenshot.xcodeproj/project.pbxproj | ✅ 已更新 |
| AppStoreReleaseChecklist.md | /LongScreenshot/AppStoreReleaseChecklist.md | ✅ 已创建 |

---

## 十一、待办事项总结

### 发布前必须完成（阻塞项）：
1. ⚠️ **配置 Apple Developer Team ID**
   - 替换 project.pbxproj 中的 YOUR_TEAM_ID_HERE
   - 或在 Xcode 中登录开发者账号

2. ⚠️ **准备应用图标**
   - 所有尺寸完整
   - 符合 Apple 人机界面指南

3. ⚠️ **准备 App Store 截图**
   - 至少 1 组 iPhone 截图
   - 展示核心功能

4. ⚠️ **真机测试**
   - Release 模式构建
   - 所有功能验证通过

5. ⚠️ **配置 App Store Connect**
   - 创建新应用
   - 填写完整元数据
   - 配置隐私政策链接

6. ⚠️ **上传构建版本**
   - 通过 Xcode Archive 上传
   - 等待处理完成

### 建议完成（非阻塞）：
- [ ] 准备预览视频
- [ ] 准备 iPad 截图
- [ ] 设置第三方分析（Firebase/友盟等）
- [ ] 准备应用推广素材

---

## 参考链接

- [Apple 官方发布指南](https://developer.apple.com/documentation/xcode/distributing-your-app)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- [App Store Connect 帮助](https://help.apple.com/app-store-connect/)

---

**祝发布顺利！**

如有问题，请参考各 md 文件中的详细说明。
