# Der Teil des NixOS-Moduls, den nur dieses Programm hat; Benutzer, Socket, Härtung und Caddy
# kommen aus project-flake (`services.beispiel.{enable,domain,socket,args,caddyConfig,…}`).
{ config, lib, ... }:
let
  cfg = config.services.beispiel;
in
{
  config = lib.mkIf cfg.enable {
    # Daten in /var/lib/beispiel
    services.beispiel.args = [
      "--data"
      "/var/lib/beispiel"
    ];
    systemd.services.beispiel.serviceConfig.StateDirectory = "beispiel";
  };
}
