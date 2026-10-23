"use strict";
// POST /api/suggest: an event, a place, a city request, or anything else.
// Saves pending/suggestions/{date}/{uuid}.json, plus the photo if sent.
const crypto = require("node:crypto");
const { app } = require("@azure/functions");
const s = require("../lib/shared");

const KINDS = ["event", "place", "city", "partner", "other"];
const LIMITS = { name: 200, date: 100, time: 100, place: 300, link: 500, blurb: 2000, contact_email: 200 };

async function handler(request) {
  if (request.method === "OPTIONS") return { status: 204, headers: s.corsHeaders(request) };
  if (!s.originOk(request)) return s.reply(request, 403, { ok: false, error: "origin" });
  const body = await s.readBody(request);
  if (body.tooBig) return s.reply(request, 413, { ok: false, error: "too_big" });
  if (body.bad) return s.reply(request, 400, { ok: false, error: "bad_body" });
  const f = body.fields;
  if (f.website) return s.reply(request, 200, { ok: true });
  const kind = KINDS.includes(f.kind) ? f.kind : "other";
  const out = {};
  for (const [key, max] of Object.entries(LIMITS)) {
    const value = s.clean(f[key], max);
    if (value === null) return s.reply(request, 400, { ok: false, error: "too_long", field: key });
    out[key] = value;
  }
  if (kind === "partner") {
    if (!out.name || !out.blurb || !out.link) return s.reply(request, 400, { ok: false, error: "empty" });
  } else if (!out.name && !out.blurb && !out.link) {
    return s.reply(request, 400, { ok: false, error: "empty" });
  }
  if (out.link && !/^https?:\/\/\S+$/i.test(out.link)) return s.reply(request, 400, { ok: false, error: "link" });
  if (!out.contact_email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(out.contact_email)) {
    return s.reply(request, 400, { ok: false, error: "email" });
  }
  let type = null;
  if (body.photo) {
    type = s.sniffImage(body.photo);
    if (!type) return s.reply(request, 415, { ok: false, error: "type" });
  }
  const hash = s.ipHash(request);
  if (await s.rateLimited(hash)) return s.reply(request, 429, { ok: false, error: "rate" });
  const id = crypto.randomUUID();
  const base = `pending/suggestions/${s.datePath()}/${id}`;
  let file = "";
  if (body.photo) {
    file = `${id}.${s.IMAGE_TYPES[type]}`;
    await s.putBlob(`pending/suggestions/${s.datePath()}/${file}`, body.photo, type);
  }
  const record = {
    id, kind, ...out, photo: file,
    received: new Date().toISOString(),
    user_agent: (request.headers.get("user-agent") || "").slice(0, 300),
    ip_hash: hash
  };
  await s.putBlob(`${base}.json`, JSON.stringify(record, null, 2), "application/json");
  return s.reply(request, 200, { ok: true, id });
}

app.http("suggest", { methods: ["POST", "OPTIONS"], authLevel: "anonymous", route: "suggest", handler });
module.exports = { handler };
