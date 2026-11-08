import { env } from "cloudflare:workers";
import { getChatGPTUser } from "../../chatgpt-auth";
import { validLibrary } from "../../blue-model";
export const dynamic = "force-dynamic";
const headers = {
  "Cache-Control": "no-store",
  "Content-Type": "application/json",
};
export async function POST(request: Request) {
  if (request.headers.get("origin") !== new URL(request.url).origin)
    return Response.json({ error: "unauthorized" }, { status: 403, headers });
  if (!(await getChatGPTUser()))
    return Response.json({ error: "sign_in" }, { status: 401, headers });
  const config = env as unknown as {
    BLUE_MODEL_BRIDGE_URL?: string;
    BLUE_MODEL_BRIDGE_TOKEN?: string;
  };
  if (!config.BLUE_MODEL_BRIDGE_URL || !config.BLUE_MODEL_BRIDGE_TOKEN)
    return Response.json(
      { error: "model_unavailable" },
      { status: 503, headers },
    );
  if (Number(request.headers.get("content-length")) > 2_000_000)
    return Response.json({ error: "too_large" }, { status: 413, headers });
  try {
    const raw = await request.text();
    if (raw.length > 2_000_000)
      return Response.json({ error: "too_large" }, { status: 413, headers });
    const body = JSON.parse(raw);
    if (
      typeof body.prompt !== "string" ||
      !body.prompt.trim() ||
      body.prompt.length > 2000 ||
      !["en", "es"].includes(body.language) ||
      !validLibrary(body.library)
    )
      return Response.json({ error: "invalid" }, { status: 400, headers });
    const response = await fetch(
      new URL("/respond", config.BLUE_MODEL_BRIDGE_URL),
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${config.BLUE_MODEL_BRIDGE_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(100000),
      },
    );
    if (!response.ok)
      return Response.json(
        { error: response.status === 429 ? "busy" : "model_unavailable" },
        { status: response.status === 429 ? 429 : 503, headers },
      );
    const result = (await response.json()) as {
      library: unknown;
      result: unknown;
    };
    if (!validLibrary(result.library) || !result.result)
      throw new Error("invalid");
    // The browser owns its one-time import marker; calendar events are shared with native inference.
    result.library = {
      ...result.library,
      imports: body.library.imports,
    };
    return Response.json(result, { headers });
  } catch {
    return Response.json(
      { error: "model_unavailable" },
      { status: 503, headers },
    );
  }
}
