import fs from 'fs';
import os from 'os';
import path from 'path';

import { MAX_BODY, MAX_DESCRIPTION, MAX_NAME, skillFileProblems, skillsFolderProblems } from '../siriSkills/validate';

const NAME = 'cart-checkout';
const DESCRIPTION = 'Guides a purchase from search to checkout in ShopApp.';
const BODY = 'Search first, then add the item to the cart, then confirm the total before checking out.\n';

function skillText({
  frontmatter = `name: ${NAME}\ndescription: ${DESCRIPTION}`,
  body = BODY,
}: { frontmatter?: string; body?: string } = {}): string {
  return `---\n${frontmatter}\n---\n${body}`;
}

describe('skillFileProblems', () => {
  it('accepts a valid skill', () => {
    expect(skillFileProblems(NAME, skillText())).toEqual([]);
  });

  it.each<[string, string, string]>([
    ['a quoted description', `name: ${NAME}\ndescription: "${DESCRIPTION}"`, NAME],
    ['a quoted name', `name: '${NAME}'\ndescription: ${DESCRIPTION}`, NAME],
    ['a one-character name', `name: a\ndescription: ${DESCRIPTION}`, 'a'],
    ['digits in the name', `name: step-2\ndescription: ${DESCRIPTION}`, 'step-2'],
  ])('accepts %s', (_label, frontmatter, folder) => {
    expect(skillFileProblems(folder, skillText({ frontmatter }))).toEqual([]);
  });

  it('accepts the longest allowed name, description and body', () => {
    const name = 'a'.repeat(MAX_NAME);
    const frontmatter = `name: ${name}\ndescription: ${'d'.repeat(MAX_DESCRIPTION)}`;
    expect(skillFileProblems(name, skillText({ frontmatter, body: 'b'.repeat(MAX_BODY) }))).toEqual([]);
  });

  it.each<[string, string, string[]]>([
    ['no frontmatter', BODY, [`${NAME}/SKILL.md: must start with --- frontmatter`]],
    ['unclosed frontmatter', `---\nname: ${NAME}\n${BODY}`, [`${NAME}/SKILL.md: the frontmatter has no closing ---`]],
  ])('reports %s', (_label, text, problems) => {
    expect(skillFileProblems(NAME, text)).toEqual(problems);
  });

  it.each<[string, string, string[]]>([
    ['a missing name', `description: ${DESCRIPTION}`, [`${NAME}/SKILL.md: name is required`]],
    ['a missing description', `name: ${NAME}`, [`${NAME}/SKILL.md: description is required`]],
    ['an empty description', `name: ${NAME}\ndescription:`, [`${NAME}/SKILL.md: description is required`]],
    [
      'a name that differs from the folder',
      `name: checkout\ndescription: ${DESCRIPTION}`,
      [`${NAME}/SKILL.md: name "checkout" must match its folder, "${NAME}"`],
    ],
    [
      'an unsupported field',
      `name: ${NAME}\ndescription: ${DESCRIPTION}\nversion: 1`,
      [`${NAME}/SKILL.md: Siri only reads name and description, not "version"`],
    ],
    [
      'a multi-line description',
      `name: ${NAME}\ndescription: >\n  Guides a purchase\n  to checkout.`,
      [`${NAME}/SKILL.md: description must be one line`],
    ],
    [
      'a description over the limit',
      `name: ${NAME}\ndescription: ${'d'.repeat(MAX_DESCRIPTION + 1)}`,
      [`${NAME}/SKILL.md: description is ${MAX_DESCRIPTION + 1} characters; the limit is ${MAX_DESCRIPTION}`],
    ],
  ])('reports %s', (_label, frontmatter, problems) => {
    expect(skillFileProblems(NAME, skillText({ frontmatter }))).toEqual(problems);
  });

  it.each([
    ['Cart-Checkout'],
    ['cart_checkout'],
    ['-cart'],
    ['cart-'],
    ['cart--checkout'],
    ['a'.repeat(MAX_NAME + 1)],
  ])('reports the name %j', (name) => {
    const frontmatter = `name: ${name}\ndescription: ${DESCRIPTION}`;
    expect(skillFileProblems(name, skillText({ frontmatter }))).toEqual([
      `${name}/SKILL.md: name must be 1 to ${MAX_NAME} lowercase letters, digits and single hyphens, not starting or ending with a hyphen`,
    ]);
  });

  it('reports a body over the limit', () => {
    expect(skillFileProblems(NAME, skillText({ body: 'b'.repeat(MAX_BODY + 1) }))).toEqual([
      `${NAME}/SKILL.md: the body is ${MAX_BODY + 1} characters; the limit is ${MAX_BODY}`,
    ]);
  });

  it('reports every problem at once', () => {
    const frontmatter = `name: checkout\nversion: 1`;
    expect(skillFileProblems(NAME, skillText({ frontmatter }))).toEqual([
      `${NAME}/SKILL.md: description is required`,
      `${NAME}/SKILL.md: name "checkout" must match its folder, "${NAME}"`,
      `${NAME}/SKILL.md: Siri only reads name and description, not "version"`,
    ]);
  });
});

