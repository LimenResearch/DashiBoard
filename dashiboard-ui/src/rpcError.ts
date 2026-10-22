// Apart from `requests.ts`, which tests replace wholesale, so a caller can tell a refusal apart
// under a mocked `postRequest`.

/** A call the server refused. No route's result has a top-level `error`, so the key says it. */
export type RpcError = { error: { code: number; message: string; data?: Record<string, unknown> | null } };

export type Failure = { errors: string[]; issues?: unknown[]; kind?: string; [key: string]: unknown };

export const isRpcError = (x: unknown): x is RpcError =>
  typeof x === "object" && x !== null && !Array.isArray(x) && "error" in x;

/** What a refusal says: the route's own report, or the server's sentence when it has none. */
export const failureOf = (e: RpcError): Failure =>
  (e.error.data ?? { errors: [e.error.message] }) as Failure;
