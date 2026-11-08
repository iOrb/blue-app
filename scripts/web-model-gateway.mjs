import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { timingSafeEqual } from 'node:crypto';

// Preview-only gateway. The public tunnel cannot reach the Mac model without this token.
const token = readFileSync(new URL('../.build/model-bridge-token', import.meta.url), 'utf8').trim();
let working = false;
const server = createServer({ maxHeaderSize: 8192, requestTimeout: 15000, headersTimeout: 10000 }, async (req, res) => {
  res.setHeader('Cache-Control', 'no-store');
  const supplied = Buffer.from(req.headers.authorization || '');
  const expected = Buffer.from(`Bearer ${token}`);
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) { res.writeHead(401).end(); return; }
  if (req.method !== 'POST' || req.url !== '/respond') { res.writeHead(404).end(); return; }
  if (working) { res.writeHead(429, { 'Retry-After': '5' }).end(); return; }
  if (Number(req.headers['content-length']) > 2_000_000) { res.writeHead(413).end(); return; }
  working = true;
  try {
    let size = 0; const chunks = [];
    for await (const chunk of req) { size += chunk.length; if (size > 2_000_000) throw new Error('limit'); chunks.push(chunk); }
    const body = Buffer.concat(chunks);
    const input = JSON.parse(body);
    if (typeof input.prompt !== 'string' || input.prompt.length > 2000 || !input.library || !['en', 'es'].includes(input.language)) { res.writeHead(400).end(); return; }
    const reply = await fetch('http://127.0.0.1:7977/respond', { method: 'POST', headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' }, body, signal: AbortSignal.timeout(95000) });
    res.writeHead(reply.status, { 'Content-Type': 'application/json' });
    res.end(Buffer.from(await reply.arrayBuffer()));
  } catch { if (!res.headersSent) res.writeHead(502); res.end(JSON.stringify({ error: 'model_unavailable' })); }
  finally { working = false; }
});
server.maxConnections = 16;
server.listen(7978, '127.0.0.1', () => console.log('Blue preview model gateway ready on loopback.'));
