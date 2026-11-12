import fs from 'fs';
import path from 'path';
import { IOSConfig, type XcodeProject } from 'expo/config-plugins';

import {
  REFERENCE_COMMENT,
  appTargetEntry,
  entries,
  quote,
  section,
  syrupAIKitReferenceId,
} from './withSyrupAIKitPackage';

export type EvalsOptions = {
  /** Folder of Swift evaluation tests, relative to the project root. Keep it outside `ios/`. */
  sourceDir: string;
  /** Name of the UI test target and its scheme. Defaults to `<AppName>Evals`. */
  targetName?: string;
};

export type EvalsTarget = {
  name: string;
  /** The source folder, relative to the `ios/` folder that holds the Xcode project. */
  sourcePath: string;
  /** Swift files, relative to the source folder. */
  files: string[];
};

type TargetRef = { id: string; name: string };
export type EvalsTargets = { app: TargetRef; evals: TargetRef };

const PRODUCT = 'SyrupAIEvalKit';
/** Siri Evaluations run on iOS 27.3 devices only. */
const EVALS_DEPLOYMENT_TARGET = '27.3';
const UI_TESTING = 'com.apple.product-type.bundle.ui-testing';

const unquote = (value: string) => value.replace(/^"(.*)"$/, '$1');

export const evalsTargetName = (options: EvalsOptions, appName: string) => options.targetName ?? `${appName}Evals`;

/** Lists the `.swift` files under `directory`, as sorted POSIX paths relative to it. */
export function findSwiftSources(directory: string): string[] {
  if (!fs.existsSync(directory)) throw new Error(`expo-syrup-ai-kit: evals.sourceDir ${directory} does not exist`);
  if (!fs.statSync(directory).isDirectory()) {
    throw new Error(`expo-syrup-ai-kit: evals.sourceDir ${directory} is not a folder`);
  }
  const files = fs
    .readdirSync(directory, { recursive: true, encoding: 'utf8' })
    .filter((file) => file.endsWith('.swift') && fs.statSync(path.join(directory, file)).isFile())
    .map((file) => file.split(path.sep).join('/'))
    .sort();
  if (files.length === 0) throw new Error(`expo-syrup-ai-kit: evals.sourceDir ${directory} has no .swift files`);
  return files;
}

function add(project: XcodeProject, isa: string, value: Record<string, any>, comment: string): string {
  const id = project.generateUuid();
  const objects = section(project, isa);
  objects[id] = { isa, ...value };
  objects[`${id}_comment`] = comment;
  return id;
}

function configurations(project: XcodeProject, target: any): any[] {
  const list = section(project, 'XCConfigurationList')[target.buildConfigurationList];
  const all = section(project, 'XCBuildConfiguration');
  return list.buildConfigurations.map((ref: { value: string }) => all[ref.value]);
}

function evalsBuildSettings(appName: string, appSettings: Record<string, any>): Record<string, any> {
  const bundleId = unquote(String(appSettings.PRODUCT_BUNDLE_IDENTIFIER ?? appName));
  return {
    CODE_SIGN_STYLE: 'Automatic',
    ...(appSettings.DEVELOPMENT_TEAM ? { DEVELOPMENT_TEAM: appSettings.DEVELOPMENT_TEAM } : {}),
    GENERATE_INFOPLIST_FILE: 'YES',
    IPHONEOS_DEPLOYMENT_TARGET: EVALS_DEPLOYMENT_TARGET,
    LD_RUNPATH_SEARCH_PATHS: ['"$(inherited)"', '"@executable_path/Frameworks"', '"@loader_path/Frameworks"'],
    PRODUCT_BUNDLE_IDENTIFIER: quote(`${bundleId}.evals`),
    PRODUCT_NAME: quote('$(TARGET_NAME)'),
    SDKROOT: 'iphoneos',
    SWIFT_VERSION: '5.0',
    TARGETED_DEVICE_FAMILY: quote('1,2'),
    TEST_TARGET_NAME: appName,
  };
}

