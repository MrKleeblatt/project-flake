# Beschreibt, was zu einem Paket dazu gehört, wie es gebaut wird und was davon
# zum Release auf dem Forge gehört. Das Paket, das wie `name` in flake.nix heißt
# (sonst das erste), ist `default` und läuft auf dem Server.
{ pkgs, lib, ... }:
[
  {
    packageName = "beispiel";
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./build.zig
        ./build.zig.zon
        ./src
        ./justfile
        ./CHANGELOG.md
      ];
    };
    build = {
      # Programme, die zum Bauen gebraucht werden (just ist immer dabei); sie kommen
      # auch in die Devshell
      tools = [ pkgs.zig ];
      # ob tests ausgeführt werden sollen. default: false
      doChecks = true;
      # Dieser Befehl startet die Tests. default: "just test"
      checkCommand = "just test";
      # Dieser Befehl wird im Source-Ordner gestartet, um das Projekt zu bauen.
      # Es darf nur ein einziger Befehl sein; Justfile empfohlen!
      command = "just build";
    };
    # Alle Dateien, die in das Release kommen sollen, relativ zum Source-Ordner
    # nach dem Build. Ausführbare Dateien kommen ins Paket nach bin/, alles andere
    # (auch Ordner) nach share/beispiel/. Im Release heißen sie
    # beispiel-v<version>-x86_64-linux und beispiel-CHANGELOG-v<version>.md, ein
    # Ordner wird zu .tar.gz.
    release = [
      "zig-out/bin/beispiel"
      "CHANGELOG.md"
    ];
    meta = {
      # Wie das Hauptprogramm heißen soll; muss eine ausführbare Datei aus `release` sein
      mainProgram = "beispiel";
      platforms = lib.platforms.linux;
    };
  }
]
