const { app } = require('@azure/functions');

const TIMEOUT_MS = 10000, MAX_BYTES = 5 * 1024 * 1024, MAX_REDIRECTS = 5;
const DEFAULT_HOSTS = 'issaquahwa.gov,www.issaquahwa.gov,woodinville.gov,www.woodinville.gov,wa-issaquah2.civicplus.com,wa-woodinville.civicplus.com,cityofissaquah.perfectmind.com';
const HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
};
const allowed = () => new Set((process.env.ALLOWED_HOSTS || DEFAULT_HOSTS).split(',').map(s => s.trim().toLowerCase()).filter(Boolean));
function check(u) {
  let p; try { p = new URL(u); } catch { return null; }
  if (p.protocol !== 'https:' || p.username || p.password || (p.port && p.port !== '443')) return null;
  return allowed().has(p.hostname.toLowerCase()) ? p : null;
}
const err = (status, msg) => ({ status, body: msg, headers: { 'Content-Type': 'text/plain' } });

app.http('fetch', {
  methods: ['GET'], authLevel: 'function',
  handler: async (req, ctx) => {
    const raw = req.query.get('url');
    if (!raw) return err(400, 'missing url');
    let target = check(raw);
    if (!target) { ctx.log(`deny ${raw.slice(0, 200)}`); return err(403, 'host not allowed'); }
    const ac = new AbortController(); const t = setTimeout(() => ac.abort(), TIMEOUT_MS);
    try {
      let res;
      for (let i = 0; ; i++) {
        res = await fetch(target, { headers: HEADERS, redirect: 'manual', signal: ac.signal });
        if (res.status >= 300 && res.status < 400 && res.headers.get('location')) {
          if (i >= MAX_REDIRECTS) return err(508, 'too many redirects');
          const next = check(new URL(res.headers.get('location'), target).toString());
          if (!next) return err(403, 'redirect to non-allowed host');
          target = next; continue;
        }
        break;
      }
      const len = Number(res.headers.get('content-length') || 0);
      if (len > MAX_BYTES) return err(502, 'response too large');
      const chunks = []; let total = 0;
      if (res.body) for await (const c of res.body) {
        total += c.length; if (total > MAX_BYTES) { ac.abort(); return err(502, 'response too large'); }
        chunks.push(c);
      }
      ctx.log(`${res.status} ${target.hostname} ${total}B`);
      const headers = {}; const ct = res.headers.get('content-type'); if (ct) headers['Content-Type'] = ct;
      return { status: res.status, body: Buffer.concat(chunks), headers };
    } catch (e) {
      ctx.log(`error ${target.hostname} ${e.name}`);
      return err(e.name === 'AbortError' ? 504 : 502, e.name === 'AbortError' ? 'upstream timeout' : 'upstream error');
    } finally { clearTimeout(t); }
  },
});
