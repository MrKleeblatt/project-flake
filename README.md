# project-flake

Eine Flake, die einheitliches Veröffentlichen und einheitliche Struktur mehrerer
Projekt ermöglicht.

## Was diese Flake bereitstellt

Einen Befehl, um ein neues Projekt anzufangen. Schreibt das Template in
<proj-dir> (Standard: ~/projects)

```
proj-create [<proj-dir>]
```

Eine Devshell für das Projekt, in der alle definierten Tools bereitgestellt
werden, sodass sie nicht global auf dem System installiert werden müssen.

## Was (auf dem Server) vorausgesetzt wird

- eine Caddy-Instanz
- DNS-Records für alle eingetragenen Domains

## Was diese Flake im Template erstellt

| Datei              | Funktion                                                       |
| ------------------ | -------------------------------------------------------------- |
| flake.nix          | Name, Version, Paket, eigene Checks                            |
| dev/flake.nix      | die Programme der Devshell mit ihren weiteren Inputs           |
| deploy/package.nix | das Paket, das durch das Projekt erstellt wird                 |
| deploy/module.nix  | die Einbindung des Pakets in den Server per NixOS-Modul        |
| deploy/release.md  | Hinweise zum Ablauf des Release und zu Einstellungen der Forge |
| justfile           | leere Regeln, wie das Projekt zu bauen ist                     |
| .forgejo/          | rufen nur `just` auf                                           |
| .github/workflows/ | ruft nur `just` auf                                            |

Neues Programm: `nix flake init -t <URL dieses Repos>`.


| Argument                                        |                                                                                             |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `self`, `nixpkgs`, `name`, `version`, `package` | Pflicht. Das Paket hat `meta.mainProgram` und versteht `--socket <pfad>`.                   |
| `title`                                         | Vorgabe `name`                                                                              |
| `systems`                                       | Vorgabe `[ "x86_64-linux" ]`, für Pakete und Checks                                         |
| `packageName`                                   | Vorgabe `name`, Name des Pakets in `packages` und im Overlay                                |
| `extraPackages`                                 | `pkgs: { … }`, z.B. statische Binaries für die Releases                                     |
| `module`                                        | der eigene Teil des NixOS-Moduls                                                            |
| `branch`                                        | Vorgabe `"master"`: jeder Merge darauf ist ein Release, Hooks lassen nichts direkt darauf   |
| `forge`                                         | `"github"` oder `"codeberg"`: `project-forge` mit gh bzw. tea in die Devshell               |
| `moduleTest`                                    | `{ config = { … }; assertions = cfg: [ { assertion; message; } ]; }` für den Check `module` |
| `smokeTest`                                     | `{ start; requests = [ { path; expect; } ]; }` für den Check `http3`                        |
| `extraChecks`                                   | `{ pkgs, evalConfig }: { … }`, `evalConfig` wertet NixOS mit dem Modul aus                  |
| `devShell`                                      | `{ pkgs, inputs, system }: { packages; shellHook; …Variablen; mkShell? }`                   |
| `devSystems`                                    | Vorgabe `systems`, für die Devshell                                                         |

Ausgaben:

- `packages.<system>.{default, <packageName>, project-release}`, mit `forge`
  auch `project-forge`, und `extraPackages`
- `overlays.default`, `nixosModules.default` (lib/service.nix und `module`, mit
  dem Paket)
- `checks.<system>`: `package`, `module`, `format` (nixfmt), `yaml` (yamllint,
  wenn es eine `.yamllint.yaml` gibt), `http3` (mit `smokeTest`), `release`
  (shellcheck), `forge` (shellcheck, mit `forge`), `extraChecks`
- `devShells.<system>.ci`: git, just, jq, curl, nixfmt, yamllint, ohne weitere
  Inputs, für Workflows, die die Devshell nicht brauchen
  (`nix develop .#ci --command just ci`)
- `lib.devShells`: die Devshell für `dev/flake.nix`, mit git, just, jq, nixfmt,
  yamllint, `project-release`, den Hooks und mit `forge` gh bzw. tea und
  `project-forge`
