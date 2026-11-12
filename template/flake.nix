{
  description = "Beispiel";

  # was der Server braucht; die Devshell hat ihre weiteren Inputs in dev/flake.nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # die URL von project-flake eintragen
    project.url = "git+https://<forge>/<besitzer>/project-flake";
  };

  outputs =
    {
      self,
      nixpkgs,
      project,
    }:
    let
      # einzige Stelle der Versionsnummer, die Tags heißen v<version>
      version = project.lib.zigVersion ./build.zig.zon;
    in
    project.lib.mkApp {
      inherit self nixpkgs version;
      name = "beispiel";
      title = "Beispiel";
      package = pkgs: pkgs.callPackage ./deploy/package.nix { inherit version; };
      module = ./deploy/module.nix;

      # das Programm hinter Caddy über HTTP/3
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
