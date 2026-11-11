export const SCALAR_TYPES = ['string', 'int', 'double', 'bool', 'date'] as const;
export type ScalarType = (typeof SCALAR_TYPES)[number];
const PARAMETER_TYPES = [...SCALAR_TYPES, 'enum'] as const;

const METHODS = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'] as const;
export type HttpMethod = (typeof METHODS)[number];

export type ToolParameter =
  | { name: string; type: ScalarType; title: string }
  | { name: string; type: 'enum'; title: string; cases: Record<string, string> };

export type ToolRequest = { method: HttpMethod; url: string; body: string[] };

export type ToolDeclaration = {
  name: string;
  title: string;
  description: string;
  parameters: ToolParameter[];
  request: ToolRequest;
  reply: string;
};

export type SiriToolsDeclaration = { appName?: string; tools: ToolDeclaration[] };

const TYPE_NAME = /^[A-Z][A-Za-z0-9]*$/;
const PROPERTY_NAME = /^[a-z][A-Za-z0-9]*$/;
const FIELD_PATH = /^[A-Za-z0-9_]+(\.[A-Za-z0-9_]+)*$/;
const URL_PLACEHOLDER = /\{([^{}]*)\}/g;

/** Keywords that can't be a bare property or case name, plus names the generated intent already uses. */
const RESERVED = new Set(
  (
    'associatedtype class deinit enum extension fileprivate func import init inout internal let open operator ' +
    'private precedencegroup protocol public rethrows static struct subscript typealias var break case catch ' +
    'continue default defer do else fallthrough for guard if in repeat return throw switch where while as Any ' +
    'await false is nil self Self super throws true try title description perform'
  ).split(' ')
);

const TOOL_FIELDS = ['name', 'title', 'description', 'parameters', 'request', 'reply'];
const PARAMETER_FIELDS = ['name', 'type', 'title', 'cases'];
const REQUEST_FIELDS = ['method', 'url', 'body'];

type Json = Record<string, unknown>;

const isObject = (value: unknown): value is Json => typeof value === 'object' && value !== null && !Array.isArray(value);
const isText = (value: unknown): value is string => typeof value === 'string' && value.trim() !== '';

function textProblem(value: unknown, path: string): string[] {
  return isText(value) ? [] : [`${path}: must be a non-empty string`];
}

function unknownFields(value: Json, allowed: string[], path: string): string[] {
  return Object.keys(value)
    .filter((key) => !allowed.includes(key))
    .map((key) => `${path}: unknown field "${key}"`);
}

function duplicates(names: unknown[], path: (index: number) => string): string[] {
  return names.flatMap((name, index) =>
    typeof name === 'string' && names.indexOf(name) !== index ? [`${path(index)}: "${name}" is declared twice`] : []
  );
}

function identifierProblems(name: unknown, pattern: RegExp, path: string, example: string): string[] {
  if (typeof name !== 'string' || !pattern.test(name)) return [`${path}: must be a ${example}`];
  return RESERVED.has(name) ? [`${path}: "${name}" is a Swift keyword`] : [];
}

function casesProblems(parameter: Json, path: string): string[] {
  const { cases } = parameter;
  if (parameter.type !== 'enum') return cases === undefined ? [] : [`${path}.cases: only enum parameters have cases`];
  if (!isObject(cases) || Object.keys(cases).length === 0 || !Object.values(cases).every(isText)) {
    return [`${path}.cases: must map case names to titles, like {"economy": "Economy"}`];
  }
  return Object.keys(cases).flatMap((name) =>
    PROPERTY_NAME.test(name) && !RESERVED.has(name)
      ? []
      : [`${path}.cases: "${name}" must be a Swift case name like firstClass`]
  );
}

function parameterProblems(parameter: unknown, path: string): string[] {
  if (!isObject(parameter)) return [`${path}: must be an object`];
  return [
    ...unknownFields(parameter, PARAMETER_FIELDS, path),
    ...identifierProblems(parameter.name, PROPERTY_NAME, `${path}.name`, 'Swift property name like orderNumber'),
    ...((PARAMETER_TYPES as readonly unknown[]).includes(parameter.type)
      ? []
      : [`${path}.type: must be one of ${PARAMETER_TYPES.join(', ')}`]),
    ...textProblem(parameter.title, `${path}.title`),
    ...casesProblems(parameter, path),
  ];
}

export function urlPlaceholders(url: string): string[] {
  return [...url.matchAll(URL_PLACEHOLDER)].flatMap(([, name]) => (name === undefined ? [] : [name]));
}

function requestProblems(request: unknown, parameterNames: string[], path: string): string[] {
  if (!isObject(request)) return [`${path}: must be an object`];
  const problems = unknownFields(request, REQUEST_FIELDS, path);
  if (!(METHODS as readonly unknown[]).includes(request.method)) {
    problems.push(`${path}.method: must be one of ${METHODS.join(', ')}`);
  }
  if (typeof request.url !== 'string' || !request.url.startsWith('https://')) {
    problems.push(`${path}.url: must start with https://`);
  } else {
    for (const name of urlPlaceholders(request.url)) {
      if (!parameterNames.includes(name)) problems.push(`${path}.url: {${name}} is not a parameter`);
    }
  }
  const { body } = request;
  if (body !== undefined) {
    if (!Array.isArray(body) || !body.every((name) => typeof name === 'string')) {
      problems.push(`${path}.body: must be an array of parameter names`);
    } else if (request.method === 'GET') {
      problems.push(`${path}.body: GET requests have no body`);
    } else {
      for (const name of body) {
        if (!parameterNames.includes(name)) problems.push(`${path}.body: "${name}" is not a parameter`);
      }
    }
  }
  return problems;
}

