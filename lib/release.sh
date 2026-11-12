# Releases für Programme nach dem Muster von project-flake, auf GitHub wie auf Forgejo (Codeberg):
#
#   project-release check <tag>    passt der Tag zur Version, liegt er auf $BRANCH?
#   project-release publish <tag>  dazu: Release mit den Dateien aus dist/ (und SHA256SUMS) anlegen,
#                                  dann den Branch `release` auf den Tag schieben (nur vorwärts)
#
# NAME, TITLE, VERSION und BRANCH setzt das Paket (lib/release.nix). Für publish im Workflow:
# RELEASE_TOKEN (dort secrets.GITHUB_TOKEN); GITHUB_SERVER_URL und GITHUB_REPOSITORY setzen GitHub
# und Forgejo selbst. Ein erneuter Lauf lädt nur hoch, was dem Release noch fehlt.

usage() {
  echo "Aufruf: project-release check|publish <tag>" >&2
  exit 2
}
[ $# -eq 2 ] || usage
cmd=$1
tag=$2

check() {
  if [ "$tag" != "v$VERSION" ]; then
    echo "$tag passt nicht zur Version $VERSION von $NAME" >&2
    exit 1
  fi
  commit=$(git rev-parse "$tag^{commit}")
  if ! git merge-base --is-ancestor "$commit" "origin/$BRANCH"; then
    echo "$tag liegt nicht auf $BRANCH" >&2
    exit 1
  fi
}

publish() {
  : "${RELEASE_TOKEN:?fehlt (im Workflow: secrets.GITHUB_TOKEN)}"
  : "${GITHUB_SERVER_URL:?fehlt}" "${GITHUB_REPOSITORY:?fehlt}"

  if [ -z "$(find dist -maxdepth 1 -type f ! -name SHA256SUMS -print -quit 2>/dev/null)" ]; then
    echo "dist/ ist leer, erst \`just dist $tag\`" >&2
    exit 1
  fi
  sums=$(cd dist && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%P\0' | sort -z | xargs -0 sha256sum)
  printf '%s\n' "$sums" >dist/SHA256SUMS

  if [ "$GITHUB_SERVER_URL" = https://github.com ]; then
    api="https://api.github.com/repos/$GITHUB_REPOSITORY"
    uploads="https://uploads.github.com/repos/$GITHUB_REPOSITORY"
  else
    api="$GITHUB_SERVER_URL/api/v1/repos/$GITHUB_REPOSITORY"
    uploads=""
  fi
  auth=(-H "Authorization: token $RELEASE_TOKEN" -H "Accept: application/json")

  if ! release=$(curl -fsS "${auth[@]}" "$api/releases/tags/$tag" 2>/dev/null); then
    # Änderungen seit dem letzten Tag
    prev=$(git describe --tags --abbrev=0 "$commit^" 2>/dev/null || true)
    notes=$(git log -n 20 --no-merges --pretty='- %s' ${prev:+"$prev.."}"$commit")
    release=$(jq -n --arg tag "$tag" --arg name "$TITLE $tag" --arg notes "$notes" --arg commit "$commit" \
      '{ tag_name: $tag, name: $name, body: $notes, target_commitish: $commit }' |
      curl -fsS "${auth[@]}" -H "Content-Type: application/json" --data-binary @- "$api/releases")
    echo "Release $tag angelegt"
  fi
  id=$(jq -r .id <<<"$release")

  for file in dist/*; do
    [ -f "$file" ] || continue
    asset=$(basename "$file")
    if jq -e --arg n "$asset" 'any(.assets[]; .name == $n)' <<<"$release" >/dev/null; then
      echo "schon da: $asset"
      continue
    fi
    if [ -n "$uploads" ]; then
      curl -fsS "${auth[@]}" -H "Content-Type: application/octet-stream" --data-binary "@$file" \
        "$uploads/releases/$id/assets?name=$asset" >/dev/null
    else
      curl -fsS "${auth[@]}" -F "attachment=@$file" "$api/releases/$id/assets?name=$asset" >/dev/null
    fi
    echo "hochgeladen: $asset"
  done

  # ein nachträglich angelegtes älteres Release setzt den Server nicht zurück
  if git ls-remote --exit-code --heads origin release >/dev/null; then
    git fetch -q origin release
    if ! git merge-base --is-ancestor FETCH_HEAD "$commit"; then
      echo "release ist schon weiter als $tag und bleibt, wo er ist."
      return
    fi
  fi
  git push origin "$commit:refs/heads/release"
}

case $cmd in
  check) check ;;
  publish)
    check
    publish
    ;;
  *) usage ;;
esac
