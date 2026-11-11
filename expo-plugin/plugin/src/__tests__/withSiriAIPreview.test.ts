import path from 'path';
import xcode from 'xcode';
import type { XcodeProject } from 'expo/config-plugins';

import { previewEnabled, requirementFrom, siriToolsOptionsFrom } from '../index';
import { enableSiriAIPreview } from '../withSiriAIPreview';

const FIXTURE = path.join(__dirname, 'fixtures', 'project.pbxproj');
const PREVIEW_DEPLOYMENT_TARGET = '27.3';

function appConfigurations(project: XcodeProject): any[] {
  return Object.entries(project.pbxXCBuildConfigurationSection())
    .filter(([key, entry]: [string, any]) => !key.endsWith('_comment') && entry.buildSettings?.PRODUCT_NAME)
    .map(([, entry]) => entry);
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
      expect(entry.buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS).toBe('"$(inherited) SIRI_AI_PREVIEW"');
      expect(entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET).toBe(PREVIEW_DEPLOYMENT_TARGET);
    }
    expect(projectConfigurations(project).map((entry) => entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET)).toEqual(
      projectTargetsBefore
    );
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
    [{}, { kind: 'version', version: '0.2.0' }],
    [{ version: '0.3.1' }, { kind: 'version', version: '0.3.1' }],
    [{ branch: 'main' }, { kind: 'branch', branch: 'main' }],
  ])('props %j give %j', (props, expected) => {
    expect(requirementFrom(props)).toEqual(expected);
  });

  it('rejects a version and a branch together', () => {
    expect(() => requirementFrom({ version: '0.2.0', branch: 'main' })).toThrow(
      'expo-siri-ai-kit: pass either `version` or `branch`, not both'
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