function addSourceGroup(project: XcodeProject, target: EvalsTarget): string[] {
  const buildFiles: string[] = [];
  const children = target.files.map((file) => {
    const name = path.posix.basename(file);
    const fileRef = add(
      project,
      'PBXFileReference',
      { lastKnownFileType: 'sourcecode.swift', name: quote(name), path: quote(file), sourceTree: quote('<group>') },
      name,
    );
    buildFiles.push(add(project, 'PBXBuildFile', { fileRef, fileRef_comment: name }, `${name} in Sources`));
    return { value: fileRef, comment: name };
  });
  const groupId = add(
    project,
    'PBXGroup',
    { children, name: target.name, path: quote(target.sourcePath), sourceTree: quote('<group>') },
    target.name,
  );
  const root = project.getFirstProject().firstProject;
  section(project, 'PBXGroup')[root.mainGroup].children.push({ value: groupId, comment: target.name });
  return buildFiles;
}

function addAppDependency(project: XcodeProject, app: TargetRef): string {
  const proxy = add(
    project,
    'PBXContainerItemProxy',
    {
      containerPortal: project.hash.project.rootObject,
      containerPortal_comment: 'Project object',
      proxyType: 1,
      remoteGlobalIDString: app.id,
      remoteInfo: app.name,
    },
    'PBXContainerItemProxy',
  );
  return add(
    project,
    'PBXTargetDependency',
    { target: app.id, target_comment: app.name, targetProxy: proxy, targetProxy_comment: 'PBXContainerItemProxy' },
    'PBXTargetDependency',
  );
}

/**
 * Adds a UI testing target that compiles the evaluation sources from outside `ios/`, tests the app target and
 * links SyrupAIEvalKit from the SyrupAIKit package reference. Run it after `addSyrupAIKitPackage`.
 */
export function addEvalsTarget(project: XcodeProject, target: EvalsTarget): EvalsTargets {
  const [appId, appTarget] = appTargetEntry(project);
  const app = { id: appId, name: unquote(appTarget.name) };

  const existing = entries(project.pbxNativeTargetSection()).find(([, value]) => unquote(value.name) === target.name);
  if (existing) return { app, evals: { id: existing[0], name: target.name } };

  const referenceId = syrupAIKitReferenceId(project);
  if (!referenceId) throw new Error('expo-syrup-ai-kit: the SyrupAIKit package reference is missing');

  const productId = add(
    project,
    'XCSwiftPackageProductDependency',
    { package: referenceId, package_comment: REFERENCE_COMMENT, productName: PRODUCT },
    PRODUCT,
  );
  const frameworkFile = add(
    project,
    'PBXBuildFile',
    { productRef: productId, productRef_comment: PRODUCT },
    `${PRODUCT} in Frameworks`,
  );
  const phase = (isa: string, comment: string, files: string[], suffix: string) =>
    add(
      project,
      isa,
      {
        buildActionMask: 2147483647,
        files: files.map((value) => ({ value, comment: suffix })),
        runOnlyForDeploymentPostprocessing: 0,
      },
      comment,
    );
  const sourcesPhase = phase('PBXSourcesBuildPhase', 'Sources', addSourceGroup(project, target), '');
  for (const ref of section(project, 'PBXSourcesBuildPhase')[sourcesPhase].files) {
    ref.comment = section(project, 'PBXBuildFile')[`${ref.value}_comment`];
  }
  const frameworksPhase = phase('PBXFrameworksBuildPhase', 'Frameworks', [frameworkFile], `${PRODUCT} in Frameworks`);

  const appConfigurations = configurations(project, appTarget);
  const configurationRefs = appConfigurations.map((configuration) => ({
    value: add(
      project,
      'XCBuildConfiguration',
      { buildSettings: evalsBuildSettings(app.name, configuration.buildSettings), name: configuration.name },
      configuration.name,
    ),
    comment: configuration.name,
  }));
  const listComment = `Build configuration list for PBXNativeTarget "${target.name}"`;
  const configurationList = add(
    project,
    'XCConfigurationList',
    {
      buildConfigurations: configurationRefs,
      defaultConfigurationIsVisible: 0,
      defaultConfigurationName: 'Release',
    },
    listComment,
  );

  const productFile = `${target.name}.xctest`;
  const productRef = add(
    project,
    'PBXFileReference',
    { explicitFileType: 'wrapper.cfbundle', includeInIndex: 0, path: productFile, sourceTree: 'BUILT_PRODUCTS_DIR' },
    productFile,
  );
  const root = project.getFirstProject().firstProject;
  section(project, 'PBXGroup')[root.productRefGroup]?.children.push({ value: productRef, comment: productFile });

  const dependency = addAppDependency(project, app);
  const evalsId = add(
    project,
    'PBXNativeTarget',
    {
      buildConfigurationList: configurationList,
      buildConfigurationList_comment: listComment,
      buildPhases: [
        { value: sourcesPhase, comment: 'Sources' },
        { value: frameworksPhase, comment: 'Frameworks' },
      ],
      buildRules: [],
      dependencies: [{ value: dependency, comment: 'PBXTargetDependency' }],
      name: target.name,
      packageProductDependencies: [{ value: productId, comment: PRODUCT }],
      productName: target.name,
      productReference: productRef,
      productReference_comment: productFile,
      productType: quote(UI_TESTING),
    },
    target.name,
  );

  root.targets.push({ value: evalsId, comment: target.name });
  root.attributes = root.attributes ?? {};
  root.attributes.TargetAttributes = { ...root.attributes.TargetAttributes, [evalsId]: { TestTargetID: appId } };

  return { app, evals: { id: evalsId, name: target.name } };
}

