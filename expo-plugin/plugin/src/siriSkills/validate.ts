import fs from 'fs';
import path from 'path';

/** Apple's limits for an App Skill's `SKILL.md`. */
export const MAX_NAME = 64;
export const MAX_DESCRIPTION = 1024;
export const MAX_BODY = 10_000;

export const SKILL_FILE = 'SKILL.md';

const NAME = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const FIELDS = ['name', 'description'];
const FENCE = '---';

type Frontmatter = { fields: Map<string, string>; continued: Set<string>; body: string };

const unquote = (value: string) => value.replace(/^(["'])(.*)\1$/, '$2');

function splitFrontmatter(text: string): Frontmatter | 'missing' | 'unclosed' {
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  if (lines[0]?.trim() !== FENCE) return 'missing';
  const close = lines.indexOf(FENCE, 1);
  if (close === -1) return 'unclosed';

  const fields = new Map<string, string>();
  const continued = new Set<string>();
  let current: string | undefined;
  for (const line of lines.slice(1, close)) {
    const field = /^([A-Za-z_][\w-]*):\s*(.*)$/.exec(line);
    if (field) {
      const [, key = '', value = ''] = field;
      current = key;
      fields.set(key, unquote(value.trim()));
    } else if (current && line.trim() !== '') {
      continued.add(current);
    }
  }
  return { fields, continued, body: lines.slice(close + 1).join('\n') };
}

/** Problems in one skill's `SKILL.md`, checked against Apple's rules. `folder` is the skill's folder name. */
export function skillFileProblems(folder: string, text: string): string[] {
  const at = `${folder}/${SKILL_FILE}`;
  const parsed = splitFrontmatter(text);
  if (parsed === 'missing') return [`${at}: must start with ${FENCE} frontmatter`];
  if (parsed === 'unclosed') return [`${at}: the frontmatter has no closing ${FENCE}`];

  const { fields, continued, body } = parsed;
  const name = fields.get('name');
  const description = fields.get('description');
  const problems: string[] = [];

  if (!name) problems.push(`${at}: name is required`);
  if (continued.has('description') || description === '>' || description === '|') {
    problems.push(`${at}: description must be one line`);
  } else if (!description) {
    problems.push(`${at}: description is required`);
  } else if (description.length > MAX_DESCRIPTION) {
    problems.push(`${at}: description is ${description.length} characters; the limit is ${MAX_DESCRIPTION}`);
  }
  if (name && (name.length > MAX_NAME || !NAME.test(name))) {
    problems.push(
      `${at}: name must be 1 to ${MAX_NAME} lowercase letters, digits and single hyphens, not starting or ending with a hyphen`
    );
  } else if (name && name !== folder) {
    problems.push(`${at}: name "${name}" must match its folder, "${folder}"`);
  }
  for (const field of fields.keys()) {
    if (!FIELDS.includes(field)) problems.push(`${at}: Siri only reads name and description, not "${field}"`);
  }
  if (body.length > MAX_BODY) problems.push(`${at}: the body is ${body.length} characters; the limit is ${MAX_BODY}`);
  return problems;
}

const visible = (directory: string) =>
  fs
    .readdirSync(directory, { withFileTypes: true })
    .filter((entry) => !entry.name.startsWith('.'))
    .sort((a, b) => a.name.localeCompare(b.name));

/**
 * Problems in a folder of skills: one folder per skill, each holding only a `SKILL.md`. `label` is the folder as
 * the person wrote it, used in the messages. Xcode ignores extra files and only warns about unsupported fields,
 * so both are reported here.
 */
export function skillsFolderProblems(directory: string, label: string): string[] {
  if (!fs.existsSync(directory)) return [`skills: ${label} does not exist`];
  if (!fs.statSync(directory).isDirectory()) return [`skills: ${label} is not a folder`];

  const entries = visible(directory);
  const problems = entries
    .filter((entry) => !entry.isDirectory())
    .map((entry) => `${label}/${entry.name}: only skill folders go here, each with a ${SKILL_FILE}`);
  const skills = entries.filter((entry) => entry.isDirectory());
  if (skills.length === 0) return [...problems, `skills: ${label} has no skill folders`];

  for (const skill of skills) {
    const folder = path.join(directory, skill.name);
    const contents = visible(folder);
    if (!contents.some((entry) => entry.name === SKILL_FILE && entry.isFile())) {
      problems.push(`${label}/${skill.name}: has no ${SKILL_FILE}`);
      continue;
    }
    for (const extra of contents.filter((entry) => entry.name !== SKILL_FILE)) {
      problems.push(`${label}/${skill.name}/${extra.name}: Siri only reads ${SKILL_FILE}; remove other files`);
    }
    const text = fs.readFileSync(path.join(folder, SKILL_FILE), 'utf8');
    problems.push(...skillFileProblems(skill.name, text).map((problem) => `${label}/${problem}`));
  }
  return problems;
}
