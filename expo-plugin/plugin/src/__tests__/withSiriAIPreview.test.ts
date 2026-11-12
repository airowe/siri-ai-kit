import path from 'path';
import xcode from 'xcode';
import type { XcodeProject } from 'expo/config-plugins';

import { previewEnabled, requirementFrom, siriSkillsOptionsFrom, siriToolsOptionsFrom } from '../index';
import { enableSiriAIPreview } from '../withSiriAIPreview';

const FIXTURE = path.join(__dirname, 'fixtures', 'project.pbxproj');
const PREVIEW_DEPLOYMENT_TARGET = '27.3';

function appConfigurations(project: XcodeProject): any[] {
  return Object.entries(project.pbxXCBuildConfigurationSection())
    .filter(([key, entry]: [string, any]) => !key.endsWith('_comment') && entry.buildSettings?.PRODUCT_NAME)
    .map(([, entry]) => entry);
}

const EVAL_SWITCHES = 'SIRI_AI_EVAL_SWITCHES';
const unquote = (value: string) => value.replace(/^"(.*)"$/, '$1');

/**
 * The Swift conditions a target compiles with, expanding `$(NAME)` the way Xcode does, nested references included.
 * Settings passed to xcodebuild win over the target's own; an undefined setting and `$(inherited)` expand to nothing.
 */
function conditions(buildSettings: Record<string, string>, commandLine: Record<string, string>): string[] {
  const lookup = (name: string): string => {
    if (name === 'inherited') return '';
    return commandLine[name] ?? (buildSettings[name] === undefined ? '' : expand(unquote(String(buildSettings[name]))));
  };
  const expand = (value: string): string => {
    let text = value;
    for (let reference = /\$\(([A-Za-z0-9_]*)\)/; reference.test(text); ) {
      text = text.replace(reference, (_, name: string) => lookup(name));
    }
    return text;
  };
  return lookup('SWIFT_ACTIVE_COMPILATION_CONDITIONS').split(/\s+/).filter(Boolean);
}

function projectConfigurations(project: XcodeProject): any[] {
  return Object.entries(project.pbxXCBuildConfigurationSection())
    .filter(([key, entry]: [string, any]) => !key.endsWith('_comment') && !entry.buildSettings?.PRODUCT_NAME)
    .map(([, entry]) => entry);
}

describe('enableSiriAIPreview', () => {
  it('turns on the SIRI_AI_PREVIEW condition and iOS 27.3 for the app target only', () => {
    const project = xcode.project(FIXTURE).parseSync();
    const projectTargetsBefore = projectConfigurations(project).map((entry) => entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET);
    enableSiriAIPreview(project);

    const app = appConfigurations(project);
    expect(app.length).toBeGreaterThan(0);
    for (const entry of app) {
      expect(conditions(entry.buildSettings, {})).toContain('SIRI_AI_PREVIEW');
      expect(entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET).toBe(PREVIEW_DEPLOYMENT_TARGET);
    }
    expect(projectConfigurations(project).map((entry) => entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET)).toEqual(
      projectTargetsBefore
    );
  });
});

describe('the SIRI_AI_EVAL_SWITCHES condition', () => {
  it.each([
    [{}, false],
    [{ SIRI_AI_EVAL_SWITCHES: 'YES' }, true],
    [{ SIRI_AI_EVAL_SWITCHES: 'NO' }, false],
  ])('with xcodebuild settings %j is on: %s', (commandLine, expected) => {
    const project = xcode.project(FIXTURE).parseSync();
    enableSiriAIPreview(project);

    for (const entry of appConfigurations(project)) {
      const resolved = conditions(entry.buildSettings, commandLine);
      expect(resolved.includes(EVAL_SWITCHES)).toBe(expected);
      expect(resolved).toContain('SIRI_AI_PREVIEW');
    }
  });
});

describe('previewEnabled', () => {
  it.each([
    [{}, {}, false],
    [{}, { SIRI_AI_PREVIEW: '1' }, true],
    [{}, { SIRI_AI_PREVIEW: '0' }, false],
    [{ preview: true }, {}, true],
    [{ preview: false }, { SIRI_AI_PREVIEW: '1' }, false],
  ])('props %j with env %j gives %s', (props, env, expected) => {
    expect(previewEnabled(props, env)).toBe(expected);
  });
});

describe('requirementFrom', () => {
  it.each([
    [{}, { kind: 'version', version: '0.3.1' }],
    [{ version: '0.3.1' }, { kind: 'version', version: '0.3.1' }],
    [{ branch: 'main' }, { kind: 'branch', branch: 'main' }],
  ])('props %j give %j', (props, expected) => {
    expect(requirementFrom(props)).toEqual(expected);
  });

  it('rejects a version and a branch together', () => {
    expect(() => requirementFrom({ version: '0.2.0', branch: 'main' })).toThrow(
      'expo-syrup-ai-kit: pass either `version` or `branch`, not both'
    );
  });
});

describe('siriToolsOptionsFrom', () => {
  const EXPO_NAME = 'My App';

  it.each([
    [{}, undefined],
    [{ tools: './siri-tools.json' }, { declarationPath: './siri-tools.json', appName: EXPO_NAME }],
  ])('props %j give %j', (props, expected) => {
    expect(siriToolsOptionsFrom(props, EXPO_NAME)).toEqual(expected);
  });
});

describe('siriSkillsOptionsFrom', () => {
  it.each([
    [{}, undefined],
    [{ skills: { sourceDir: 'siri-skills' } }, { sourceDir: 'siri-skills' }],
  ])('props %j give %j', (props, expected) => {
    expect(siriSkillsOptionsFrom(props)).toEqual(expected);
  });

  it.each([[{ skills: {} }], [{ skills: { sourceDir: '' } }], [{ skills: 'siri-skills' }]])('rejects %j', (props) => {
    expect(() => siriSkillsOptionsFrom(props as any)).toThrow(
      'expo-syrup-ai-kit: skills.sourceDir must name a folder of App Skills'
    );
  });
});
