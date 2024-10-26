# triangle

A simple triangle drawing using zig and opengl.
Can only be used in wayland.

## Usage

This repo provides nix, just use that lol

```sh
nix develop # activate nix shell (you don't need to if you have direnv)
WAYLAND_DEBUG=1 zig build run # run the thing with wayland log
```
