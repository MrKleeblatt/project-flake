# Bausteine, siehe README.md
{
  # alle Ausgaben der Flake eines Programms
  mkApp = import ./app.nix;

  # der Dienst `services.<name>` allein, ohne Paket (mkApp bindet ihn in nixosModules.default ein)
  serviceModule = import ./service.nix;

  # `.version = "…"` aus einer build.zig.zon, als einzige Stelle für die Versionsnummer
  zigVersion =
    file:
    let
      lines = builtins.filter builtins.isString (builtins.split "\n" (builtins.readFile file));
      found = builtins.filter (m: m != null) (
        map (builtins.match ''[[:space:]]*\.version = "([^"]+)",.*'') lines
      );
    in
    if found == [ ] then
      throw "${toString file}: keine Zeile `.version = \"…\",`"
    else
      builtins.head (builtins.head found);
}
