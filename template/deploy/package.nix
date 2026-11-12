# Das Programm als Paket, siehe flake.nix. Es muss `--socket <pfad>` verstehen.
{
  lib,
  stdenv,
  zig,
  version,
}:
stdenv.mkDerivation {
  pname = "beispiel";
  inherit version;
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../build.zig
      ../build.zig.zon
      ../src
    ];
  };
  nativeBuildInputs = [ zig ];
  doCheck = true;
  meta = {
    mainProgram = "beispiel";
    platforms = lib.platforms.linux;
  };
}
