{
  description = "balenaEtcher - Flash OS images to SD cards and USB drives";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        nodejs = pkgs.nodejs_20;
        
        # X11 libraries
        x11Libs = with pkgs; [
          libx11
          libxcomposite
          libxdamage
          libxext
          libxfixes
          libxrandr
          libxcb
          libxcursor
          libxi
          libxrender
          libxscrnsaver
          libXtst
        ];
        
        # All runtime libraries for Electron
        runtimeLibs = with pkgs; [
          gtk3
          libusb1
          udev
          cups
          nss
          nspr
          alsa-lib
          atk
          cairo
          dbus
          expat
          fontconfig
          freetype
          gdk-pixbuf
          glib
          pango
          libdrm
          libxkbcommon
          mesa
        ] ++ x11Libs;

        # Desktop item for the application
        desktopItem = pkgs.makeDesktopItem {
          name = "balena-etcher";
          exec = "balena-etcher";
          icon = "balena-etcher";
          desktopName = "balenaEtcher";
          comment = "Flash OS images to SD cards and USB drives";
          categories = [ "System" "Utility" ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            nodejs
            nodejs.pkgs.npm
            electron
            python3
            pkg-config
          ];

          buildInputs = runtimeLibs;

          ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
          npm_config_build_from_source = "true";
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath runtimeLibs;

          shellHook = ''
            echo "balenaEtcher development shell"
            echo "Node: $(node --version), npm: $(npm --version)"
          '';
        };

        # Build from source using buildNpmPackage
        packages.default = pkgs.buildNpmPackage rec {
          pname = "balena-etcher";
          version = "2.1.4";
          
          src = ./.;
          
          npmDepsHash = "sha256-Ae0yMz0p7YBZrYTibKyA1TqFT7LubigRkalecImunBI=";
          
          makeCacheWritable = true;
          
          # Ensure devDependencies are installed (needed for electron-forge)
          npmInstallFlags = [ "--include=dev" ];
          
          nativeBuildInputs = with pkgs; [
            python3
            pkg-config
            makeWrapper
            copyDesktopItems
            autoPatchelfHook
          ];
          
          buildInputs = with pkgs; [
            stdenv.cc.cc.lib  # glibc - needed by autoPatchelfHook for the dynamic linker
            zlib
          ] ++ runtimeLibs;
          
          desktopItems = [ desktopItem ];
          
          NODE_ENV = "production";
          
          # Don't download Electron during build
          ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
          
          # Add electron to PATH
          PATH = "${pkgs.electron}/bin:$PATH";
          
          buildPhase = ''
            runHook preBuild
            
            # Remove SidecarPlugin from forge.config.ts to avoid sidecar build
            sed -i '/new sidecar.SidecarPlugin()/d' forge.config.ts
            
            # Create a directory with the pre-downloaded Electron zip
            # electron-packager's electronZipDir option bypasses @electron/get entirely
            ELECTRON_ZIP_DIR=$TMPDIR/electron-zip
            mkdir -p $ELECTRON_ZIP_DIR
            cp ${pkgs.fetchurl {
              url = "https://github.com/electron/electron/releases/download/v37.2.4/electron-v37.2.4-linux-x64.zip";
              sha256 = "1nq1nvrg860wrmyzx810lk3i42f1znrym3qmz78hby7fynx6wz82";
            }} $ELECTRON_ZIP_DIR/electron-v37.2.4-linux-x64.zip
            
            # Patch forge.config.ts to use electronZipDir
            sed -i "s|asar: true,|asar: true,\n\t\telectronZipDir: '$ELECTRON_ZIP_DIR',|" forge.config.ts
            
            # Run electron-forge package
            node_modules/.bin/electron-forge package 2>&1
            
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            
            echo "Installing to $out..."
            
            # electron-forge creates out/balena-etcher-linux-x64/
            OUT_DIR=$(ls -d out/*linux*/ 2>/dev/null | head -1)
            echo "Found output directory: $OUT_DIR"
            
            if [ -d "$OUT_DIR" ]; then
              # Copy the packaged app
              mkdir -p $out/share/balena-etcher
              cp -r $OUT_DIR/* $out/share/balena-etcher/
              
              # Fix broken symlinks that point to /build/ paths
              # electron-packager creates a 'balenaEtcher' symlink that points to /build/ - remove it
              # since we have the actual 'balena-etcher' binary and our own wrapper
              rm -f $out/share/balena-etcher/balenaEtcher
              echo "Removed broken balenaEtcher symlink"
              
              echo "Installed contents:"
              ls -la $out/share/balena-etcher/
              
              # Create wrapper that sets XDG_DATA_DIRS for desktop integration
              mkdir -p $out/bin
              makeWrapper $out/share/balena-etcher/balena-etcher $out/bin/balena-etcher \
                --set XDG_DATA_DIRS "$out/share:${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/${pkgs.gsettings-desktop-schemas.name}:${pkgs.gtk3}/share/gsettings-schemas/${pkgs.gtk3.name}" \
                --prefix GIO_EXTRA_MODULES : "${pkgs.dconf}/lib/gio/modules" \
                --prefix PATH : "${pkgs.lib.makeBinPath [ pkgs.xdg-utils ]}"
            else
              echo "ERROR: No output directory found in out/"
              ls -la out/ 2>&1 || true
              exit 1
            fi
            
            echo "Wrapper created at $out/bin/balena-etcher"
            
            runHook postInstall
          '';
          
          # Skip npm audit (has network requests)
          npmAudit = false;
          
          # Fix for node-gyp and native addons
          npmFlags = [ "--legacy-peer-deps" ];
          
          meta = with pkgs.lib; {
            description = "Flash OS images to SD cards and USB drives";
            homepage = "https://www.balena.io/etcher/";
            license = licenses.asl20;
            platforms = platforms.linux;
          };
        };
      });
}
