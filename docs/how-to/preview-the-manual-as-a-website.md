# How to preview the manual as a website

<!-- tags: website preview -->

You can build the manual as a static website and read it in a browser. The
steps assume a checkout of paw and Nix. [About the website](../explanation/about-the-website.md)
tells how the build works.

1. To build the site, run the following command. The pages are in
   `result`.

   ```sh
   nix build .#website
   ```

2. To read the pages, open `result/index.html` in a browser. The search box
   works from a file, and the pages need no server.
3. To serve the site and see a change of the build files, run the following
   command in the checkout, then open `http://127.0.0.1:3000`.

   ```sh
   nix develop -c tools/website/build.sh /tmp/paw-site serve
   ```

   Set `PORT` to use another port. The server rebuilds the pages when a
   staged file changes, but it does not copy your edits of the Markdown.
   Stop the server and run the command again after you edit a page.
4. To build without Nix, run `tools/website/build.sh /tmp/paw-site` in the
   dev shell. The pages are in `/tmp/paw-site/site`.

If the build fails with `BROKEN`, the line names the page and the link that
reaches nothing. Fix the link in the Markdown file.
