# Git-Hooks für die Devshell (core.hooksPath): auf `branch` kommt nur, was über einen Pull Request
# gemerget wurde. Lokal umgehbar (`--no-verify`), verbindlich sind die Schutzregeln der Forge.
{
  linkFarm,
  writeShellScript,
  branch,
}:
linkFarm "project-hooks" {
  pre-commit = writeShellScript "pre-commit" ''
    if [ "$(git symbolic-ref --short -q HEAD)" = ${branch} ]; then
      echo "Nicht auf ${branch} committen, sondern auf einem Branch dev/…: git switch -c dev/<name>" >&2
      exit 1
    fi
  '';
  pre-push = writeShellScript "pre-push" ''
    while read -r _ _ remote_ref _; do
      if [ "$remote_ref" = refs/heads/${branch} ]; then
        echo "Nicht nach ${branch} pushen, sondern einen Pull Request von dev/… öffnen." >&2
        exit 1
      fi
    done
  '';
}
