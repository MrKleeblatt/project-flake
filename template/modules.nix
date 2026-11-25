# Der Teil des NixOS-Moduls, den nur dieses Programm hat; Benutzer, Socket, Daten in /var/lib/beispiel,
# Härtung und Caddy kommen aus project-flake (`services.beispiel.{enable,domain,socket,args,caddyConfig,…}`).
# Alles hier gilt nur mit `services.beispiel.enable`.
{ ... }:
{
  config = {
    services.beispiel.args = [
      "--data"
      "/var/lib/beispiel"
    ];
  };
}
