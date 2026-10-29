# Sandbox: test the UAT release pipeline without Heroku

A throwaway public repo for testing `workflows/phase2.yaml` end to end on a personal GitHub account. The workflow in `.github/workflows/pr_validation.yml` is **generated from `phase2.yaml`** by `build_sandbox.py`: every gate, the queue, the pinned merge and the deploy breaker are the real code. Only the outside services are simulated.

| Real pipeline | Sandbox simulation |
|---|---|
| Jira ticket status + PCI field | Repo variable `SIM_JIRA_<KEY>`, e.g. `SIM_JIRA_DEV_1 = Ready For Production\|No` |
| Confluence App Lock row | Repo variable `SIM_CONFLUENCE_STATUS` (`OPEN`, `FROZEN`, ... ; deleted = blank) |
| Heroku build + dynos + Cloudflare purge | Waits `SIM_DEPLOY_SECONDS` (default 90), then succeeds. Fails if the PR has the `sim:deploy-fail` label |
| Jira deploy comment | Shown as a notice in the run summary |

**Never install the sandbox workflow in a real repo** - it reports fake deploys as healthy. The only secret it needs is `GH_PAT`; no Jira, Confluence, Heroku or Cloudflare credentials go anywhere near it. Company names and the real PCI path list are replaced (`sandbox-app`; PCI paths `./* .github/** config/** src/payments/**`).

## 1. One-time setup

1. **Organization.** Create a free organization from your personal account (Your profile → Organizations → New organization → Free). Teams only exist in organizations, and the workflow checks team membership.
2. **Teams.** In the org: a team named exactly **`release`** with you in it. Optional: a `release-bot` team.
3. **Second account (recommended).** Invite a second GitHub account to the org with write access (e.g. through a `developers` team), **not** in `release`. It plays the developer: it opens the test PRs, and it is the "someone outside release" in the authorisation tests. With one account, skip those tests (A5, A7, A9's developer half, C3, C5).
4. **Repo.** Create a **public** repo in the org (default branch `main`). Copy **everything in this `sandbox/` folder** into the repo root, including `.github/`. In `.github/CODEOWNERS`, replace `YOUR-ORG`. Push to `main`.
5. **`GH_PAT` secret.** Create a classic token on your account with `repo` and `read:org`, then store it (gh prompts for the value - don't put it on the command line):
   ```bash
   gh secret set GH_PAT --repo YOUR-ORG/YOUR-REPO
   ```
   In the sandbox your own account plays the bot.
6. **Labels, UAT branch, variables:**
   ```bash
   ./setup.sh YOUR-ORG/YOUR-REPO
   ```
   This creates `UAT` from `main`, the labels, `APP_LOCKED=false`, `SIM_CONFLUENCE_STATUS=OPEN`, `SIM_DEPLOY_SECONDS=90`, and tickets `SIM_JIRA_DEV_1` … `SIM_JIRA_DEV_12` all `Ready For Production|No`. It leaves `CONTROLLED_DEPLOYMENTS_ENABLED` unset.
7. **Settings → General → Pull Requests:** allow squash merging.
8. **Branch rule on `UAT`** (Settings → Rules → Rulesets → New branch ruleset, target `UAT`, enforcement Active):
   - Require a pull request before merging, with **Require review from Code Owners**.
   - Require status checks: **`PR validation`**. Never add `Release to UAT`.
   - Restrict who can update the branch to you (you stand in for the bot), and leave the developer account out.
   - Required approvals: leave at 0 for now; test B2 turns it on.
9. **Push ruleset** (New push ruleset): **Restrict file paths** `.github/**/*`, enforcement Active, bypass = the `release` team.

## 2. Running the tests

Use the test plan (UAT release pipeline test plan page) and run phases A, B and C in order. **Skip** setup items S2 and S7 and phase D - the simulations replace them. Translate the real-world steps like this:

| Test plan says | In the sandbox |
|---|---|
| Ticket Ready For Production / In Progress | `gh variable set SIM_JIRA_DEV_2 --body "In Progress\|No"` (and back) |
| Set the ticket's PCI field to Yes | `gh variable set SIM_JIRA_DEV_6 --body "Ready For Production\|Yes"` |
| Confluence row not OPEN | `gh variable set SIM_CONFLUENCE_STATUS --body FROZEN`, or `gh variable delete SIM_CONFLUENCE_STATUS` for blank; set back to `OPEN` after |
| A PR that crashes on boot | Add the `sim:deploy-fail` label **before** requesting release |
| "While another release is deploying" | Any release holds the queue for `SIM_DEPLOY_SECONDS`; raise it (e.g. 180) if you need more time |
| Non-PCI file / PCI file | `src/pages/home.html` / `src/payments/card.js` or `config/app.json` |
| Jira comment | Notice in the run summary: `SANDBOX Jira comment on DEV-…` |

**Use one ticket per PR** (`DEV-1` … `DEV-12`): put the key in the PR title, e.g. `DEV-3 change home page`.

### Handy commands

From a clone of the sandbox repo (as the developer account for opening PRs):

```bash
git switch UAT && git pull
git switch -c test/dev-1
echo "<!-- $(date) -->" >> src/pages/home.html
git commit -am "DEV-1 non-PCI change" && git push -u origin test/dev-1
gh pr create --base UAT --title "DEV-1 non-PCI change" --body "sandbox test"
```

As the release account:

```bash
gh pr edit 1 --add-reviewer YOUR-ORG/release        # request release (non-PCI)
gh pr edit 1 --remove-reviewer YOUR-ORG/release     # then add again to re-request
gh pr edit 1 --add-label pci-approved               # release a PCI PR
gh variable set APP_LOCKED --body true              # lock
gh variable set CONTROLLED_DEPLOYMENTS_ENABLED --body true   # phase B onwards
gh variable set UAT_DEPLOY_FAILED --body false      # clear the breaker
gh run list --limit 5 && gh run watch               # follow the runs
```

## 3. Keeping it in sync

After any change to `workflows/phase2.yaml`, regenerate and copy the result into the sandbox repo:

```bash
python sandbox/build_sandbox.py
```

It rewrites `sandbox/.github/workflows/pr_validation.yml`, refuses to run if any real-service call or company name would survive into the copy, and syntax-checks every script (needs `node` and `bash`; skipped otherwise).
