import path from 'path';
import xcode from 'xcode';
import type { XcodeProject } from 'expo/config-plugins';

import { addSyrupAIKitPackage } from '../withSyrupAIKitPackage';
import { enableSiriAIPreview } from '../withSiriAIPreview';
import { addEvalsTarget, evalsScheme, evalsTargetName, findSwiftSources } from '../withSiriAIEvals';

const parser = require('xcode/lib/parser/pbxproj');

const FIXTURE = path.join(__dirname, 'fixtures', 'project.pbxproj');
const SOURCE_DIR = path.join(__dirname, 'fixtures', 'siri-evals');
const APP_NAME = 'HelloWorld';
const APP_BUNDLE_ID = 'org.name.HelloWorld';
const TARGET_NAME = 'HelloWorldEvals';
const SOURCE_PATH = '../siri-evals';
const SOURCES = ['OrderStatusEvaluationTests.swift', 'Scenarios/CartScenarios.swift'];
const UI_TESTING = '"com.apple.product-type.bundle.ui-testing"';
const EVAL_PRODUCT = 'SyrupAIEvalKit';
const EVAL_DEPLOYMENT_TARGET = '27.3';
const RELEASE = { kind: 'version', version: '0.2.0' } as const;
const EVALS = { name: TARGET_NAME, sourcePath: SOURCE_PATH, files: SOURCES };

function objects(project: XcodeProject, isa: string): [string, any][] {
  return Object.entries(project.hash.project.objects[isa] ?? {}).filter(([key]) => !key.endsWith('_comment'));
}

function loadProjectWithPackage(): XcodeProject {
  const project = xcode.project(FIXTURE).parseSync();
  addSyrupAIKitPackage(project, RELEASE);
  return project;
}

function nativeTarget(project: XcodeProject, name: string): [string, any] | undefined {
  return objects(project, 'PBXNativeTarget').find(([, target]) => target.name === name);
}

function evalsTarget(project: XcodeProject): any {
  const found = nativeTarget(project, TARGET_NAME);
  if (!found) throw new Error('no evals target');
  return found[1];
}

function buildSettings(project: XcodeProject, target: any): Record<string, any>[] {
  const lists = project.hash.project.objects.XCConfigurationList;
  const configurations = project.hash.project.objects.XCBuildConfiguration;
  return lists[target.buildConfigurationList].buildConfigurations.map(
    (ref: { value: string }) => configurations[ref.value].buildSettings,
  );
}

function phase(project: XcodeProject, target: any, isa: string): any {
  const section = project.hash.project.objects[isa];
  return target.buildPhases.map((ref: { value: string }) => section[ref.value]).find(Boolean);
}

describe('evalsTargetName', () => {
  it.each([
    [{ sourceDir: 'siri-evals' }, `${APP_NAME}Evals`],
    [{ sourceDir: 'siri-evals', targetName: 'SiriEvals' }, 'SiriEvals'],
  ])('names the target for %o', (options, expected) => {
    expect(evalsTargetName(options, APP_NAME)).toBe(expected);
  });
});

describe('findSwiftSources', () => {
  it('lists the Swift files under the folder, nested ones included, and nothing else', () => {
    expect(findSwiftSources(SOURCE_DIR)).toEqual(SOURCES);
  });

  it('explains when the folder does not exist', () => {
    const missing = path.join(__dirname, 'fixtures', 'no-such-folder');
    expect(() => findSwiftSources(missing)).toThrow(`expo-syrup-ai-kit: evals.sourceDir ${missing} does not exist`);
  });

  it('explains when the path is a file', () => {
    const file = path.join(SOURCE_DIR, SOURCES[0]);
    expect(() => findSwiftSources(file)).toThrow(`expo-syrup-ai-kit: evals.sourceDir ${file} is not a folder`);
  });

  it('explains when the folder has no Swift files', () => {
    const noSwift = path.join(__dirname, 'fixtures', 'no-swift');
    expect(() => findSwiftSources(noSwift)).toThrow(`expo-syrup-ai-kit: evals.sourceDir ${noSwift} has no .swift files`);
  });
});

