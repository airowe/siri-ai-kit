import { type ConfigPlugin, createRunOncePlugin } from 'expo/config-plugins';

import { type PackageRequirement, withSiriAIKitPackage } from './withSiriAIKitPackage';
import { PREVIEW_FLAG, withSiriAIPreview } from './withSiriAIPreview';

const pkg = require('../../package.json');

/** The SiriAIKit release this plugin version was tested with. */
const DEFAULT_VERSION = '0.2.0';

export type SiriAIKitPluginProps = {
  /** SiriAIKit version to use, up to the next minor. Defaults to the release this plugin was tested with. */
  version?: string;
  /** Follow a SiriAIKit branch instead of a release, for trying unreleased changes. */
  branch?: string;
  /** Turn on the Siri AI Developer Preview code. Defaults to `SIRI_AI_PREVIEW=1` in the environment. */
  preview?: boolean;
};

export function requirementFrom(props: SiriAIKitPluginProps): PackageRequirement {
  if (props.version && props.branch) {
    throw new Error('expo-siri-ai-kit: pass either `version` or `branch`, not both');
  }
  return props.branch
    ? { kind: 'branch', branch: props.branch }
    : { kind: 'version', version: props.version ?? DEFAULT_VERSION };
}

export function previewEnabled(props: SiriAIKitPluginProps, env: NodeJS.ProcessEnv): boolean {
  return props.preview ?? env[PREVIEW_FLAG] === '1';
}

const withSiriAIKit: ConfigPlugin<SiriAIKitPluginProps | void> = (config, props) => {
  const options = props ?? {};
  config = withSiriAIKitPackage(config, requirementFrom(options));
  if (previewEnabled(options, process.env)) {
    config = withSiriAIPreview(config);
  }
  return config;
};

export default createRunOncePlugin(withSiriAIKit, pkg.name, pkg.version);
