# About the website

<!-- tags: website mdbook -->

The manual of paw is Markdown in the repository, and GitHub shows it well.
A website adds a search box, a sidebar that follows the contents page, and
a dark theme. The site is built from the same files, and the build never
changes them. A page is written once, for GitHub, for `:help` and for the
site.

## What the build does

`tools/website/build.sh` copies `README.md`, `AGENTS.md`, `docs/`, the
Markdown and pictures of `extensions/` and the README of each crate into a
folder with the same layout as the repository. Every relative link then
works as it does on GitHub. The script writes the sidebar from
`docs/README.md`: its `##` headings are the parts, its `###` headings are
the groups and its list items are the chapters. A page that the contents
omit goes under "More pages".

The parts follow the same order as `:help`:
tutorials, how-to guides, reference, explanation and extensions. The Lua
API reference (`docs/reference/api.md`) has a part of its own after the
reference, and each extension has a chapter in the part "Extensions", with
the pages of its `doc/` folder under it. Every page has a link to edit its
file on GitHub, and links to the previous and the next page.

The first page of the site is a landing page. It is the file
`tools/website/landing.md`, and the script copies it over `README.md` in the
staging folder only, so GitHub still shows the README of the repository.
The page uses a few lines of CSS from `tools/website/landing.css`. Facts on
the landing page come from the README and the manual, and the page follows
the plain writing rules like any other external page.

Then mdBook builds the pages. After that, a link checker reads the built
pages. A link or an anchor that reaches nothing fails the build. `nix flake check` builds the site, so it fails on the same broken links. A link to a
file that is not a page, such as a source file or the example
configuration, goes to the file on GitHub.

`nix build .#website` runs the same script in a sandbox with no network, and
the result is a folder of static files.

## Recorded sessions and a live paw

The website has two parts that move, and a reader can copy keys from both.
A recorded session plays a terminal session of paw in the page, and the
reader can pause it, go to a step and copy the keys of each step. The file
is an asciicast, which is a list of what paw wrote to the terminal and of
the keys that were typed, with their times. A scene script in
`docs/images/make` makes it, as the scripts there make the GIFs, so a
change to a view only needs the script to run again. The player,
`tools/website/paw-cast.js`, reads the few terminal sequences that paw
writes, and it is about 300 lines with no library.

A live paw runs the real terminal paw in the page, in a pod of BrowserPod,
which runs Linux programs in a browser tab. The landing page has a "Try
paw" button, and some how-to guides have a "Try the steps in your browser"
button that opens paw at the start of the guide. The pod and the page
component come from [paw in a BrowserPod pod](../../web/browserpod/README.md).
A guide asks for a live paw with an HTML comment, so GitHub and `:help`
show the page as before, and the build turns the comment into the button.
Nothing loads from BrowserPod's servers before the reader presses the
button, because BrowserPod's license doesn't allow a copy of its runtime on
another server, and a reader who only reads the page shouldn't send a
request to a third party.

The recorded sessions and the live paw need the site to come from a web
server. From a file, the landing page shows a GIF in place of the
recorded session, and the live paw doesn't start.

## The choice of generator

Four generators were compared against these needs: search, a sidebar that
follows the contents page, code highlighting, a dark theme, pictures,
relative links and anchors as GitHub makes them, a build with no network
in Nix, and speed.

| Generator | What happened |
| --- | --- |
| mdBook 0.5 | Built the 264 pages and 4762 links with 0 broken links and 0 broken anchors, in 2 seconds. One Rust program in nixpkgs. Search, six themes and a highlighter are inside it. |
| MkDocs Material 9.7 | Also builds the pages with no broken anchor, in 15 seconds. It needs Python packages. Its authors say that MkDocs 2.0 will break all plugins and theme overrides, and Material depends on it. |
| Zola | Does not follow relative links to `.md` files. Each link would need the `@/` form, which breaks the same page on GitHub. It was not built. |
| Astro Starlight | Needs a Node dependency tree with a hash, and the build needs more rewriting of the pages than the others do. It was not built. |

mdBook wins on speed, on the small number of parts and on the build in Nix.
Its costs are these.

- mdBook needs each page in `SUMMARY.md`. The build writes that file from
  `docs/README.md`, so the contents page stays the one place that lists the
  pages.
- mdBook writes `README.md` as `index.html` but links to it as
  `README.html`, and the build keeps both names.
- The highlighter has no Teal grammar. The pages use `lua` for Lua and
  Teal examples.
- The search index is 8.5 MB, and `docs/reference/api.md` is most of it.
  The browser fetches it when the reader first searches.
- A bare `<name>` in the text of `docs/reference/api.md` is read as an
  HTML tag. GitHub does the same.

The GitHub Pages workflow builds `.#website-live`, which includes the pod.
The browser checks serve the site under `/paw/`, the same path as on
GitHub Pages. GitHub Pages doesn't set the isolation headers that
BrowserPod needs, so the site uses a service worker to add them.

See [How to preview the manual as a website](../how-to/preview-the-manual-as-a-website.md).
