import { declarationProblems, parseSiriTools } from '../siriTools/declaration';

const SOURCE = 'siri-tools.json';

function validTool(): Record<string, any> {
  return {
    name: 'GetOrderStatus',
    title: 'Get Order Status',
    description: 'Tells the person where an order is.',
    parameters: [{ name: 'orderNumber', type: 'string', title: 'Order Number' }],
    request: { method: 'GET', url: 'https://api.example.com/orders/{orderNumber}' },
    reply: 'Order {id} is {status}.',
  };
}

function withTool(change: (tool: Record<string, any>) => void): unknown {
  const tool = validTool();
  change(tool);
  return { tools: [tool] };
}

const PARAMETER_DESCRIPTION = 'The order number from the confirmation email, like A1234.';

describe('declarationProblems', () => {
  it('accepts a minimal declaration', () => {
    expect(declarationProblems({ tools: [validTool()] })).toEqual([]);
  });

  it('accepts every parameter type and a body', () => {
    const declaration = withTool((tool) => {
      tool.parameters = [
        { name: 'city', type: 'string', title: 'City' },
        { name: 'nights', type: 'int', title: 'Nights' },
        { name: 'budget', type: 'double', title: 'Budget' },
        { name: 'refundable', type: 'bool', title: 'Refundable' },
        { name: 'departure', type: 'date', title: 'Departure' },
        { name: 'cabin', type: 'enum', title: 'Cabin', cases: { economy: 'Economy', business: 'Business' } },
      ];
      tool.request = {
        method: 'POST',
        url: 'https://api.example.com/trips/{city}?nights={nights}',
        body: ['budget', 'refundable', 'departure', 'cabin'],
      };
    });
    expect(declarationProblems(declaration)).toEqual([]);
  });

  it('accepts a parameter description', () => {
    const declaration = withTool((tool) => (tool.parameters[0].description = PARAMETER_DESCRIPTION));
    expect(declarationProblems(declaration)).toEqual([]);
  });

  it.each<[string, unknown, string[]]>([
    ['a non-object', 'tools', ['the declaration must be a JSON object']],
    ['no tools', {}, ['tools: must be a non-empty array']],
    ['an empty tools array', { tools: [] }, ['tools: must be a non-empty array']],
    ['a non-string appName', { appName: 3, tools: [validTool()] }, ['appName: must be a non-empty string']],
    [
      'a lowercase tool name',
      withTool((tool) => (tool.name = 'getOrder')),
      ['tools[0].name: must be a Swift type name like GetOrderStatus']
    ],
    [
      'a name ending in Intent',
      withTool((tool) => (tool.name = 'GetOrderIntent')),
      ['tools[0].name: leave off "Intent"; it is added for you']
    ],
    ['a missing title', withTool((tool) => delete tool.title), ['tools[0].title: must be a non-empty string']],
    [
      'a blank description',
      withTool((tool) => (tool.description = ' ')),
      ['tools[0].description: must be a non-empty string']
    ],
    [
      'an unknown tool field',
      withTool((tool) => (tool.icon = 'cart')),
      ['tools[0]: unknown field "icon"']
    ],
    [
      'an unknown parameter type',
      withTool((tool) => (tool.parameters[0].type = 'url')),
      ['tools[0].parameters[0].type: must be one of string, int, double, bool, date, enum']
    ],
    [
      'a parameter name that is not a Swift identifier',
      withTool((tool) => {
        tool.parameters[0].name = 'order-number';
        tool.request.url = 'https://api.example.com/orders/{order-number}';
      }),
      ['tools[0].parameters[0].name: must be a Swift property name like orderNumber']
    ],
    [
      'a parameter named with a Swift keyword',
      withTool((tool) => {
        tool.parameters[0].name = 'default';
        tool.request.url = 'https://api.example.com/orders/{default}';
      }),
      ['tools[0].parameters[0].name: "default" is a Swift keyword']
    ],
    [
      'a blank parameter description',
      withTool((tool) => (tool.parameters[0].description = ' ')),
      ['tools[0].parameters[0].description: must be a non-empty string']
    ],
    [
      'a parameter description that is not text',
      withTool((tool) => (tool.parameters[0].description = 3)),
      ['tools[0].parameters[0].description: must be a non-empty string']
    ],
    [
      'a parameter description on two lines',
      withTool((tool) => (tool.parameters[0].description = 'The order number,\nlike A1234.')),
      ['tools[0].parameters[0].description: must be one line']
    ],
    [
      'a duplicate parameter',
      withTool((tool) => tool.parameters.push({ name: 'orderNumber', type: 'int', title: 'Again' })),
      ['tools[0].parameters[1].name: "orderNumber" is declared twice']
    ],
    [
      'an enum without cases',
      withTool((tool) => (tool.parameters[0] = { name: 'orderNumber', type: 'enum', title: 'Order' })),
      ['tools[0].parameters[0].cases: must map case names to titles, like {"economy": "Economy"}']
    ],
    [
      'an enum case that is not a Swift identifier',
      withTool(
        (tool) => (tool.parameters[0] = { name: 'orderNumber', type: 'enum', title: 'Order', cases: { 'first-class': 'First' } })
      ),
      ['tools[0].parameters[0].cases: "first-class" must be a Swift case name like firstClass']
    ],
    [
      'cases on a non-enum',
      withTool((tool) => (tool.parameters[0].cases = { a: 'A' })),
      ['tools[0].parameters[0].cases: only enum parameters have cases']
    ],
    [
      'an unknown method',
      withTool((tool) => (tool.request.method = 'HEAD')),
      ['tools[0].request.method: must be one of GET, POST, PUT, PATCH, DELETE']
    ],
    [
      'a plain http URL',
      withTool((tool) => (tool.request.url = 'http://api.example.com/orders/{orderNumber}')),
      ['tools[0].request.url: must start with https://']
    ],
    [
      'a URL placeholder that is not a parameter',
      withTool((tool) => (tool.request.url = 'https://api.example.com/orders/{orderNumber}/{line}')),
      ['tools[0].request.url: {line} is not a parameter']
    ],
    [
      'a parameter that is never sent',
      withTool((tool) => (tool.request.url = 'https://api.example.com/orders')),
      ['tools[0].parameters[0]: "orderNumber" is not used in request.url or request.body']
    ],
    [
      'a body on a GET',
      withTool((tool) => {
        tool.request.url = 'https://api.example.com/orders';
        tool.request.body = ['orderNumber'];
      }),
      ['tools[0].request.body: GET requests have no body']
    ],
    [
      'a body field that is not a parameter',
      withTool((tool) => {
        tool.request.method = 'POST';
        tool.request.body = ['note'];
      }),
      ['tools[0].request.body: "note" is not a parameter']
    ],
    [
      'an auth field, which the generated tools do not support',
      withTool((tool) => (tool.request.auth = { service: 'com.example.app', account: 'token' })),
      ['tools[0].request: unknown field "auth"']
    ],
    ['an empty reply', withTool((tool) => (tool.reply = '')), ['tools[0].reply: must be a non-empty string']],
    [
      'a reply placeholder that is not a field path',
      withTool((tool) => (tool.reply = 'Status: {status code}')),
      ['tools[0].reply: {status code} must be a response field path like {order.status}']
    ],
    [
      'an unclosed reply placeholder',
      withTool((tool) => (tool.reply = 'Status: {status')),
      ['tools[0].reply: has a { without a matching }']
    ],
    [
      'two tools with the same name',
      { tools: [validTool(), validTool()] },
      ['tools[1].name: "GetOrderStatus" is declared twice']
    ],
  ])('reports %s', (_label, input, problems) => {
    expect(declarationProblems(input)).toEqual(problems);
  });

  it('reports every problem at once', () => {
    const declaration = withTool((tool) => {
      tool.title = '';
      tool.reply = '';
    });
    expect(declarationProblems(declaration)).toEqual([
      'tools[0].title: must be a non-empty string',
      'tools[0].reply: must be a non-empty string',
    ]);
  });
});

