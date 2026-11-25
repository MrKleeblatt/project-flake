# Die Dateien eines Releases als ein Ordner (`packages.<system>.dist`), `just dist` kopiert ihn nach
# dist/, `project-release publish` lädt dist/ hoch. Aus `release` jedes Pakets mit `dist` (hier
# `beispiel`); beginnt der Dateiname schon mit dem Paketnamen, kommt er nicht noch einmal davor:
#
#   zig-out/bin/beispiel   → beispiel-v<version>-<system>          (ausführbar, $out/bin; mit
#                                                                    `build.target` dieses statt <system>)
#   zig-out/bin/helfer     → beispiel-helfer-v<version>-<system>
#   zig-out/bin/beispiel-x → beispiel-x-v<version>-<system>
#   CHANGELOG.md           → beispiel-CHANGELOG-v<version>.md       (die Endung bleibt)
#   zig-out/webapp         → beispiel-webapp-v<version>.tar.gz      (ein Ordner wird gepackt)
{
  lib,
  stdenv,
  runCommand,
  name,
  version,
  packages,
}:
runCommand "${name}-dist-${version}" { } ''
  mkdir $out
  # add <paket> <packageName> <dateiname> <ziel>
  add() {
    base=$3
    case $base in
      *.*) ext=.''${base#*.} stem=''${base%%.*} ;;
      *) ext= stem=$base ;;
    esac
    case $stem in
      "$2" | "$2"-*) stem=$stem-v${version} ;;
      *) stem=$2-$stem-v${version} ;;
    esac
    share=$1/share/$2
    if [ -d "$share/$base" ]; then
      target=$stem.tar.gz
    elif [ -e "$1/bin/$base" ]; then
      target=$stem-$4
    else
      target=$stem$ext
    fi
    if [ -e "$out/$target" ]; then
      echo "doppelter Name im Release: $target" >&2
      exit 1
    fi
    if [ -d "$share/$base" ]; then
      # reproduzierbar: feste Zeiten, Besitzer und Reihenfolge
      tar -C "$share" --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
        --mode=u+w,go-w -c "$base" | gzip -9n > "$out/$target"
    elif [ -e "$1/bin/$base" ]; then
      install -m755 "$1/bin/$base" "$out/$target"
    else
      install -m644 "$share/$base" "$out/$target"
    fi
  }
  ${lib.concatMapStrings (
    p:
    lib.concatMapStrings (base: ''
      add ${p} ${lib.escapeShellArg p.packageName} ${lib.escapeShellArg base} ${
        lib.escapeShellArg (if p.target != null then p.target else stdenv.hostPlatform.system)
      }
    '') p.release
  ) packages}
''
