# sbox.nix

Run nixpkgs apps in an isolated QEMU virtual machine sandbox.

Sometimes you need a fresh isolated instance of an app to do something zany in a safe and fun way, sbox.nix is here for it.

## Examples

Run an app in nixpkgs via the dynamic `sbox` CLI (resolves a binary via nix-index-database and runs it in the VM):

`nix run github:0xferrous/sbox.nix#sbox -- chromium --incognito`

Mode selection:

- `--mode auto` (default): heuristic GUI/CLI detection
- `--mode gui`: force graphical VM + cage
- `--mode cli`: force non-graphical VM run

CLI behavior:

- CLI mode uses interactive serial TTY (`/dev/ttyS0`)

MicroVM tuning:

- `--mem <MiB>` to set VM memory (e.g. `--mem 8192`)
- `--vcpu <N>` to set vCPU count
- `--microvm-json '<json>'` to override/extend microvm options (merged into defaults)
- `--dry-run` to print resolved package/mode/config without launching

## How dynamic MicroVM config works

`microvm.nix` is still used declaratively; nothing is mutated imperatively.

At runtime, `sbox` does 3 steps:

1. Resolve a command (e.g. `chromium`) to a nixpkgs attribute via `nix-locate`.
2. Build an argument set (mode, args, `--mem`, `--vcpu`, `--microvm-json`).
3. Pass that data into `mkSboxRunner` via `nix build --expr ...`.

`mkSboxRunner` is a normal declarative NixOS/microvm definition. The only dynamic part is the input values. Nix evaluates that expression and returns a runner derivation, then `sbox` executes `.../bin/microvm-run`.

## CLI mode implementation

In `--mode cli` (or auto-detected CLI), sbox does **not** use cage. The guest runs `sbox-cli` attached to serial TTY (`/dev/ttyS0`), executes the command, then powers off.

## I/O contract

- **GUI mode:** I/O is graphical app window via cage.
- **CLI mode:** stdin/stdout/stderr are attached to VM serial TTY (`ttyS0`).

## Validation / smoke tests

CLI examples:

- `nix run .#sbox -- --mode cli bash`
- `nix run .#sbox -- --mode cli htop`
- `nix run .#sbox -- --mode cli ls`

## nix-locate / nixpkgs sync note

`sbox` resolves commands with `nix-locate`, then builds attributes from your system `<nixpkgs>` (via `nix-build '<nixpkgs>' -A ...`). For best results, keep your `nix-locate` index in sync with that same `<nixpkgs>` source (`NIX_PATH` / registry), otherwise resolution can point to attrs that differ from what your current system nixpkgs provides.

Examples:

`nix run github:0xferrous/sbox.nix#sbox -- --mode cli jq -- --version`

`nix run github:0xferrous/sbox.nix#sbox -- --mem 8192 --vcpu 4 chromium --incognito`

`nix run github:0xferrous/sbox.nix#sbox -- --dry-run chromium --incognito`

Override nixpkgs to use my local nixpkgs, rather than sbox.nix's possibly outdated flake.lock:

`nix run github:0xferrous/sbox.nix#sbox --override-input nixpkgs nixpkgs -- chromium`

Use the latest unstable nixpkgs:

`nix run github:0xferrous/sbox.nix#sbox --override-input nixpkgs github:NixOS/nixpkgs/nixpkgs-unstable -- chromium`

## TODO

- [ ] Make it into a library so people can `mkSbox { program, settings, ... }` easily in their own flakes.
- [ ] Add `qemuGuest` and other quality of life features?
- [ ] Example for sandboxing a specific website.

## License

MIT
