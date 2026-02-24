# kiosk.nix

Run any nixpkgs graphical app in a QEMU virtual machine in kiosk mode (single, maximized application).

Sometimes you need a fresh isolated instance of a graphical app to do something zany in a safe and fun way, kiosk.nix is here for it.

## Examples

Run an app in nixpkgs, like chromium:

`nix run github:shazow/kiosk.nix#chromium`

Override nixpkgs to use my local nixpkgs, rather than kiosk.nix's possibly outdated flake.lock:

`nix run github:shazow/kiosk.nix#chromium --override-input nixpkgs nixpkgs`

Use the latest unstable nixpkgs:

`nix run github:shazow/kiosk.nix#chromium --override-input nixpkgs github:NixOS/nixpkgs/nixpkgs-unstable`

## License

MIT