const buildableReference = (target: TargetRef, product: string, container: string, indent: string) =>
  [
    `${indent}<BuildableReference`,
    `${indent}   BuildableIdentifier = "primary"`,
    `${indent}   BlueprintIdentifier = "${target.id}"`,
    `${indent}   BuildableName = "${product}"`,
    `${indent}   BlueprintName = "${target.name}"`,
    `${indent}   ReferencedContainer = "${container}">`,
    `${indent}</BuildableReference>`,
  ].join('\n');

/** A shared scheme named after the evals target, so `xcodebuild test -scheme <targetName>` runs the evaluations. */
export function evalsScheme({ projectName, app, evals }: EvalsTargets & { projectName: string }): string {
  const container = `container:${projectName}.xcodeproj`;
  const appRef = (indent: string) => buildableReference(app, `${app.name}.app`, container, indent);
  const evalsRef = (indent: string) => buildableReference(evals, `${evals.name}.xctest`, container, indent);
  return `<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2700"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
${appRef('            ')}
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "NO"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
${evalsRef('            ')}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
${evalsRef('            ')}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
${appRef('         ')}
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
`;
}

type ModPaths = { projectRoot: string; platformProjectRoot: string };

/** Adds the evals target from `options.sourceDir` and writes its shared scheme next to the Xcode project. */
export function addSiriAIEvals(project: XcodeProject, options: EvalsOptions, paths: ModPaths): void {
  if (typeof options.sourceDir !== 'string' || options.sourceDir.length === 0) {
    throw new Error('expo-syrup-ai-kit: evals.sourceDir must name a folder of Swift evaluation tests');
  }
  const sourceDir = path.resolve(paths.projectRoot, options.sourceDir);
  const [, appTarget] = appTargetEntry(project);
  const targets = addEvalsTarget(project, {
    name: evalsTargetName(options, unquote(appTarget.name)),
    sourcePath: path.relative(paths.platformProjectRoot, sourceDir).split(path.sep).join('/'),
    files: findSwiftSources(sourceDir),
  });

  const xcodeProject = IOSConfig.Paths.getXcodeProjectPath(paths.projectRoot);
  const schemes = path.join(xcodeProject, 'xcshareddata', 'xcschemes');
  fs.mkdirSync(schemes, { recursive: true });
  const projectName = path.basename(xcodeProject, '.xcodeproj');
  fs.writeFileSync(path.join(schemes, `${targets.evals.name}.xcscheme`), evalsScheme({ projectName, ...targets }));
}
