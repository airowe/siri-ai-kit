import type { XcodeProject } from 'expo/config-plugins';

export const PREVIEW_FLAG = 'SIRI_AI_PREVIEW';

/**
 * The tool macros exist only in the iOS 27.3 SDK, and `@Property(title:description:)` needs iOS 27.3 at
 * runtime. Only the app target is raised, so prebuilt pods keep their own deployment targets.
 */
const PREVIEW_DEPLOYMENT_TARGET = '27.3';

/**
 * Evaluations of an Expo app run a Release build, where `#if DEBUG` code is compiled out. Passing
 * `SIRI_AI_EVAL_SWITCHES=YES` to `xcodebuild` adds this condition, so `#if DEBUG || SIRI_AI_EVAL_SWITCHES` code reads
 * `EvalSwitch` in that build only. No other build, including an App Store archive, compiles it.
 */
export const EVAL_SWITCHES_FLAG = 'SIRI_AI_EVAL_SWITCHES';

/** Expands to the condition when `SIRI_AI_EVAL_SWITCHES` is `YES`, and to nothing when it is unset or anything else. */
const EVAL_SWITCHES_CONDITION = `$(${EVAL_SWITCHES_FLAG}_CONDITION_$(${EVAL_SWITCHES_FLAG}))`;

/**
 * Turns on the `SIRI_AI_PREVIEW` Swift condition and iOS 27.3 for the app target, and lets an evaluation build add
 * `SIRI_AI_EVAL_SWITCHES`.
 */
export function enableSiriAIPreview(project: XcodeProject): void {
  const configurations = project.pbxXCBuildConfigurationSection();
  for (const [key, entry] of Object.entries<any>(configurations)) {
    if (key.endsWith('_comment') || !entry?.buildSettings?.PRODUCT_NAME) continue;
    entry.buildSettings.SWIFT_ACTIVE_COMPILATION_CONDITIONS = `"$(inherited) ${PREVIEW_FLAG} ${EVAL_SWITCHES_CONDITION}"`;
    entry.buildSettings[`${EVAL_SWITCHES_FLAG}_CONDITION_YES`] = EVAL_SWITCHES_FLAG;
    entry.buildSettings.IPHONEOS_DEPLOYMENT_TARGET = PREVIEW_DEPLOYMENT_TARGET;
  }
}
