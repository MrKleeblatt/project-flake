# Alle Ausgaben der Flake eines Programms, siehe README.md:
#
#   packages.<system>.{default, <packageName>…, dist, project-release, branch-protection?} (+ extraPackages)
#   overlays.default, nixosModules.default
#   checks.<system>.{package, package-<packageName>…, dist, module, format, yaml?, http3?} (+ extraChecks)
#   devShells.<system>.default   die Devshell, mit den `build.tools` aller Pakete (ohne dev/flake.nix)
#   lib.devShells                die Devshell für dev/flake.nix, wenn `devShell` `inputs` nennt
#   devShells.<system>.ci        die Werkzeuge der Workflows
#   formatter.<system>
{
  self,
  nixpkgs,
  # services.<name>, Benutzer, Socket, Name des Standardpakets
  name,
  # für Beschreibungen und den Namen der Releases
  title ? name,
  # einzige Stelle der Versionsnummer, z.B. `project.lib.zigVersion ./build.zig.zon`; Tags heißen v<version>
  version,
  systems ? [ "x86_64-linux" ],
  # packages.nix: { pkgs, lib, version, ... } → [ { packageName; src; build; release; meta; dist?; } ],
  # siehe buildPackage; `default` und der Dienst ist das Paket mit `packageName == name` (ohne
  # `build.target`), sonst das erste
  packages,
  extraPackages ? _pkgs: { },
  # der eigene Teil des NixOS-Moduls (Pfad oder Modul), dazu kommt lib/service.nix; sein `config`
  # gilt nur mit `services.<name>.enable`
  module ? { },
  # jeder Merge auf diesen Branch ist ein Release; die Hooks lassen nichts direkt darauf
  branch ? "master",
  # "github" oder "codeberg": Forge des Repos; gh bzw. tea in der Devshell und `branch-protection`
  # (Anmeldung und Schutzregeln, über das justfile)
  forge ? null,
  # zusätzliche Werte für `services.<name>` und Prüfungen (cfg → [ { assertion; message; } ]) im Check `module`
  moduleTest ? { },
  # Programm hinter Caddy über HTTP/3, siehe lib/checks.nix
  smokeTest ? null,
  # { pkgs, evalConfig } → { <name> = Derivation; }
  extraChecks ? _: { },
  # { pkgs, system, inputs? } → Argumente für mkShell (`packages`, `shellHook`, Variablen, optional
  # `mkShell`, Vorgabe pkgs.mkShellNoCC), zusätzlich zu den `build.tools` der Pakete. Nennt die
  # Funktion `inputs`, braucht die Devshell weitere Inputs: dann kommt sie aus dev/flake.nix
  # (`lib.devShells inputs`, die Inputs von dort), damit sie nicht im Lock der Server landen
  devShell ? _: { },
  devSystems ? systems,
}:
let
  inherit (nixpkgs) lib;
  forSystems = systems: f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

  # die Einträge aus packages.nix
  entries =
    pkgs:
    (if builtins.isFunction packages then packages else import packages) {
      inherit pkgs lib version;
    };

  # ein Eintrag aus packages.nix als Derivation:
  #
  #   build.command        ein Befehl im Quellordner, der das Projekt baut (z.B. `just build`)
  #   build.tools          Programme, die dafür gebraucht werden (just ist immer dabei); auch in der Devshell
  #   build.doChecks       Tests ausführen, Vorgabe false
  #   build.checkCommand   Vorgabe `just test`
  #   build.target         Ziel eines Cross-Builds (z.B. "aarch64-linux-musl"): steht in den
  #                        Release-Dateien statt des Systems, das Paket heißt <packageName>-<target>
  #   build.extra          weitere Attribute für mkDerivation (buildInputs, env, npmDeps, preBuild, …)
  #   release              Pfade im Quellordner nach dem Build: ausführbare Dateien kommen nach
  #                        $out/bin, alles andere (auch Ordner) nach $out/share/<packageName>
  #   dist                 Vorgabe true; false: nicht ins Release
  buildPackage =
    pkgs: p:
    let
      b = p.build;
      bases = map baseNameOf p.release;
      target = b.target or null;
    in
    assert lib.assertMsg (p.release != [ ]) "${p.packageName}: `release` ist leer";
    assert lib.assertMsg (lib.allUnique bases)
      "${p.packageName}: doppelte Dateinamen in `release`: ${toString bases}";
    pkgs.stdenv.mkDerivation (
      {
        pname = p.packageName + lib.optionalString (target != null) "-${target}";
        inherit version;
        inherit (p) src;
        nativeBuildInputs = [ pkgs.just ] ++ b.tools or [ ];
        doCheck = b.doChecks or false;
        dontConfigure = true;
        buildPhase = ''
          runHook preBuild
          # Compiler und Werkzeuge wollen einen Cache
          export HOME=$TMPDIR
          ${b.command}
          runHook postBuild
        '';
        checkPhase = ''
          runHook preCheck
          ${b.checkCommand or "just test"}
          runHook postCheck
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out
          share=$out/share/${p.packageName}
          add() {
            if [ -d "$1" ]; then
              mkdir -p "$share"
              cp -r "$1" "$share/"
            elif [ -x "$1" ]; then
              install -Dm755 "$1" "$out/bin/$(basename "$1")"
            else
              install -Dm644 "$1" "$share/$(basename "$1")"
            fi
          }
          ${lib.concatMapStrings (path: ''
            add ${lib.escapeShellArg path}
          '') p.release}
          ${lib.optionalString (p ? meta.mainProgram) ''
            if [ ! -x $out/bin/${p.meta.mainProgram} ]; then
              echo "${p.packageName}: meta.mainProgram ${p.meta.mainProgram} ist keine ausführbare Datei aus \`release\`" >&2
              exit 1
            fi
          ''}
          runHook postInstall
        '';
        # für lib/dist.nix
        passthru = b.extra.passthru or { } // {
          inherit (p) packageName;
          inherit target;
          release = bases;
          dist = p.dist or true;
        };
        meta = p.meta or { };
      }
      // builtins.removeAttrs (b.extra or { }) [ "passthru" ]
    );

  buildAll =
    pkgs:
    let
      built = map (buildPackage pkgs) (entries pkgs);
      named = builtins.filter (p: p.pname == name) built;
      inDist = builtins.filter (p: p.dist) built;
    in
    assert lib.assertMsg (built != [ ]) "packages.nix: keine Pakete";
    {
      packages = lib.listToAttrs (map (p: lib.nameValuePair p.pname p) built);
      default = if named != [ ] then builtins.head named else builtins.head built;
      inherit inDist;
    };

  # der eigene Teil des Moduls; sein `config` (oder bei einem Modul ohne `config`/`options` alles
  # außer `imports`) nur mit `services.<name>.enable`
  ownModule =
    let
      m = if builtins.isPath module || builtins.isString module then import module else module;
      guard =
        args: r:
        let
          cfg = lib.mkIf args.config.services.${name}.enable;
        in
        if r ? config || r ? options then
          r // { config = cfg r.config or { }; }
        else
          {
            imports = r.imports or [ ];
            config = cfg (builtins.removeAttrs r [ "imports" ]);
          };
      wrapped =
        if builtins.isFunction m then
          lib.setFunctionArgs (args: guard args (m args)) (lib.functionArgs m // { config = false; })
        else
          args: guard args m;
    in
    if builtins.isPath module || builtins.isString module then
      {
        _file = toString module;
        imports = [ wrapped ];
      }
    else
      wrapped;

  nixosModule =
    { lib, pkgs, ... }:
    {
      imports = [
        (import ./service.nix { inherit name title; })
        ownModule
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

  dist =
    pkgs:
    pkgs.callPackage ./dist.nix {
      inherit name version;
      packages = (buildAll pkgs).inDist;
    };

  forgeCli =
    pkgs:
    assert lib.assertOneOf "forge" forge [
      "github"
      "codeberg"
    ];
    {
      github = pkgs.gh;
      codeberg = pkgs.tea;
    }
    .${forge};
  branchProtection =
    pkgs:
    pkgs.callPackage ./branch-protection.nix {
      inherit forge branch;
      cli = forgeCli pkgs;
    };
  # braucht die Devshell weitere Inputs (aus dev/flake.nix)?
  devInputs = lib.functionArgs devShell ? inputs;
  mkDevShell =
    pkgs: inputs:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
      shell = devShell (
        {
          inherit pkgs system;
        }
        // lib.optionalAttrs devInputs { inherit inputs; }
      );
      mkShell = shell.mkShell or pkgs.mkShellNoCC;
    in
    mkShell (
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
          ++ lib.concatMap (p: p.build.tools or [ ]) (entries pkgs)
          # branch-protection nicht, das ruft das justfile mit `nix run` auf
          ++ lib.optional (forge != null) (forgeCli pkgs)
          ++ shell.packages or [ ];
        shellHook = ''
          # Hooks aus project-flake: kein Commit auf und kein Push nach ${branch}, siehe README.md von project-flake
          if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
            git -C "$root" config core.hooksPath ${hooks pkgs}
          fi
        ''
        + shell.shellHook or "";
      }
    );
in
{
  packages = forSystems systems (
    pkgs:
    let
      all = buildAll pkgs;
    in
    all.packages
    // {
      inherit (all) default;
      dist = dist pkgs;
      project-release = release pkgs;
    }
    // lib.optionalAttrs (forge != null) { branch-protection = branchProtection pkgs; }
    // extraPackages pkgs
  );

  overlays.default = final: _prev: (buildAll final).packages;

  nixosModules.default = nixosModule;

  checks = forSystems systems (
    pkgs:
    let
      all = buildAll pkgs;
    in
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
      server = all.default;
    }
    # die übrigen Pakete
    // lib.mapAttrs' (n: lib.nameValuePair "package-${n}") (
      lib.filterAttrs (_: p: p != all.default) all.packages
    )
    // {
      # alles, was ins Release kommt, soll schon im Pull Request bauen
      dist = dist pkgs;
      # mit shellcheck
      release = release pkgs;
    }
    // lib.optionalAttrs (forge != null) { branch-protection = branchProtection pkgs; }
  );

  # ci für `systems`, default für `devSystems`
  devShells =
    lib.recursiveUpdate
      (forSystems systems (pkgs: {
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
      }))
      (
        lib.optionalAttrs (!devInputs) (
          forSystems devSystems (pkgs: {
            default = mkDevShell pkgs { };
          })
        )
      );

  # für dev/flake.nix: `outputs = inputs: { devShells = inputs.app.lib.devShells inputs; };`
  lib.devShells =
    inputs:
    lib.genAttrs devSystems (system: {
      default = mkDevShell inputs.nixpkgs.legacyPackages.${system} inputs;
    });

  formatter = forSystems systems (pkgs: pkgs.nixfmt);
}
