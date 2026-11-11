import { type ConfigPlugin, type XcodeProject, withXcodeProject } from 'expo/config-plugins';

export type PackageRequirement = { kind: 'version'; version: string } | { kind: 'branch'; branch: string };

const REPOSITORY = 'https://github.com/airowe/siri-ai-kit';
const PRODUCT = 'SiriAIKit';
const REFERENCE_COMMENT = 'XCRemoteSwiftPackageReference "siri-ai-kit"';
const FRAMEWORKS_COMMENT = `${PRODUCT} in Frameworks`;

const quote = (value: string) => `"${value}"`;

type Section = Record<string, any>;

function section(project: XcodeProject, isa: string): Section {
  const objects = project.hash.project.objects;
  objects[isa] = objects[isa] ?? {};
  return objects[isa];
}

function entries(target: Section): [string, any][] {
  return Object.entries(target).filter(([key]) => !key.endsWith('_comment'));
}

function packageRequirement(requirement: PackageRequirement) {
  return requirement.kind === 'branch'
    ? { kind: 'branch', branch: quote(requirement.branch) }
    : { kind: 'upToNextMinorVersion', minimumVersion: requirement.version };
}

function appTarget(project: XcodeProject): any {
  const target = entries(project.pbxNativeTargetSection())
    .map(([, value]) => value)
    .find((value) => value.productType === quote('com.apple.product-type.application'));
  if (!target) throw new Error('expo-siri-ai-kit: no iOS app target found');
  return target;
}

function frameworksPhase(project: XcodeProject, target: any): any {
  const phases = section(project, 'PBXFrameworksBuildPhase');
  const phase = target.buildPhases.map((ref: { value: string }) => phases[ref.value]).find(Boolean);
  if (!phase) throw new Error('expo-siri-ai-kit: the iOS app target has no Frameworks build phase');
  return phase;
}

/** Adds SiriAIKit as a remote Swift package and links it to the app target, where inline-module intents compile. */
export function addSiriAIKitPackage(project: XcodeProject, requirement: PackageRequirement): void {
  const references = section(project, 'XCRemoteSwiftPackageReference');
  if (entries(references).some(([, reference]) => reference.repositoryURL === quote(REPOSITORY))) return;

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

export const withSiriAIKitPackage: ConfigPlugin<PackageRequirement> = (config, requirement) =>
  withXcodeProject(config, (next) => {
    addSiriAIKitPackage(next.modResults, requirement);
    return next;
  });
