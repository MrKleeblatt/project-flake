# Schutzregeln der Forge für Programme nach dem Muster von project-flake, mit gh (GitHub) bzw.
# tea (Forgejo, Codeberg) und gum für die Abfragen. Das Repo ergibt sich aus dem Remote origin.
# Aufgerufen über das justfile (`just forge-login`, `just branch-protect`, `just protection-info`).
#
#   branch-protection login
#       geführt bei der Forge anmelden, wenn noch nicht geschehen; das Token speichert gh bzw. tea
#   branch-protection protect [--approvals <n>] [--check <name>]
#       Schutzregel für $BRANCH anlegen oder aktualisieren: nur per Pull Request, kein Force-Push,
#       nicht löschbar, <n> Freigaben (Vorgabe 1, veraltete verfallen), der Check aus „Prüfen und
#       bauen“ muss grün und der Branch aktuell sein; meldet vorher an und fragt nach
#   branch-protection show
#       die Schutzregeln des Repos
#
# FORGE (github oder codeberg) und BRANCH setzt das Paket (lib/branch-protection.nix).

usage() {
  echo "Aufruf: branch-protection login | protect [--approvals <n>] [--check <name>] | show" >&2
  exit 2
}
[ $# -ge 1 ] || usage
cmd=$1
shift

codeberg=https://codeberg.org
tokens=$codeberg/user/settings/applications

approvals=1
# der Job `build` aus .forgejo/ bzw. .github/workflows/ci.yml; Forgejo nennt ihn
# „<Workflow> / build (pull_request)“ und erlaubt Muster
case $FORGE in
  github) check=build ;;
  codeberg) check="* / build (pull_request)" ;;
  *)
    echo "unbekannte Forge $FORGE" >&2
    exit 1
    ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --approvals)
      approvals=${2:?--approvals braucht eine Zahl}
      shift 2
      ;;
    --check)
      check=${2:?--check braucht einen Namen}
      shift 2
      ;;
    *) usage ;;
  esac
done

# gum braucht ein Terminal; im Workflow wird nichts gefragt
interactive() {
  [ -t 0 ] && [ -t 1 ]
}

box() {
  gum style --border rounded --border-foreground 212 --padding "0 1" "$@"
}

logged_in() {
  case $FORGE in
    github) gh auth status >/dev/null 2>&1 ;;
    codeberg) tea logins list -o json | jq -e --arg url "$codeberg" 'any(.[]; .url == $url)' >/dev/null ;;
  esac
}

github_login() {
  # gh fragt selbst alles ab und speichert das Token
  gh auth login --hostname github.com
}

codeberg_login() {
  box "Anmeldung bei Codeberg" "" \
    "1. Token anlegen: $tokens" \
    "   unter „Zugangstoken generieren“, Name z.B. tea" \
    "2. Berechtigungen: repository „Lesen und Schreiben“, user „Lesen“" \
    "3. Das Token wird nur einmal angezeigt: kopieren und hier einfügen" \
    "" \
    "tea speichert es, danach ist keine Anmeldung mehr nötig."
  if command -v xdg-open >/dev/null && gum confirm "Seite im Browser öffnen?"; then
    xdg-open "$tokens" >/dev/null 2>&1 || true
  fi
  token=$(gum input --password --header "Token von Codeberg" --placeholder "Token einfügen")
  if [ -z "$token" ]; then
    echo "kein Token eingegeben" >&2
    exit 1
  fi
  # tea prüft das Token beim Anlegen; über die Umgebung, damit es nicht in der Prozessliste steht
  GITEA_SERVER_TOKEN=$token gum spin --show-error --title "Token prüfen und speichern …" -- \
    tea login add --name codeberg.org --url "$codeberg"
}

login() {
  if logged_in; then
    return
  fi
  if ! interactive; then
    echo "bei der Forge nicht angemeldet: im Terminal \`just forge-login\` aufrufen" >&2
    exit 1
  fi
  "${FORGE}_login"
  gum style --foreground 2 "✓ bei $FORGE angemeldet"
}

