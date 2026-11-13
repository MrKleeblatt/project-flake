# Releases für Programme nach dem Muster von project-flake, auf GitHub wie auf Forgejo (Codeberg).
# Jeder Merge nach $BRANCH ist ein Release, sein Tag heißt v<version>:
#
#   project-release tag      der Tag zur Version: v$VERSION
#   project-release check    gibt es v$VERSION noch nicht und ist es neuer als der letzte Tag?
#                            (Pull Request; im Release darf der Tag schon auf dem Commit liegen)
#   project-release publish  dazu: liegt der Commit auf $BRANCH? Tag setzen, Release mit den
#                            Dateien aus dist/ (und SHA256SUMS) anlegen
#
# NAME, TITLE, VERSION und BRANCH setzt das Paket (lib/release.nix). Für publish im Workflow:
# RELEASE_TOKEN (dort secrets.GITHUB_TOKEN); GITHUB_SERVER_URL und GITHUB_REPOSITORY setzen GitHub
# und Forgejo selbst. Ein erneuter Lauf lädt nur hoch, was dem Release noch fehlt.

usage() {
  echo "Aufruf: project-release tag|check|publish" >&2
  exit 2
}
[ $# -eq 1 ] || usage
cmd=$1
tag="v$VERSION"

# Tags werden auf origin nachgesehen, so reicht im Pull Request ein flacher Checkout
check() {
  commit=$(git rev-parse HEAD)
  tags=$(git ls-remote --tags --refs origin 'v*' | sed 's|.*refs/tags/||')
  # bei einem annotierten Tag zählt der Commit dahinter (^{})
  existing=$(git ls-remote --tags origin "refs/tags/$tag" "refs/tags/$tag^{}" | tail -n1 | cut -f1)
  if [ -n "$existing" ]; then
    # ein erneuter Lauf des Releases für denselben Commit
    if [ "$existing" = "$commit" ]; then
      return
    fi
    echo "$tag gibt es schon, für ein Release die Version von $NAME erhöhen" >&2
    exit 1
  fi
  latest=$(printf '%s\n' "$tags" | sort -V | tail -n1)
  if [ -n "$latest" ] && [ "$(printf '%s\n%s\n' "$latest" "$tag" | sort -V | tail -n1)" != "$tag" ]; then
    echo "$tag ist nicht neuer als $latest" >&2
    exit 1
  fi
}

publish() {
  : "${RELEASE_TOKEN:?fehlt (im Workflow: secrets.GITHUB_TOKEN)}"
  : "${GITHUB_SERVER_URL:?fehlt}" "${GITHUB_REPOSITORY:?fehlt}"

  git fetch -q origin "$BRANCH"
  if ! git merge-base --is-ancestor "$commit" FETCH_HEAD; then
    echo "$commit liegt nicht auf $BRANCH" >&2
    exit 1
  fi

  if [ -z "$(find dist -maxdepth 1 -type f ! -name SHA256SUMS -print -quit 2>/dev/null)" ]; then
    echo "dist/ ist leer, erst \`just dist\`" >&2
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

  if [ -z "$existing" ]; then
    git tag "$tag" "$commit"
    git push -q origin "refs/tags/$tag"
    echo "Tag $tag gesetzt"
  fi

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
}

case $cmd in
  tag) echo "$tag" ;;
  check) check ;;
  publish)
    check
    publish
    ;;
  *) usage ;;
esac
