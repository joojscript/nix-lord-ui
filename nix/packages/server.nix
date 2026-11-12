{
  lib,
  stdenv,
  lordosSrc,
  version,
  pkg-config,
  wayland,
  wayland-scanner,
  wayland-protocols,
  libxkbcommon,
  libxcrypt,
  mesa,
  libgbm,
  libglvnd,
  openssl,
  srtp,
  usrsctp,
  clang,
}:

# lord-server, the from-scratch LordOS display server / Wayland compositor (C),
# plus its helper daemons (lord-sessiond, lord-netperm, lord-fand, ...).
#
# Builds the Makefile's default target. Feature detection is pkg-config driven:
#   GPU=1       (mesa gbm/egl/glesv2 present)   -> hardware compositing path
#   SESSIOND=1  (openssl + libsrtp2 + usrsctp)  -> login/session daemon
#   BPF=1       (clang present)                 -> per-app network permissions
# RELEASE is left at 0 so the server runs the unsigned bundle in DEVELOPMENT
# code-signing state. Media/doc/ocr helpers auto-disable (their -dev libs are
# intentionally absent) to keep the closure lean.
stdenv.mkDerivation {
  pname = "lord-server";
  inherit version;

  src = lordosSrc;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    clang
  ];

  buildInputs = [
    wayland
    libxkbcommon
    libxcrypt
    mesa
    libgbm
    libglvnd
    openssl
    srtp
    usrsctp
  ];

  # The Makefile hardcodes Debian's wayland-protocols location; point it at the
  # Nix one. wayland-scanner itself comes from nativeBuildInputs.
  makeFlags = [
    "WLPROTO=${wayland-protocols}/share/wayland-protocols"
  ];

  # lord-netperm's cgroup BPF programs are built with `clang -target bpf`, which
  # rejects the cc-wrapper's -fzero-call-used-regs=used-gpr hardening flag. The
  # BPF target has no use for it; drop it for this derivation.
  hardeningDisable = [ "zerocallusedregs" ];

  enableParallelBuilding = true;

  # The desktop-essential targets. We deliberately skip the optional helpers
  # that `all` also pulls in — RDP (needs FreeRDP), the VM guest agent (needs a
  # static libc), TTS, the web-view helper, mail/sql/sftp — so the first-class
  # desktop (compositor, shell, terminal, files, login/session, networking,
  # per-app firewall, fan control, secret vault) builds cleanly with a lean
  # closure. They can be added back behind options later.
  lordTargets = [
    "build/lord-server"
    "build/lord-sessiond"
    "build/lord-netd"
    "build/lord-netperm"
    "build/lord-fand"
    "build/lord-pkexec"
    "build/lord-vault"
    "build/lordos-firstrun"
    "build/lord-claude-status"
  ];

  buildPhase = ''
    runHook preBuild
    make -C server -j"$NIX_BUILD_CORES" $makeFlags $lordTargets
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/lordos/bin"
    for f in server/build/lord-server server/build/lord-* server/build/lordos-*; do
      [ -f "$f" ] && [ -x "$f" ] || continue
      install -m 0755 "$f" "$out/lib/lordos/bin/$(basename "$f")"
    done

    # A convenience top-level symlink for `lord-server` on PATH, though the
    # runtime resolves ../themes and ../assets relative to this bin dir.
    mkdir -p "$out/bin"
    ln -s ../lib/lordos/bin/lord-server "$out/bin/lord-server"

    runHook postInstall
  '';

  meta = {
    description = "LordOS display server and Wayland compositor (lord-server) and helper daemons";
    homepage = "https://lordos.org";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "lord-server";
  };
}
