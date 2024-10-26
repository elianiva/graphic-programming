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
          dotnetCorePackages.sdk_7_0 # used to run the codegen for zig opengl binding
        ];
        buildInputs = with pkgs; [
          wayland # used to show the window on wayland
          wayland-protocols
          wayland-scanner
          egl-wayland
          libGL
          libglvnd
        ];
        nativeBuildInputs = with pkgs; [
          pkg-config # used to find library paths
        ];
      };
    };
}
