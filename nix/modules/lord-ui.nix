{ self }:
{ config, lib, pkgs, ... }:

let
  cfg = config.services.lord-ui;
  defaultPackage = self.packages.${pkgs.stdenv.hostPlatform.system}.lord-ui;
  ttyUnit = n: "${n}@tty${toString cfg.tty}.service";
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
        login screen asks for a user and password (verified against /etc/shadow).
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

    # lord-server composites with Mesa (GBM/EGL/GLES2) when a GPU is present;
    # libglvnd finds the driver through /run/opengl-driver, which this populates.
    hardware.graphics.enable = true;

    # Native system apps talk to the session bus and polkit; lord-sessiond and
    # lord-server open DRM/KMS and evdev through the udev-provided device nodes.
    services.dbus.enable = true;
    security.polkit.enable = true;
    services.udev.enable = true;

    # The login screen runs as a dedicated, unprivileged system user
    # (lord-sessiond execs `lord-server --greeter --user lordos-greeter`). It is
    # declared here so lord-sessiond never has to create it with useradd (which
    # does not work on NixOS).
    users.groups.lordos-greeter = { };
    users.users.lordos-greeter = {
      isSystemUser = true;
      group = "lordos-greeter";
      home = "/var/lib/lordos-greeter";
      createHome = true;
      shell = "${pkgs.shadow}/bin/nologin";
      description = "LordOS login screen";
      # The greeter's lord-server touches the GPU render node and input devices.
      extraGroups = [ "video" "render" "input" ];
    };

    # LordOS state and config trees.
    systemd.tmpfiles.rules = [
      "d /var/lib/lordos 0755 root root -"
      "d /var/lib/lordos-greeter 0700 lordos-greeter lordos-greeter -"
      "d /etc/lordos 0755 root root -"
    ];

    environment.etc."lordos/session.conf" = lib.mkIf (cfg.autologinUser != null) {
      text = "AUTOLOGIN=${cfg.autologinUser}\n";
      mode = "0644";
    };

    # lord-sessiond owns the VT; keep a text getty off it.
    systemd.services.${lib.removeSuffix ".service" (ttyUnit "getty")}.enable = false;
    systemd.services.${lib.removeSuffix ".service" (ttyUnit "autovt")}.enable = false;

    # The "display manager": lord-sessiond on tty1, mirroring upstream's
    # lordos.service. It opens the video card and input as root, then runs each
    # session's lord-server as the logged-in user (dropping privileges).
    systemd.services.lordos = {
      description = "LordOS (lord-sessiond: login screen, sessions and desktop)";
      after = [ "systemd-user-sessions.service" "systemd-logind.service" ];
      conflicts = [ (ttyUnit "getty") ];
      wantedBy = [ "graphical.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/lib/lordos/bin/lord-sessiond";
        ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
        TTYPath = "/dev/tty${toString cfg.tty}";
        TTYReset = "no";
        TTYVHangup = "yes";
        StandardInput = "null";
        StandardOutput = "journal";
        StandardError = "journal";
        # User sessions survive a restart of the supervisor.
        KillMode = "process";
        # lord-sessiond splits the cgroup tree per session/app.
        Delegate = "yes";
        RuntimeDirectory = "lordos";
        RuntimeDirectoryPreserve = "yes";
      };
    };

    # Boot straight to the LordOS seat.
    systemd.defaultUnit = lib.mkDefault "graphical.target";
  };
}
