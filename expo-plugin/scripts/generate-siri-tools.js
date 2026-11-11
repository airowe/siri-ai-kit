#!/usr/bin/env node
// Writes the Swift the plugin would generate at prebuild, without an Expo project. Run `npm run build` first.
// Usage: node expo-plugin/scripts/generate-siri-tools.js <declaration.json> <output dir> [app name]
// With no arguments, refreshes the approved sample in plugin/src/__tests__/fixtures/siri-tools.
const fs = require('fs');
const path = require('path');

const { parseSiriTools } = require('../plugin/build/siriTools/declaration');
const { siriToolFiles } = require('../plugin/build/siriTools/swift');

const SAMPLE_DIR = path.join(__dirname, '..', 'plugin', 'src', '__tests__', 'fixtures', 'siri-tools');
const SAMPLE_APP_NAME = 'Siri Spike';

const [declarationPath = path.join(SAMPLE_DIR, 'siri-tools.json'), outputDir = SAMPLE_DIR, appName = SAMPLE_APP_NAME] =
  process.argv.slice(2);

const declaration = parseSiriTools(JSON.parse(fs.readFileSync(declarationPath, 'utf8')), path.basename(declarationPath));
fs.mkdirSync(outputDir, { recursive: true });
for (const file of siriToolFiles(declaration, declaration.appName ?? appName)) {
  fs.writeFileSync(path.join(outputDir, file.fileName), file.contents);
  console.log(path.join(outputDir, file.fileName));
}
