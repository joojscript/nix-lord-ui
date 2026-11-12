{
  description = "Nix packaging for the LordOS desktop (lord-server) — a self-hosted port of the LordOS display server, UI engine and native apps as a NixOS module.";

  inputs = {
    # Match the common consumer channel so the store is shared with typical
    # NixOS 26.05 hosts. The port is nixpkgs-version sensitive (freerdp3,
    # wayland, mesa), so it is pinned here and locked by flake.lock.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Upstream LordOS. Vendored QuickJS/stb/monocypher/nanosvg live in-tree, so
    # this single source is all the build needs. Pinned by flake.lock.
    lordos = {
      url = "github:lordbasex/LordOS";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, lordos }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      pkgsFor = system: import nixpkgs { inherit system; };

      packagesFor =
        system:
        let
          pkgs = pkgsFor system;
          version = "0.8.8.7";
        in
        rec {
          # The React themes + native apps bundled for QuickJS, plus assets and
          # the (unsigned, DEVELOPMENT-state) code-manifest.json.
          lord-ui-bundle = pkgs.callPackage ./nix/packages/bundle.nix {
            inherit version;
            lordosSrc = lordos;
          };

          # The lord-server compositor and its helper daemons (C).
          lord-server = pkgs.callPackage ./nix/packages/server.nix {
            inherit version;
            lordosSrc = lordos;
          };

          # The assembled lib/lordos tree that lord-server expects at runtime.
          lord-ui = pkgs.callPackage ./nix/packages/default.nix {
            inherit version lord-server lord-ui-bundle;
          };

          default = lord-ui;
        };
    in
    {
      packages = forAllSystems packagesFor;

      overlays.default = final: _prev: {
        lord-ui = (packagesFor final.stdenv.hostPlatform.system).lord-ui;
        lord-server = (packagesFor final.stdenv.hostPlatform.system).lord-server;
      };

      # NixOS module. By default it uses the lord-ui package built from this
      # flake's pinned nixpkgs, keeping the desktop reproducible regardless of
      # the host channel.
      nixosModules.default = import ./nix/modules/lord-ui.nix {
        inherit self;
      };
      nixosModules.lord-ui = self.nixosModules.default;

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
