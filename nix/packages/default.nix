{
  lib,
  runCommand,
  version,
  lord-server,
  lord-ui-bundle,
}:

# The runtime tree lord-server expects: a bin/ directory with the server and
# helpers, and sibling themes/ and assets/ plus code-manifest.json one level up
# (the server resolves ../themes and ../assets relative to its own binary, and
# the code-signing check reads <assets>/../code-manifest.json).
#
#   $out/lib/lordos/bin/lord-server
#   $out/lib/lordos/themes/...
#   $out/lib/lordos/assets/...
#   $out/lib/lordos/code-manifest.json
runCommand "lord-ui-${version}"
  {
    inherit version;
    passthru = { inherit lord-server lord-ui-bundle; };
    meta = {
      description = "Assembled LordOS desktop tree (lord-server + UI bundle) for NixOS";
      homepage = "https://lordos.org";
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.linux;
      mainProgram = "lord-server";
    };
  }
  ''
    mkdir -p "$out/lib/lordos"
    cp -r ${lord-server}/lib/lordos/bin "$out/lib/lordos/bin"
    cp -r ${lord-ui-bundle}/themes      "$out/lib/lordos/themes"
    cp -r ${lord-ui-bundle}/assets      "$out/lib/lordos/assets"
    cp ${lord-ui-bundle}/code-manifest.json "$out/lib/lordos/code-manifest.json"

    mkdir -p "$out/bin"
    ln -s ../lib/lordos/bin/lord-server "$out/bin/lord-server"
  ''
