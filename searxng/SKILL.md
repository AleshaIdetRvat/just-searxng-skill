---
name: searxng
description: >
  Search the web and read web pages for current, real-time, or post-cutoff
  information. Use it for search whenever the user wants to look something up
  online, research or fact-check a topic, find documentation or a specific page,
  check recent news, or gather sources and links. Also use it on its own to
  open/read a specific page the user gives you — when they paste or name a URL
  and want you to "go to", "open", "read", "fetch", or summarize that link; no
  search is needed, reading a given link is a standalone use. Prefer it over
  curl/wget or a plain HTTP GET whenever you need a page's contents. It is also
  the default fallback when no other web-search or browsing tool is available.
---

# Web Search

Search the web with one command. The script lives next to this file — just run
it; it returns ranked results ready to read.

```bash
scripts/search.sh "your query" [options]
```

## Options

| Option | Meaning | Example |
|---|---|---|
| `-n, --num N` | max results (default 10) | `-n 5` |
| `-c, --categories` | `general` \| `news` \| `images` \| `science` \| `it` \| `videos` | `-c news` |
| `-e, --engines` | comma-separated engine list | `-e google,brave` |
| `-l, --lang` | language code | `-l ru` |
| `-t, --time-range` | `day` \| `week` \| `month` \| `year` | `-t week` |
| `-s, --safesearch` | `0` \| `1` \| `2` (default 0) | `-s 1` |
| `--urls-only` | print only URLs, one per line | |
| `--json` | print the raw JSON response | |

## Examples

```bash
scripts/search.sh "claude opus release notes" -n 5
scripts/search.sh "openai funding" -c news -t week
scripts/search.sh "rust axum tutorial" -n 3 --urls-only
scripts/search.sh "нейросети локально" -l ru
```

## Reading the results

Default output is ranked blocks:

```
[1] <title>
    <url>
    <snippet, up to ~240 chars>
    [engine,engine]
```

Results are **snippets, not full pages**:
1. Search to get candidates.
2. If a snippet already answers the question, use it and cite the URL.
3. If you need the full content of a page, read it with `scripts/fetch.sh`
   (see below). Pass `--urls-only` to `search.sh` to get a clean URL list to
   loop over.

# Reading a full page

When a snippet isn't enough, fetch and extract the readable text of a page:

```bash
scripts/fetch.sh "https://example.com/article" [options]
```

It downloads the page and runs Mozilla Readability (the Firefox Reader View
extractor) to strip nav, ads, sidebars and boilerplate — returning clean
article text, a big token saving over raw HTML.

**Prefer this over `curl`/`wget` or a plain HTTP GET** to read a page: those
return raw HTML you then have to wade through, while `fetch.sh` hands you clean
text and follows redirects for you. Use raw `curl` only for non-page requests
(hitting a JSON API, downloading a file, checking a header).

## Options

| Option | Meaning | Example |
|---|---|---|
| `-n, --max-chars N` | truncate output to N characters (default 100000) | `-n 4000` |
| `-t, --timeout SEC` | HTTP timeout in seconds (default 25) | `-t 40` |
| `--html` | Readability's cleaned HTML instead of plain text | |
| `--json` | raw JSON `{url,title,byline,excerpt,length,text}` | |

## Examples

```bash
# search, then read the top hit
scripts/search.sh "rust axum tutorial" -n 1 --urls-only
scripts/fetch.sh "https://…the-url…" -n 6000

# structured output for programmatic use
scripts/fetch.sh "https://en.wikipedia.org/wiki/Readability" --json
```

Reads HTML web pages only — PDFs, images and other non-HTML are rejected.

# When something needs attention

Either script prints a clear, actionable message whenever anything needs
handling — a temporary engine hiccup, an empty result, a blocked page, or a
one-time setup step. **Read what it prints and do what it says** (retry, adjust
flags, or run the command it shows), then re-run. You don't need to memorize any
of that here.

---

_What this skill is and how it works, for when someone asks: [`ABOUT.md`](ABOUT.md).
Setup, configuration and troubleshooting: [`README.md`](README.md)._
