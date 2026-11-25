# Die Dateien eines Releases als ein Ordner (`packages.<system>.dist`), `just dist` kopiert ihn nach
# dist/, `project-release publish` lädt dist/ hoch. Aus `release` jedes Pakets (hier `beispiel`):
#
#   zig-out/bin/beispiel   → beispiel-v<version>-<system>          (ausführbar, $out/bin)
#   zig-out/bin/helfer     → beispiel-helfer-v<version>-<system>
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
  # add <paket> <packageName> <dateiname>
  add() {
    base=$3
    case $base in
      *.*) ext=.''${base#*.} stem=''${base%%.*} ;;
      *) ext= stem=$base ;;
    esac
    if [ "$stem" = "$2" ]; then
      stem=$2-v${version}
    else
      stem=$2-$stem-v${version}
    fi
    if [ -d "$1/share/$2/$base" ]; then
      target=$stem.tar.gz
    elif [ -e "$1/bin/$base" ]; then
      target=$stem-${stdenv.hostPlatform.system}
    else
      target=$stem$ext
    fi
    if [ -e "$out/$target" ]; then
      echo "doppelter Name im Release: $target" >&2
      exit 1
    fi
    if [ -d "$1/share/$2/$base" ]; then
      # reproduzierbar: feste Zeiten, Besitzer und Reihenfolge
      tar -C "$1/share/$2" --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner \
        --mode=u+w,go-w -c "$base" | gzip -9n > "$out/$target"
    elif [ -e "$1/bin/$base" ]; then
      install -m755 "$1/bin/$base" "$out/$target"
    else
      install -m644 "$1/share/$2/$base" "$out/$target"
    fi
  }
  ${lib.concatMapStrings (
    p:
    lib.concatMapStrings (base: ''
      add ${p} ${lib.escapeShellArg p.pname} ${lib.escapeShellArg base}
    '') p.release
  ) packages}
''
