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
            echo "Running electron-forge package..."
            
            # Tell electron-forge to use system electron
            export ELECTRON_PATH=${pkgs.electron}/bin/electron
            export ELECTRON_SKIP_BINARY_DOWNLOAD=1
            
            # Run electron-forge package (this will use webpack plugin internally)
            ./node_modules/.bin/electron-forge package 2>&1 || true
            
            echo ""
            echo "Build attempted. Checking outputs..."
            ls -la out/ 2>&1 || true
            find . -name "*.asar" 2>&1 || true
            
            runHook postBuild
          '';
          
          installPhase = ''
            runHook preInstall
            
            echo "Installing to $out..."
            
            # Create the electron app structure
            mkdir -p $out/share/balena-etcher
            
            # Copy webpack output
            cp -r .webpack/* $out/share/balena-etcher/ 2>/dev/null || true
            
            # Copy package resources
            cp -r lib $out/share/balena-etcher/ 2>/dev/null || true
            cp package.json $out/share/balena-etcher/ 2>/dev/null || true
            
            echo "Installed contents:"
            find $out/share/balena-etcher -type f | head -20
            
            # Create wrapper script
            mkdir -p $out/bin
            makeWrapper ${pkgs.electron}/bin/electron $out/bin/balena-etcher \
              --add-flags $out/share/balena-etcher \
              --prefix LD_LIBRARY_PATH : ${pkgs.lib.makeLibraryPath runtimeLibs}
            
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
