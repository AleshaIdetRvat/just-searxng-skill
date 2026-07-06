#!/usr/bin/env node
//
// extract.mjs — turn raw HTML (read from stdin) into clean, readable text.
//
// Uses Mozilla Readability (the same extractor Firefox Reader View uses) on a
// linkedom DOM to strip nav, ads, sidebars and boilerplate, leaving the main
// article. If the page isn't an article (a search/list page, an app shell),
// it falls back to the page's stripped text so the caller still gets content.
//
// Called by fetch.sh; not meant to be run directly. Reads HTML on stdin.
//
//   node extract.mjs --url <url> --mode <text|html|json> --max-chars <n>
//
import { parseHTML } from "linkedom";
import { Readability } from "@mozilla/readability";

function arg(name, def = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : def;
}

const url = arg("url", "");
const mode = arg("mode", "text"); // text | html | json
const maxChars = parseInt(arg("max-chars", "100000"), 10) || 0;

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (c) => (data += c));
    process.stdin.on("end", () => resolve(data));
    process.stdin.on("error", reject);
  });
}

function clip(text, n) {
  text = text || "";
  if (!n || text.length <= n) return text;
  return text.slice(0, n) + "\n\n[truncated — raise --max-chars to see more]";
}

function tidy(text) {
  return (text || "")
    .replace(/[ \t ]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

let html = await readStdin();
if (!html.trim()) {
  process.stderr.write("ERROR: empty document — nothing to extract.\n");
  process.exit(4);
}

// Give Readability a base href so relative links resolve to absolute URLs.
if (url && !/<base\s/i.test(html)) {
  const baseTag = `<base href="${url.replace(/"/g, "&quot;")}">`;
  html = /<head[^>]*>/i.test(html)
    ? html.replace(/<head[^>]*>/i, (m) => m + baseTag)
    : baseTag + html;
}

const { document } = parseHTML(html);

let article = null;
try {
  article = new Readability(document).parse();
} catch {
  article = null;
}

if (mode === "json") {
  const out = article
    ? {
        url,
        title: article.title || "",
        byline: article.byline || null,
        excerpt: article.excerpt || null,
        length: article.length || 0,
        text: clip(tidy(article.textContent), maxChars),
      }
    : {
        url,
        title: document.title || "",
        byline: null,
        excerpt: null,
        length: 0,
        fallback: true,
        text: clip(tidy(document.body?.textContent || ""), maxChars),
      };
  process.stdout.write(JSON.stringify(out, null, 2) + "\n");
  process.exit(0);
}

if (!article) {
  // Not a readable article (search page, app shell, etc.) — return stripped text.
  const text = clip(tidy(document.body?.textContent || ""), maxChars);
  if (!text) {
    process.stderr.write(
      "ERROR: could not extract readable content from this page.\n"
    );
    process.exit(4);
  }
  process.stderr.write(
    "Note: this page is not a readable article; returning stripped page text.\n"
  );
  process.stdout.write(text + "\n");
  process.exit(0);
}

if (mode === "html") {
  const head = article.title ? `<h1>${article.title}</h1>\n` : "";
  process.stdout.write(head + clip(article.content || "", maxChars) + "\n");
  process.exit(0);
}

// default: plain readable text with a small header
const parts = [];
if (article.title) parts.push(article.title);
if (article.byline) parts.push(article.byline);
if (url) parts.push(url);
parts.push("");
parts.push(clip(tidy(article.textContent), maxChars));
process.stdout.write(parts.join("\n") + "\n");