/** Placeholders in a reply, or `undefined` if a `{` is never closed. */
export function replyPlaceholders(reply: string): string[] | undefined {
  const placeholders: string[] = [];
  let rest = reply;
  for (let open = rest.indexOf('{'); open !== -1; open = rest.indexOf('{')) {
    const close = rest.indexOf('}', open);
    if (close === -1) return undefined;
    placeholders.push(rest.slice(open + 1, close));
    rest = rest.slice(close + 1);
  }
  return placeholders;
}

function replyProblems(reply: unknown, path: string): string[] {
  if (!isText(reply)) return [`${path}: must be a non-empty string`];
  const placeholders = replyPlaceholders(reply);
  if (!placeholders) return [`${path}: has a { without a matching }`];
  return placeholders
    .filter((placeholder) => !FIELD_PATH.test(placeholder))
    .map((placeholder) => `${path}: {${placeholder}} must be a response field path like {order.status}`);
}

/** Parameters that never reach the API would make Siri ask the person for something that does nothing. */
function unusedParameterProblems(tool: Json, parameters: unknown[], path: string): string[] {
  const request = isObject(tool.request) ? tool.request : {};
  const used = new Set([
    ...(typeof request.url === 'string' ? urlPlaceholders(request.url) : []),
    ...(Array.isArray(request.body) ? request.body : []),
  ]);
  return parameters.flatMap((parameter, index) =>
    isObject(parameter) && typeof parameter.name === 'string' && !used.has(parameter.name)
      ? [`${path}.parameters[${index}]: "${parameter.name}" is not used in request.url or request.body`]
      : []
  );
}

function toolProblems(tool: unknown, path: string): string[] {
  if (!isObject(tool)) return [`${path}: must be an object`];
  const parameters = tool.parameters ?? [];
  if (!Array.isArray(parameters)) return [`${path}.parameters: must be an array`];
  const names = parameters.map((parameter) => (isObject(parameter) ? parameter.name : undefined));
  const nameProblems =
    typeof tool.name === 'string' && tool.name.endsWith('Intent')
      ? [`${path}.name: leave off "Intent"; it is added for you`]
      : identifierProblems(tool.name, TYPE_NAME, `${path}.name`, 'Swift type name like GetOrderStatus');
  return [
    ...unknownFields(tool, TOOL_FIELDS, path),
    ...nameProblems,
    ...textProblem(tool.title, `${path}.title`),
    ...textProblem(tool.description, `${path}.description`),
    ...parameters.flatMap((parameter, index) => parameterProblems(parameter, `${path}.parameters[${index}]`)),
    ...duplicates(names, (index) => `${path}.parameters[${index}].name`),
    ...requestProblems(tool.request, names.filter((name): name is string => typeof name === 'string'), `${path}.request`),
    ...unusedParameterProblems(tool, parameters, path),
    ...replyProblems(tool.reply, `${path}.reply`),
  ];
}

/** Every problem with a declaration, in a form a person can fix from; empty when it's valid. */
export function declarationProblems(input: unknown): string[] {
  if (!isObject(input)) return ['the declaration must be a JSON object'];
  const problems = unknownFields(input, ['appName', 'tools', '$schema'], 'declaration');
  if (input.appName !== undefined) problems.push(...textProblem(input.appName, 'appName'));
  const { tools } = input;
  if (!Array.isArray(tools) || tools.length === 0) return [...problems, 'tools: must be a non-empty array'];
  return [
    ...problems,
    ...tools.flatMap((tool, index) => toolProblems(tool, `tools[${index}]`)),
    ...duplicates(
      tools.map((tool) => (isObject(tool) ? tool.name : undefined)),
      (index) => `tools[${index}].name`
    ),
  ];
}

function withDefaults(tool: Json): ToolDeclaration {
  const request = tool.request as Json;
  return {
    name: tool.name as string,
    title: tool.title as string,
    description: tool.description as string,
    parameters: (tool.parameters ?? []) as ToolParameter[],
    request: {
      method: request.method as HttpMethod,
      url: request.url as string,
      body: (request.body ?? []) as string[],
    },
    reply: tool.reply as string,
  };
}

/** The declaration with defaults filled in, or an error listing every problem in `source`. */
export function parseSiriTools(input: unknown, source: string): SiriToolsDeclaration {
  const problems = declarationProblems(input);
  if (problems.length > 0) {
    throw new Error(
      `expo-siri-ai-kit: ${source} has problems:\n${problems.map((problem) => `  - ${problem}`).join('\n')}`
    );
  }
  const { appName, tools } = input as Json;
  return {
    ...(typeof appName === 'string' && { appName }),
    tools: (tools as Json[]).map(withDefaults),
  };
}
