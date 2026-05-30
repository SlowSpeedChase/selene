# Research: Excalidraw + ExcaliBrain for a "Knowledge Constellation" in Obsidian

**Date:** 2026-05-29
**Status:** Research (input to design doc)
**Question owner:** Chase
**Method:** Deep-research harness — 5 search angles, 20 sources fetched, 87 claims extracted, 25 adversarially verified (3-vote), 24 confirmed / 1 refuted.

---

## TL;DR

A first-prototype navigable "knowledge constellation" inside Obsidian on a Mac is **low-effort and achievable**, because **ExcaliBrain already renders exactly the thing we want**: a live, auto-laid-out, **read-only** graph derived from each note's links / Dataview fields / tags / YAML, recomputed from Obsidian's metadata cache on every navigation. Because the live view is read-only and recomputed, **Selene's scheduled note regeneration can never clobber it** — there is nothing hand-drawn in the live graph to overwrite.

The two harder asks are only partially met:

1. **Programmatic Excalidraw generation works, but the annotation conflict is REAL on that path.** Selene can emit `.excalidraw`/`.excalidraw.md` files (documented JSON schema; LZ-String-compressed embedded JSON), and those files can transclude/wikilink real notes. But there is **no merge/layering mechanism** to protect hand-drawn marks when a scheduled job rewrites the file. Plus a hard operational gotcha: **`ExcalidrawAutomate` runs only inside Obsidian's plugin runtime — a headless Selene workflow cannot `import` it** and must emit the file JSON itself.
2. **True semantic zoom does not exist in Obsidian.** Neither Excalidraw nor Canvas morphs element *content* with zoom. The closest is Advanced Canvas "Variable Breakpoints" — binary hide/unrender by zoom (LOD-by-hiding), not content substitution.

**Recommended prototype path:** drive the constellation through **ExcaliBrain** (no file generation, zero annotation conflict); have Selene only write Dataview fields/links into the notes it already generates to shape the graph. A **native (non-Obsidian) build is forced only if** we require true content-morphing semantic zoom, or a single artifact that mixes user-persistent annotation with scheduled regeneration.

---

## Q1 — ExcaliBrain: what it renders & navigation

**It builds a LIVE, auto-laid-out, effectively read-only graph** from each note's links, Dataview fields, tags, and YAML front-matter, via Obsidian's metadata cache. The Excalidraw plugin is just its rendering engine. The live view's save is explicitly disabled in source (`Scene.ts`: `//disable saving`, `//hack to prevent excalidraw from saving the changes`) — confirming it is recomputed, not persisted. **Regenerating the underlying notes only changes inferred relationships; it never destroys user work.** *(Confidence: high — README + detailed spec + plugin source.)*

**Navigation affordances (the "fly-through"):**
- **Click-to-recenter** on any node.
- **Five relationship types** around the center: Children, Parents, Friends, Other Friends (lateral/right), Siblings.
- Relationships inferred automatically (**forward-link = child, backlink = parent**) or set explicitly via Dataview fields (e.g. `Author:: [[Isaac Asimov]]`).
- **Back/forward navigation history**, a **force-refresh/reindex** button, and a **workspace-sync toggle** (v0.2.7).

*(Confidence: high — README + releases.)*

**Limitations:**
- **Hard dependency on Dataview + Excalidraw** plugins; a past Dataview API change broke ExcaliBrain startup entirely — **version-pin and test after updates**.
- Algorithmic grid/directional layout — **no manual node dragging** in the live view.
- Persistent manual annotation is a **separate one-way "Take Snapshot"** command: it forks the current live graph into a static Excalidraw drawing stored as its own file, which you then annotate. The live graph keeps regenerating. **Annotation and live-regeneration are cleanly separated and never collide.**
- **Performance ceiling unknown** at Selene's real note volume (recomputes from metadata cache on each navigation) — see Open Questions.

> **Refuted claim (0-3):** the specific compass layout "Parents=North, Children=South, Friends=West, Next=East" is *not* accurate — that came from AI-flavored spec prose. The real model is the relationship-ring set above.

---

## Q2 — Programmatic Excalidraw generation & the regeneration conflict

**Generation is possible.** The `.excalidraw` JSON has a stable, documented top-level schema — `type`, `version`, `source`, `elements`, `appState`, `files` — supporting the element types a node-link graph needs (rectangles/ellipses/diamonds, text, lines/arrows, labelled arrows/text containers, frames as ID-referenced containers). The Excalidraw package exposes `convertToExcalidrawElements()` to build valid elements from simplified skeletons. **Caveat: this skeleton API is officially beta, "subject to change before stable."** *(Confidence: high — official Excalidraw docs.)*

**Obsidian storage format.** Since plugin v1.2.0, drawings are stored as **Markdown (`.excalidraw.md`) with embedded JSON, LZ-String/Base64-compressed by default**. Legacy pure-JSON `.excalidraw` is supported. To hand-edit/emit plaintext JSON you must enable **"Decompress Excalidraw JSON in Markdown View."** *(Confidence: high.)*

**Linking to real notes works.** A generated constellation node can transclude (`![[myfile#^blockref]]`, `![[myfile#section]]`) or wikilink (`[[My file|Alias]]`) actual vault notes, and those links appear in the target note's backlinks. *(Confidence: high.)*

**🔴 Operational gotcha for Selene:** `ExcalidrawAutomate` (the `ea.addRect/addText/await ea.create()` API) **runs inside Obsidian's plugin runtime and is NOT importable as a standalone Node module.** A headless Selene background workflow therefore **cannot call `ea.create()`** — it must either (a) write the compressed/plaintext `.excalidraw.md` JSON itself, or (b) run inside Obsidian (ScriptEngine/Templater). *(Confidence: high.)*

