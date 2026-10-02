#!/usr/bin/env node
// Build 1200x630 share cards for city pages, seasonal hubs, explore
// pages, and articles. The title on the card is the page name.
//
// The Pages workflow runs this before Jekyll. PNGs and _data/share_manifest.yml
// are not committed. A card is redrawn only when its photo, title, credit,
// logo, or this script changes. --from-cache copies a restored cache.

import { createHash } from "node:crypto";
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const W = 1200;
const H = 630;
const OUT_DIR = join(ROOT, "assets", "images", "share");
const CACHE = join(ROOT, ".share-cache");
const CACHE_OUT = join(CACHE, "out");
const MANIFEST = join(ROOT, "_data", "share_manifest.yml");
const LOGO = join(ROOT, "assets", "images", "favicon.svg");
const SERIF = "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf";
const SANS = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf";
const LAYOUT = "share-card-v1";

function sha256(buf) {
  return createHash("sha256").update(buf).digest("hex");
}

function read(path) {
  return readFileSync(path);
}

function yamlScalar(value) {
  return JSON.stringify(String(value));
}

function parseShareYaml(text) {
  const cards = [];
  let current = null;
  for (const line of text.split("\n")) {
    if (line.startsWith("#") || line.trim() === "") continue;
    if (line.startsWith("- id: ")) {
      if (current) cards.push(current);
      current = { id: line.slice(6).trim() };
      continue;
    }
    if (!current) continue;
    const match = line.match(/^  ([a-z_]+): (.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if (value.startsWith('"') && value.endsWith('"')) value = JSON.parse(value);
    current[match[1]] = value;
  }
  if (current) cards.push(current);
  return cards;
}

function parseCities(text) {
  const cities = [];
  let current = null;
  let inHero = false;
  for (const line of text.split("\n")) {
    if (line.startsWith("- id: ")) {
      if (current) cities.push(current);
      current = { id: line.slice(6).trim() };
      inHero = false;
      continue;
    }
    if (!current) continue;
    if (line.startsWith("  name: ")) current.name = line.slice(8).trim().replace(/^"|"$/g, "");
    if (line.startsWith("  hero:")) {
      inHero = true;
      continue;
    }
    if (inHero && line.startsWith("    ")) {
      const match = line.match(/^    ([a-z_]+): (.*)$/);
      if (!match) continue;
      let value = match[2].trim();
      if (value.startsWith('"') && value.endsWith('"')) value = JSON.parse(value);
      current[match[1]] = value;
      continue;
    }
    if (line.startsWith("  ") && !line.startsWith("    ")) inHero = false;
  }
  if (current) cities.push(current);
  return cities.filter((city) => city.image);
}

function creditRequired(license) {
  const text = String(license || "").toLowerCase();
  if (text.includes("cc0") || text.includes("public domain")) return false;
  return true;
}

function cards() {
  const cities = parseCities(read(join(ROOT, "_data", "cities.yml")).toString("utf8"));
  const extras = parseShareYaml(read(join(ROOT, "_data", "share_cards.yml")).toString("utf8"));
  const cityCards = cities.map((city) => ({
    id: city.id,
    path: `/${city.id}/`,
    title: city.name,
    image: city.image,
    alt: city.alt || city.name,
    credit: city.credit || "",
    license: city.license || "",
  }));
  return cityCards.concat(extras);
}

function cardHash(card, photo, logo, script) {
  return sha256(Buffer.concat([
    Buffer.from(LAYOUT),
    Buffer.from(JSON.stringify({
      id: card.id,
      title: card.title,
      alt: card.alt,
      credit: card.credit,
      license: card.license,
      showCredit: creditRequired(card.license),
    })),
    photo,
    logo,
    script,
  ]));
}

function fingerprintOf(list, logo, script) {
  const parts = [Buffer.from(LAYOUT), logo, script];
  for (const card of list) {
    const photoPath = join(ROOT, card.image.replace(/^\//, ""));
    parts.push(Buffer.from(card.id + card.title + card.credit + card.license));
    parts.push(read(photoPath));
  }
  return sha256(Buffer.concat(parts));
}

function h(type, props, ...children) {
  const flat = children.flat().filter((child) => child !== undefined && child !== null && child !== false);
  return { type, props: { ...props, children: flat.length === 1 ? flat[0] : flat } };
}

async function overlay(card, logoDataUri) {
  const { default: satori } = await import("satori");
  const { Resvg } = await import("@resvg/resvg-js");
  const showCredit = creditRequired(card.license) && card.credit;
  const titleSize = card.title.length > 32 ? 52 : 64;
  const tree = h(
    "div",
    {
      style: {
        width: W,
        height: H,
        display: "flex",
        flexDirection: "column",
        justifyContent: "flex-end",
        background: "linear-gradient(to top, rgba(16,28,22,0.82) 0%, rgba(16,28,22,0.45) 28%, rgba(16,28,22,0) 52%)",
        padding: "0 48px 40px",
      },
    },
    h(
      "div",
      { style: { display: "flex", alignItems: "flex-end", justifyContent: "space-between", width: "100%" } },
      h(
        "div",
        { style: { display: "flex", alignItems: "center", gap: 22 } },
        h("img", { src: logoDataUri, width: 72, height: 72 }),
        h(
          "div",
          { style: { display: "flex", flexDirection: "column" } },
          h("div", {
            style: {
              fontFamily: "Liberation Serif",
              fontSize: titleSize,
              fontWeight: 700,
              color: "#fffdf8",
              lineHeight: 1.05,
              letterSpacing: "-0.02em",
              maxWidth: showCredit ? 760 : 980,
            },
          }, card.title),
          h("div", {
            style: {
              marginTop: 8,
              fontFamily: "Liberation Sans",
              fontSize: 26,
              color: "#f4efe6",
              letterSpacing: "0.01em",
            },
          }, "eastsidecalendar.com"),
        ),
      ),
      showCredit
        ? h("div", {
          style: {
            fontFamily: "Liberation Sans",
            fontSize: 18,
            color: "rgba(255,253,248,0.88)",
            maxWidth: 280,
            textAlign: "right",
            lineHeight: 1.3,
            marginBottom: 6,
          },
        }, card.credit)
        : null,
    ),
  );
  const svg = await satori(tree, {
    width: W,
    height: H,
    fonts: [
      { name: "Liberation Serif", data: read(SERIF), weight: 700, style: "normal" },
      { name: "Liberation Sans", data: read(SANS), weight: 400, style: "normal" },
    ],
  });
  return new Resvg(svg, { fitTo: { mode: "width", value: W } }).render().asPng();
}

async function renderCard(card, logoPng) {
  const sharp = (await import("sharp")).default;
  const photoPath = join(ROOT, card.image.replace(/^\//, ""));
  const photo = await sharp(photoPath)
    .resize(W, H, { fit: "cover", position: "attention" })
    .png()
    .toBuffer();
  const logoDataUri = `data:image/png;base64,${logoPng.toString("base64")}`;
  const layer = await overlay(card, logoDataUri);
  return sharp(photo).composite([{ input: layer, top: 0, left: 0 }]).jpeg({ quality: 82, mozjpeg: true }).toBuffer();
}

function writeManifest(list) {
  const lines = list.map((card) => {
    const image = `/assets/images/share/${card.id}.jpg`;
    const alt = `${card.title}. ${card.alt}`.replace(/\s+/g, " ").trim();
    return [
      `- path: ${card.path}`,
      `  image: ${image}`,
      `  alt: ${yamlScalar(alt)}`,
      "  width: 1200",
      "  height: 630",
    ].join("\n");
  });
  mkdirSync(dirname(MANIFEST), { recursive: true });
  writeFileSync(MANIFEST, `${lines.join("\n")}\n`);
}

function copyCached(list) {
  mkdirSync(OUT_DIR, { recursive: true });
  for (const card of list) {
    const src = join(CACHE_OUT, `${card.id}.jpg`);
    if (!existsSync(src)) throw new Error(`missing cached card ${card.id}`);
    copyFileSync(src, join(OUT_DIR, `${card.id}.jpg`));
  }
  writeManifest(list);
}

async function build(list) {
  const sharp = (await import("sharp")).default;
  const logoPng = await sharp(read(LOGO)).resize(144, 144).png().toBuffer();
  const script = read(fileURLToPath(import.meta.url));
  mkdirSync(CACHE_OUT, { recursive: true });
  mkdirSync(OUT_DIR, { recursive: true });
  let drawn = 0;
  for (const card of list) {
    const photo = read(join(ROOT, card.image.replace(/^\//, "")));
    const hash = cardHash(card, photo, logoPng, script);
    const metaPath = join(CACHE, "meta", `${card.id}.json`);
    const cached = join(CACHE_OUT, `${card.id}.jpg`);
    let reuse = false;
    if (existsSync(metaPath) && existsSync(cached)) {
      const meta = JSON.parse(read(metaPath).toString("utf8"));
      reuse = meta.hash === hash;
    }
    const dest = join(OUT_DIR, `${card.id}.jpg`);
    if (reuse) {
      copyFileSync(cached, dest);
      continue;
    }
    const png = await renderCard(card, logoPng);
    mkdirSync(dirname(metaPath), { recursive: true });
    writeFileSync(cached, png);
    writeFileSync(dest, png);
    writeFileSync(metaPath, JSON.stringify({ hash }));
    drawn += 1;
    console.log(`drew ${card.id}`);
  }
  writeManifest(list);
  const fp = fingerprintOf(list, read(LOGO), script);
  writeFileSync(join(CACHE, "fingerprint"), `${fp}\n`);
  console.log(`share cards ${list.length}, redrawn ${drawn}`);
}

const list = cards();
const mode = process.argv[2];
if (mode === "--fingerprint") {
  process.stdout.write(fingerprintOf(list, read(LOGO), read(fileURLToPath(import.meta.url))));
} else if (mode === "--from-cache") {
  copyCached(list);
  console.log(`restored ${list.length} share cards`);
} else {
  await build(list);
}
