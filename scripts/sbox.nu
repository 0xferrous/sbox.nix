#!/usr/bin/env nix-shell
#! nix-shell -i nu -p nushell nix jq fzy file binutils nix-index

def usage [] {
  print -e "Usage: sbox [--mode auto|gui|cli] [--mem MiB] [--vcpu N] [--microvm-json JSON] [--dry-run] <binary> [args...]"
}

def detect_mode [attr: string, cmd: string] {
  let pkg_path = (
    ^nix-build '<nixpkgs>' -A $attr --no-out-link
    | lines
    | last
    | str trim
  )

  let exe = $"($pkg_path)/bin/($cmd)"
  if (not ($exe | path exists)) {
    "gui"
    return
  }

  let file_kind = (^file -Lb $exe | str trim)
  if ($file_kind | str contains "ELF") {
    let needed = (do -i {
      ^readelf -d $exe
      | lines
      | where ($it | str contains "(NEEDED)")
      | str join (char nl)
    })

    let gui_needles = [
      "libX11"
      "libwayland-client"
      "libgtk-"
      "libgdk-"
      "libQt5"
      "libQt6"
      "libSDL2"
      "libEGL"
      "libGLX"
      "libGL.so"
      "libvulkan"
      "libwebkit2gtk"
      "libwx_"
    ]

    if ($gui_needles | any {|n| $needed | str contains $n}) {
      "gui"
    } else {
      "cli"
    }
  } else {
    let text = ((do -i { open --raw $exe }) | str downcase)
    let gui_words = [ "electron" "gtk" "qt" "wayland" "x11" ]
    if ($gui_words | any {|w| $text | str contains $w}) {
      "gui"
    } else {
      "cli"
    }
  }
}

def --wrapped main [
  --mode: string = "auto"
  --mem: int
  --vcpu: int
  --microvm-json: string = "{}"
  --dry-run
  cmd: string
  ...cmd_args: string
] {
  if ($mode not-in ["auto", "gui", "cli"]) {
    print -e $"Invalid --mode '($mode)' (expected: auto|gui|cli)"
    exit 1
  }

  mut microvm_cfg = (try { $microvm_json | from json } catch {
    print -e "--microvm-json must be valid JSON"
    exit 1
  })

  if (($microvm_cfg | describe) !~ 'record') {
    print -e "--microvm-json must be a JSON object"
    exit 1
  }

  let matches = (
    ^nix-locate --minimal --at-root --whole-name $"/bin/($cmd)"
    | lines
    | where {|l| $l != ""}
  )

  if ($matches | is-empty) {
    print -e $"No package found for /bin/($cmd) in nix-index database."
    exit 1
  }

  mut choice = ($matches | first)
  if (($matches | length) > 1) {
    if $dry_run {
      print -e $"dry-run: multiple matches found; selecting first: ($choice)"
    } else {
      $choice = (
        $matches
        | str join (char nl)
        | ^fzy
        | str trim
      )
      if ($choice | is-empty) {
        exit 1
      }
    }
  }

  let attr = ($choice | str replace -r '\.[^.]+$' '')

  let resolved_mode = if $mode == "auto" {
    detect_mode $attr $cmd
  } else {
    $mode
  }

  let gui_arg = if $resolved_mode == "gui" { "true" } else { "false" }

  if ($mem != null) {
    $microvm_cfg = ($microvm_cfg | upsert mem $mem)
  }

  if ($vcpu != null) {
    $microvm_cfg = ($microvm_cfg | upsert vcpu $vcpu)
  }

  let args_json = ($cmd_args | to json --raw)
  let microvm_json = ($microvm_cfg | to json --raw)

  if $dry_run {
    print "dry-run: true"
    print $"binary: ($cmd)"
    print $"package-attr: ($attr)"
    print $"mode-requested: ($mode)"
    print $"mode-resolved: ($resolved_mode)"
    print $"gui: ($gui_arg)"
    print $"args-json: ($args_json)"
    print $"microvm-json: ($microvm_json)"
    exit 0
  }

  let expr = '
{ pkgAttr, cmd, argsJson, gui, microvmJson }:
  let
    flake = builtins.getFlake "@FLAKE@";
    system = builtins.currentSystem;
  in flake.lib.${system}.mkSboxRunner {
    pkgAttr = pkgAttr;
    command = cmd;
    args = builtins.fromJSON argsJson;
    gui = gui;
    microvmConfig = builtins.fromJSON microvmJson;
    useSystemNixpkgs = true;
  }
'

  let runner = (
    ^nix build
      --extra-experimental-features 'nix-command flakes'
      --impure
      --no-link
      --print-out-paths
      --expr $expr
      --argstr pkgAttr $attr
      --argstr cmd $cmd
      --argstr argsJson $args_json
      --arg gui $gui_arg
      --argstr microvmJson $microvm_json
    | lines
    | last
    | str trim
  )

  ^$"($runner)/bin/microvm-run"
}
