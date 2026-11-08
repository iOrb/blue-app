import { env } from "cloudflare:workers";
import { getChatGPTUser } from "../../chatgpt-auth";
import { validLibrary } from "../../blue-model";
export const dynamic = "force-dynamic";
const headers = { "Cache-Control": "private, no-store", Vary: "Cookie" };
export async function POST(request: Request) {
  if (request.headers.get("origin") !== new URL(request.url).origin)
    return Response.json({ error: "unauthorized" }, { status: 403, headers });
  if (!(await getChatGPTUser()))
    return Response.json({ error: "sign_in" }, { status: 401, headers });
  const data = (env as unknown as { BLUE_LIBRARY_IMPORT?: string })
    .BLUE_LIBRARY_IMPORT;
  if (!data)
    return Response.json({ error: "not_configured" }, { status: 503, headers });
  try {
    const bytes = Uint8Array.from(atob(data), (c) => c.charCodeAt(0));
    const stream = new Blob([bytes])
      .stream()
      .pipeThrough(new DecompressionStream("gzip"));
    const imported = (await new Response(stream).json()) as {
      library: unknown;
      importID: string;
    };
    if (
      !validLibrary(imported.library) ||
      !/^[\w-]{1,80}$/.test(imported.importID)
    )
      throw new Error("invalid");
    return Response.json(imported, { headers });
  } catch {
    return Response.json(
      { error: "import_unavailable" },
      { status: 503, headers },
    );
  }
}
