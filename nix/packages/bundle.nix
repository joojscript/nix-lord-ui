{
  lib,
  buildNpmPackage,
  lordosSrc,
  version,
}:

# Bundles every LordOS theme (the shell + SDK + runtime + native apps, written
# in React) into the single QuickJS .js files lord-server loads, and emits the
# matching code-manifest.json. The manifest is left unsigned, which puts
# lord-server in its DEVELOPMENT code-signing state (hashes still enforced); we
# never build with RELEASE=1, which would refuse that state.
buildNpmPackage {
  pname = "lord-ui-bundle";
  inherit version;

  src = lordosSrc;

  # Pure JS/esbuild build with vendored React deps; no network at build time.
  npmDepsHash = "sha256-T1dCo70IOMe8nHoDUfApxez64uzd1lzAkMpSKmDUfBE=";

  # package.json "build" = `node tools/build-theme.mjs` (all themes).
  npmBuildScript = "build";

  # The theme bundler writes its outputs in place (themes/<t>/theme.bundle.js,
  # assets/app-host.bundle.js, assets/sysapps/*, code-manifest.json). Collect
  # the runtime root lord-server reads: <root>/{themes,assets,code-manifest.json}.
  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r themes "$out/themes"
    cp -r assets "$out/assets"
    cp code-manifest.json "$out/code-manifest.json"

    runHook postInstall
  '';

  dontFixup = true;

  meta = {
    description = "LordOS React themes, SDK, runtime and native apps bundled for QuickJS";
    homepage = "https://lordos.org";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
