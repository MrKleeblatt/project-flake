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
      # "codeberg" oder "github": bringt `project-forge` (Schutzregeln für master) mit tea bzw. gh
      # in die Devshell; die Workflows der Vorlage liegen in .forgejo/, für GitHub nach
      # .github/workflows/ verschieben
      forge = "codeberg";

      # am besten einfach so lassen
      package = pkgs: pkgs.callPackage ./deploy/package.nix { inherit version; };
      module = ./deploy/module.nix;

      # Optional.
      # Hiermit wird das Programm hinter Caddy über HTTP/3 getestet.
      smokeTest = {
        start = "exec beispiel --socket $SOCKET";
        requests = [
          {
            path = "/";
            expect = "";
          }
        ];
      };

      devShell =
        { pkgs, ... }:
        {
          packages = with pkgs; [ zig ];
        };
    };
}
