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
   works from a file, and the pages need no server. The recorded sessions
   need a server, and from a file the landing page shows a GIF in their
   place.
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
5. To try the live paw of the landing page and the how-to guides, build the
   pod image, build the site with it, and serve the site:

   ```sh
   nix build .#paw-pod -o pod
   PAW_POD=pod tools/website/build.sh /tmp/paw-site
   python3 web/browserpod/serve.py /tmp/paw-site/site 8000
   ```

   Open `http://127.0.0.1:8000` in Chromium and press "Try paw". The
   browser then loads BrowserPod from browserpod.io. Without `PAW_POD`, the
   button says that paw for the browser isn't on this copy of the pages.

Each page has a "Suggest an edit" link to its file on GitHub. `nix flake
check` builds the site too, so a broken link fails the check.

If the build fails with `BROKEN`, the line names the page and the link that
reaches nothing. Fix the link in the Markdown file.

## Publish the website on GitHub Pages

1. To build the same site that GitHub publishes, run `nix build .#website-live`.
2. On GitHub, open the repository's **Settings → Pages**. Under **Build and
   deployment**, set **Source** to **GitHub Actions**.
3. Open **Actions → Docs and Pages**, choose **Run workflow**, and select
   `main`. GitHub publishes the same files that pass the browser checks.
   Pull requests can run the checks but can't publish the site.
4. Open the site from the **Publish the website** job. Search for a page,
   play the recorded session, then press **Try paw** and play the song.
   If the browser checks fail, open **Live website** and download
   `browser-results` from **Artifacts** to see the reports and screenshots.
