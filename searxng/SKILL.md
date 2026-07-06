---
name: searxng
description: >
  Search the web for current, real-time, or post-cutoff information. Use
  whenever the user wants to look something up online, research or fact-check a
  topic, find documentation or a specific page, check recent news or releases,
  gather sources and links, or answer anything that needs fresh external
  information rather than the model's own memory — and as the default fallback
  when no other web-search or browsing tool is available. Returns ranked web
  results (title, URL, snippet).
argument-hint: "\"<search query>\" [-n N] [-c category] [-e engines] [-l lang] [-t time-range]"
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
3. If you need the full content, fetch the URL (pass `--urls-only` to get a
   clean list to loop over).

## When something needs attention

The script prints a clear, actionable message whenever anything needs handling —
a temporary engine hiccup, an empty result, or a one-time setup step. **Read
what it prints and do what it says** (retry, adjust flags, or run the command it
shows), then re-run the search. You don't need to memorize any of that here.

---

_What this skill is and how it works, for when someone asks: [`ABOUT.md`](ABOUT.md).
Setup, configuration and troubleshooting: [`README.md`](README.md)._
