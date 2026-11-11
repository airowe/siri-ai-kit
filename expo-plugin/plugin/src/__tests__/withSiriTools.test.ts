import fs from 'fs';
import os from 'os';
import path from 'path';
import xcode from 'xcode';
import type { XcodeProject } from 'expo/config-plugins';

import { SUPPORT_FILE } from '../siriTools/swift';
import { addSiriToolsGroup, siriToolFilesFrom, writeSiriToolFiles } from '../withSiriTools';

const FIXTURE = path.join(__dirname, 'fixtures', 'project.pbxproj');
const SAMPLE = path.join(__dirname, 'fixtures', 'siri-tools', 'siri-tools.json');
const GROUP_PATH = 'MyApp/SiriTools';
const SYNCHRONIZED_GROUP = 'PBXFileSystemSynchronizedRootGroup';

function objects(project: XcodeProject, isa: string): [string, any][] {
  return Object.entries(project.hash.project.objects[isa] ?? {}).filter(([key]) => !key.endsWith('_comment'));
}

function appTarget(project: XcodeProject): any {
  return objects(project, 'PBXNativeTarget')
    .map(([, target]) => target)
    .find((target) => target.productType === '"com.apple.product-type.application"');
}

describe('addSiriToolsGroup', () => {
  it('compiles the folder into the app target as a synchronized group', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSiriToolsGroup(project, GROUP_PATH);

    const groups = objects(project, SYNCHRONIZED_GROUP);
    expect(groups).toHaveLength(1);
    const [id, group] = groups[0];
    expect(group).toEqual({
      isa: SYNCHRONIZED_GROUP,
      explicitFileTypes: {},
      explicitFolders: [],
      name: 'SiriTools',
      path: `"${GROUP_PATH}"`,
      sourceTree: 'SOURCE_ROOT',
    });
    expect(appTarget(project).fileSystemSynchronizedGroups.map((ref: any) => ref.value)).toEqual([id]);
    const mainGroup = project.getPBXGroupByKey(project.getFirstProject().firstProject.mainGroup);
    expect(mainGroup!.children.map((ref: any) => ref.value)).toContain(id);
  });

  it('survives writing and parsing the project again', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSiriToolsGroup(project, GROUP_PATH);
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'siri-tools-pbxproj-'));
    try {
      const written = path.join(directory, 'project.pbxproj');
      fs.writeFileSync(written, project.writeSync());
      const reparsed = xcode.project(written).parseSync();
      expect(objects(reparsed, SYNCHRONIZED_GROUP).map(([, group]) => group.path)).toEqual([`"${GROUP_PATH}"`]);
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });

  it('adds nothing on a second prebuild', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSiriToolsGroup(project, GROUP_PATH);
    addSiriToolsGroup(project, GROUP_PATH);
    expect(objects(project, SYNCHRONIZED_GROUP)).toHaveLength(1);
    expect(appTarget(project).fileSystemSynchronizedGroups).toHaveLength(1);
  });
});

describe('writeSiriToolFiles', () => {
  let directory: string;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), 'siri-tools-'));
  });

  afterEach(() => {
    fs.rmSync(directory, { recursive: true, force: true });
  });

  it('writes each file and removes tools that are no longer declared', () => {
    const target = path.join(directory, 'SiriTools');
    writeSiriToolFiles(target, [
      { fileName: 'OldIntent.swift', contents: 'old' },
      { fileName: SUPPORT_FILE, contents: 'support' },
    ]);
    writeSiriToolFiles(target, [
      { fileName: SUPPORT_FILE, contents: 'support v2' },
      { fileName: 'NewIntent.swift', contents: 'new' },
    ]);

    expect(fs.readdirSync(target).sort()).toEqual(['NewIntent.swift', SUPPORT_FILE]);
    expect(fs.readFileSync(path.join(target, SUPPORT_FILE), 'utf8')).toBe('support v2');
  });
});

describe('siriToolFilesFrom', () => {
  const APP_NAME_IN_SAMPLE = 'Siri Spike';
  const FALLBACK_APP_NAME = 'Expo Name';
  let directory: string;

  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), 'siri-tools-project-'));
  });

  afterEach(() => {
    fs.rmSync(directory, { recursive: true, force: true });
  });

  it('reads the declaration relative to the project and uses its app name', () => {
    fs.copyFileSync(SAMPLE, path.join(directory, 'siri-tools.json'));
    const files = siriToolFilesFrom(directory, './siri-tools.json', FALLBACK_APP_NAME);
    expect(files.map((file) => file.fileName)).toHaveLength(4);
    expect(files[0].contents).toContain(`SiriTool(appName: "${APP_NAME_IN_SAMPLE}")`);
  });

  it("falls back to the Expo app's name", () => {
    const declaration = JSON.parse(fs.readFileSync(SAMPLE, 'utf8'));
    delete declaration.appName;
    fs.writeFileSync(path.join(directory, 'tools.json'), JSON.stringify(declaration));
    const files = siriToolFilesFrom(directory, 'tools.json', FALLBACK_APP_NAME);
    expect(files[0].contents).toContain(`SiriTool(appName: "${FALLBACK_APP_NAME}")`);
  });

  it('says which file is missing', () => {
    expect(() => siriToolFilesFrom(directory, 'missing.json', FALLBACK_APP_NAME)).toThrow(
      `expo-siri-ai-kit: can't read the Siri tools declaration at ${path.join(directory, 'missing.json')}`
    );
  });

  it('says which file is not JSON', () => {
    fs.writeFileSync(path.join(directory, 'bad.json'), '{ tools: ');
    expect(() => siriToolFilesFrom(directory, 'bad.json', FALLBACK_APP_NAME)).toThrow(
      /^expo-siri-ai-kit: bad\.json is not valid JSON/
    );
  });

  it('reports declaration problems with the file name', () => {
    fs.writeFileSync(path.join(directory, 'empty.json'), '{"tools": []}');
    expect(() => siriToolFilesFrom(directory, 'empty.json', FALLBACK_APP_NAME)).toThrow(
      'expo-siri-ai-kit: empty.json has problems:\n  - tools: must be a non-empty array'
    );
  });
});
