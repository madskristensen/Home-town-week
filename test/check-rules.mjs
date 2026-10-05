import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const rules = JSON.parse(fs.readFileSync(path.join(root, "test/fixtures/rules.json"), "utf8"));
const pwa = fs.readFileSync(path.join(root, "_includes/pwa.html"), "utf8");
const map = fs.readFileSync(path.join(root, "_includes/playground-map.html"), "utf8");

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
  sliceFn(map, "queryText", "encodeQuery")
].join("\n");
const queryText = new Function(`${mapSource}\nreturn queryText;`)();

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
console.log(`browser rules ok (${rules.buckets.length} buckets, ${rules.maps.length} maps)`);
