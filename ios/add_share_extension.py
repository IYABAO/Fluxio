#!/usr/bin/env python3
"""
Fluxio iOS Share Extension Target 注入脚本。

功能：
- 读取现有的 project.pbxproj
- 添加 Share Extension 的文件引用、Build Phase、Target、Build Configuration
- 保存修改后的文件

注意：这是一个谨慎的脚本，会先备份原文件。
"""

import re
import sys
import os
import shutil
from datetime import datetime

# 配置
PROJECT_FILE = r"E:\github\Fluxio\ios\Runner.xcodeproj\project.pbxproj"
BACKUP_FILE = PROJECT_FILE + ".share_ext_backup"

# Share Extension 配置
SHARE_EXT_NAME = "ShareExtension"
SHARE_EXT_BUNDLE_ID = "com.plbear.fluxio.ShareExtension"
SHARE_EXT_PRODUCT_NAME = "ShareExtension"

# 生成唯一的 24 字符 hex ID
def generate_id():
    import random
    return ''.join(random.choices('0123456789ABCDEF', k=24))

# 生成所有需要的 ID
IDS = {
    'target': generate_id(),
    'product': generate_id(),
    'sources_phase': generate_id(),
    'resources_phase': generate_id(),
    'config_list': generate_id(),
    'config_debug': generate_id(),
    'config_release': generate_id(),
    'config_profile': generate_id(),
    'group': generate_id(),
    'file_swift': generate_id(),
    'file_info_plist': generate_id(),
    'file_storyboard': generate_id(),
    'file_entitlements': generate_id(),
    'build_file_swift': generate_id(),
    'build_file_storyboard': generate_id(),
    'build_file_entitlements': generate_id(),
    'target_dependency': generate_id(),
    'container_proxy': generate_id(),
    'product_ref': generate_id(),
}

def read_file(path):
    """读取文件内容。"""
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def write_file(path, content):
    """写入文件内容。"""
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

def add_build_files(content):
    """在 PBXBuildFile section 添加 Share Extension 的构建文件。"""
    build_file_section = f"""
		{IDS['build_file_swift']} /* ShareViewController.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {IDS['file_swift']} /* ShareViewController.swift */; }};
		{IDS['build_file_storyboard']} /* MainInterface.storyboard in Resources */ = {{isa = PBXBuildFile; fileRef = {IDS['file_storyboard']} /* MainInterface.storyboard */; }};
"""

    # 在 PBXBuildFile section 结束前插入
    pattern = r'(/\* End PBXBuildFile section \*/)'
    replacement = build_file_section + r'\1'
    return re.sub(pattern, replacement, content, count=1)

def add_file_references(content):
    """在 PBXFileReference section 添加 Share Extension 的文件引用。"""
    file_ref_section = f"""
		{IDS['file_swift']} /* ShareViewController.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ShareViewController.swift; sourceTree = "<group>"; }};
		{IDS['file_info_plist']} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
		{IDS['file_storyboard']} /* MainInterface.storyboard */ = {{isa = PBXFileReference; lastKnownFileType = file.storyboard; name = MainInterface.storyboard; path = Base.lproj/MainInterface.storyboard; sourceTree = "<group>"; }};
		{IDS['file_entitlements']} /* ShareExtension.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = ShareExtension.entitlements; sourceTree = "<group>"; }};
		{IDS['product_ref']} /* ShareExtension.appex */ = {{isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = ShareExtension.appex; sourceTree = BUILT_PRODUCTS_DIR; }};
"""

    pattern = r'(/\* End PBXFileReference section \*/)'
    replacement = file_ref_section + r'\1'
    return re.sub(pattern, replacement, content, count=1)

def add_group(content):
    """在 PBXGroup section 添加 Share Extension 的组。"""
    group_section = f"""
		{IDS['group']} /* ShareExtension */ = {{
			isa = PBXGroup;
			children = (
				{IDS['file_swift']} /* ShareViewController.swift */,
				{IDS['file_info_plist']} /* Info.plist */,
				{IDS['file_storyboard']} /* MainInterface.storyboard */,
				{IDS['file_entitlements']} /* ShareExtension.entitlements */,
			);
			path = ShareExtension;
			sourceTree = "<group>";
		}};
"""

    pattern = r'(/\* End PBXGroup section \*/)'
    replacement = group_section + r'\1'
    return re.sub(pattern, replacement, content, count=1)

def add_native_target(content):
    """在 PBXNativeTarget section 添加 Share Extension 的 Target。"""
    target_section = f"""
		{IDS['target']} /* ShareExtension */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {IDS['config_list']} /* Build configuration list for PBXNativeTarget "ShareExtension" */;
			buildPhases = (
				{IDS['sources_phase']} /* Sources */,
				{IDS['resources_phase']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{IDS['target_dependency']} /* PBXTargetDependency */,
			);
			name = ShareExtension;
			productName = ShareExtension;
			productReference = {IDS['product_ref']} /* ShareExtension.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
"""

    pattern = r'(/\* End PBXNativeTarget section \*/)'
    replacement = target_section + r'\1'
    return re.sub(pattern, replacement, content, count=1)

