require 'fileutils'

pbxproj_path = "/Users/chenhanzhong/Documents/trae_projects/Long-Screenshot/LongScreenshot/LongScreenshot.xcodeproj/project.pbxproj"
content = File.read(pbxproj_path)

test_target_id = "D10000000000000000000070"
test_product_id = "D10000000000000000000071"
test_sources_phase = "D10000000000000000000072"
test_frameworks_phase = "D10000000000000000000073"
test_resources_phase = "D10000000000000000000074"
test_config_list = "D10000000000000000000075"
test_config_debug = "D10000000000000000000076"
test_config_release = "D10000000000000000000077"
test_group = "D10000000000000000000078"
test_services_group = "D10000000000000000000079"
test_utils_group = "D1000000000000000000007A"
test_models_group = "D1000000000000000000007B"

test_helper_ref = "D10200000000000000000070"
ncc_test_ref = "D10200000000000000000071"
stitcher_test_ref = "D10200000000000000000072"
overlap_test_ref = "D10200000000000000000073"
similarity_test_ref = "D10200000000000000000074"
coredata_test_ref = "D10200000000000000000075"
ncc_stitcher_ref = "D10200000000000000000076"

test_helper_bf = "D10100000000000000000070"
ncc_test_bf = "D10100000000000000000071"
ncc_stitcher_bf = "D10100000000000000000072"

proxy_id = "D10000000000000000000060"
dep_id = "D10000000000000000000061"

content.sub!("/* End PBXBuildFile section */", <<~STR + "/* End PBXBuildFile section */")
\t\t#{test_helper_bf} /* TestHelper.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{test_helper_ref} /* TestHelper.swift */; };
\t\t#{ncc_test_bf} /* NCCStitcherCropTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{ncc_test_ref} /* NCCStitcherCropTests.swift */; };
\t\t#{ncc_stitcher_bf} /* NCCStitcher.swift in Sources */ = {isa = PBXBuildFile; fileRef = #{ncc_stitcher_ref} /* NCCStitcher.swift */; };
STR

content.sub!("/* End PBXFileReference section */", <<~STR + "/* End PBXFileReference section */")
\t\t#{test_product_id} /* LongScreenshotTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = LongScreenshotTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
\t\t#{test_helper_ref} /* TestHelper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TestHelper.swift; sourceTree = "<group>"; };
\t\t#{ncc_test_ref} /* NCCStitcherCropTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NCCStitcherCropTests.swift; sourceTree = "<group>"; };
\t\t#{stitcher_test_ref} /* ImageStitcherTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ImageStitcherTests.swift; sourceTree = "<group>"; };
\t\t#{overlap_test_ref} /* OverlapDetectorTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = OverlapDetectorTests.swift; sourceTree = "<group>"; };
\t\t#{similarity_test_ref} /* ImageSimilarityTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ImageSimilarityTests.swift; sourceTree = "<group>"; };
\t\t#{coredata_test_ref} /* CoreDataTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CoreDataTests.swift; sourceTree = "<group>"; };
\t\t#{ncc_stitcher_ref} /* NCCStitcher.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = NCCStitcher.swift; sourceTree = "<group>"; };
STR

content.sub!("D10000000000000000000001 /* LongScreenshot.app */,", "D10000000000000000000001 /* LongScreenshot.app */,\n\t\t\t\t#{test_product_id} /* LongScreenshotTests.xctest */,")

content.sub!("/* End PBXGroup section */", <<~STR + "/* End PBXGroup section */")
\t\t#{test_group} /* LongScreenshotTests */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t#{test_services_group} /* ServicesTests */,
\t\t\t\t#{test_utils_group} /* Utils */,
\t\t\t\t#{test_models_group} /* ModelsTests */,
\t\t\t);
\t\t\tpath = LongScreenshotTests;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{test_services_group} /* ServicesTests */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t#{ncc_test_ref} /* NCCStitcherCropTests.swift */,
\t\t\t\t#{stitcher_test_ref} /* ImageStitcherTests.swift */,
\t\t\t\t#{overlap_test_ref} /* OverlapDetectorTests.swift */,
\t\t\t\t#{similarity_test_ref} /* ImageSimilarityTests.swift */,
\t\t\t);
\t\t\tpath = ServicesTests;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{test_utils_group} /* Utils */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t#{test_helper_ref} /* TestHelper.swift */,
\t\t\t);
\t\t\tpath = Utils;
\t\t\tsourceTree = "<group>";
\t\t};
\t\t#{test_models_group} /* ModelsTests */ = {
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t#{coredata_test_ref} /* CoreDataTests.swift */,
\t\t\t);
\t\t\tpath = ModelsTests;
\t\t\tsourceTree = "<group>";
\t\t};
STR

