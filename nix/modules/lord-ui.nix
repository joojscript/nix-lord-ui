{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.lord-ui;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.lord-ui;
  lordDir = "${cfg.package}/lib/lordos";
in
{
  options.services.lord-ui = {
    enable = lib.mkEnableOption "the LordOS desktop (lord-server + lord-sessiond)";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "nix-lord-ui.packages.\${system}.lord-ui";
      description = "The assembled LordOS desktop tree (lord-server, helpers, themes and assets).";
    };

    autologinUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "joao";
      description = ''
        If set, lord-sessiond logs this user in automatically (writes
        AUTOLOGIN=<user> to /etc/lordos/session.conf). If null, the LordOS
        login screen asks for a user and password.
      '';
    };

    tty = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "Virtual terminal lord-sessiond runs the desktop on.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    # lord-server composites with Mesa (GBM/EGL/GLES2) when a GPU is present.
    hardware.graphics.enable = true;

    # Session, login screen and seat management all live inside lord-sessiond;
    # it opens DRM/KMS and evdev directly, so it needs the udev-provided device
    # nodes, dbus and polkit for the native system apps, and a runtime dir.
    services.dbus.enable = true;
    security.polkit.enable = true;
    services.udev.enable = true;

    # LordOS reads/writes its own state tree.
    systemd.tmpfiles.rules = [
      "d /var/lib/lordos 0755 root root -"
      "d /etc/lordos 0755 root root -"
    ];

    environment.etc."lordos/session.conf" = lib.mkIf (cfg.autologinUser != null) {
      text = "AUTOLOGIN=${cfg.autologinUser}\n";
      mode = "0644";
    };

    # lord-sessiond owns tty1; keep a text getty off it.
    systemd.services."getty@tty${toString cfg.tty}".enable = false;
    systemd.services."autovt@tty${toString cfg.tty}".enable = false;

    systemd.services.lordos = {
      description = "LordOS (lord-sessiond: login screen, sessions and desktop)";
      after = [ "systemd-user-sessions.service" "systemd-logind.service" ];
      conflicts = [ "getty@tty${toString cfg.tty}.service" ];
      wantedBy = [ "graphical.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lordDir}/bin/lord-sessiond";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        TTYPath = "/dev/tty${toString cfg.tty}";
        TTYReset = "no";
        TTYVHangup = "yes";
        StandardInput = "null";
        StandardOutput = "journal";
        StandardError = "journal";
        KillMode = "process";
        Delegate = "yes";
      };
    };

    # LordOS targets a graphical seat; make it the boot default.
    services.displayManager.enable = lib.mkDefault false;
    systemd.defaultUnit = lib.mkDefault "graphical.target";
  };
}