describe('skillsFolderProblems', () => {
  let root: string;

  beforeEach(() => {
    root = fs.mkdtempSync(path.join(os.tmpdir(), 'siri-skills-'));
  });

  afterEach(() => {
    fs.rmSync(root, { recursive: true, force: true });
  });

  function addSkill(name: string, text = skillText({ frontmatter: `name: ${name}\ndescription: ${DESCRIPTION}` })) {
    fs.mkdirSync(path.join(root, name), { recursive: true });
    fs.writeFileSync(path.join(root, name, 'SKILL.md'), text);
  }

  it('accepts a folder of valid skills, ignoring hidden files', () => {
    addSkill('cart-checkout');
    addSkill('order-tracking');
    fs.writeFileSync(path.join(root, '.DS_Store'), '');
    expect(skillsFolderProblems(root, 'siri-skills')).toEqual([]);
  });

  it('reports a missing folder', () => {
    const missing = path.join(root, 'nope');
    expect(skillsFolderProblems(missing, 'nope')).toEqual(['skills: nope does not exist']);
  });

  it('reports a file where the folder should be', () => {
    const file = path.join(root, 'file');
    fs.writeFileSync(file, '');
    expect(skillsFolderProblems(file, 'file')).toEqual(['skills: file is not a folder']);
  });

  it('reports a folder with no skills', () => {
    expect(skillsFolderProblems(root, 'siri-skills')).toEqual(['skills: siri-skills has no skill folders']);
  });

  it('reports a loose file next to the skill folders', () => {
    addSkill(NAME);
    fs.writeFileSync(path.join(root, 'notes.md'), '');
    expect(skillsFolderProblems(root, 'siri-skills')).toEqual([
      'siri-skills/notes.md: only skill folders go here, each with a SKILL.md',
    ]);
  });

  it('reports a skill folder without a SKILL.md', () => {
    fs.mkdirSync(path.join(root, NAME));
    expect(skillsFolderProblems(root, 'siri-skills')).toEqual([`siri-skills/${NAME}: has no SKILL.md`]);
  });

  it('reports supporting files, which Siri never reads', () => {
    addSkill(NAME);
    fs.mkdirSync(path.join(root, NAME, 'references'));
    fs.writeFileSync(path.join(root, NAME, 'references', 'a.md'), '');
    fs.writeFileSync(path.join(root, NAME, 'notes.txt'), '');
    expect(skillsFolderProblems(root, 'siri-skills')).toEqual([
      `siri-skills/${NAME}/notes.txt: Siri only reads SKILL.md; remove other files`,
      `siri-skills/${NAME}/references: Siri only reads SKILL.md; remove other files`,
    ]);
  });

  it('reports problems inside each SKILL.md', () => {
    addSkill(NAME, skillText({ frontmatter: `name: ${NAME}` }));
    expect(skillsFolderProblems(root, 'siri-skills')).toEqual([`siri-skills/${NAME}/SKILL.md: description is required`]);
  });
});
