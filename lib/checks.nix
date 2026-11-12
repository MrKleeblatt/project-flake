# Checks eines Programms (`nix flake check`), siehe mkApp in lib/app.nix:
#
#   package   Build mit den Tests des Pakets
#   module    NixOS mit `services.<name>` unter einer Domain: Socket, Caddy, keine offenen Ports
#   format    alle .nix-Dateien wie `nix fmt`
#   yaml      alle YAML-Dateien mit yamllint, wenn das Repo eine .yamllint.yaml hat
#   http3     mit smokeTest: das Programm hinter Caddy mit der Konfiguration aus dem Modul, über HTTP/3
#
# smokeTest = {
#   start = "befehl";  # startet das Programm auf $SOCKET (läuft im Hintergrund), $TMPDIR ist frei
#   requests = [ { path = "/api/health"; expect = "core"; } ];  # 200 und `expect` in der Antwort
# };
{
  self,
  nixpkgs,
  pkgs,
  name,
  version,
  server,
  nixosModule,
  moduleTest,
  smokeTest,
  extraChecks,
}:
let
  inherit (pkgs) lib;
  domain = "${name}.example.com";

  evalConfig =
    extra:
    (nixpkgs.lib.nixosSystem {
      inherit (pkgs.stdenv.hostPlatform) system;
      modules = [
        nixosModule
        {
          services.${name} = {
            enable = true;
            inherit domain;
            secretsDir = "/run/secrets/${name}";
          };
          boot.loader.grub.enable = false;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          system.stateVersion = lib.trivial.release;
        }
        extra
      ];
    }).config;

  cfg = evalConfig (moduleTest.config or { });
  service = cfg.services.${name};
  unit = cfg.systemd.services.${name};
  vhost = cfg.services.caddy.virtualHosts.${domain}.extraConfig;

  require =
    checks:
    let
      failed = builtins.filter (c: !c.assertion) checks;
    in
    if failed == [ ] then true else throw (lib.concatMapStringsSep "\n" (c: c.message) failed);

  moduleChecks = [
    {
      assertion = server.version == version;
      message = "Paket ${server.version}, aber Version ${version}";
    }
    {
      assertion = service.socket == "/run/${name}/${name}.sock";
      message = "Socket ${toString service.socket} statt /run/${name}/${name}.sock";
    }
    {
      assertion = builtins.elem cfg.services.caddy.user cfg.users.groups.${name}.members;
      message = "Caddy ist nicht in der Gruppe ${name}";
    }
    {
      assertion = lib.hasInfix "unix/${service.socket}" vhost;
      message = "Caddy spricht unter ${domain} nicht über den Socket";
    }
    {
      assertion = lib.hasInfix "--socket ${service.socket}" unit.serviceConfig.ExecStart;
      message = "${name}.service startet ohne --socket";
    }
    {
      assertion = unit.serviceConfig.PrivateNetwork;
      message = "${name}.service hat mit Socket Netzwerk";
    }
    {
      assertion = builtins.elem "caddy.service" unit.before;
      message = "${name}.service startet nicht vor Caddy";
    }
    {
      assertion =
        cfg.networking.firewall.allowedTCPPorts == [ ] && cfg.networking.firewall.allowedUDPPorts == [ ];
      message = "das Modul öffnet Ports, das ist Sache des Servers";
    }
  ]
  # die Assertions der Module selbst
  ++ cfg.assertions
  ++ (moduleTest.assertions or (_: [ ])) cfg;
in
{
  package = server;

  module =
    assert require moduleChecks;
    pkgs.writeText "${name}-module-check" (cfg.systemd.units."${name}.service".text + vhost);

  format = pkgs.runCommand "${name}-format-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
    find ${self} -name '*.nix' -print0 | xargs -0 -r nixfmt --check
    touch $out
  '';
}
// lib.optionalAttrs (builtins.pathExists (self + "/.yamllint.yaml")) {
  yaml = pkgs.runCommand "${name}-yaml-check" { nativeBuildInputs = [ pkgs.yamllint ]; } ''
    cd ${self}
    yamllint .
    touch $out
  '';
}
// lib.optionalAttrs (smokeTest != null) {
  http3 =
    pkgs.runCommand "${name}-http3-check"
      {
        nativeBuildInputs = [
          server
          pkgs.caddy
          pkgs.curl
        ];
        # der virtuelle Host aus dem Modul, mit dem Socket der Sandbox statt /run/…
        inherit vhost;
        socketPath = service.socket;
        passAsFile = [ "vhost" ];
      }
      ''
        export HOME=$TMPDIR XDG_DATA_HOME=$TMPDIR XDG_CONFIG_HOME=$TMPDIR
        export SOCKET=$TMPDIR/${name}.sock
        (${smokeTest.start}) &
        {
          cat <<EOF
        {
          admin off
          storage file_system $TMPDIR/caddy
          local_certs
          skip_install_trust
          http_port 18080
          https_port 18443
        }
        localhost:18443 {
        EOF
          sed "s#$socketPath#$SOCKET#g" "$vhostPath"
          # extraConfig endet nicht immer mit einem Zeilenumbruch
          printf '\n}\n'
        } > Caddyfile
        caddy run --config Caddyfile --adapter caddyfile &

        check() {
          for _ in $(seq 100); do
            if curl -sk --http3-only -o out -w '%{http_version} %{http_code}' "https://localhost:18443$1" > status &&
              [ "$(cat status)" = "3 200" ]; then
              break
            fi
            sleep 0.2
          done
          echo "$1: $(cat status) $(head -c 200 out)"
          test "$(cat status)" = "3 200"
          grep -qF -- "$2" out
        }
        ${lib.concatMapStrings (r: ''
          check ${lib.escapeShellArg r.path} ${lib.escapeShellArg r.expect}
        '') smokeTest.requests}

        kill $(jobs -p)
        touch $out
      '';
}
// extraChecks { inherit pkgs evalConfig; }
