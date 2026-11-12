import fs from 'fs';
import os from 'os';
import path from 'path';
import xcode from 'xcode';
import type { XcodeProject } from 'expo/config-plugins';

import { addSkillsBundle, skillsBundlePath, writeSkillsBundle } from '../withSiriSkills';

const FIXTURE = path.join(__dirname, 'fixtures', 'project.pbxproj');
const BUNDLE_PATH = 'MyApp/Skills.skillsbundle';
const SKILL = `---\nname: cart-checkout\ndescription: Guides a purchase to checkout.\n---\nSearch, add to cart, then check out.\n`;

function objects(project: XcodeProject, isa: string): [string, any][] {
  return Object.entries(project.hash.project.objects[isa] ?? {}).filter(([key]) => !key.endsWith('_comment'));
}

function appTarget(project: XcodeProject): any {
  return objects(project, 'PBXNativeTarget')
    .map(([, target]) => target)
    .find((target) => target.productType === '"com.apple.product-type.application"');
}

function resourceFileIds(project: XcodeProject): string[] {
  const phaseIds = appTarget(project).buildPhases.map((phase: any) => phase.value);
  const [, phase] = objects(project, 'PBXResourcesBuildPhase').find(([id]) => phaseIds.includes(id))!;
  return phase.files.map((file: any) => file.value);
}

function bundleReferences(project: XcodeProject): [string, any][] {
  return objects(project, 'PBXFileReference').filter(([, file]) => file.lastKnownFileType === 'wrapper.skillsbundle');
}

describe('skillsBundlePath', () => {
  it('puts the bundle in the app folder under ios/', () => {
    expect(skillsBundlePath('MyApp')).toBe(BUNDLE_PATH);
  });
});

describe('addSkillsBundle', () => {
  it('adds the bundle to the app target as a skills bundle resource', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSkillsBundle(project, BUNDLE_PATH);

    const references = bundleReferences(project);
    expect(references).toHaveLength(1);
    const [referenceId, reference] = references[0];
    expect(reference).toEqual({
      isa: 'PBXFileReference',
      lastKnownFileType: 'wrapper.skillsbundle',
      name: 'Skills.skillsbundle',
      path: `"${BUNDLE_PATH}"`,
      sourceTree: 'SOURCE_ROOT',
    });

    const [buildFileId] = objects(project, 'PBXBuildFile').find(([, file]) => file.fileRef === referenceId)!;
    expect(resourceFileIds(project)).toContain(buildFileId);
    const mainGroup = project.getPBXGroupByKey(project.getFirstProject().firstProject.mainGroup);
    expect(mainGroup!.children.map((ref: any) => ref.value)).toContain(referenceId);
  });

  it('keeps the existing resources', () => {
    const project = xcode.project(FIXTURE).parseSync();
    const before = resourceFileIds(project);
    addSkillsBundle(project, BUNDLE_PATH);
    expect(resourceFileIds(project).slice(0, before.length)).toEqual(before);
    expect(resourceFileIds(project)).toHaveLength(before.length + 1);
  });

  it('adds nothing on a second prebuild', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSkillsBundle(project, BUNDLE_PATH);
    const resources = resourceFileIds(project);
    addSkillsBundle(project, BUNDLE_PATH);
    expect(bundleReferences(project)).toHaveLength(1);
    expect(resourceFileIds(project)).toEqual(resources);
  });

  it('refuses a second skills bundle, since a target can only have one', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSkillsBundle(project, 'MyApp/Other.skillsbundle');
    expect(() => addSkillsBundle(project, BUNDLE_PATH)).toThrow(
      'expo-syrup-ai-kit: the app target already has a skills bundle, "MyApp/Other.skillsbundle", and can only have one'
    );
  });

  it('survives writing and parsing the project again', () => {
    const project = xcode.project(FIXTURE).parseSync();
    addSkillsBundle(project, BUNDLE_PATH);
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'siri-skills-pbxproj-'));
    try {
      const written = path.join(directory, 'project.pbxproj');
      fs.writeFileSync(written, project.writeSync());
      const reparsed = xcode.project(written).parseSync();
      expect(bundleReferences(reparsed).map(([, file]) => file.path)).toEqual([`"${BUNDLE_PATH}"`]);
    } finally {
      fs.rmSync(directory, { recursive: true, force: true });
    }
  });
});

describe('writeSkillsBundle', () => {
  let root: string;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'siri-skills-write-'));
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  function addSkill(name: string, text = SKILL.replace('cart-checkout', name)) {
    fs.mkdirSync(path.join(root, 'siri-skills', name), { recursive: true });
    fs.writeFileSync(path.join(root, 'siri-skills', name, 'SKILL.md'), text);
  }

  const bundle = () => path.join(root, 'ios', BUNDLE_PATH);
  const listBundle = () =>
    (fs.readdirSync(bundle(), { recursive: true }) as string[]).map((entry) => entry.split(path.sep).join('/')).sort();

  it("copies each skill's SKILL.md into Skills/ inside the bundle", () => {
    addSkill('cart-checkout');
    addSkill('order-tracking');
    writeSkillsBundle(path.join(root, 'siri-skills'), 'siri-skills', bundle());
    expect(listBundle()).toEqual([
      'Skills',
      'Skills/cart-checkout',
      'Skills/cart-checkout/SKILL.md',
      'Skills/order-tracking',
      'Skills/order-tracking/SKILL.md',
    ]);
    expect(fs.readFileSync(path.join(bundle(), 'Skills', 'cart-checkout', 'SKILL.md'), 'utf8')).toBe(SKILL);
  });

  it('removes a skill that was deleted from the source folder', () => {
    addSkill('cart-checkout');
    addSkill('order-tracking');
    writeSkillsBundle(path.join(root, 'siri-skills'), 'siri-skills', bundle());
    fs.rmSync(path.join(root, 'siri-skills', 'order-tracking'), { recursive: true });
    writeSkillsBundle(path.join(root, 'siri-skills'), 'siri-skills', bundle());
    expect(listBundle()).toEqual(['Skills', 'Skills/cart-checkout', 'Skills/cart-checkout/SKILL.md']);
  });

  it('stops prebuild with every problem, and writes nothing', () => {
    addSkill('cart-checkout', SKILL.replace('description: Guides a purchase to checkout.\n', 'version: 1\n'));
    expect(() => writeSkillsBundle(path.join(root, 'siri-skills'), 'siri-skills', bundle())).toThrow(
      [
        'expo-syrup-ai-kit: the App Skills in siri-skills have problems:',
        '- siri-skills/cart-checkout/SKILL.md: description is required',
        '- siri-skills/cart-checkout/SKILL.md: Siri only reads name and description, not "version"',
      ].join('\n')
    );
    expect(fs.existsSync(bundle())).toBe(false);
  });
});
