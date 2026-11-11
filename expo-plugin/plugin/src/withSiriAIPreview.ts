import type { XcodeProject } from 'expo/config-plugins';

export const PREVIEW_FLAG = 'SIRI_AI_PREVIEW';

/**
 * The tool macros exist only in the iOS 27.3 SDK, and `@Property(title:description:)` needs iOS 27.3 at
 * runtime. Only the app target is raised, so prebuilt pods keep their own deployment targets.
 */
const PREVIEW_DEPLOYMENT_TARGET = '27.3';

/** Turns on the `SIRI_AI_PREVIEW` Swift condition and iOS 27.3 for the app target. */
export function enableSiriAIPreview(project: XcodeProject): void {
  const configurations = project.pbxXCBuildConfigurationSection();
  for (const [key, entry] of Object.entries<any>(configurations)) {
    if (key.endsWith('_comment') || !entry?.buildSettings?.PRODUCT_NAME) continue;
    entry.buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = `"$(inherited) ${PREVIEW_FLAG}"`;
    entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET = PREVIEW_DEPLOYMENT_TARGET;
  }
}
