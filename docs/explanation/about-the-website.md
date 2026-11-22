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
omit goes under "More pages". Each extension has a part of its own.

Then mdBook builds the pages. After that, a link checker reads the built
pages. A link or an anchor that reaches nothing fails the build. A link to a
file that is not a page, such as a source file or the example
configuration, goes to the file on GitHub.

`nix build .#website` runs the same script in a sandbox with no network, and
the result is a folder of static files.

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

The next tickets of the website (the landing page, the structure of the
pages, a paw in the page, publishing) build on this output.

See [How to preview the manual as a website](../how-to/preview-the-manual-as-a-website.md).
