#!/usr/bin/env bash
# One-time setup for the sandbox repo: labels, the UAT branch and the
# simulation variables. Run it with gh logged in as the sandbox org's owner:
#
#   ./setup.sh <org>/<repo>
#
# It does NOT set the GH_PAT secret, branch rules or the push ruleset -
# those are manual steps in README.md.
set -euo pipefail
REPO="${1:?usage: ./setup.sh <org>/<repo>}"

echo "== Labels"
while IFS='|' read -r name color desc; do
  gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" --force
done <<'EOF'
deployment:pci|b60205|Set by the workflow
deployment:non-pci|0e8a16|Set by the workflow
pci-approved|5319e7|Release team: release this exact PCI commit
bug-fix|fbca04|Skips the App Locks (release team only)
bypass-lock|d93f0b|Skips the App Locks (release team only)
sim:deploy-fail|000000|SANDBOX: add before requesting release to make the deploy fail
EOF

echo "== UAT branch (created from main if missing)"
if ! gh api "repos/$REPO/git/ref/heads/UAT" >/dev/null 2>&1; then
  SHA=$(gh api "repos/$REPO/git/ref/heads/main" --jq .object.sha)
  gh api "repos/$REPO/git/refs" -f ref=refs/heads/UAT -f sha="$SHA" >/dev/null
  echo "created UAT at ${SHA:0:7}"
else
  echo "UAT already exists"
fi

echo "== Variables"
gh variable set APP_LOCKED --repo "$REPO" --body false
gh variable set SIM_CONFLUENCE_STATUS --repo "$REPO" --body OPEN
gh variable set SIM_DEPLOY_SECONDS --repo "$REPO" --body 90
# One simulated Jira ticket per test PR: "status|PCI field"
for n in $(seq 1 12); do
  gh variable set "SIM_JIRA_DEV_$n" --repo "$REPO" --body "Ready For Production|No"
done

echo
echo "Done. CONTROLLED_DEPLOYMENTS_ENABLED is deliberately NOT set (phase A)."
echo "Still to do by hand: the GH_PAT secret, branch rules and the push ruleset - see README.md."
