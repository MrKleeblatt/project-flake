# project-flake

Eine Flake, die einheitliches Veröffentlichen und einheitliche Struktur mehrerer
Projekt ermöglicht.

## Was diese Flake bereitstellt

Eine Vorlage für neue Projekte: `nix flake init -t <URL dieses Repos>`.

Eine Devshell für das Projekt (`nix develop` oder direnv), in der alle
definierten Tools bereitgestellt werden, sodass sie nicht global auf dem System
installiert werden müssen.

## Was (auf dem Server) vorausgesetzt wird

- eine Caddy-Instanz
- DNS-Records für alle eingetragenen Domains

## Was diese Flake im Template erstellt

| Datei              | Funktion                                                             |
| ------------------ | -------------------------------------------------------------------- |
| flake.nix          | Name, Version, Forge                                                 |
| packages.nix       | die Pakete: Quellen, Build, Tests, Dateien für das Release           |
| modules.nix        | die Einbindung des Pakets in den Server per NixOS-Modul              |
| justfile           | wie das Projekt gebaut und getestet wird, CI/CD                      |
| CHANGELOG.md       | kommt mit ins Release                                                |
| .forgejo/          | Workflows für Forgejo (Codeberg), rufen nur `just` auf               |
| .github/workflows/ | dieselben für GitHub; Forgejo nimmt `.forgejo/`, der andere kann weg |

| Argument                                         |                                                                                             |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------- |
| `self`, `nixpkgs`, `name`, `version`, `packages` | Pflicht. `packages` ist packages.nix, siehe unten.                                          |
| `title`                                          | Vorgabe `name`                                                                              |
| `systems`                                        | Vorgabe `[ "x86_64-linux" ]`, für Pakete und Checks                                         |
| `extraPackages`                                  | `pkgs: { … }`, weitere Pakete                                                               |
| `module`                                         | der eigene Teil des NixOS-Moduls, sein `config` gilt nur mit `services.<name>.enable`       |
| `branch`                                         | Vorgabe `"master"`: jeder Merge darauf ist ein Release, Hooks lassen nichts direkt darauf   |
| `forge`                                          | `"github"` oder `"codeberg"`: gh bzw. tea in die Devshell, `branch-protection`              |
| `moduleTest`                                     | `{ config = { … }; assertions = cfg: [ { assertion; message; } ]; }` für den Check `module` |
| `smokeTest`                                      | `{ start; requests = [ { path; expect; } ]; }` für den Check `http3`                        |
| `extraChecks`                                    | `{ pkgs, evalConfig }: { … }`, `evalConfig` wertet NixOS mit dem Modul aus                  |
| `devShell`                                       | `{ pkgs, system, inputs? }: { packages; shellHook; …Variablen; mkShell? }`, siehe unten     |
| `devSystems`                                     | Vorgabe `systems`, für die Devshell                                                         |

### packages.nix

Eine Funktion `{ pkgs, lib, version, ... }:`, die eine Liste von Paketen
liefert. Das Paket mit `packageName == name` und ohne `build.target` (sonst das
erste) ist `default` und läuft als Dienst; es hat `meta.mainProgram` und
versteht `--socket <pfad>`.

| Feld                 |                                                                                       |
| -------------------- | ------------------------------------------------------------------------------------- |
| `packageName`        | Name in `packages`, im Overlay und vorne in den Release-Dateien                       |
| `src`                | die Quellen, z.B. `lib.fileset.toSource`                                              |
| `build.command`      | ein Befehl im Quellordner, der baut (z.B. `just build`)                               |
| `build.tools`        | Programme zum Bauen, just ist immer dabei; sie kommen auch in die Devshell            |
| `build.doChecks`     | Tests ausführen, Vorgabe `false`                                                      |
| `build.checkCommand` | Vorgabe `"just test"`                                                                 |
| `build.target`       | Ziel eines Cross-Builds, statt des Systems im Release; Paket `<packageName>-<target>` |
| `build.extra`        | weitere Attribute für `mkDerivation`, z.B. `buildInputs`, `npmDeps`, `preBuild`       |
| `dist`               | Vorgabe `true`; `false`: das Paket kommt nicht ins Release                            |
| `release`            | Pfade im Quellordner nach dem Build, siehe Releases                                   |
| `meta`               | wie bei nixpkgs; `mainProgram` muss eine ausführbare Datei aus `release` sein         |

Ins Paket kommen genau die Dateien aus `release`: ausführbare nach `bin/`,
alles andere (auch Ordner, z.B. die Assets einer Webapp) nach
`share/<packageName>/`.

Ausgaben:

- `packages.<system>.{default, <packageName>…, dist, project-release}`, mit
  `forge` auch `branch-protection`, und `extraPackages`
- `overlays.default` (alle Pakete), `nixosModules.default` (lib/service.nix und
  `module`, mit dem Paket)
- `checks.<system>`: `package` (`default`), `package-<packageName>` (die
  übrigen), `dist`, `module`, `format` (nixfmt), `yaml` (yamllint,
  wenn es eine `.yamllint.yaml` gibt), `http3` (mit `smokeTest`), `release`
  (shellcheck), `branch-protection` (shellcheck, mit `forge`), `extraChecks`
