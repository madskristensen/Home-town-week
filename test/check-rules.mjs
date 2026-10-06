import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rules = JSON.parse(fs.readFileSync(path.join(root, "test/fixtures/rules.json"), "utf8"));
const pwa = fs.readFileSync(path.join(root, "_includes/pwa.html"), "utf8");
const map = fs.readFileSync(path.join(root, "_includes/playground-map.html"), "utf8");
const page = fs.readFileSync(path.join(root, "_js/page.js"), "utf8");

function sliceFn(source, startName, endName) {
  const start = source.indexOf(`function ${startName}`);
  const end = source.indexOf(`function ${endName}`);
  if (start < 0 || end < 0 || end <= start) {
    throw new Error(`could not find ${startName} before ${endName}`);
  }
  return source.slice(start, end);
}

const bucketSource = [
  sliceFn(pwa, "parseISO", "isoFromDate"),
  sliceFn(pwa, "isoFromDate", "addDays"),
  sliceFn(pwa, "addDays", "bucketLabel"),
  sliceFn(pwa, "bucketLabel", "cardLastDay")
].join("\n");
const bucket = new Function(`${bucketSource}\nreturn bucketLabel;`)();

const cities = fs.readFileSync(path.join(root, "_data/cities.yml"), "utf8")
  .split("\n")
  .map(line => line.match(/^  name: (.+)$/))
  .filter(Boolean)
  .map(match => match[1].trim());

const mapSource = [
  "var knownCities = " + JSON.stringify(cities) + ";",
  sliceFn(map, "squash", "endsWithPhrase"),
  sliceFn(map, "endsWithPhrase", "endsWithKnownCity"),
  sliceFn(map, "endsWithKnownCity", "queryText"),
  sliceFn(map, "queryText", "encodeQuery"),
  sliceFn(map, "encodeQuery", "mapsHref"),
  sliceFn(map, "mapsHref", "escapeHtml")
].join("\n");
const queryText = new Function(`${mapSource}\nreturn queryText;`)();
const mapsHref = new Function(`${mapSource}\nreturn mapsHref;`)();

// page.js points place links at the chosen map app.
const basesStart = page.indexOf("var bases = {");
const basesEnd = page.indexOf("};", basesStart);
if (basesStart < 0 || basesEnd < 0) throw new Error("could not find map app bases in page.js");
const appSource = [
  page.slice(basesStart, basesEnd + 2),
  sliceFn(page, "mapQuery", "mapHref"),
  sliceFn(page, "mapHref", "chosenApp").replace(/var picked = null;\s*$/, "")
].join("\n");
const mapHref = new Function(`${appSource}\nreturn mapHref;`)();

for (const row of rules.buckets) {
  const label = bucket(row.date, row.today);
  if (label !== row.label) {
    throw new Error(`bucket ${row.date}: ${label} != ${row.label}`);
  }
}
for (const row of rules.maps) {
  const query = queryText(row.place, row.city, row.name);
  if (query !== row.query) {
    throw new Error(`map ${row.place}: ${query} != ${row.query}`);
  }
}
for (const row of rules.map_links) {
  const href = mapsHref(row.place, row.city, row.name);
  if (href !== row.href) {
    throw new Error(`map link ${row.place}: ${href} != ${row.href}`);
  }
}
for (const row of rules.map_apps) {
  const out = mapHref(row.href, row.app);
  if (out !== row.out) {
    throw new Error(`map app ${row.href} -> ${row.app}: ${out} != ${row.out}`);
  }
}
console.log(`browser rules ok (${rules.buckets.length} buckets, ${rules.maps.length} maps, ${rules.map_links.length + rules.map_apps.length} map links)`);