github_protect() {
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  rules=$(jq -n --arg branch "$BRANCH" --arg check "$check" --argjson approvals "$approvals" '{
    name: $branch,
    target: "branch",
    enforcement: "active",
    conditions: { ref_name: { include: ["refs/heads/\($branch)"], exclude: [] } },
    rules: [
      { type: "deletion" },
      { type: "non_fast_forward" },
      { type: "pull_request", parameters: {
          required_approving_review_count: $approvals,
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: false,
          require_last_push_approval: false,
          required_review_thread_resolution: false } },
      { type: "required_status_checks", parameters: {
          strict_required_status_checks_policy: true,
          required_status_checks: [ { context: $check } ] } }
    ]
  }')
  id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$BRANCH\") | .id")
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$repo/rulesets/$id" --input - <<<"$rules" >/dev/null
    echo "Ruleset $BRANCH in $repo aktualisiert"
  else
    gh api -X POST "repos/$repo/rulesets" --input - <<<"$rules" >/dev/null
    echo "Ruleset $BRANCH in $repo angelegt"
  fi
}

# tea api endet bei einem HTTP-Fehler nicht unbedingt mit einem Fehler, Forgejo antwortet dann
# aber mit { message: … }
tea_api() {
  response=$(tea api "$@")
  if jq -e 'type == "object" and has("message") and (has("rule_name") | not)' <<<"$response" >/dev/null; then
    echo "Codeberg lehnt ab: $(jq -r .message <<<"$response")" >&2
    exit 1
  fi
  printf '%s\n' "$response"
}

codeberg_protect() {
  rule=$(jq -n --arg branch "$BRANCH" --arg check "$check" --argjson approvals "$approvals" '{
    rule_name: $branch,
    enable_push: false,
    required_approvals: $approvals,
    dismiss_stale_approvals: true,
    block_on_rejected_reviews: true,
    block_on_outdated_branch: true,
    enable_status_check: true,
    status_check_contexts: [$check]
  }')
  # erst in eine Variable: in der Pipeline des if beendete ein Fehler nur die Pipeline
  existing=$(tea_api '/repos/{owner}/{repo}/branch_protections')
  if jq -e --arg b "$BRANCH" 'any(.[]; .rule_name == $b)' <<<"$existing" >/dev/null; then
    tea_api -X PATCH "/repos/{owner}/{repo}/branch_protections/$BRANCH" -d @- <<<"$rule" >/dev/null
    echo "Schutzregel $BRANCH aktualisiert"
  else
    tea_api -X POST '/repos/{owner}/{repo}/branch_protections' -d @- <<<"$rule" >/dev/null
    echo "Schutzregel $BRANCH angelegt"
  fi
}

protect() {
  login
  if interactive; then
    box "Schutzregel für $BRANCH auf $FORGE" "" \
      "• nur per Pull Request, kein Force-Push, nicht löschbar" \
      "• $approvals Freigabe(n), veraltete verfallen" \
      "• der Check „$check“ muss grün und der Branch aktuell sein"
    if [ "$approvals" -gt 0 ]; then
      gum style --faint "Den eigenen Pull Request freigeben kann man nicht: allein besser --approvals 0."
    fi
    gum confirm "Anlegen bzw. aktualisieren?" || exit 1
  fi
  "${FORGE}_protect"
}

show() {
  login
  case $FORGE in
    github)
      repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
      gh ruleset list -R "$repo"
      ;;
    codeberg)
      tea_api '/repos/{owner}/{repo}/branch_protections' |
        jq '.[] | { rule_name, enable_push, required_approvals, dismiss_stale_approvals, block_on_outdated_branch, status_check_contexts }'
      ;;
  esac
}

case $cmd in
  login)
    if logged_in; then
      gum style --foreground 2 "✓ schon bei $FORGE angemeldet"
    else
      login
    fi
    ;;
  protect) protect ;;
  show) show ;;
  *) usage ;;
esac