- `devShells.<system>.ci`: git, just, jq, curl, nixfmt, yamllint, ohne weitere
  Inputs, für Workflows, die die Devshell nicht brauchen
  (`nix develop .#ci --command just ci`)
- `devShells.<system>.default`: mit git, just, jq, nixfmt, yamllint,
  `project-release`, den `build.tools` aller Pakete, den Hooks und mit `forge`
  gh bzw. tea; nennt `devShell` `inputs`, stattdessen
  `lib.devShells` für `dev/flake.nix`

Braucht die Devshell Inputs, die der Server nicht im Lock haben soll (z.B.
nixpkgs-unstable), nennt `devShell` `inputs` und sie kommt aus einer eigenen
Flake `dev/flake.nix` (`nix develop ./dev`, `.envrc`: `use flake ./dev`):

```nix
{
  inputs = {
    app.url = "path:..";
    nixpkgs.follows = "app/nixpkgs";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = inputs: { devShells = inputs.app.lib.devShells inputs; };
}
```

- `formatter.<system>`

## Der Dienst `services.<name>`

`lib/service.nix`, für jedes Programm gleich:

- Benutzer und Gruppe `<name>`, Unit `<name>.service`, gestartet wird
  `<mainProgram> --socket /run/<name>/<name>.sock <args>`.
- Mit Socket kein Netzwerk; dazu `ProtectSystem=strict`, eigenes `/tmp`, kein
  `/home`, keine Capabilities, fremde Prozesse unsichtbar, von `/var/lib` nur
  das eigene `StateDirectory`, höchstens die Hälfte des Speichers. Alles mit
  `mkDefault`, das Modul des Programms kann einzelnes lockern.
- Daten in `/var/lib/<name>` (`StateDirectory`).
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

Welche Dateien ins Release kommen, steht in `release` der Pakete. Daraus baut
`packages.<system>.dist` einen Ordner, den `just dist` nach `dist/` kopiert; als
Check baut er schon im Pull Request. Vorne steht der `packageName`, wenn der
Dateiname nicht schon mit ihm beginnt; ausführbare Dateien bekommen das System
(bzw. `build.target`), Ordner werden zu `.tar.gz`, andere Dateien behalten ihre
Endung:

```
zig-out/bin/beispiel   → beispiel-v1.0.0-x86_64-linux
zig-out/bin/helfer     → beispiel-helfer-v1.0.0-x86_64-linux
zig-out/bin/beispiel-x → beispiel-x-v1.0.0-x86_64-linux
CHANGELOG.md           → beispiel-CHANGELOG-v1.0.0.md
zig-out/webapp         → beispiel-webapp-v1.0.0.tar.gz
```

Auf GitHub wie auf Forgejo (Codeberg), erkannt an `GITHUB_SERVER_URL`. Der
Workflow gibt das Token als `RELEASE_TOKEN` mit (`secrets.GITHUB_TOKEN`) und
checkt mit `fetch-depth: 0` aus. Ein erneuter Lauf lädt nur hoch, was fehlt.

## Anmeldung und Schutzregeln: `branch-protection`

Mit `forge = "github"` bzw. `"codeberg"` hat die Devshell gh bzw. tea, und das
Paket `branch-protection` steht bereit. Es ist kein Befehl in der Devshell,
sondern wird über das justfile aufgerufen (`nix run .#branch-protection -- …`):

```
just forge-login
    geführt anmelden (mit gum), wenn noch nicht geschehen: auf Codeberg mit
    Link zur Token-Seite und den nötigen Berechtigungen, verdeckter Eingabe
    und Prüfung des Tokens; auf GitHub `gh auth login`. Das Token speichert
    tea bzw. gh
just branch-protect [<n>]
    Schutzregel für `branch` anlegen oder aktualisieren: nur per Pull Request,
    kein Force-Push, nicht löschbar, <n> Freigaben (Vorgabe 1, veraltete
    verfallen), der Check muss grün und der Branch aktuell sein; meldet vorher
    an, zeigt die Regel und fragt nach
just protection-info
    die Schutzregeln des Repos
```

Dahinter steht `branch-protection login | protect [--approvals <n>]
[--check <name>] | show`. Das Repo ergibt sich aus dem Remote `origin`. Ohne
Terminal (im Workflow) wird nichts gefragt; ist man dann nicht angemeldet,
bricht es ab. Der Check ist der Job `build` aus `ci.yml`, auf GitHub `build`,
auf Forgejo das Muster `* / build (pull_request)`; anders heißt er mit
`--check`. Den eigenen Pull Request freigeben kann man nicht: wer allein
arbeitet, nimmt `just branch-protect 0`. Auf GitHub gibt es Schutzregeln für
private Repos eines persönlichen Kontos nur mit GitHub Pro.

## Hooks

Die Devshell setzt `core.hooksPath` auf die Hooks aus `lib/hooks.nix`: kein
Commit auf und kein Push nach `branch`, entwickelt wird auf `dev/…` und per Pull
Request gemerget. Verbindlich sind die Schutzregeln der Forge, siehe
`branch-protection`.
