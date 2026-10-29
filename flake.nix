{
  description = "Pritunl WG: macOS status bar app for DFINITY's Pritunl VPN";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

  outputs = { nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;

      # Nixpkgs 26.05 is the last release that supports x86_64-darwin; the
      # filter drops it automatically on newer releases.
      systems = lib.intersectLists lib.systems.flakeExposed [ "aarch64-darwin" "x86_64-darwin" ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Info.plist is the source of truth for the version and the minimum macOS version.
      plistString = key:
        let
          match = builtins.match ".*<key>${key}</key>[[:space:]]*<string>([^<]*)</string>.*"
            (builtins.readFile ./Info.plist);
        in
        if match == null then throw "Info.plist has no string value for ${key}" else builtins.head match;
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = pritunl-wg-statusbar;

        pritunl-wg-statusbar = pkgs.stdenv.mkDerivation {
          pname = "pritunl-wg-statusbar";
          version = plistString "CFBundleVersion";

          src = lib.fileset.toSource {
            root = ./.;
            fileset = lib.fileset.unions [ ./Info.plist ./Sources ./Resources ];
          };

          strictDeps = true;
          nativeBuildInputs = [ pkgs.swift pkgs.rcodesign ];
          # Raises the deployment target to LSMinimumSystemVersion when that is newer
          # than the oldest macOS Nixpkgs supports (14.0 in 26.05). It never lowers it.
          buildInputs = [ (pkgs.darwinMinVersionHook (plistString "LSMinimumSystemVersion")) ];

          # Silence the Nix cc-wrapper's warning about Swift's
          # <arch>-apple-macosx<version> target; it is expected here.
          env.NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING = true;

          buildPhase = ''
            runHook preBuild
            # Expand Sources/*.swift bytewise: otherwise the order, and with it
            # the binary, differs between sandboxed and unsandboxed builds.
            export LC_ALL=C
            # Without -target, newer (unwrapped) Swift toolchains in Nixpkgs
            # build for the macOS version of the build machine.
            swiftc -O \
              -target ${pkgs.stdenv.hostPlatform.darwinArch}-apple-macosx$MACOSX_DEPLOYMENT_TARGET \
              -framework AppKit -framework Foundation \
              Sources/*.swift -o PritunlWG
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            app=$out/Applications/PritunlWG.app
            install -Dm755 PritunlWG "$app/Contents/MacOS/PritunlWG"
            install -Dm644 Info.plist "$app/Contents/Info.plist"
            install -Dm755 -t "$app/Contents/Resources" Resources/pritunl-wg Resources/install.sh
            runHook postInstall
          '';

          # Ship the scripts verbatim, as build.sh does: patched shebangs would
          # point into the store.
          dontPatchShebangs = true;

          # Ad-hoc signature that also seals Info.plist and Resources, like
          # `codesign --force --sign -` in build.sh. It must come after
          # fixupPhase, because stripping the binary would invalidate it.
          postFixup = ''
            rcodesign sign "$out/Applications/PritunlWG.app"
          '';

          # The binary only links macOS system libraries, so the app keeps working
          # when copied out of the store. Fail the build if a store path sneaks in.
          allowedReferences = [ ];

          meta = {
            description = "Status bar app for DFINITY's Pritunl VPN";
            platforms = lib.platforms.darwin;
          };
        };
      });
    };
}