content.sub!("D10000000000000000000005 /* Products */,", "D10000000000000000000005 /* Products */,\n\t\t\t\t#{test_group} /* LongScreenshotTests */,")

content.sub!("/* End PBXNativeTarget section */", <<~STR + "/* End PBXNativeTarget section */")
\t\t#{test_target_id} /* LongScreenshotTests */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = #{test_config_list} /* Build configuration list for PBXNativeTarget "LongScreenshotTests" */;
\t\t\tbuildPhases = (
\t\t\t\t#{test_sources_phase} /* Sources */,
\t\t\t\t#{test_frameworks_phase} /* Frameworks */,
\t\t\t\t#{test_resources_phase} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t#{dep_id} /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = LongScreenshotTests;
\t\t\tproductName = LongScreenshotTests;
\t\t\tproductReference = #{test_product_id} /* LongScreenshotTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t};
STR

content.sub!("D10000000000000000000006 /* LongScreenshot */,", "D10000000000000000000006 /* LongScreenshot */,\n\t\t\t\t#{test_target_id} /* LongScreenshotTests */,")

content.sub!("D10000000000000000000006 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;", "D10000000000000000000006 = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t};\n\t\t\t\t\t#{test_target_id} = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 15.0;\n\t\t\t\t\t\tTestTargetID = D10000000000000000000006;")

content.sub!("/* Begin PBXResourcesBuildPhase section */", <<~STR + "/* Begin PBXResourcesBuildPhase section */")

/* Begin PBXContainerItemProxy section */
\t\t#{proxy_id} /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = D1000000000000000000000A /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = D10000000000000000000006;
\t\t\tremoteInfo = LongScreenshot;
\t\t};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
\t\t#{dep_id} /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = D10000000000000000000006 /* LongScreenshot */;
\t\t\ttargetProxy = #{proxy_id} /* PBXContainerItemProxy */;
\t\t};
/* End PBXTargetDependency section */
STR

content.sub!("/* End PBXSourcesBuildPhase section */", <<~STR + "/* End PBXSourcesBuildPhase section */")
\t\t#{test_sources_phase} /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t\t#{test_helper_bf} /* TestHelper.swift in Sources */,
\t\t\t\t#{ncc_test_bf} /* NCCStitcherCropTests.swift in Sources */,
\t\t\t\t#{ncc_stitcher_bf} /* NCCStitcher.swift in Sources */,
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
STR

content.sub!("/* End PBXFrameworksBuildPhase section */", <<~STR + "/* End PBXFrameworksBuildPhase section */")
\t\t#{test_frameworks_phase} /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
STR

content.sub!("/* End PBXResourcesBuildPhase section */", <<~STR + "/* End PBXResourcesBuildPhase section */")
\t\t#{test_resources_phase} /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
STR

content.sub!("/* End XCBuildConfiguration section */", <<~STR + "/* End XCBuildConfiguration section */")
\t\t#{test_config_debug} /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = U6JW8977CR;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chenhanzhong.longscreenshot.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/LongScreenshot.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LongScreenshot";
\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t#{test_config_release} /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = U6JW8977CR;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 16.0;
\t\t\t\tMARKETING_VERSION = 1.0.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.chenhanzhong.longscreenshot.tests;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = NO;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/LongScreenshot.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LongScreenshot";
\t\t\t};
\t\t\tname = Release;
\t\t};
STR

content.sub!("/* End XCConfigurationList section */", <<~STR + "/* End XCConfigurationList section */")
\t\t#{test_config_list} /* Build configuration list for PBXNativeTarget "LongScreenshotTests" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t#{test_config_debug} /* Debug */,
\t\t\t\t#{test_config_release} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
STR

File.write(pbxproj_path, content)
puts "Done - test target added"
