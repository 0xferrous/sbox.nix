# Run nixpkgs apps in an isolated QEMU sandbox VM.
# Examples:
#   nix run .#sbox -- chromium --incognito
{
  inputs.microvm = {
    url = "github:astro/microvm.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  inputs.nix-index-database = {
    url = "github:nix-community/nix-index-database";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    microvm,
    nix-index-database,
  }: let
    system = "x86_64-linux";
    lib = nixpkgs.lib;
    pkgs = nixpkgs.legacyPackages.${system};

    mkSboxRunner = {
      pkgAttr,
      command ? null,
      args ? [ ],
      gui ? true,
      microvmConfig ? { },
      useSystemNixpkgs ? false,
    }:
      let
        runnerPkgs =
          if useSystemNixpkgs
          then import <nixpkgs> {
            inherit system;
            config.allowUnfree = true;
          }
          else pkgs;

        pkg = lib.attrByPath (lib.splitString "." pkgAttr)
          (throw "Unknown nixpkgs attribute path: ${pkgAttr}")
          runnerPkgs;

        cmdName = if command == null then lib.getName pkg else command;

        launcher = pkgs.writeShellScript "sbox-launch-${lib.replaceStrings [ "." ] [ "-" ] pkgAttr}" ''
          exec "${lib.getBin pkg}/bin/${cmdName}" ${lib.escapeShellArgs args}
        '';

        cliLauncher = pkgs.writeShellScript "sbox-cli-${lib.replaceStrings [ "." ] [ "-" ] pkgAttr}" ''
          set +e
          "${lib.getBin pkg}/bin/${cmdName}" ${lib.escapeShellArgs args}
          ${runnerPkgs.systemd}/bin/poweroff -f
        '';

        defaultMicrovmConfig = {
          mem = 4096;
          graphics.enable = gui;
          shares = [
            {
              proto = "9p";
              tag = "ro-store";
              source = "/nix/store";
              mountPoint = "/nix/.ro-store";
            }
          ];
          hypervisor = "qemu";
          interfaces = [
            {
              type = "user";
              id = "microvm1";
              mac = "02:02:00:00:00:01";
            }
          ];
        };

        finalMicrovmConfig = lib.recursiveUpdate defaultMicrovmConfig microvmConfig;
      in
        (nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            microvm.nixosModules.microvm
            {
              microvm = finalMicrovmConfig;
            }
            ({ lib, ... }: {
              networking.hostName = "${lib.replaceStrings [ "." ] [ "-" ] pkgAttr}-sbox";
              system.stateVersion = lib.trivial.release;
              nixpkgs.config.allowUnfree = true;
              hardware.graphics.enable = gui;

              users.users.guest = {
                isNormalUser = true;
                extraGroups = [ "video" "input" ];
              };

              services.cage = lib.mkIf gui {
                enable = true;
                program = launcher;
                user = "guest";
              };

              systemd.services.sbox-cli = lib.mkIf (!gui) {
                description = "Run non-GUI sbox command in serial TTY and shutdown";
                wantedBy = [ "multi-user.target" ];
                conflicts = [ "serial-getty@ttyS0.service" ];
                before = [ "serial-getty@ttyS0.service" ];
                serviceConfig = {
                  Type = "simple";
                  ExecStart = cliLauncher;
                  StandardInput = "tty-force";
                  StandardOutput = "tty";
                  StandardError = "tty";
                  TTYPath = "/dev/ttyS0";
                  TTYReset = true;
                  TTYVHangup = true;
                  TTYVTDisallocate = false;
                };
              };

              systemd.services."serial-getty@ttyS0" = lib.mkIf (!gui) {
                enable = false;
              };
            })
          ];
        }).config.microvm.declaredRunner;

    sboxCli = pkgs.writeTextFile {
      name = "sbox";
      executable = true;
      destination = "/bin/sbox";
      text = lib.replaceStrings
        [ "@FLAKE@" ]
        [ (toString self) ]
        (builtins.readFile ./scripts/sbox.nu);
    };
  in {
    lib.${system}.mkSboxRunner = mkSboxRunner;

    packages.${system} = {
      default = sboxCli;
      sbox = sboxCli;
      kiosk = sboxCli;
    };

    apps.${system} = {
      default = {
        type = "app";
        program = "${sboxCli}/bin/sbox";
      };
      sbox = {
        type = "app";
        program = "${sboxCli}/bin/sbox";
      };
      kiosk = {
        type = "app";
        program = "${sboxCli}/bin/sbox";
      };
    };
  };
}
