# Sweeping an app's data layer

Data libraries already sort an app's network and state calls into reads and writes. A read is a candidate question tool, and a write is a candidate action tool. Each definition also names the function a handler would call. This file says where to find those definitions for each library, and how to tell whether a handler can call one without React.

Find the libraries from `package.json`, then confirm with imports. An app often uses two, such as React Query for server data and Zustand for local state.

## Where the definitions are

| Library | Reads | Writes | Search for |
|---|---|---|---|
| TanStack / React Query | `useQuery`, `useSuspenseQuery`, `useInfiniteQuery`, `queryOptions(...)`, query key factories | `useMutation`, `mutationOptions(...)` | `queryFn`, `mutationFn`, `queryOptions(` |
| RTK Query | `builder.query` endpoints | `builder.mutation` endpoints | `createApi(`, `injectEndpoints(` |
| SWR | `useSWR` keys and fetchers | `useSWRMutation` | `useSWR(`, `useSWRMutation(` |
| Apollo / urql / Relay | `query` operations | `mutation` operations | `gql\``, `graphql(`, `.graphql` files, generated `use…Query` hooks |
| tRPC | `.query(` procedures | `.mutation(` procedures | `createTRPCReact`, `createTRPCProxyClient`, the router type |
| Generated OpenAPI clients (orval, openapi-typescript, Kubb) | GET operations | POST, PUT, PATCH, DELETE operations | the generated folder, `openapi.yaml` or `openapi.json` |
| Hand-written API modules (axios, ky, fetch, apisauce) | functions that GET | functions that POST, PUT, PATCH, DELETE | `api/`, `services/`, `client.ts`, `axios.create(` |
| Zustand / Redux / Jotai / MobX | selectors over **persisted** state | actions and thunks | `create(`, `createSlice(`, `persist(` |

List every definition, whether or not a screen uses it. A definition no screen reaches is still a candidate: it may run in the background, sit deep inside a screen, or be new.

## Can a handler call it without React?

| Library | Callable | Needs extraction |
|---|---|---|
| TanStack / React Query | The `queryFn` is a named, exported function; or the query is an exported `queryOptions(...)` that the app's exported `QueryClient` can run with `queryClient.fetchQuery(options)`. | The `queryFn` is written inline in a `useQuery` call. Extract it as a named function. |
| RTK Query | Any endpoint: `store.dispatch(api.endpoints.<name>.initiate(args))` works outside React, as long as the store is exported. | The store is only created inside a component or provider. |
| SWR | The fetcher is a named, exported function. | The fetcher is inline. |
| Apollo / urql | The app's client is exported and the operation is a named document: `client.query({ query: Doc })`. | The client is only created inside a provider. |
| tRPC | A vanilla client (`createTRPCProxyClient` / `createTRPCClient`) exists, or can be made from the exported router type and the app's link setup. | Only `createTRPCReact` hooks exist. Name the vanilla client to add. |
| Generated OpenAPI clients | Almost always: generated functions are plain. Check for generated hooks with no plain function underneath. | Only hooks were generated. |
| Hand-written API modules | Exported functions. | Logic inside a component or hook. |
| Zustand / Redux | The store is exported: `useStore.getState()`, `store.getState()`, `store.dispatch(action)`. | The store is created inside a provider. |

**Apollo, urql and Relay hooks can't call a plain function**, because `useQuery` runs the document itself. Extraction there means exporting a function that runs the same document with the same variables through the shared client, and sharing the variables and any filtering with the hook, so both give the same answer. Say in the report that the hook and the function are two paths over one document.

Record the function, or the exact call (`store.dispatch(api.endpoints.getOrders.initiate())`), with its `file:line`. What a call needs to reach the server is already in it; don't trace it further.

## Merging with what the screens show

The screens tell you how people use a call: what they look at and what they tap. The data layer tells you which calls exist. Merge the two lists into one set of candidates, and note where each came from (`screen`, `data layer` or `both`). Then send every candidate through the shortlist rules in the skill.

Most data-layer candidates are rejected, and quickly:

- paged and infinite queries are feeds (too long to speak);
- mutations that take an id the person can't say;
- queries that only feed a settings or developer screen;
- prefetches, health checks and analytics calls, which aren't anything a person asks for.

A data-layer candidate that no screen uses needs one extra check: make sure the app still calls it somewhere. If nothing references it, reject it as dead code.
