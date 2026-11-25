{
  description = "Beispiel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    project.url = "git+https://codeberg.org/MrKleeblatt/project-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      project,
    }:
    let
      # Versionsnummer im Format <major>.<minor>.<patch> (Beispiel: 1.0.3)
      # Hier wird die Version aus der build.zig.zon gezogen, das muss aber nicht unbedingt so sein.
      # Man kann die Version auch manuell eintragen.
      version = project.lib.zigVersion ./build.zig.zon;
    in
    project.lib.mkApp {
      inherit self nixpkgs version;

      # selber einstellen
      name = "beispiel";
      title = "Beispiel";
      # "codeberg" oder "github"
      # Das entscheidet, ob `gh` oder `tea` in die Devshell geladen wird. Dazu kommen
      # `just forge-login` (geführte Anmeldung) und `just branch-protect` (stellt die
      # Schutzregeln für master ein), siehe justfile. Die Workflows liegen für beide in
      # `.forgejo/workflows/` und `.github/workflows/`; Forgejo nimmt `.forgejo/`, GitHub
      # `.github/`, der andere Ordner kann weg.
      forge = "codeberg";

      # einfach so lassen
      packages = ./packages.nix;
      module = ./modules.nix;
    };
}
