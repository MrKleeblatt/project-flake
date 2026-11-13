# Alle Ausgaben der Flake eines Programms, siehe README.md:
#
#   packages.<system>.{default, <packageName>, project-release} (+ extraPackages)
#   overlays.default, nixosModules.default
#   checks.<system>.{package, module, format, yaml?, http3?} (+ extraChecks)
#   devShells.<system>.ci   die Werkzeuge der Workflows, ohne weitere Inputs
#   lib.devShells           die Devshell für dev/flake.nix (dort kommen die weiteren Inputs herein)
#   formatter.<system>
{
  self,
  nixpkgs,
  # services.<name>, Benutzer, Socket, Dateinamen der Releases
  name,
  # für Beschreibungen und den Namen der Releases
  title ? name,
  # einzige Stelle der Versionsnummer, z.B. `project.lib.zigVersion ./build.zig.zon`; Tags heißen v<version>
  version,
  systems ? [ "x86_64-linux" ],
  # Paket (pkgs → Derivation) mit `meta.mainProgram`, das `--socket <pfad>` versteht
  package,
  packageName ? name,
  extraPackages ? _pkgs: { },
  # der eigene Teil des NixOS-Moduls (Pfad oder Modul), dazu kommt lib/service.nix
  module ? { },
  # jeder Merge auf diesen Branch ist ein Release; die Hooks lassen nichts direkt darauf
  branch ? "master",
  # zusätzliche Werte für `services.<name>` und Prüfungen (cfg → [ { assertion; message; } ]) im Check `module`
  moduleTest ? { },
  # Programm hinter Caddy über HTTP/3, siehe lib/checks.nix
  smokeTest ? null,
  # { pkgs, evalConfig } → { <name> = Derivation; }
  extraChecks ? _: { },
  # { pkgs, inputs, system } → Argumente für mkShell (`packages`, `shellHook`, Variablen, optional
  # `mkShell`, Vorgabe pkgs.mkShellNoCC); `inputs` sind die von dev/flake.nix
  devShell ? _: { },
  devSystems ? systems,
}:
let
  inherit (nixpkgs) lib;
  forSystems = systems: f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

  nixosModule =
    { lib, pkgs, ... }:
    {
      imports = [
        (import ./service.nix { inherit name title; })
        module
      ];
      services.${name}.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };

  release =
    pkgs:
    pkgs.callPackage ./release.nix {
      inherit
        name
        title
        version
        branch
        ;
    };
  hooks = pkgs: pkgs.callPackage ./hooks.nix { inherit branch; };
in
{
  packages = forSystems systems (
    pkgs:
    let
      server = package pkgs;
    in
    {
      default = server;
      ${packageName} = server;
      project-release = release pkgs;
    }
    // extraPackages pkgs
  );

  overlays.default = final: _prev: { ${packageName} = package final; };

  nixosModules.default = nixosModule;

  checks = forSystems systems (
    pkgs:
    import ./checks.nix {
      inherit
        self
        nixpkgs
        pkgs
        name
        version
        nixosModule
        moduleTest
        smokeTest
        extraChecks
        ;
      server = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
    }
    # mit shellcheck
    // {
      release = release pkgs;
    }
  );

  devShells = forSystems systems (pkgs: {
    ci = pkgs.mkShellNoCC {
      packages = with pkgs; [
        git
        just
        jq
        curl
        nixfmt
        yamllint
      ];
    };
  });

  lib.devShells =
    inputs:
    lib.genAttrs devSystems (
      system:
      let
        pkgs = inputs.nixpkgs.legacyPackages.${system};
        shell = devShell { inherit pkgs inputs system; };
        mkShell = shell.mkShell or pkgs.mkShellNoCC;
      in
      {
        default = mkShell (
          builtins.removeAttrs shell [ "mkShell" ]
          // {
            packages =
              (with pkgs; [
                git
                just
                jq
                nixfmt
                yamllint
                (release pkgs)
              ])
              ++ shell.packages or [ ];
            shellHook = ''
              # Hooks aus project-flake: kein Commit auf und kein Push nach ${branch}, siehe deploy/release.md
              if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
                git -C "$root" config core.hooksPath ${hooks pkgs}
              fi
            ''
            + shell.shellHook or "";
          }
        );
      }
    );

  formatter = forSystems systems (pkgs: pkgs.nixfmt);
}