def add_sources_phase(content):
    """添加 Sources Build Phase。"""
    sources_phase = f"""
		{IDS['sources_phase']} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{IDS['build_file_swift']} /* ShareViewController.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""

    pattern = r'(/\* End PBXSourcesBuildPhase section \*/)'
    replacement = sources_phase + r'\1'
    return re.sub(pattern, replacement, content, count=1)

def add_resources_phase(content):
    """添加 Resources Build Phase。"""
    resources_phase = f"""
		{IDS['resources_phase']} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{IDS['build_file_storyboard']} /* MainInterface.storyboard in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
"""

    pattern = r'(/\* End PBXResourcesBuildPhase section \*/)'
    replacement = resources_phase + r'\1'
    return re.sub(pattern, replacement, content, count=1)

def add_target_dependency(content):
    """添加 Target Dependency 和 Container Item Proxy。"""
    # 先找到 Runner Target 的 ID
    runner_target_match = re.search(r'(\w+) /\* Runner \*/ = \{\s*isa = PBXNativeTarget;', content)
    if not runner_target_match:
        print("❌ 找不到 Runner Target ID")
        return content
    runner_target_id = runner_target_match.group(1)

    # 找到 Project 的 ID
    project_match = re.search(r'(\w+) /\* Project object \*/ = \{\s*isa = PBXProject;', content)
    if not project_match:
        print("❌ 找不到 Project ID")
        return content
    project_id = project_match.group(1)

    dependency_section = f"""
		{IDS['target_dependency']} /* PBXTargetDependency */ = {{
			isa = PBXTargetDependency;
			target = {runner_target_id} /* Runner */;
			targetProxy = {IDS['container_proxy']} /* PBXContainerItemProxy */;
		}};
"""

    container_proxy_section = f"""
		{IDS['container_proxy']} /* PBXContainerItemProxy */ = {{
			isa = PBXContainerItemProxy;
			containerPortal = {project_id} /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = {runner_target_id};
			remoteInfo = Runner;
		}};
"""

    # 添加 Target Dependency
    pattern = r'(/\* End PBXTargetDependency section \*/)'
    replacement = dependency_section + r'\1'
    content = re.sub(pattern, replacement, content, count=1)

    # 添加 Container Item Proxy
    pattern = r'(/\* End PBXContainerItemProxy section \*/)'
    replacement = container_proxy_section + r'\1'
    content = re.sub(pattern, replacement, content, count=1)

    return content

def add_build_configurations(content):
    """添加 Build Configuration。"""
    # 先找到 Runner 的 Build Configuration，复制其设置
    # 简化版本：使用基本配置
    debug_config = f"""
		{IDS['config_debug']} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShareExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 12.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";
				PRODUCT_BUNDLE_IDENTIFIER = {SHARE_EXT_BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
"""

    release_config = f"""
		{IDS['config_release']} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShareExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 12.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";
				PRODUCT_BUNDLE_IDENTIFIER = {SHARE_EXT_BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
"""

    profile_config = f"""
		{IDS['config_profile']} /* Profile */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = ShareExtension/Info.plist;
				IPHONEOS_DEPLOYMENT_TARGET = 12.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";
				PRODUCT_BUNDLE_IDENTIFIER = {SHARE_EXT_BUNDLE_ID};
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Profile;
		}};
"""

    config_list = f"""
		{IDS['config_list']} /* Build configuration list for PBXNativeTarget "ShareExtension" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{IDS['config_debug']} /* Debug */,
				{IDS['config_release']} /* Release */,
				{IDS['config_profile']} /* Profile */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
"""

    # 添加 Build Configuration
    pattern = r'(/\* End XCBuildConfiguration section \*/)'
    replacement = debug_config + release_config + profile_config + r'\1'
    content = re.sub(pattern, replacement, content, count=1)

    # 添加 Configuration List
    pattern = r'(/\* End XCConfigurationList section \*/)'
    replacement = config_list + r'\1'
    content = re.sub(pattern, replacement, content, count=1)

    return content

def add_target_to_project(content):
    """在 PBXProject 的 targets 列表中添加 Share Extension。"""
    # 找到 targets 列表
    pattern = r'(targets = \(\s*\n\s*\w+ /\* Runner \*/,\s*\n\s*\w+ /\* RunnerTests \*/,)'
    match = re.search(pattern, content)
    if match:
        old_targets = match.group(1)
        new_targets = old_targets + f"\n\t\t\t{IDS['target']} /* ShareExtension */,"
        content = content.replace(old_targets, new_targets)
        print("✅ 已添加 Share Extension 到 Project targets 列表")
    else:
        print("⚠️ 未找到 targets 列表，尝试其他方式...")
        # 备用方案：在 RunnerTests 后面添加
        pattern = r'(\w+ /\* RunnerTests \*/,)'
        match = re.search(pattern, content)
        if match:
            old = match.group(1)
            new = old + f"\n\t\t\t{IDS['target']} /* ShareExtension */,"
            content = content.replace(old, new, 1)
            print("✅ 已添加 Share Extension 到 Project targets 列表（备用方案）")

    return content

