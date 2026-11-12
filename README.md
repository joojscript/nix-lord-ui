# nix-lord-ui

A Nix/NixOS port of the [LordOS](https://lordos.org) desktop — `lord-server`,
its React-on-QuickJS UI engine, and the native apps — packaged as a flake and a
NixOS module, in the spirit of `nix-ryoku`.

LordOS ships its own desktop environment instead of GNOME/KDE: a from-scratch
display server and Wayland compositor written in C (`lord-server`) that talks to
DRM/KMS and evdev directly (no libdrm, no libinput, no X11), with the shell and
native apps written in React running on a vendored QuickJS. This flake builds
that stack from the upstream [LordOS](https://github.com/lordbasex/LordOS)
source and wires it into NixOS.

## Status

Early port. The desktop runs in LordOS's **DEVELOPMENT** code-signing state: the
JS bundle is rebuilt here and its `code-manifest.json` is left unsigned (hashes
are still enforced; `RELEASE=1`, which would reject an unsigned bundle, is never
used). System-management panels in the native apps that shell out to Debian
tooling (`dpkg`, `useradd`, `systemctl` at Debian paths) are expected to be
degraded on NixOS; the compositor, shell, terminal and files are the focus.

## Layout

- `flake.nix` — inputs (nixpkgs, pinned LordOS source) and outputs.
- `nix/packages/bundle.nix` — the React themes/SDK/apps bundled for QuickJS (`node tools/build-theme.mjs`).
- `nix/packages/server.nix` — `lord-server` and helper daemons (`make -C server`).
- `nix/packages/default.nix` — the assembled `lib/lordos/{bin,themes,assets}` tree.
- `nix/modules/lord-ui.nix` — the NixOS module (`services.lord-ui`).

## Usage

```nix
{
  inputs.nix-lord-ui.url = "github:joojscript/nix-lord-ui";

  # in your NixOS configuration:
  imports = [ inputs.nix-lord-ui.nixosModules.default ];
  services.lord-ui = {
    enable = true;
    autologinUser = "youruser"; # omit for the LordOS login screen
  };
}
```

## Packages

- `packages.<system>.lord-ui` (default) — the assembled desktop tree.
- `packages.<system>.lord-server` — just the C compositor + helper daemons.
- `packages.<system>.lord-ui-bundle` — just the JS themes/assets bundle.

## Credits

LordOS is © the LordOS authors, GPL-3.0. This repository only packages it for
Nix; it contains no LordOS source, which is fetched from upstream at build time.
