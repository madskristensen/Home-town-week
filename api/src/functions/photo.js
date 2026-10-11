"use strict";
// POST /api/photo: a better photo for one card. Saves the image and a
// sidecar JSON under pending/photos/{date}/{uuid}.
const crypto = require("node:crypto");
const { app } = require("@azure/functions");
const s = require("../lib/shared");

async function handler(request) {
  if (request.method === "OPTIONS") return { status: 204, headers: s.corsHeaders(request) };
  if (!s.originOk(request)) return s.reply(request, 403, { ok: false, error: "origin" });
  const body = await s.readBody(request);
  if (body.tooBig) return s.reply(request, 413, { ok: false, error: "too_big" });
  if (body.bad) return s.reply(request, 400, { ok: false, error: "bad_body" });
  const f = body.fields;
  // Honeypot: people never see this field. Pretend it worked.
  if (f.website) return s.reply(request, 200, { ok: true });
  if (!body.photo) return s.reply(request, 400, { ok: false, error: "no_photo" });
  const type = s.sniffImage(body.photo);
  if (!type) return s.reply(request, 415, { ok: false, error: "type" });
  const page = s.clean(f.page, 300);
  const cardId = s.clean(f.card_id, 200);
  const cardName = s.clean(f.card_name, 200);
  const credit = s.clean(f.credit, 100);
  if (page === null || cardId === null || cardName === null || credit === null) {
    return s.reply(request, 400, { ok: false, error: "too_long" });
  }
  if (!page.startsWith("/")) return s.reply(request, 400, { ok: false, error: "page" });
  const hash = s.ipHash(request);
  if (await s.rateLimited(hash)) return s.reply(request, 429, { ok: false, error: "rate" });
  const id = crypto.randomUUID();
  const base = `pending/photos/${s.datePath()}/${id}`;
  const ext = s.IMAGE_TYPES[type];
  await s.putBlob(`${base}.${ext}`, body.photo, type);
  const meta = {
    id, kind: "photo", page, card_id: cardId, card_name: cardName, credit,
    file: `${id}.${ext}`, content_type: type, bytes: body.photo.length,
    received: new Date().toISOString(),
    user_agent: (request.headers.get("user-agent") || "").slice(0, 300),
    ip_hash: hash
  };
  await s.putBlob(`${base}.json`, JSON.stringify(meta, null, 2), "application/json");
  return s.reply(request, 200, { ok: true, id });
}

app.http("photo", { methods: ["POST", "OPTIONS"], authLevel: "anonymous", route: "photo", handler });
module.exports = { handler };
