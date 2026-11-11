import fs from 'fs';
import path from 'path';
import { type ConfigPlugin, type XcodeProject, withDangerousMod, withXcodeProject } from 'expo/config-plugins';

import { parseSiriTools } from './siriTools/declaration';
import { type GeneratedFile, siriToolFiles } from './siriTools/swift';
import { appTarget } from './withSiriAIKitPackage';

const FOLDER = 'SiriTools';
const SYNCHRONIZED_GROUP = 'PBXFileSystemSynchronizedRootGroup';

export type SiriToolsOptions = { declarationPath: string; appName: string };

type Section = Record<string, any>;

function section(project: XcodeProject, isa: string): Section {
  const objects = project.hash.project.objects;
  objects[isa] = objects[isa] ?? {};
  return objects[isa];
}

/**
 * Compiles `groupPath` (relative to `ios/`) into the app target as a synchronized folder, the way Expo adds
 * inline modules, so every Swift file the plugin writes there builds without listing each one in the project.
 */
export function addSiriToolsGroup(project: XcodeProject, groupPath: string): void {
  const groups = section(project, SYNCHRONIZED_GROUP);
  const quoted = `"${groupPath}"`;
  if (Object.values(groups).some((group) => group?.path === quoted)) return;

  const id = project.generateUuid();
  groups[id] = {
    isa: SYNCHRONIZED_GROUP,
    explicitFileTypes: {},
    explicitFolders: [],
    name: FOLDER,
    path: quoted,
    sourceTree: 'SOURCE_ROOT',
  };
  groups[`${id}_comment`] = FOLDER;

  const target = appTarget(project);
  target.fileSystemSynchronizedGroups = [...(target.fileSystemSynchronizedGroups ?? []), { value: id, comment: FOLDER }];
  const mainGroup = project.getPBXGroupByKey(project.getFirstProject().firstProject.mainGroup);
  mainGroup?.children.push({ value: id, comment: FOLDER });
}

/** Replaces the folder's Swift files with `files`, so a tool removed from the declaration stops compiling. */
export function writeSiriToolFiles(directory: string, files: GeneratedFile[]): void {
  fs.mkdirSync(directory, { recursive: true });
  for (const name of fs.readdirSync(directory)) {
    if (name.endsWith('.swift')) fs.rmSync(path.join(directory, name));
  }
  for (const file of files) fs.writeFileSync(path.join(directory, file.fileName), file.contents);
}

function readJson(file: string, declarationPath: string): unknown {
  let text: string;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    throw new Error(`expo-siri-ai-kit: can't read the Siri tools declaration at ${file}`);
  }
  try {
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`expo-siri-ai-kit: ${declarationPath} is not valid JSON: ${(error as Error).message}`);
  }
}

/** The generated Swift for the declaration at `declarationPath`, relative to the project root. */
export function siriToolFilesFrom(projectRoot: string, declarationPath: string, fallbackAppName: string): GeneratedFile[] {
  const source = path.normalize(declarationPath);
  const declaration = parseSiriTools(readJson(path.resolve(projectRoot, declarationPath), source), source);
  return siriToolFiles(declaration, declaration.appName ?? fallbackAppName);
}

/** Generates a Swift tool per declared tool into `ios/<App>/SiriTools` and compiles that folder into the app. */
export const withSiriTools: ConfigPlugin<SiriToolsOptions> = (config, { declarationPath, appName }) => {
  config = withDangerousMod(config, [
    'ios',
    (next) => {
      const { projectRoot, platformProjectRoot, projectName } = next.modRequest;
      const files = siriToolFilesFrom(projectRoot, declarationPath, appName);
      writeSiriToolFiles(path.join(platformProjectRoot, projectName!, FOLDER), files);
      return next;
    },
  ]);
  return withXcodeProject(config, (next) => {
    addSiriToolsGroup(next.modResults, `${next.modRequest.projectName}/${FOLDER}`);
    return next;
  });
};