def add_group_to_main_group(content):
    """将 Share Extension 组添加到主组中。"""
    # 找到 Runner 组
    pattern = r'(\w+ /\* Runner \*/ = \{\s*isa = PBXGroup;\s*children = \()'
    match = re.search(pattern, content)
    if match:
        old = match.group(1)
        new = old + f"\n\t\t\t\t{IDS['group']} /* ShareExtension */,"
        content = content.replace(old, new, 1)
        print("✅ 已添加 Share Extension 组到 Runner 组")
    else:
        print("⚠️ 未找到 Runner 组")

    return content

def add_entitlements_to_runner(content):
    """给 Runner Target 添加 entitlements 配置。"""
    # 在 Runner 的 Debug/Release/Profile 配置中添加 CODE_SIGN_ENTITLEMENTS
    # 找到 Runner 的 Build Configuration
    pattern = r'(97C147061CF9000F007C117D /\* Debug \*/ = \{\s*isa = XCBuildConfiguration;\s*buildSettings = \{)'
    match = re.search(pattern, content)
    if match:
        old = match.group(1)
        new = old + '\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
        content = content.replace(old, new, 1)
        print("✅ 已给 Runner Debug 添加 entitlements")

    # Release
    pattern = r'(97C147071CF9000F007C117D /\* Release \*/ = \{\s*isa = XCBuildConfiguration;\s*buildSettings = \{)'
    match = re.search(pattern, content)
    if match:
        old = match.group(1)
        new = old + '\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
        content = content.replace(old, new, 1)
        print("✅ 已给 Runner Release 添加 entitlements")

    # Profile
    pattern = r'(249021D4217E4FDB00AE95B9 /\* Profile \*/ = \{\s*isa = XCBuildConfiguration;\s*buildSettings = \{)'
    match = re.search(pattern, content)
    if match:
        old = match.group(1)
        new = old + '\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
        content = content.replace(old, new, 1)
        print("✅ 已给 Runner Profile 添加 entitlements")

    return content

def main():
    print("=" * 60)
    print("Fluxio iOS Share Extension Target 注入脚本")
    print("=" * 60)

    # 1. 备份原文件
    print(f"\n📦 备份原文件到: {BACKUP_FILE}")
    shutil.copy2(PROJECT_FILE, BACKUP_FILE)

    # 2. 读取原文件
    print(f"\n📖 读取原文件: {PROJECT_FILE}")
    content = read_file(PROJECT_FILE)
    print(f"   原文件大小: {len(content)} 字符")

    # 3. 逐步添加配置
    print("\n🔧 开始注入 Share Extension 配置...")

    print("\n1/9 添加 PBXBuildFile...")
    content = add_build_files(content)

    print("2/9 添加 PBXFileReference...")
    content = add_file_references(content)

    print("3/9 添加 PBXGroup...")
    content = add_group(content)

    print("4/9 添加 PBXSourcesBuildPhase...")
    content = add_sources_phase(content)

    print("5/9 添加 PBXResourcesBuildPhase...")
    content = add_resources_phase(content)

    print("6/9 添加 PBXNativeTarget...")
    content = add_native_target(content)

    print("7/9 添加 PBXTargetDependency 和 ContainerItemProxy...")
    content = add_target_dependency(content)

    print("8/9 添加 XCBuildConfiguration 和 XCConfigurationList...")
    content = add_build_configurations(content)

    print("9/9 添加 Target 到 Project 和主组...")
    content = add_target_to_project(content)
    content = add_group_to_main_group(content)
    content = add_entitlements_to_runner(content)

    # 4. 保存修改后的文件
    print(f"\n💾 保存修改后的文件...")
    write_file(PROJECT_FILE, content)
    print(f"   新文件大小: {len(content)} 字符")

    # 5. 验证
    print("\n🔍 验证修改结果...")
    verify_content = read_file(PROJECT_FILE)

    checks = [
        ("ShareExtension Target", f"{IDS['target']} /* ShareExtension */"),
        ("ShareExtension Product", f"{IDS['product_ref']} /* ShareExtension.appex */"),
        ("ShareViewController.swift", "ShareViewController.swift"),
        ("ShareExtension.entitlements", "ShareExtension.entitlements"),
        ("App Group", "group.com.plbear.fluxio"),
        ("Bundle ID", SHARE_EXT_BUNDLE_ID),
    ]

    all_passed = True
    for name, pattern in checks:
        if pattern in verify_content:
            print(f"   ✅ {name}")
        else:
            print(f"   ❌ {name} - 未找到!")
            all_passed = False

    print("\n" + "=" * 60)
    if all_passed:
        print("✅ 所有验证通过！Share Extension Target 注入成功！")
        print(f"\n📝 生成的 ID:")
        for key, value in IDS.items():
            print(f"   {key}: {value}")
    else:
        print("⚠️ 部分验证未通过，请检查文件！")
        print(f"   原文件备份在: {BACKUP_FILE}")
    print("=" * 60)

    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())
