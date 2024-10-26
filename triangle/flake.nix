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
      devShells.x86_64-linux.default = pkgs.mkShell {
        name = "triangle";
        packages = with pkgs; [
          zig # used to compile c
        ];
      };
    };
}
