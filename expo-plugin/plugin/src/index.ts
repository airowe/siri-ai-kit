import { type ConfigPlugin, createRunOncePlugin, withXcodeProject } from 'expo/config-plugins';

import { type EvalsOptions, addSiriAIEvals } from './withSiriAIEvals';
import { type PackageRequirement, addSyrupAIKitPackage } from './withSyrupAIKitPackage';
import { PREVIEW_FLAG, enableSiriAIPreview } from './withSiriAIPreview';
import { type SiriSkillsOptions, addSkillsBundle, skillsBundlePath, withSiriSkillsBundle } from './withSiriSkills';
import { type SiriToolsOptions, addSiriToolsGroup, siriToolsFolder, withSiriToolFiles } from './withSiriTools';

const pkg = require('../../package.json');

/** The SyrupAIKit release this plugin version was tested with. */
const DEFAULT_VERSION = '0.4.0';

export type SyrupAIKitPluginProps = {
  /** SyrupAIKit version to use, up to the next minor. Defaults to the release this plugin was tested with. */
  version?: string;
  /** Follow a SyrupAIKit branch instead of a release, for trying unreleased changes. */
  branch?: string;
  /** Turn on the Siri AI Developer Preview code. Defaults to `SIRI_AI_PREVIEW=1` in the environment. */
  preview?: boolean;
  /** Add a UI test target for Siri Evaluations, built from Swift files kept outside `ios/`. */
  evals?: EvalsOptions;
  /** Path to a Siri tools declaration, relative to the project root. Generates a Swift tool for each entry. */
  tools?: string;
  /** Apple App Skills: a folder, relative to the project root, with one folder per skill holding its `SKILL.md`. */
  skills?: SiriSkillsOptions;
};

export function requirementFrom(props: SyrupAIKitPluginProps): PackageRequirement {
  if (props.version && props.branch) {
    throw new Error('expo-syrup-ai-kit: pass either `version` or `branch`, not both');
  }
  return props.branch
    ? { kind: 'branch', branch: props.branch }
    : { kind: 'version', version: props.version ?? DEFAULT_VERSION };
}

export function previewEnabled(props: SyrupAIKitPluginProps, env: NodeJS.ProcessEnv): boolean {
  return props.preview ?? env[PREVIEW_FLAG] === '1';
}

export function siriToolsOptionsFrom(props: SyrupAIKitPluginProps, expoName: string): SiriToolsOptions | undefined {
  return props.tools ? { declarationPath: props.tools, appName: expoName } : undefined;
}

export function siriSkillsOptionsFrom(props: SyrupAIKitPluginProps): SiriSkillsOptions | undefined {
  if (props.skills === undefined) return undefined;
  const { sourceDir } = (props.skills ?? {}) as Partial<SiriSkillsOptions>;
  if (typeof sourceDir !== 'string' || sourceDir.length === 0) {
    throw new Error('expo-syrup-ai-kit: skills.sourceDir must name a folder of App Skills');
  }
  return { sourceDir };
}

/**
 * One Xcode project mod, so the steps run in this order: the evals target links a product from the package
 * reference, and the preview settings then cover the evals target as well as the app.
 */
const withSyrupAIKit: ConfigPlugin<SyrupAIKitPluginProps | void> = (config, props) => {
  const options = props ?? {};
  const requirement = requirementFrom(options);
  const preview = previewEnabled(options, process.env);
  const tools = siriToolsOptionsFrom(options, config.name);
  const skills = siriSkillsOptionsFrom(options);
  if (tools) config = withSiriToolFiles(config, tools);
  if (skills) config = withSiriSkillsBundle(config, skills);
  return withXcodeProject(config, (next) => {
    addSyrupAIKitPackage(next.modResults, requirement);
    if (tools) addSiriToolsGroup(next.modResults, siriToolsFolder(next.modRequest.projectName!));
    if (skills) addSkillsBundle(next.modResults, skillsBundlePath(next.modRequest.projectName!));
    if (options.evals) addSiriAIEvals(next.modResults, options.evals, next.modRequest);
    if (preview) enableSiriAIPreview(next.modResults);
    return next;
  });
};

export default createRunOncePlugin(withSyrupAIKit, pkg.name, pkg.version);
