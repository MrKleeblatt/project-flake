# Der Dienst `services.<name>`, gleich für alle Programme:
#
# - Benutzer und Gruppe `<name>`, Unit `<name>.service`, das Programm (`meta.mainProgram` des
#   Pakets) lauscht mit `--socket` auf /run/<name>/<name>.sock und hat dann kein Netzwerk.
# - Mit `domain` liefert Caddy es aus (`caddyConfig`, Vorgabe: alles an den Socket); Caddy kommt in
#   die Gruppe `<name>`, um den Socket zu benutzen. Ports öffnet das Modul keine, das ist Sache des
#   Servers.
# - Secrets nennt das Programm in `secrets` (Dateiname → wofür), der Server legt sie in `secretsDir`.
#
# Was das Programm darüber hinaus braucht (Argumente, StateDirectory, weitere Dienste), setzt sein
# eigenes Modul, siehe `module` in mkApp.
{ name, title }:
{
  config,
  lib,
  ...
}:
let
  cfg = config.services.${name};
  inherit (lib) mkOption mkDefault types;

  # nichts vom übrigen System sehen oder verändern; mit mkDefault, damit ein Programm einzelnes lockern kann
  confined = lib.mapAttrs (_: mkDefault) {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    CapabilityBoundingSet = "";
    AmbientCapabilities = "";
    RestrictSUIDSGID = true;
    RestrictRealtime = true;
    RestrictNamespaces = true;
    LockPersonality = true;
    RemoveIPC = true;
    MemoryDenyWriteExecute = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@privileged"
    ];
    # Daten anderer Dienste; das eigene StateDirectory bringt systemd selbst in das tmpfs
    TemporaryFileSystem = [ "/var/lib" ];
    # der Rest des Servers soll weiterlaufen
    MemoryMax = "50%";
    CPUWeight = 50;
  };
in
{
  options.services.${name} = {
    enable = lib.mkEnableOption title;

    package = mkOption {
      type = types.package;
      description = "Paket von ${title}, gestartet wird `meta.mainProgram`.";
    };

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "${name}.example.com";
      description = ''
        Domain, unter der Caddy ${title} ausliefert (das Zertifikat holt Caddy selbst). `null`: den
        Reverse-Proxy selbst einrichten, z.B. `reverse_proxy unix/''${config.services.${name}.socket}`.
      '';
    };

    socket = mkOption {
      type = types.nullOr types.path;
      default = "/run/${name}/${name}.sock";
      description = "Unix-Socket, auf dem ${title} lauscht (`--socket`). `null` nur, wenn das Programm selbst eine andere Art anbietet.";
    };

    socketGroupMembers = mkOption {
      type = types.listOf types.str;
      default = lib.optional config.services.caddy.enable config.services.caddy.user;
      defaultText = lib.literalExpression "lib.optional config.services.caddy.enable config.services.caddy.user";
      description = "Benutzer, die den Socket benutzen dürfen (Mitglieder der Gruppe `${name}`).";
    };

    args = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "weitere Argumente für das Programm, nach `--socket`";
    };

    caddyConfig = mkOption {
      type = types.lines;
      default = "reverse_proxy unix/${cfg.socket}";
      defaultText = lib.literalExpression ''"reverse_proxy unix/''${config.services.${name}.socket}"'';
      description = "Inhalt des virtuellen Hosts `domain` in Caddy";
    };

    secrets = mkOption {
      type = types.attrsOf types.str;
      # nicht readOnly: das zählt die Vorgabe als Definition, das Modul des Programms setzt den Wert
      default = { };
      description = ''
        Secrets, die ${title} aus `secretsDir` liest (Dateiname → wofür), damit ein Server sie
        abfragen und dort ablegen kann. Setzt nur das Modul des Programms.
      '';
    };

    secretsDir = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "/run/secrets/${name}";
      description = ''
        Ordner mit je einer Datei für jedes Secret aus `secrets`, z.B. von sops-nix. Die Dateien
        dürfen root gehören, die Dienste bekommen sie per systemd-Credential.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != null -> cfg.socket != null;
        message = "services.${name}.domain: Caddy spricht über den Unix-Socket mit ${title}, services.${name}.socket darf nicht null sein.";
      }
    ];

    users.users.${name} = {
      isSystemUser = true;
      group = name;
    };
    users.groups.${name}.members = cfg.socketGroupMembers;

    systemd.services.${name} = {
      description = title;
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      # Proxy erst starten, wenn der Socket da ist
      before = lib.optional (cfg.socket != null && config.services.caddy.enable) "caddy.service";
      serviceConfig =
        confined
        // {
          ExecStart = lib.escapeShellArgs (
            [ (lib.getExe cfg.package) ]
            ++ lib.optionals (cfg.socket != null) [
              "--socket"
              cfg.socket
            ]
            ++ cfg.args
          );
          User = name;
          Group = name;
          Restart = "on-failure";
          RuntimeDirectory = name;
          RuntimeDirectoryMode = "0750";
          # Socket für die Gruppe les- und schreibbar
          UMask = mkDefault "0007";
        }
        // (
          if cfg.socket != null then
            {
              # nur der Unix-Socket im Dateisystem, kein Netzwerk
              PrivateNetwork = true;
              IPAddressDeny = "any";
              RestrictAddressFamilies = [ "AF_UNIX" ];
            }
          else
            {
              RestrictAddressFamilies = [
                "AF_UNIX"
                "AF_INET"
                "AF_INET6"
              ];
            }
        );
    };

    # HTTP/3 bietet Caddy auf HTTPS von sich aus an
    services.caddy = lib.mkIf (cfg.domain != null) {
      enable = true;
      virtualHosts.${cfg.domain}.extraConfig = cfg.caddyConfig;
    };
  };
}
