# About the SearXNG web-search skill

What this skill is and how it works — for when a person asks. An agent that just
wants to search doesn't need this file; everything operational is in
[`SKILL.md`](SKILL.md).

## What it is

A web-search tool for agents. One command returns ranked web results (title,
URL, snippet). Nothing to sign up for, nothing to configure.

## Key properties

- **No API keys, no cost, private.** Search runs through a local, self-hosted
  [SearXNG](https://docs.searxng.org) instance on `127.0.0.1` — queries are not
  sent to a paid third-party search API.
- **Aggregates many engines.** SearXNG queries Google, Bing, Brave, DuckDuckGo,
  Mojeek, Presearch and 70+ others at once, then merges and ranks the results.
- **Zero setup.** The first search auto-launches SearXNG in a local Docker or
  Podman container and reuses it afterwards. The first call takes a few seconds;
  later calls are ~1s. A human is only involved if no container runtime exists
  at all — then the script prints the exact one-time install command.
- **Snippet-first, with full-page reading on demand.** Search returns snippets,
  not full pages. When you need the full content of a page, `scripts/fetch.sh`
  downloads it and extracts clean, readable article text with Mozilla
  Readability (the Firefox Reader View extractor) — stripping nav, ads and
  boilerplate. Needs Node.js 18+; its deps install themselves on first use.

## How it works (in one line)

`scripts/search.sh` makes sure SearXNG is up — auto-starting the container via
`scripts/ensure-searxng.sh` if needed — sends one JSON search request, and
prints clean, ranked results (parsed with `jq`, or `python3` as a fallback).

## More detail

Setup, environment variables, ports, the resilient engine set, and
troubleshooting live in [`README.md`](README.md).