describe('addEvalsTarget', () => {
  it('adds a UI testing target that tests the app', () => {
    const project = loadProjectWithPackage();
    const result = addEvalsTarget(project, EVALS);

    const [appId, app] = nativeTarget(project, APP_NAME)!;
    const [evalsId, target] = nativeTarget(project, TARGET_NAME)!;
    expect(target.productType).toBe(UI_TESTING);
    expect(result).toEqual({ app: { id: appId, name: APP_NAME }, evals: { id: evalsId, name: TARGET_NAME } });

    const root = project.getFirstProject().firstProject;
    expect(root.targets.map((ref: any) => ref.value)).toEqual([appId, evalsId]);
    expect(root.attributes.TargetAttributes[evalsId].TestTargetID).toBe(appId);
    expect(app.dependencies).toEqual([]);
  });

  it('depends on the app target', () => {
    const project = loadProjectWithPackage();
    addEvalsTarget(project, EVALS);

    const [appId] = nativeTarget(project, APP_NAME)!;
    const target = evalsTarget(project);
    expect(target.dependencies).toHaveLength(1);
    const dependency = project.hash.project.objects.PBXTargetDependency[target.dependencies[0].value];
    expect(dependency.target).toBe(appId);
    const proxy = project.hash.project.objects.PBXContainerItemProxy[dependency.targetProxy];
    expect(proxy.remoteGlobalIDString).toBe(appId);
    expect(proxy.containerPortal).toBe(project.hash.project.rootObject);
  });

  it('builds for iOS 27.3 against the app, signed like the app', () => {
    const project = loadProjectWithPackage();
    addEvalsTarget(project, EVALS);

    const settings = buildSettings(project, evalsTarget(project));
    expect(settings).toHaveLength(2);
    for (const setting of settings) {
      expect(setting).toMatchObject({
        TEST_TARGET_NAME: APP_NAME,
        IPHONEOS_DEPLOYMENT_TARGET: EVAL_DEPLOYMENT_TARGET,
        PRODUCT_NAME: '"$(TARGET_NAME)"',
        PRODUCT_BUNDLE_IDENTIFIER: `"${APP_BUNDLE_ID}.evals"`,
        GENERATE_INFOPLIST_FILE: 'YES',
        CODE_SIGN_STYLE: 'Automatic',
      });
    }
  });

  it('copies the development team from the app target when it has one', () => {
    const project = loadProjectWithPackage();
    const [, app] = nativeTarget(project, APP_NAME)!;
    for (const setting of buildSettings(project, app)) setting.DEVELOPMENT_TEAM = 'ABCDE12345';
    addEvalsTarget(project, EVALS);

    for (const setting of buildSettings(project, evalsTarget(project))) {
      expect(setting.DEVELOPMENT_TEAM).toBe('ABCDE12345');
    }
  });

  it('compiles the Swift files from the source folder outside ios/', () => {
    const project = loadProjectWithPackage();
    addEvalsTarget(project, EVALS);

    const sources = phase(project, evalsTarget(project), 'PBXSourcesBuildPhase');
    const buildFiles = project.hash.project.objects.PBXBuildFile;
    const fileRefs = project.hash.project.objects.PBXFileReference;
    const compiled = sources.files.map((ref: any) => fileRefs[buildFiles[ref.value].fileRef]);
    expect(compiled.map((file: any) => file.path)).toEqual(SOURCES.map((source) => `"${source}"`));
    expect(compiled.every((file: any) => file.lastKnownFileType === 'sourcecode.swift')).toBe(true);

    const group = objects(project, 'PBXGroup').find(([, entry]) => entry.name === TARGET_NAME);
    expect(group?.[1].path).toBe(`"${SOURCE_PATH}"`);
    const mainGroup = project.hash.project.objects.PBXGroup[project.getFirstProject().firstProject.mainGroup];
    expect(mainGroup.children.map((ref: any) => ref.value)).toContain(group?.[0]);
  });

  it('links SyrupAIEvalKit from the existing SyrupAIKit package reference', () => {
    const project = loadProjectWithPackage();
    addEvalsTarget(project, EVALS);

    expect(objects(project, 'XCRemoteSwiftPackageReference')).toHaveLength(1);
    const [[referenceId]] = objects(project, 'XCRemoteSwiftPackageReference');
    const products = objects(project, 'XCSwiftPackageProductDependency');
    const [productId, product] = products.find(([, entry]) => entry.productName === EVAL_PRODUCT)!;
    expect(product.package).toBe(referenceId);

    const target = evalsTarget(project);
    expect(target.packageProductDependencies.map((ref: any) => ref.value)).toEqual([productId]);
    const frameworks = phase(project, target, 'PBXFrameworksBuildPhase');
    const buildFiles = project.hash.project.objects.PBXBuildFile;
    expect(frameworks.files.map((ref: any) => buildFiles[ref.value].productRef)).toEqual([productId]);
  });

  it('adds the target once when prebuild runs the plugin twice', () => {
    const project = loadProjectWithPackage();
    const first = addEvalsTarget(project, EVALS);
    const objectCount = JSON.stringify(project.hash).length;
    const second = addEvalsTarget(project, EVALS);

    expect(second).toEqual(first);
    expect(JSON.stringify(project.hash).length).toBe(objectCount);
  });

  it('explains when the SyrupAIKit package has not been added', () => {
    const project = xcode.project(FIXTURE).parseSync();
    expect(() => addEvalsTarget(project, EVALS)).toThrow('expo-syrup-ai-kit: the SyrupAIKit package reference is missing');
  });

  it('is raised to the preview build settings with the app', () => {
    const project = loadProjectWithPackage();
    addEvalsTarget(project, EVALS);
    enableSiriAIPreview(project);

    for (const setting of buildSettings(project, evalsTarget(project))) {
      expect(setting.SWIFT_ACTIVE_COMPILATION_CONDITIONS).toBe('"$(inherited) SIRI_AI_PREVIEW"');
      expect(setting.IPHONEOS_DEPLOYMENT_TARGET).toBe(EVAL_DEPLOYMENT_TARGET);
    }
  });

  it('writes a project the pbxproj parser reads back', () => {
    const project = loadProjectWithPackage();
    addEvalsTarget(project, EVALS);
    const written = project.writeSync();

    expect(() => parser.parse(written)).not.toThrow();
    expect(written).toContain(`productType = ${UI_TESTING};`);
    expect(written).toContain(`TEST_TARGET_NAME = ${APP_NAME};`);
    expect(written).toContain(`productName = ${EVAL_PRODUCT};`);
    expect(written).toContain(`path = "${SOURCE_PATH}";`);
  });
});

describe('evalsScheme', () => {
  const ids = { app: { id: 'APPID', name: APP_NAME }, evals: { id: 'EVALSID', name: TARGET_NAME } };
  const scheme = evalsScheme({ projectName: APP_NAME, ...ids });

  it('tests the evals target', () => {
    expect(scheme).toMatch(
      /<TestableReference[\s\S]*BlueprintIdentifier = "EVALSID"[\s\S]*BuildableName = "HelloWorldEvals\.xctest"[\s\S]*<\/TestableReference>/,
    );
  });

  it('builds and launches the app it tests', () => {
    expect(scheme).toMatch(/<BuildActionEntry[\s\S]*BlueprintIdentifier = "APPID"[\s\S]*BuildableName = "HelloWorld\.app"/);
    expect(scheme).toMatch(/<LaunchAction[\s\S]*BlueprintIdentifier = "APPID"[\s\S]*<\/LaunchAction>/);
  });

  it('points at the project container', () => {
    expect(scheme).toContain('ReferencedContainer = "container:HelloWorld.xcodeproj"');
    expect(scheme.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
  });
});
