import type { XcodeProject } from 'expo/config-plugins';

export type PackageRequirement = { kind: 'version'; version: string } | { kind: 'branch'; branch: string };

const REPOSITORY = 'https://github.com/airowe/syrup-ai-kit';
const PRODUCT = 'SyrupAIKit';
export const REFERENCE_COMMENT = 'XCRemoteSwiftPackageReference "syrup-ai-kit"';
const FRAMEWORKS_COMMENT = `${PRODUCT} in Frameworks`;

export const quote = (value: string) => `"${value}"`;

export type Section = Record<string, any>;

export function section(project: XcodeProject, isa: string): Section {
  const objects = project.hash.project.objects;
  objects[isa] = objects[isa] ?? {};
  return objects[isa];
}

export function entries(target: Section): [string, any][] {
  return Object.entries(target).filter(([key]) => !key.endsWith('_comment'));
}

function packageRequirement(requirement: PackageRequirement) {
  return requirement.kind === 'branch'
    ? { kind: 'branch', branch: quote(requirement.branch) }
    : { kind: 'upToNextMinorVersion', minimumVersion: requirement.version };
}

export function appTargetEntry(project: XcodeProject): [string, any] {
  const entry = entries(project.pbxNativeTargetSection()).find(
    ([, value]) => value.productType === quote('com.apple.product-type.application'),
  );
  if (!entry) throw new Error('expo-syrup-ai-kit: no iOS app target found');
  return entry;
}

const appTarget = (project: XcodeProject) => appTargetEntry(project)[1];

/** The id of the SyrupAIKit package reference that `addSyrupAIKitPackage` added, if any. */
export function syrupAIKitReferenceId(project: XcodeProject): string | undefined {
  return entries(section(project, 'XCRemoteSwiftPackageReference')).find(
    ([, reference]) => reference.repositoryURL === quote(REPOSITORY),
  )?.[0];
}

function frameworksPhase(project: XcodeProject, target: any): any {
  const phases = section(project, 'PBXFrameworksBuildPhase');
  const phase = target.buildPhases.map((ref: { value: string }) => phases[ref.value]).find(Boolean);
  if (!phase) throw new Error('expo-syrup-ai-kit: the iOS app target has no Frameworks build phase');
  return phase;
}

/** Adds SyrupAIKit as a remote Swift package and links it to the app target, where inline-module intents compile. */
export function addSyrupAIKitPackage(project: XcodeProject, requirement: PackageRequirement): void {
  if (syrupAIKitReferenceId(project)) return;
  const references = section(project, 'XCRemoteSwiftPackageReference');

  const target = appTarget(project);
  const phase = frameworksPhase(project, target);

  const referenceId = project.generateUuid();
  references[referenceId] = {
    isa: 'XCRemoteSwiftPackageReference',
    repositoryURL: quote(REPOSITORY),
    requirement: packageRequirement(requirement),
  };
  references[`${referenceId}_comment`] = REFERENCE_COMMENT;

  const productId = project.generateUuid();
  const products = section(project, 'XCSwiftPackageProductDependency');
  products[productId] = {
    isa: 'XCSwiftPackageProductDependency',
    package: referenceId,
    package_comment: REFERENCE_COMMENT,
    productName: PRODUCT,
  };
  products[`${productId}_comment`] = PRODUCT;

  const buildFileId = project.generateUuid();
  const buildFiles = section(project, 'PBXBuildFile');
  buildFiles[buildFileId] = { isa: 'PBXBuildFile', productRef: productId, productRef_comment: PRODUCT };
  buildFiles[`${buildFileId}_comment`] = FRAMEWORKS_COMMENT;

  phase.files.push({ value: buildFileId, comment: FRAMEWORKS_COMMENT });
  target.packageProductDependencies = [
    ...(target.packageProductDependencies ?? []),
    { value: productId, comment: PRODUCT },
  ];

  const root = project.getFirstProject().firstProject;
  root.packageReferences = [...(root.packageReferences ?? []), { value: referenceId, comment: REFERENCE_COMMENT }];
}