- `formatter.<system>`

## Der Dienst `services.<name>`

`lib/service.nix`, für jedes Programm gleich:

- Benutzer und Gruppe `<name>`, Unit `<name>.service`, gestartet wird
  `<mainProgram> --socket /run/<name>/<name>.sock <args>`.
- Mit Socket kein Netzwerk; dazu `ProtectSystem=strict`, eigenes `/tmp`, kein
  `/home`, keine Capabilities, fremde Prozesse unsichtbar, von `/var/lib` nur
  das eigene `StateDirectory`, höchstens die Hälfte des Speichers. Alles mit
  `mkDefault`, das Modul des Programms kann einzelnes lockern.
- Mit `domain` liefert Caddy `caddyConfig` aus (Vorgabe: alles an den Socket).
  Caddy kommt in die Gruppe `<name>`, der Dienst startet vor Caddy. Ports öffnet
  das Modul keine.

| Option                        |                                                                                      |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| `enable`, `package`, `domain` |                                                                                      |
| `socket`                      | Vorgabe `/run/<name>/<name>.sock`; `null` nur, wenn das Programm selbst TCP anbietet |
| `socketGroupMembers`          | Vorgabe der Caddy-Benutzer                                                           |
| `args`                        | weitere Argumente, setzt das Modul des Programms                                     |
| `caddyConfig`                 | Inhalt des virtuellen Hosts                                                          |
| `secrets`, `secretsDir`       | Secrets (Dateiname → wofür) und wo der Server sie ablegt                             |

## Releases: `project-release`

Jeder Merge nach `branch` (nur per Pull Request) ist ein Release mit dem Tag
`v<version>`. Einen eigenen Branch für Releases gibt es nicht: `branch` ist immer
das neueste Release, ältere Stände findet man über ihre Tags.

```
project-release tag      der Tag zur Version: v<version>
project-release check    gibt es den Tag noch nicht, ist er neuer als der letzte?
                         (im Pull Request, damit kein Merge ohne neue Version durchgeht)
project-release publish  dazu: liegt der Commit auf `branch`? Tag setzen und Release
                         mit den Dateien aus dist/ (und SHA256SUMS) anlegen
```

Auf GitHub wie auf Forgejo (Codeberg), erkannt an `GITHUB_SERVER_URL`. Der
Workflow gibt das Token als `RELEASE_TOKEN` mit (`secrets.GITHUB_TOKEN`) und
checkt mit `fetch-depth: 0` aus. Die Dateien in `dist/` heißen
`<programm>-<tag>-<ziel>`. Ein erneuter Lauf lädt nur hoch, was fehlt.

## Schutzregeln: `project-forge`

Mit `forge = "github"` bzw. `"codeberg"` hat die Devshell gh bzw. tea und:

```
project-forge protect [--approvals <n>] [--check <name>]
    Schutzregel für `branch` anlegen oder aktualisieren: nur per Pull Request,
    kein Force-Push, nicht löschbar, <n> Freigaben (Vorgabe 1, veraltete
    verfallen), der Check muss grün und der Branch aktuell sein
project-forge show
    die Schutzregeln des Repos
```

Das Repo ergibt sich aus dem Remote `origin`. Vorher anmelden: `gh auth login`
bzw. `tea login add --url https://codeberg.org --token …`. Der Check ist der Job
`build` aus `ci.yml`, auf GitHub `build`, auf Forgejo das Muster
`* / build (pull_request)`; anders heißt er mit `--check`. Den eigenen Pull
Request freigeben kann man nicht: wer allein arbeitet, nimmt `--approvals 0`.
Auf GitHub gibt es Schutzregeln für private Repos eines persönlichen Kontos nur
mit GitHub Pro.

## Hooks

Die Devshell setzt `core.hooksPath` auf die Hooks aus `lib/hooks.nix`: kein
Commit auf und kein Push nach `branch`, entwickelt wird auf `dev/…` und per Pull
Request gemerget. Verbindlich sind die Schutzregeln der Forge, siehe
`deploy/release.md` der Programme.
