{
  description = "Beispiel – Entwicklungsumgebung";

  # eigene Flake, damit Systeme, die ../flake.nix einbinden, nur dessen Inputs im Lock haben. Was in
  # die Shell kommt, steht in ../flake.nix (`devShell`). Aufruf: `nix develop ./dev`
  inputs = {
    app.url = "path:..";
    nixpkgs.follows = "app/nixpkgs";
  };

  outputs = inputs: { devShells = inputs.app.lib.devShells inputs; };
}
