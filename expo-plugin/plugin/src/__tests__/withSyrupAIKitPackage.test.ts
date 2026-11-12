import path from 'path';
import xcode from 'xcode';
import type { XcodeProject } from 'expo/config-plugins';

import { addSyrupAIKitPackage } from '../withSyrupAIKitPackage';

const FIXTURE = path.join(__dirname, 'fixtures', 'project.pbxproj');
const REPOSITORY = '"https://github.com/airowe/syrup-ai-kit"';
const PRODUCT = 'SyrupAIKit';
const RELEASE = { kind: 'version', version: '0.2.0' } as const;

function loadProject(): XcodeProject {
  return xcode.project(FIXTURE).parseSync();
}

function objects(project: XcodeProject, isa: string): [string, any][] {
  return Object.entries(project.hash.project.objects[isa] ?? {}).filter(([key]) => !key.endsWith('_comment'));
}

function appTarget(project: XcodeProject): any {
  return objects(project, 'PBXNativeTarget')
    .map(([, target]) => target)
    .find((target) => target.productType === '"com.apple.product-type.application"');
}

describe('addSyrupAIKitPackage', () => {
  it('adds a remote package reference pinned to the next minor version', () => {
    const project = loadProject();
    addSyrupAIKitPackage(project, RELEASE);

    const references = objects(project, 'XCRemoteSwiftPackageReference');
    expect(references).toHaveLength(1);
    expect(references[0][1].repositoryURL).toBe(REPOSITORY);
    expect(references[0][1].requirement).toEqual({ kind: 'upToNextMinorVersion', minimumVersion: '0.2.0' });

    const root = project.getFirstProject().firstProject;
    expect(root.packageReferences.map((ref: any) => ref.value)).toEqual([references[0][0]]);
  });

  it('follows a branch when asked', () => {
    const project = loadProject();
    addSyrupAIKitPackage(project, { kind: 'branch', branch: 'feat/0.2.0' });

    const [[, reference]] = objects(project, 'XCRemoteSwiftPackageReference');
    expect(reference.requirement).toEqual({ kind: 'branch', branch: '"feat/0.2.0"' });
  });

  it('links the SyrupAIKit product to the app target', () => {
    const project = loadProject();
    addSyrupAIKitPackage(project, RELEASE);

    const [[productId, product]] = objects(project, 'XCSwiftPackageProductDependency');
    const [[referenceId]] = objects(project, 'XCRemoteSwiftPackageReference');
    expect(product.productName).toBe(PRODUCT);
    expect(product.package).toBe(referenceId);

    const target = appTarget(project);
    expect(target.packageProductDependencies.map((dep: any) => dep.value)).toEqual([productId]);

    const buildFile = objects(project, 'PBXBuildFile').find(([, file]) => file.productRef === productId);
    expect(buildFile).toBeDefined();
    const phases = project.hash.project.objects.PBXFrameworksBuildPhase;
    const frameworks = target.buildPhases.map((ref: any) => phases[ref.value]).find(Boolean);
    expect(frameworks.files.map((file: any) => file.value)).toContain(buildFile![0]);
  });

  it('adds the package once when prebuild runs the plugin twice', () => {
    const project = loadProject();
    addSyrupAIKitPackage(project, RELEASE);
    addSyrupAIKitPackage(project, RELEASE);

    expect(objects(project, 'XCRemoteSwiftPackageReference')).toHaveLength(1);
    expect(objects(project, 'XCSwiftPackageProductDependency')).toHaveLength(1);
    expect(appTarget(project).packageProductDependencies).toHaveLength(1);
  });

  it('writes a project Xcode can read', () => {
    const project = loadProject();
    addSyrupAIKitPackage(project, RELEASE);
    const written = project.writeSync();

    expect(written).toContain(`repositoryURL = ${REPOSITORY};`);
    expect(written).toMatch(/requirement = \{\s*kind = upToNextMinorVersion;\s*minimumVersion = 0\.2\.0;\s*\};/);
    expect(written).toContain(`productName = ${PRODUCT};`);
    expect(written).toContain(`/* ${PRODUCT} in Frameworks */`);
    expect(() => xcode.project(FIXTURE).parse).not.toThrow();
  });

  it('explains when the project has no app target', () => {
    const project = loadProject();
    appTarget(project).productType = '"com.apple.product-type.framework"';

    expect(() => addSyrupAIKitPackage(project, RELEASE)).toThrow('expo-syrup-ai-kit: no iOS app target found');
  });
});
