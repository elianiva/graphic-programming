{
  description = "Triangle drawing using GPU (OpenGL)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      devShells.x86_64-linux.default = pkgs.mkShell.override { stdenv = pkgs.clangStdenv; } {
        name = "triangle";
        packages = with pkgs; [
          zig # used to compile c
        ];
        buildInputs = with pkgs; [
          wayland # used to show the window on wayland
        ];
        nativeBuildInputs = with pkgs; [
          pkg-config # used to find wayland
          wayland-scanner
        ];
        shellHook = ''
          export LD_LIBRARY_PATH=${(pkgs.lib.makeLibraryPath [ pkgs.wayland ])}:$LD_LIBRARY_PATH
          export LIBRARY_PATH=${(pkgs.lib.makeLibraryPath [ pkgs.wayland ])}:$LIBRARY_PATH
        '';
      };
    };
}
