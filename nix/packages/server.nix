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

  enableParallelBuilding = true;

  buildPhase = ''
    runHook preBuild
    make -C server -j"$NIX_BUILD_CORES" $makeFlags
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
