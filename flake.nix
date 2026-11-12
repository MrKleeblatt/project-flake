{
  description = "Gemeinsames Deployment für Programme auf einem NixOS-Server: Paket, Dienst hinter Caddy, Checks, Devshell, Releases";

  # keine Inputs: nixpkgs kommt vom Programm (`mkApp { nixpkgs = …; }`), so hat ein Server, der die
  # Programme einbindet, nur sein eigenes nixpkgs im Lock
  outputs =
    { self }:
    {
      lib = import ./lib;

      # `nix flake init -t <URL dieses Repos>`
      templates.default = {
        path = ./template;
        description = "Programm nach dem Muster von project-flake (Forgejo, Runner auf dem Server)";
      };
    };
}