describe('parseSiriTools', () => {
  it('keeps a parameter description', () => {
    const declaration = parseSiriTools(
      withTool((tool) => (tool.parameters[0].description = PARAMETER_DESCRIPTION)),
      SOURCE
    );
    expect(declaration.tools[0].parameters[0]).toEqual({
      name: 'orderNumber',
      type: 'string',
      title: 'Order Number',
      description: PARAMETER_DESCRIPTION,
    });
  });

  it('fills in the defaults', () => {
    const declaration = parseSiriTools({ tools: [validTool()] }, SOURCE);
    expect(declaration.tools[0].parameters).toEqual([{ name: 'orderNumber', type: 'string', title: 'Order Number' }]);
    expect(declaration.tools[0].request).toEqual({
      method: 'GET',
      url: 'https://api.example.com/orders/{orderNumber}',
      body: [],
    });
  });

  it('treats missing parameters as none', () => {
    const declaration = parseSiriTools(
      withTool((tool) => {
        delete tool.parameters;
        tool.request.url = 'https://api.example.com/orders/latest';
      }),
      SOURCE
    );
    expect(declaration.tools[0].parameters).toEqual([]);
  });

  it('throws one error naming the file and every problem', () => {
    const declaration = withTool((tool) => {
      tool.title = '';
      tool.reply = '';
    });
    expect(() => parseSiriTools(declaration, SOURCE)).toThrow(
      'expo-siri-ai-kit: siri-tools.json has problems:\n' +
        '  - tools[0].title: must be a non-empty string\n' +
        '  - tools[0].reply: must be a non-empty string'
    );
  });
});
