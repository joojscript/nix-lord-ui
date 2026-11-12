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

      # A throwaway VM for bringing the desktop up without touching a real host.
      # Build: nix build .#nixosConfigurations.test-vm.config.system.build.vm
      # Run:   ./result/bin/run-lord-ui-vm-vm
      nixosConfigurations.test-vm = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.default
          ({ pkgs, lib, modulesPath, ... }: {
            imports = [ "${modulesPath}/virtualisation/qemu-vm.nix" ];

            system.stateVersion = "26.05";
            networking.hostName = "lord-ui-vm";

            users.users.lord = {
              isNormalUser = true;
              password = "lord";
              extraGroups = [ "wheel" "video" "render" "input" ];
            };
            users.users.root.password = "root";

            services.lord-ui = {
              enable = true;
              autologinUser = "lord";
            };

            # Give the VM a GPU path lord-server can composite on.
            virtualisation = {
              memorySize = 2048;
              cores = 2;
              qemu.options = [ "-vga virtio" ];
            };

            # Serial console (last console= wins as /dev/console) so a headless
            # boot's logs land on stdio; tty1 stays a real VT for lord-server.
            boot.kernelParams = [ "console=tty1" "console=ttyS0,115200" ];

            # Automated self-test: after the desktop has had a moment to come up,
            # report what happened on the serial console and power the VM off, so
            # a CI-style `nix run`/qemu boot yields a pass/fail without a GUI.
            systemd.services.lord-selftest = {
              description = "Report lord-ui session state, then power off";
              after = [ "lordos.service" ];
              wants = [ "lordos.service" ];
              wantedBy = [ "graphical.target" ];
              serviceConfig.Type = "oneshot";
              script = ''
                sleep 25
                exec > /dev/ttyS0 2>&1
                echo "================ LORD-UI SELFTEST ================"
                echo "## systemctl status lordos:"
                systemctl status lordos --no-pager -l || true
                echo "## lord-server processes:"
                ${pkgs.procps}/bin/ps -eo pid,user,comm,args | grep -i 'lord-server\|lord-sessiond' | grep -v grep || echo "  (none)"
                echo "## /run/lordos:"
                ls -la /run/lordos 2>&1 || true
                echo "## /dev/dri:"
                ls -la /dev/dri 2>&1 || true
                echo "## last 60 journal lines for lordos:"
                journalctl -u lordos -u lord-selftest --no-pager -n 60 || true
                echo "================ SELFTEST DONE ==================="
                systemctl poweroff
              '';
            };
          })
        ];
      };

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
