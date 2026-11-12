# project-flake

Gemeinsames Deployment für Programme, die auf einen NixOS-Server kommen: Paket, Dienst hinter
Caddy, Checks, Devshell mit Git-Hooks und Releases, für alle Programme gleich. Im Repo eines Programms bleibt nur, was es selbst hat:

```
flake.nix            Name, Version, Paket, eigene Checks und die Programme der Devshell
dev/flake.nix        die Devshell mit ihren weiteren Inputs (immer gleich, drei Zeilen)
deploy/package.nix   das Paket
deploy/module.nix    der eigene Teil des NixOS-Moduls
deploy/release.md    Ablauf und Einstellungen der Forge
justfile             ci, dist, release-check, release und was das Programm sonst braucht
.forgejo/ bzw. .github/workflows/   rufen nur `just` auf
```

Neues Programm: `nix flake init -t <URL dieses Repos>`.

Die Flake hat keine Inputs: nixpkgs kommt vom Programm, so steht in den Locks des Programms und
des Servers kein weiteres nixpkgs.

## `lib.mkApp`

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    project.url = "git+https://<forge>/<besitzer>/project-flake";
  };

  outputs =
    { self, nixpkgs, project }:
    let
      version = project.lib.zigVersion ./build.zig.zon;
    in
    project.lib.mkApp {
      inherit self nixpkgs version;
      name = "beispiel";                 # services.beispiel, Benutzer, Socket, Dateinamen
      title = "Beispiel";                # Beschreibungen, Name der Releases
      package = pkgs: pkgs.callPackage ./deploy/package.nix { inherit version; };
      module = ./deploy/module.nix;
      smokeTest = {
        start = "exec beispiel --socket $SOCKET";
        requests = [ { path = "/api/health"; expect = "ok"; } ];
      };
      devShell = { pkgs, inputs, system }: { packages = [ pkgs.zig ]; };
    };
}
```

| Argument | |
|---|---|
| `self`, `nixpkgs`, `name`, `version`, `package` | Pflicht. Das Paket hat `meta.mainProgram` und versteht `--socket <pfad>`. |
| `title` | Vorgabe `name` |
| `systems` | Vorgabe `[ "x86_64-linux" ]`, für Pakete und Checks |
| `packageName` | Vorgabe `name`, Name des Pakets in `packages` und im Overlay |
| `extraPackages` | `pkgs: { … }`, z.B. statische Binaries für die Releases |
| `module` | der eigene Teil des NixOS-Moduls |
| `branch` | Vorgabe `"master"`: Releases müssen darauf liegen, die Hooks lassen nichts direkt darauf |
| `moduleTest` | `{ config = { … }; assertions = cfg: [ { assertion; message; } ]; }` für den Check `module` |
| `smokeTest` | `{ start; requests = [ { path; expect; } ]; }` für den Check `http3` |
| `extraChecks` | `{ pkgs, evalConfig }: { … }`, `evalConfig` wertet NixOS mit dem Modul aus |
| `devShell` | `{ pkgs, inputs, system }: { packages; shellHook; …Variablen; mkShell? }` |
| `devSystems` | Vorgabe `systems`, für die Devshell |

Ausgaben:

- `packages.<system>.{default, <packageName>, project-release}` und `extraPackages`
- `overlays.default`, `nixosModules.default` (lib/service.nix und `module`, mit dem Paket)
- `checks.<system>`: `package`, `module`, `format` (nixfmt), `yaml` (yamllint, wenn es eine
  `.yamllint.yaml` gibt), `http3` (mit `smokeTest`), `release` (shellcheck), `extraChecks`
- `devShells.<system>.ci`: git, just, jq, curl, nixfmt, yamllint, ohne weitere Inputs, für
  Workflows, die die Devshell nicht brauchen (`nix develop .#ci --command just ci`)
- `lib.devShells`: die Devshell für `dev/flake.nix`, mit git, just, jq, nixfmt, yamllint,
  `project-release` und den Hooks
- `formatter.<system>`

## Der Dienst `services.<name>`

`lib/service.nix`, für jedes Programm gleich:

- Benutzer und Gruppe `<name>`, Unit `<name>.service`, gestartet wird
  `<mainProgram> --socket /run/<name>/<name>.sock <args>`.
- Mit Socket kein Netzwerk; dazu `ProtectSystem=strict`, eigenes `/tmp`, kein `/home`, keine
  Capabilities, fremde Prozesse unsichtbar, von `/var/lib` nur das eigene `StateDirectory`,
  höchstens die Hälfte des Speichers. Alles mit `mkDefault`, das Modul des Programms kann
  einzelnes lockern.
- Mit `domain` liefert Caddy `caddyConfig` aus (Vorgabe: alles an den Socket). Caddy kommt in die
  Gruppe `<name>`, der Dienst startet vor Caddy. Ports öffnet das Modul keine.

| Option | |
|---|---|
| `enable`, `package`, `domain` | |
| `socket` | Vorgabe `/run/<name>/<name>.sock`; `null` nur, wenn das Programm selbst TCP anbietet |
| `socketGroupMembers` | Vorgabe der Caddy-Benutzer |
| `args` | weitere Argumente, setzt das Modul des Programms |
| `caddyConfig` | Inhalt des virtuellen Hosts |
| `secrets`, `secretsDir` | Secrets (Dateiname → wofür) und wo der Server sie ablegt |

## Releases: `project-release`

```
project-release check <tag>    passt der Tag zu `version`, liegt er auf `branch`?
project-release publish <tag>  dazu: Release mit den Dateien aus dist/ (und SHA256SUMS),
                               dann den Branch `release` auf den Tag schieben (nur vorwärts)
```

Auf GitHub wie auf Forgejo (Codeberg), erkannt an `GITHUB_SERVER_URL`. Der Workflow gibt das
Token als `RELEASE_TOKEN` mit (`secrets.GITHUB_TOKEN`) und checkt mit `fetch-depth: 0` aus. Die
Dateien in `dist/` heißen `<programm>-<tag>-<ziel>`. Ein erneuter Lauf lädt nur hoch, was fehlt.

## Hooks

Die Devshell setzt `core.hooksPath` auf die Hooks aus `lib/hooks.nix`: kein Commit auf und kein
Push nach `branch`, entwickelt wird auf `dev/…` und per Pull Request gemerget. Verbindlich sind
die Schutzregeln der Forge, siehe `deploy/release.md` der Programme.
