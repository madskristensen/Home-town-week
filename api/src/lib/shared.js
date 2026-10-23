"use strict";
// Shared helpers for the upload functions: CORS, rate limit, blob writes,
// image checks. Settings come from app settings, never from the repo:
//   SUBMIT_STORAGE (or AzureWebJobsStorage): storage connection string
//   IP_SALT: random string mixed into the IP hash
//   ALLOWED_ORIGINS: optional comma list, overrides the default list
//   PARTNER_WEBHOOK_URL / PARTNER_WEBHOOK_KEY: optional partner fulfillment
const crypto = require("node:crypto");
const {
  BlobServiceClient,
  BlobSASPermissions,
  StorageSharedKeyCredential,
  generateBlobSASQueryParameters
} = require("@azure/storage-blob");

const CONTAINER = "submissions";
const MAX_PHOTO = 8 * 1024 * 1024;
const MAX_BODY = 12 * 1024 * 1024;
const RATE_LIMIT = Number(process.env.RATE_LIMIT || 10);
const DEFAULT_ORIGINS = [
  "https://www.eastsidecalendar.com",
  "https://eastsidecalendar.com",
  "http://localhost:4000",
  "http://127.0.0.1:4000",
  "http://localhost:8765"
];

function origins() {
  const list = (process.env.ALLOWED_ORIGINS || "").split(",").map((s) => s.trim()).filter(Boolean);
  return list.length ? list : DEFAULT_ORIGINS;
}

function corsHeaders(request) {
  const origin = request.headers.get("origin") || "";
  const headers = { "Vary": "Origin" };
  if (origins().includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    headers["Access-Control-Allow-Headers"] = "Content-Type";
    headers["Access-Control-Max-Age"] = "86400";
  }
  return headers;
}

function originOk(request) {
  return origins().includes(request.headers.get("origin") || "");
}

function reply(request, status, body) {
  return {
    status,
    headers: { ...corsHeaders(request), "Content-Type": "application/json", "Cache-Control": "no-store" },
    body: JSON.stringify(body)
  };
}

function clientIp(request) {
  const fwd = request.headers.get("x-forwarded-for") || request.headers.get("x-client-ip") || "";
  // Azure adds the port: "1.2.3.4:5678". Keep the address only.
  let ip = fwd.split(",")[0].trim();
  // An IPv4 address, maybe IPv6-mapped or with a port: keep just the address.
  const v4 = ip.match(/(\d{1,3}(?:\.\d{1,3}){3})/);
  if (v4) return v4[1];
  const bracket = ip.match(/^\[([^\]]+)\](?::\d+)?$/);
  if (bracket) ip = bracket[1];
  return ip || "unknown";
}

function ipHash(request) {
  const salt = process.env.IP_SALT || "eastsidecal";
  return crypto.createHash("sha256").update(salt + "|" + clientIp(request)).digest("hex").slice(0, 32);
}

let containerClient = null;
function container() {
  if (containerClient) return containerClient;
  const conn = process.env.SUBMIT_STORAGE || process.env.AzureWebJobsStorage;
  if (!conn) throw new Error("No storage connection setting");
  containerClient = BlobServiceClient.fromConnectionString(conn).getContainerClient(CONTAINER);
  return containerClient;
}

async function putBlob(name, data, contentType) {
  const blob = container().getBlockBlobClient(name);
  const bytes = Buffer.isBuffer(data) ? data : Buffer.from(String(data), "utf8");
  await blob.uploadData(bytes, { blobHTTPHeaders: { blobContentType: contentType } });
}

function storageCred() {
  const conn = process.env.SUBMIT_STORAGE || process.env.AzureWebJobsStorage;
  if (!conn) throw new Error("No storage connection setting");
  const parts = Object.fromEntries(
    conn.split(";").filter(Boolean).map((p) => {
      const i = p.indexOf("=");
      return [p.slice(0, i), p.slice(i + 1)];
    })
  );
  if (!parts.AccountName || !parts.AccountKey) {
    throw new Error("Storage connection string needs AccountName and AccountKey");
  }
  return {
    accountName: parts.AccountName,
    credential: new StorageSharedKeyCredential(parts.AccountName, parts.AccountKey),
    suffix: parts.EndpointSuffix || "core.windows.net"
  };
}

