#!/usr/bin/env bash
# Väntar på CI-körningen för en commit och skriver ut resultatet.
# Vid fel skrivs de felande stegen och kompilator-/testfel ur loggen ut.
#
# Användning: scripts/ci-wait.sh [commit-sha]      (standard: HEAD)
# Kräver: gh (GitHub CLI) med läsrätt till repots Actions.
# Avslutningskod: 0 = grönt, 1 = rött, 2 = ingen körning hittades / timeout.
set -euo pipefail

REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || echo cufk/stemsplitter-macos)}"
SHA="$(git rev-parse "${1:-HEAD}")"
TIMEOUT="${CI_WAIT_TIMEOUT:-1800}"
INTERVAL=20
start=$(date +%s)

echo "==> Väntar på CI för ${SHA:0:7} i $REPO"
run_id=""
while :; do
    if [ -z "$run_id" ]; then
        run_id=$(gh api "repos/$REPO/actions/runs?head_sha=$SHA&per_page=20" \
            --jq '[.workflow_runs[] | select(.name=="CI")] | sort_by(.created_at) | last | .id // empty')
    fi
    if [ -n "$run_id" ]; then
        read -r status conclusion url < <(gh api "repos/$REPO/actions/runs/$run_id" \
            --jq '"\(.status) \(.conclusion // "-") \(.html_url)"')
        [ "$status" = "completed" ] && break
        [ "$status" != "${last:-}" ] && echo "    $status …"
        last="$status"
    else
        [ -z "${announced:-}" ] && echo "    ingen körning ännu …"
        announced=1
    fi
    if [ $(( $(date +%s) - start )) -gt "$TIMEOUT" ]; then
        echo "==> Timeout efter ${TIMEOUT}s"; exit 2
    fi
    sleep "$INTERVAL"
done

echo "==> $conclusion  $url"
gh api "repos/$REPO/actions/runs/$run_id/jobs" \
    --jq '.jobs[] | "    [\(.conclusion)] \(.name)"'

[ "$conclusion" = "success" ] && exit 0

gh api "repos/$REPO/actions/runs/$run_id/jobs" \
    --jq '.jobs[] | select(.conclusion!="success" and .conclusion!="skipped") | "\(.id)\t\(.name)\t\(.conclusion)\t" + ([.steps[] | select(.conclusion=="failure") | .name] | join(", "))' |
while IFS=$'\t' read -r job_id job_name job_conclusion steps; do
    echo
    echo "==> Jobb '$job_name' ($job_conclusion) föll på steg: ${steps:-–}"
    # Infrastrukturfel (t.ex. ingen ledig runner) syns bara som annotationer
    gh api "repos/$REPO/check-runs/$job_id/annotations" \
        --jq '.[] | select(.annotation_level=="failure") | "    [annotation] \(.message)"' 2>/dev/null || true
    log=$(gh api "repos/$REPO/actions/jobs/$job_id/logs" 2>/dev/null | sed -E 's/^[0-9T:.-]+Z //')
    errs=$(printf '%s\n' "$log" | grep -E '(: error: |error: |✘|FAIL|Traceback|AssertionError|##\[error\])' | sort -u | head -40)
    if [ -n "$errs" ]; then
        printf '%s\n' "$errs"
    else
        printf '%s\n' "$log" | tail -40
    fi
done
exit 1
