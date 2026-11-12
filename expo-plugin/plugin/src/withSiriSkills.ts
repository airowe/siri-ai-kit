import fs from 'fs';
import path from 'path';
import { type ConfigPlugin, type XcodeProject, withDangerousMod } from 'expo/config-plugins';

import { SKILL_FILE, skillsFolderProblems } from './siriSkills/validate';
import { appTargetEntry } from './withSyrupAIKitPackage';

const BUNDLE = 'Skills.skillsbundle';
/** Xcode's file type for a skills bundle. Any other type copies the folder raw: no validation and no skills. */
const FILE_TYPE = 'wrapper.skillsbundle';

export type SiriSkillsOptions = { sourceDir: string };

type Section = Record<string, any>;

function section(project: XcodeProject, isa: string): Section {
  const objects = project.hash.project.objects;
  objects[isa] = objects[isa] ?? {};
  return objects[isa];
}

const entries = (values: Section): [string, any][] => Object.entries(values).filter(([key]) => !key.endsWith('_comment'));

const unquote = (value: string) => value.replace(/^"(.*)"$/, '$1');

/** Where the bundle lives, relative to `ios/`. */
export const skillsBundlePath = (projectName: string) => `${projectName}/${BUNDLE}`;

function resourcesPhase(project: XcodeProject, target: any): any {
  const phases = section(project, 'PBXResourcesBuildPhase');
  const id = target.buildPhases.map((phase: any) => phase.value).find((value: string) => phases[value]);
  if (!id) throw new Error('expo-syrup-ai-kit: the app target has no Copy Bundle Resources phase');
  return phases[id];
}

/**
 * Adds the skills bundle at `bundlePath` (relative to `ios/`) to the app target's Copy Bundle Resources, typed as a
 * skills bundle so Xcode validates it and compiles it into `Metadata.appintents`.
 */
export function addSkillsBundle(project: XcodeProject, bundlePath: string): void {
  const [, target] = appTargetEntry(project);
  const phase = resourcesPhase(project, target);
  const references = section(project, 'PBXFileReference');
  const buildFiles = section(project, 'PBXBuildFile');
  const inPhase = new Set(phase.files.map((file: any) => file.value));

  const bundled = entries(buildFiles)
    .filter(([id]) => inPhase.has(id))
    .map(([, file]) => references[file.fileRef])
    .filter((reference) => reference?.lastKnownFileType === FILE_TYPE);
  const existing = bundled.find((reference) => unquote(reference.path) === bundlePath);
  if (existing) return;
  if (bundled.length > 0) {
    throw new Error(
      `expo-syrup-ai-kit: the app target already has a skills bundle, "${unquote(bundled[0].path)}", and can only have one`
    );
  }

  const referenceId = project.generateUuid();
  references[referenceId] = {
    isa: 'PBXFileReference',
    lastKnownFileType: FILE_TYPE,
    name: BUNDLE,
    path: `"${bundlePath}"`,
    sourceTree: 'SOURCE_ROOT',
  };
  references[`${referenceId}_comment`] = BUNDLE;

  const buildFileId = project.generateUuid();
  buildFiles[buildFileId] = { isa: 'PBXBuildFile', fileRef: referenceId, fileRef_comment: BUNDLE };
  buildFiles[`${buildFileId}_comment`] = `${BUNDLE} in Resources`;

  phase.files.push({ value: buildFileId, comment: `${BUNDLE} in Resources` });
  const mainGroup = project.getPBXGroupByKey(project.getFirstProject().firstProject.mainGroup);
  mainGroup?.children.push({ value: referenceId, comment: BUNDLE });
}

/**
 * Checks the skills in `sourceDir` and copies each `SKILL.md` into `bundleDir/Skills/<name>/`, replacing what was
 * there so a deleted skill stops shipping. Throws with every problem, and writes nothing, if any skill breaks
 * Apple's rules. `label` is `sourceDir` as the person wrote it, for the messages.
 */
export function writeSkillsBundle(sourceDir: string, label: string, bundleDir: string): void {
  const problems = skillsFolderProblems(sourceDir, label);
  if (problems.length > 0) {
    throw new Error(
      [`expo-syrup-ai-kit: the App Skills in ${label} have problems:`, ...problems.map((problem) => `- ${problem}`)].join('\n')
    );
  }
  fs.rmSync(bundleDir, { recursive: true, force: true });
  for (const skill of fs.readdirSync(sourceDir, { withFileTypes: true })) {
    if (!skill.isDirectory() || skill.name.startsWith('.')) continue;
    const target = path.join(bundleDir, 'Skills', skill.name);
    fs.mkdirSync(target, { recursive: true });
    fs.copyFileSync(path.join(sourceDir, skill.name, SKILL_FILE), path.join(target, SKILL_FILE));
  }
}

/** Writes the App Skills from `sourceDir` into `ios/<App>/Skills.skillsbundle` at prebuild. */
export const withSiriSkillsBundle: ConfigPlugin<SiriSkillsOptions> = (config, { sourceDir }) =>
  withDangerousMod(config, [
    'ios',
    (next) => {
      const { projectRoot, platformProjectRoot, projectName } = next.modRequest;
      writeSkillsBundle(
        path.resolve(projectRoot, sourceDir),
        path.normalize(sourceDir),
        path.join(platformProjectRoot, skillsBundlePath(projectName!))
      );
      return next;
    },
  ]);