// Read-only SAS URL for a blob in the submissions container, valid about 7 days.
function photoSasUrl(blobName, days = 7) {
  const { accountName, credential, suffix } = storageCred();
  const startsOn = new Date(Date.now() - 60 * 1000);
  const expiresOn = new Date(Date.now() + days * 24 * 60 * 60 * 1000);
  const sas = generateBlobSASQueryParameters({
    containerName: CONTAINER,
    blobName,
    permissions: BlobSASPermissions.parse("r"),
    startsOn,
    expiresOn
  }, credential).toString();
  return `https://${accountName}.blob.${suffix}/${CONTAINER}/${blobName}?${sas}`;
}

// Best effort: one small blob per hashed IP per hour, bumped with an ETag
// check. Falls back to an in-memory count if storage is unhappy.
const memory = new Map();
async function rateLimited(hash) {
  const hour = new Date().toISOString().slice(0, 13);
  const key = hour + "/" + hash;
  const local = (memory.get(key) || 0) + 1;
  memory.set(key, local);
  if (memory.size > 5000) memory.clear();
  try {
    const blob = container().getBlockBlobClient("ratelimit/" + key);
    for (let attempt = 0; attempt < 3; attempt++) {
      let count = 0;
      let etag = null;
      try {
        const buf = await blob.downloadToBuffer();
        count = Number(buf.toString()) || 0;
        const props = await blob.getProperties();
        etag = props.etag;
      } catch (err) {
        if (err.statusCode !== 404) throw err;
      }
      if (count >= RATE_LIMIT) return true;
      const body = String(count + 1);
      const conditions = etag ? { ifMatch: etag } : { ifNoneMatch: "*" };
      try {
        await blob.upload(body, body.length, { conditions, blobHTTPHeaders: { blobContentType: "text/plain" } });
        return false;
      } catch (err) {
        if (err.statusCode !== 412 && err.statusCode !== 409) throw err;
      }
    }
    return false;
  } catch (err) {
    return local > RATE_LIMIT;
  }
}

const IMAGE_TYPES = {
  "image/jpeg": "jpg",
  "image/png": "png",
  "image/webp": "webp",
  "image/heic": "heic",
  "image/heif": "heic"
};

// Read the type from the bytes, not from the client.
function sniffImage(buf) {
  if (!buf || buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return "image/jpeg";
  if (buf.slice(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png";
  if (buf.toString("ascii", 0, 4) === "RIFF" && buf.toString("ascii", 8, 12) === "WEBP") return "image/webp";
  if (buf.toString("ascii", 4, 8) === "ftyp") {
    const brand = buf.toString("ascii", 8, 12);
    if (["heic", "heix", "hevc", "hevx", "heim", "heis", "mif1", "msf1"].includes(brand)) return "image/heic";
  }
  return null;
}

function clean(value, max) {
  if (value === undefined || value === null) return "";
  const text = String(value).replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").trim();
  return text.length > max ? null : text;
}

function datePath() {
  return new Date().toISOString().slice(0, 10);
}

// Body: multipart/form-data (fields plus a "photo" file) or JSON with
// photo as base64 or a data URL. Returns { fields, photo: Buffer|null }.
async function readBody(request) {
  const length = Number(request.headers.get("content-length") || 0);
  if (length > MAX_BODY) return { tooBig: true };
  const type = (request.headers.get("content-type") || "").toLowerCase();
  if (type.startsWith("multipart/form-data")) {
    const form = await request.formData();
    const fields = {};
    let photo = null;
    for (const [key, value] of form.entries()) {
      if (typeof value === "string") fields[key] = value;
      else if (key === "photo" && value && value.size) {
        if (value.size > MAX_PHOTO) return { tooBig: true };
        photo = Buffer.from(await value.arrayBuffer());
      }
    }
    return { fields, photo };
  }
  const raw = Buffer.from(await request.arrayBuffer());
  if (raw.length > MAX_BODY) return { tooBig: true };
  let fields;
  try {
    fields = JSON.parse(raw.toString("utf8") || "{}");
  } catch (err) {
    return { bad: true };
  }
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) return { bad: true };
  let photo = null;
  if (typeof fields.photo === "string" && fields.photo) {
    const b64 = fields.photo.replace(/^data:[^,]*,/, "");
    photo = Buffer.from(b64, "base64");
    if (photo.length > MAX_PHOTO) return { tooBig: true };
  }
  delete fields.photo;
  return { fields, photo };
}

module.exports = {
  MAX_PHOTO, IMAGE_TYPES, corsHeaders, originOk, reply, ipHash, putBlob, photoSasUrl, rateLimited,
  sniffImage, clean, datePath, readBody
};
