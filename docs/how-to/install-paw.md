# How to install paw with Nix

<!-- tags: installing-with-nix install -->

You can install paw from its flake on Linux with Nix and flakes. You do
not need NixOS or home-manager.

Do the steps in a checkout of paw's source, where `.` is the flake.

1. Try paw before you install it:
   - Run `nix run .` to start the terminal interface, `paw`.
   - Run `nix run .#paw-gui` to start the graphical window.
2. To build the programs without an install, run `nix build`. The
   programs are in `./result/bin`: `paw`, `paw-gui` and `paw-mcp`.
3. To install the three programs in your profile, run `nix profile install .`.
4. Run `paw` from any shell.

The graphical window starts its own kernel, which is the `paw` program next
to it, so you do not have to install anything more for it.

If the graphical window does not open on NixOS, set
`hardware.graphics.enable = true` in your system configuration, because
the window uses the OpenGL driver of the system.

To remove the programs from your profile, run `nix profile remove paw`.

## See also

- [The Nix package](../reference/nix-package.md): the outputs of the flake and what each package holds.
- [How to build and run paw from the source](build-paw-from-source.md): the dev shell, for work on paw itself.
- [About the Nix build](../explanation/about-the-nix-build.md): why the build has two layers.