**🔴 The regeneration-vs-annotation conflict is REAL on this path.** The plugin documents **no merge, layering, locking, or conflict-resolution** mechanism to protect hand-drawn marks when a drawing file is rewritten on a schedule. (A `create({templatePath})` base-layer feature exists, but it only stacks generated elements over a *separate template* when creating a *new* drawing — it does **not** preserve marks a user adds to an already-generated file that the next run overwrites.) *(Confidence: medium — README-scoped, 2-1 vote.)*

---

## Q3 — Semantic zoom / level-of-detail

**Neither Excalidraw nor Obsidian Canvas supports TRUE semantic zoom** (element content morphing/substituting with zoom level). Zoom is **geometric**. *(Confidence: high.)*

The **closest in-Obsidian behavior** is the **Advanced Canvas** plugin's **"Variable Breakpoints"**: a node's content is **unrendered once zoom passes a configured threshold** (CSS `--variable-breakpoint`, e.g. `0.5`; zoom range `1` to `-4`). This is **binary hide/show LOD** (performance-oriented), **not** content summarization or auto-collapse-by-zoom.

**ExcaliBrain's "levels" are the relationship hierarchy, not viewport-aware detail.** Its spec has zero mentions of semantic zoom/LOD/viewport. So ExcaliBrain gives **containers-and-detail via *navigation*** (click-to-recenter through relationship rings) — **not** in-place level-of-detail as you zoom.

**Verdict on "containers AND detail levels":** the *navigation*-based version (descend by clicking) is real and usable. The *zoom*-based version (cards swapping content as you zoom) is **not available in Obsidian at all** and would force a native build.

---

## Q4 — Lowest-effort prototype path & native escape hatch

**Lowest-effort prototype (recommended):**
1. Install **ExcaliBrain** + its hard deps **Dataview** and **Excalidraw** in the dev vault.
2. Have **Selene emit Dataview fields / links / tags** into the notes it already generates, to shape the parent/child/friend graph.
3. Open ExcaliBrain and **fly through** by clicking to recenter.

This requires **no file generation** and has **no annotation conflict**. Generating `.excalidraw.md` files yourself is a heavier path, warranted only if you need a fixed bespoke layout the auto-layout can't express.

**A native (non-Obsidian) build is forced only if** you require either:
- **true content-substitution semantic zoom** (cluster label → note titles → note body as you zoom), or
- **a single artifact that mixes user-persistent annotation with scheduled regeneration** (no in-Obsidian merge mechanism exists).

This ties directly into the already-designed **Lumen** native port (reads Selene's output read-only).

---

## Caveats (source quality / time-sensitivity)

1. `convertToExcalidrawElements` / ElementSkeleton API is **beta** — risky for a long-lived production workflow.
2. ExcaliBrain's `EXCALIBRAIN_DETAILED_SPECIFICATION.md` has AI/marketing-flavored prose; the load-bearing read-only/snapshot facts were re-confirmed against actual source (`Scene.ts`, `en.ts`), so they hold — but the compass-layout claim from that doc was **refuted**.
3. "No merge/layering" is README-scoped (2-1 vote). Accurate phrasing: *no mechanism protects hand-drawn marks on an existing file from being overwritten by scheduled regeneration.*
4. **`ExcalidrawAutomate` is not a standalone Node module** — headless Selene must emit file JSON itself or run inside Obsidian.
5. ExcaliBrain's **hard Dataview dependency has broken on version bumps** — pin & test.
6. `.excalidraw.md` embedded JSON is **LZ-String-compressed by default** — a generator must emit the compressed block or the file must be in plaintext/decompressed mode.

---

## Open Questions (carry into design)

1. **Headless generation format:** is there a stable non-Obsidian way to emit the LZ-String-compressed `.excalidraw.md` block, or must Selene write plaintext-mode files and rely on the user keeping "Decompress JSON" enabled? (Pin the compression lib + frontmatter format before building any generator.)
2. **Hybrid two-file annotation:** could Selene regenerate a base constellation file while user annotations live in a separate overlay layer never rewritten? Docs hint at template base-layers but confirm no non-destructive overlay-on-regenerate workflow.
3. **Performance ceiling:** ExcaliBrain's practical node-count/depth limit at Selene's real note volume during click-to-recenter — unquantified by any source.
4. **Native semantic-zoom stack:** if true zoom-morphing is required, what's the minimal macOS stack (SwiftUI/Canvas or web-canvas reading Selene's SQLite/vault read-only)? Ties into Lumen; was out of scope for these Obsidian-focused sources.

---

## Key sources (primary)

- ExcaliBrain: [repo](https://github.com/zsviczian/excalibrain) · [spec](https://github.com/zsviczian/excalibrain/blob/master/EXCALIBRAIN_DETAILED_SPECIFICATION.md) · [releases](https://github.com/zsviczian/excalibrain/releases)
- Excalidraw plugin: [repo/README](https://github.com/zsviczian/obsidian-excalidraw-plugin/blob/master/README.md) · [Automate API](https://zsviczian.github.io/obsidian-excalidraw-plugin/API/introduction.html)
- Excalidraw core: [JSON schema](https://docs.excalidraw.com/docs/codebase/json-schema) · [ElementSkeleton](https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/excalidraw-element-skeleton)
- Advanced Canvas (semantic-zoom substitute): [repo/README](https://github.com/Developer-Mike/obsidian-advanced-canvas/blob/main/README.md)
