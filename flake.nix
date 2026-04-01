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
          
          nativeBuildInputs = with pkgs; [
            python3
            pkg-config
            makeWrapper
            copyDesktopItems
          ];
          
          buildInputs = runtimeLibs;
          
          desktopItems = [ desktopItem ];
          
          NODE_ENV = "production";
          
          # Don't download Electron during build
          ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
          
          # Add electron to PATH
          PATH = "${pkgs.electron}/bin:$PATH";
          
          buildPhase = ''
            runHook preBuild
            echo "Building with electron-forge..."
            
            export ELECTRON_SKIP_BINARY_DOWNLOAD=1
            
            # Debug: check node_modules structure
            echo "Node modules structure:"
            ls -la node_modules/ | head -20
            echo ""
            echo "Looking for electron-forge..."
            find node_modules -name "electron-forge.js" -o -name "electron-forge" 2>/dev/null | head -10
            echo ""
            echo "Checking .bin directory:"
            ls -la node_modules/.bin/ 2>/dev/null | head -10 || echo "No .bin directory"
            
            # Try running via npx with offline mode
            echo ""
            echo "Trying npx electron-forge..."
            npx --offline electron-forge package 2>&1 || {
              echo "npx failed, trying direct node..."
              node -e "require('@electron-forge/cli').default package()" 2>&1 || {
                echo "All methods failed, exiting"
                exit 1
              }
            }
            
            echo ""
            echo "Build complete. Checking outputs..."
            ls -la out/ 2>&1 || true
            
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
              
              echo "Installed contents:"
              ls -la $out/share/balena-etcher/
              
              # Create wrapper - the packaged app has balena-etcher executable
              mkdir -p $out/bin
              if [ -f "$out/share/balena-etcher/balena-etcher" ]; then
                makeWrapper $out/share/balena-etcher/balena-etcher $out/bin/balena-etcher \
                  --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath runtimeLibs}
              else
                # Fallback to electron direct
                makeWrapper ${pkgs.electron}/bin/electron $out/bin/balena-etcher \
                  --add-flags $out/share/balena-etcher/resources/app.asar \
                  --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath runtimeLibs}
              fi
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
