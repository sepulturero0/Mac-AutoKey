#!/usr/bin/env python3
"""Regenerate the checked-in Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parent.parent
project = root / 'MacAutoKey.xcodeproj'
project.mkdir(exist_ok=True)
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(identity_name, isa, **props):
    identity = uid(identity_name)
    objects[identity] = {'isa': isa, **props}
    return identity

def q(value): return json.dumps(str(value))
def serialize(value, indent=0):
    if isinstance(value, dict):
        return '{\n' + ''.join('\t'*(indent+1) + q(k) + ' = ' + serialize(v, indent+1) + ';\n' for k,v in value.items()) + '\t'*indent + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t'*(indent+1) + serialize(v, indent+1) + ',\n' for v in value) + '\t'*indent + ')'
    return q(value)

app_sources = sorted((root/'Sources/MacAutoKey').glob('*.swift'))
test_sources = sorted((root/'Tests/MacAutoKeyTests').glob('*.swift'))
def source_group(name, sources):
    refs, builds = [], []
    for path in sources:
        rel = str(path.relative_to(root))
        ref = add(rel+'ref', 'PBXFileReference', lastKnownFileType='sourcecode.swift', path=rel, sourceTree='<group>')
        refs.append(ref)
        builds.append(add(rel+'build', 'PBXBuildFile', fileRef=ref))
    return add(name+'group', 'PBXGroup', name=name, children=refs, sourceTree='<group>'), builds

app_group, app_builds = source_group('Application', app_sources)
test_group, test_builds = source_group('Tests', test_sources)
app_product = add('app-product', 'PBXFileReference', explicitFileType='wrapper.application', path='Mac AutoKey.app', sourceTree='BUILT_PRODUCTS_DIR')
test_product = add('test-product', 'PBXFileReference', explicitFileType='wrapper.cfbundle', path='MacAutoKeyTests.xctest', sourceTree='BUILT_PRODUCTS_DIR')
products = add('products', 'PBXGroup', name='Products', children=[app_product, test_product], sourceTree='<group>')
info = add('info', 'PBXFileReference', lastKnownFileType='text.plist.xml', path='Resources/Info.plist', sourceTree='<group>')
readme = add('readme', 'PBXFileReference', lastKnownFileType='net.daringfireball.markdown', path='README.md', sourceTree='<group>')
icon = add('icon', 'PBXFileReference', lastKnownFileType='image.icns', path='Resources/AppIcon.icns', sourceTree='<group>')
iconbuild = add('iconbuild', 'PBXBuildFile', fileRef=icon)
main_group = add('main-group', 'PBXGroup', children=[app_group, test_group, info, icon, readme, products], sourceTree='<group>')

common = {'MACOSX_DEPLOYMENT_TARGET':'14.0', 'SDKROOT':'macosx', 'SWIFT_VERSION':'6.0', 'CLANG_ENABLE_MODULES':'YES', 'SWIFT_STRICT_CONCURRENCY':'complete', 'CODE_SIGN_IDENTITY':'-', 'CODE_SIGN_STYLE':'Manual', 'ENABLE_HARDENED_RUNTIME':'NO', 'ENABLE_APP_SANDBOX':'NO'}
def configs(name, extra):
    result = []
    for mode in ['Debug','Release']:
        settings = {**common, 'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if mode=='Debug' else '-O', 'SWIFT_COMPILATION_MODE':'singlefile' if mode=='Debug' else 'wholemodule', 'ENABLE_TESTABILITY':'YES' if mode=='Debug' else 'NO', 'DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym', **extra}
        if mode=='Debug': settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        result.append(add(name+mode, 'XCBuildConfiguration', name=mode, buildSettings=settings))
    return add(name+'configs', 'XCConfigurationList', buildConfigurations=result, defaultConfigurationIsVisible='0', defaultConfigurationName='Release')

app_id = uid('app-target')
app = add('app-target', 'PBXNativeTarget', name='MacAutoKey', productName='Mac AutoKey', productType='com.apple.product-type.application', productReference=app_product,
    buildConfigurationList=configs('app', {'PRODUCT_NAME':'Mac AutoKey','EXECUTABLE_NAME':'MacAutoKey','PRODUCT_MODULE_NAME':'MacAutoKey','PRODUCT_BUNDLE_IDENTIFIER':'com.macautokey.app','INFOPLIST_FILE':'Resources/Info.plist','GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/../Frameworks','SUPPORTED_PLATFORMS':'macosx','ARCHS':'$(ARCHS_STANDARD)'}),
    buildPhases=[add('app-sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=app_builds,runOnlyForDeploymentPostprocessing='0'), add('app-frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0'),add('app-resources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[iconbuild],runOnlyForDeploymentPostprocessing='0')], buildRules=[],dependencies=[])
proxy = add('proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=app,remoteInfo='MacAutoKey')
dep = add('dependency','PBXTargetDependency',target=app,targetProxy=proxy)
tests = add('test-target','PBXNativeTarget',name='MacAutoKeyTests',productName='MacAutoKeyTests',productType='com.apple.product-type.bundle.unit-test',productReference=test_product,
    buildConfigurationList=configs('tests',{'PRODUCT_NAME':'$(TARGET_NAME)','PRODUCT_BUNDLE_IDENTIFIER':'com.macautokey.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Mac AutoKey.app/Contents/MacOS/MacAutoKey','BUNDLE_LOADER':'$(TEST_HOST)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @loader_path/../Frameworks @executable_path/../Frameworks'}),
    buildPhases=[add('test-sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=test_builds,runOnlyForDeploymentPostprocessing='0'),add('test-frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')],buildRules=[],dependencies=[dep])
project_id = add('project','PBXProject',attributes={'LastSwiftUpdateCheck':'1600','LastUpgradeCheck':'1600','TargetAttributes':{app:{'CreatedOnToolsVersion':'16.0'},tests:{'CreatedOnToolsVersion':'16.0','TestTargetID':app}}},buildConfigurationList=configs('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],mainGroup=main_group,productRefGroup=products,projectDirPath='',projectRoot='',targets=[app,tests])
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n'+serialize({'archiveVersion':'1','classes':{},'objectVersion':'56','objects':objects,'rootObject':project_id})+'\n')
schemes = project/'xcshareddata/xcschemes'
schemes.mkdir(parents=True,exist_ok=True)
def reference(target, name, product):
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{product}" BlueprintName="{name}" ReferencedContainer="container:MacAutoKey.xcodeproj"/>'
appref = reference(app,'MacAutoKey','Mac AutoKey.app')
testref = reference(tests,'MacAutoKeyTests','MacAutoKeyTests.xctest')
(schemes/'MacAutoKey.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated {project}')
