# Getting started, zero to hero: Claude Code on Azure (Microsoft Foundry)

Written **2026-10-21** at `main` = `92f7f23` (after PR #21, parking note 002).

**Goal.** Keep working on `idq-cli` with a Claude coding agent while the **day laptop** (no Claude allowed) is the only
machine in reach, and pick the work up again on the **home laptop** (this one, Claude Code 2.1.306) in the evening.
**GitHub (`visakha/idq-cli`) is the only channel between the two.**

**Contents**

0. [Read this first: two blockers](#0-read-this-first-two-blockers)
1. [The three ways to run Claude through Azure](#1-the-three-ways-to-run-claude-through-azure)
2. [Step 1: Foundry resource and Claude deployments](#2-step-1-foundry-resource-and-claude-deployments)
3. [Step 2 (Option A): Claude Code on an Azure VM](#3-step-2-option-a-claude-code-on-an-azure-vm)
4. [Step 3 (Option B): `@claude` from GitHub issues and PRs](#4-step-3-option-b-claude-from-github-issues-and-prs)
5. [Carrying the session context across machines](#5-carrying-the-session-context-across-machines)
6. [The daily loop](#6-the-daily-loop)
7. [What can and cannot be done away from the home laptop](#7-what-can-and-cannot-be-done-away-from-the-home-laptop)
8. [Prompt cheat sheet: the work of the last 24 hours](#8-prompt-cheat-sheet-the-work-of-the-last-24-hours)
9. [Costs and limits](#9-costs-and-limits)
10. [Troubleshooting](#10-troubleshooting)
11. [Checklist](#11-checklist)

---

## 0. Read this first: two blockers

### 0.1 The repository is public and holds live database credentials

`gh repo view` reports **`visibility: PUBLIC`**, and these files have been in Git since the first commit (`993f085`):

| File | What it exposes |
|---|---|
| `src/main/resources/application.properties` | `spring.datasource.password=${IDQ_DB_PASSWORD:<real ADMIN password as the default>}` |
| `docs/Oracle-OCI-Connection-Info.txt` | `OCI_ORACLE_USER='ADMIN'`, the ADMIN password, the wallet password |
| `docs/oci-oracle-info.txt` | connection sample |
| `docs/wallet/*`, `docs/Wallet_OCI4IDQ.zip` | the OCI Autonomous DB wallet (`cwallet.sso` opens without a password) |

Together these give anyone on the internet ADMIN access to the OCI database. Before building a cloud workflow on top
of this repository, do this **in order**:

1. **Rotate** the OCI ADMIN password and **re-download / rotate the wallet** (OCI console → Autonomous Database →
   *Database connection* → *Rotate wallet*). Removing the files from Git does not undo the leak: the old values stay in
   history, forks and caches.
2. Make the repository **private** (GitHub → Settings → *Danger zone* → *Change visibility*). A private repo also
   stops strangers from triggering the `@claude` workflow in Option B (see the warning in §4).
3. Stop tracking the secrets and load them from the environment instead:
   * `application.properties`: `spring.datasource.password=${IDQ_DB_PASSWORD}` (no default),
     `idq.wallet-dir=${IDQ_WALLET_DIR}` (already a variable; drop the `C:/Users/vamsi/...` default or keep it only for
     the home laptop).
   * `git rm --cached` the wallet and connection-info files, add them to `.gitignore`, keep the wallet outside the repo
     (e.g. `C:\Users\vamsi\secrets\oci-wallet` at home, `~/secrets/oci-wallet` on the VM).
   * Optionally purge history with `git filter-repo`. This rewrites every commit and needs a force-push, so decide it
     deliberately; rotation (step 1) is what actually closes the hole.
4. On the cloud side, put the DB password and wallet in **Azure Key Vault** (or the VM's own disk, `chmod 600`), never
   in the repo, an issue, a PR comment or a prompt.

### 0.2 "Claude is not allowed" on the day laptop

Find out what the rule actually covers before relying on this guide. It may forbid the Claude *desktop/CLI app*, or
the *anthropic.com endpoints*, or *any* AI tool on company data. Claude models served from your **own Azure
subscription** (Microsoft Foundry) are a different contract and data path, and IT often treats them differently, but
that is IT's decision, not ours. The options below are ordered so that **nothing Claude-related ever runs on the day
laptop**: it only uses a browser (GitHub, Azure portal) and, at most, an SSH client.

---

## 1. The three ways to run Claude through Azure

| | **Option A: Claude Code on an Azure VM** (recommended) | **Option B: `@claude` in GitHub (Actions + Foundry)** | **Option C: Claude Code CLI on the day laptop → Foundry** |
|---|---|---|---|
| Feels like | Exactly these sessions: interactive terminal, same commands, same tools | Writing an issue / PR comment and getting a PR back | Exactly these sessions |
| Day laptop needs | Browser (Azure Bastion / VS Code for the Web) or SSH | Browser only (github.com) | Claude Code installed locally |
| Can reach OCI Oracle | Yes (wallet on the VM) | Only if you add DB secrets to Actions (not recommended) | Yes |
| Can run IDQ `infacmd` | No | No | Only if that laptop has the Informatica client |
| Policy risk | Low (Claude runs in Azure) | Lowest | High: this *is* "Claude on the laptop" |
| Cost | VM hours + tokens | Actions minutes + tokens | Tokens |

**Recommendation:** set up **A** for real work (long interactive sessions, `mvnw test`, OCI runs) and **B** as a
lightweight fallback for small asks from any browser ("@claude update the parking note", "@claude review this PR").
Skip C unless IT explicitly allows it; the Foundry part of §2 and §3.4 applies to it unchanged.

```
 day laptop (browser/SSH only)            Azure subscription                         GitHub (visakha/idq-cli)
 ─────────────────────────────            ─────────────────────────────────          ─────────────────────────
  Bastion / SSH  ───────────────────────▶  VM: claude + JDK 27 + mvnw  ─── git ──▶  branches, PRs, parking notes
  github.com issue "@claude ..."  ──────────────────────────────────────────────▶  Actions runner ─┐
                                           Foundry resource                                         │
                                           Claude Opus / Sonnet / Haiku  ◀── inference ─────────────┘ (and from the VM)
 home laptop (evening): git pull, claude (Anthropic login as today)  ◀── git ──────  same branches
```

---

## 2. Step 1: Foundry resource and Claude deployments

Needed by every option. Source: [Claude Code on Microsoft Foundry](https://code.claude.com/docs/en/microsoft-foundry).

**Prerequisites**: an Azure subscription with Microsoft Foundry access, permission to create Foundry resources and
deployments (Contributor/Owner on a resource group), Azure CLI (optional).

1. Open the [Microsoft Foundry portal](https://ai.azure.com/) → **Create a resource**. Note the **resource name**, e.g.
   `idq-claude` (Claude Code wants the bare name, never a URL).
2. In the model catalog, deploy three Claude models. **Name each deployment after its model ID** (this lets Claude Code
   recognise the model and give it the 1M-token context window):

   | Role | Deploy (use the newest version your catalog lists) | Deployment name |
   |---|---|---|
   | Opus (main work, like these sessions) | e.g. `claude-opus-5-5` | `claude-opus-5-5` |
   | Sonnet (cheaper day-to-day) | e.g. `claude-sonnet-5-5` | `claude-sonnet-5-5` |
   | Haiku (background tasks, titles) | e.g. `claude-haiku-5-5` | `claude-haiku-5-5` |

   * Pick a **specific model version**, not "auto-update to latest".
   * Choose the **hosting option** (inference on Azure vs on Anthropic infrastructure). If the "not allowed" policy is
     about data leaving Azure, pick Azure hosting and say so to IT.
   * If a model is missing from the catalog for your region/subscription, use what is there and adjust the names below.
3. **Access** (choose one):
   * **Microsoft Entra ID (recommended)**: give your user (and later the VM's managed identity / the GitHub Entra app)
     the **`Azure AI User`** or **`Cognitive Services User`** role on the Foundry resource. No key to store.
   * **API key**: Foundry resource → **Endpoints and keys** → copy **API Key**. Treat it like the DB password.
4. Set a **budget alert** on the resource group (Cost Management → Budgets), e.g. 80 % / 100 % of a monthly figure.

**The Claude Code environment** (used on the VM in §3 and on any machine pointed at Foundry):

```bash
export CLAUDE_CODE_USE_FOUNDRY=1
export ANTHROPIC_FOUNDRY_RESOURCE=idq-claude          # resource name only
# Auth: leave both unset to use Entra ID (az login / managed identity), or set ONE of:
# export ANTHROPIC_FOUNDRY_API_KEY=...                # from Endpoints and keys
# export ANTHROPIC_FOUNDRY_AUTH_TOKEN=...             # an Entra access token obtained elsewhere
export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-5-5'     # = your deployment names
export ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-5-5'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-5-5'
# Optional: 1-hour prompt cache (long sessions like ours re-send a lot of context; writes cost more)
export ENABLE_PROMPT_CACHING_1H=1
```

PowerShell equivalent (for Option C or testing from the home laptop): `$env:CLAUDE_CODE_USE_FOUNDRY = '1'`, etc.

If a deployment name is not a model ID (e.g. `team-opus-prod`), map it in `~/.claude/settings.json` so the 1M window
still applies:

```json
{ "modelOverrides": { "claude-opus-5-5": "team-opus-prod" } }
```

Inside Claude Code, **`/status`** must show **API provider: Microsoft Foundry** and your resource. `/logout` does not
exist in this mode (auth is Azure's).

---

## 3. Step 2 (Option A): Claude Code on an Azure VM

### 3.1 Create the VM

* Image **Ubuntu 24.04 LTS**, size **Standard_D4s_v5** (4 vCPU, 16 GB; Maven + Spring Boot tests are comfortable)
  or B4ms to save money. 64 GB disk.
* **No public IP** if you will use Azure Bastion from the browser; otherwise SSH key only, and restrict inbound port 22
  to your IP.
* Turn on **Auto-shutdown** (VM → Operations → Auto-shutdown), e.g. 18:00 local, so a forgotten VM does not burn
  money in the evening when you are back on the home laptop.
* **Identity** → System assigned: **On**. Then on the Foundry resource → Access control (IAM) → add role
  **`Azure AI User`** → the VM's managed identity. Claude Code then authenticates with no key at all (Entra default
  credential chain picks up the managed identity).

### 3.2 Reaching it from the day laptop without installing anything

In order of preference:

1. **Azure Bastion** (portal → VM → Connect → Bastion): a terminal in the browser tab.
2. **VS Code for the Web / `vscode.dev` with Remote Tunnels**: on the VM run `code tunnel` once (install the VS Code
   CLI), sign in with GitHub, then open `https://vscode.dev/tunnel/<name>` from the day laptop's browser. Gives an
   editor + terminal; run `claude` in that terminal.
3. Plain **SSH** from the laptop, if an SSH client is allowed.

Run Claude Code inside **`tmux`** so a dropped browser tab does not kill the session: `tmux new -A -s idq`.

### 3.3 Install the toolchain (one time)

```bash
sudo apt-get update && sudo apt-get install -y git tmux unzip curl python3 python3-venv
# GitHub CLI
(type -p wget >/dev/null || sudo apt-get install -y wget) && sudo mkdir -p -m 755 /etc/apt/keyrings \
 && wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null \
 && sudo apt-get update && sudo apt-get install -y gh
# Azure CLI (only needed for az login as yourself instead of the managed identity)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
# JDK 27: same vendor as home (Azul Zulu 27, Linux x64 tar.gz from azul.com/downloads)
mkdir -p ~/jdk && tar -xzf zulu27*-linux_x64.tar.gz -C ~/jdk && mv ~/jdk/zulu27* ~/jdk/zulu27
# Claude Code (native installer)
curl -fsSL https://claude.ai/install.sh | bash
```

Maven is not needed: the repo ships `mvnw`.

### 3.4 Environment file

`~/.idq-env` (`chmod 600`), sourced from `~/.bashrc`:

```bash
export JAVA_HOME=$HOME/jdk/zulu27
export PATH=$JAVA_HOME/bin:$HOME/.local/bin:$PATH
# Claude Code -> Foundry (managed identity, no key)
export CLAUDE_CODE_USE_FOUNDRY=1
export ANTHROPIC_FOUNDRY_RESOURCE=idq-claude
export ANTHROPIC_DEFAULT_OPUS_MODEL='claude-opus-5-5'
export ANTHROPIC_DEFAULT_SONNET_MODEL='claude-sonnet-5-5'
export ANTHROPIC_DEFAULT_HAIKU_MODEL='claude-haiku-5-5'
# idq-cli -> OCI Oracle (after §0.1: wallet and password live outside the repo)
export IDQ_WALLET_DIR=$HOME/secrets/oci-wallet
export IDQ_DB_USER=ADMIN
export IDQ_DB_PASSWORD='...'      # better: az keyvault secret show --vault-name ... --name idq-db-password --query value -o tsv
```

Copy the (rotated) wallet to `~/secrets/oci-wallet` with `scp` or download it from the OCI console on the VM. If the
Autonomous DB has an **access control list**, add the VM's outbound IP (or the NAT gateway's) to it.

### 3.5 Clone, check, go

```bash
gh auth login                                     # HTTPS, browser device code; use a fine-grained PAT if preferred
git config --global user.name  "Vamsi Vegi"
git config --global user.email "viz.ply@gmail.com"
mkdir -p ~/wrk-java && cd ~/wrk-java && gh repo clone visakha/idq-cli && cd idq-cli
./mvnw -q test                                    # expect 47 tests passing, no DB needed
tmux new -A -s idq
claude                                            # then /status -> "Microsoft Foundry"
```

Windows-only bits of the repo and what to do on Linux:

| Thing | On the VM |
|---|---|
| `README.md` "use the JDK in C:\Users\vamsi\jdk\zulu27" | `JAVA_HOME=$HOME/jdk/zulu27` (above) |
| `idq.wallet-dir` default `C:/Users/vamsi/...` | `IDQ_WALLET_DIR` env var |
| `docs/batch-script-windows*.bat` (`infacmd`) | not runnable; keep `mock_infacmd=true` (the default) |
| `ext-tools/*.py` | `python3 -I ext-tools/<tool>.py ...`; files have stray bare CRs, open with `newline=''` |
| Line endings | `git config core.autocrlf input` so the VM does not rewrite CRLF files |

### 3.6 Permissions mode

At home these sessions run in *bypass permissions* mode. On the VM the same is reasonable (it is a throwaway box with
nothing but this repo and the wallet), but the wallet is a production-grade credential and the CLI may be pointed at
production: prefer `claude --permission-mode acceptEdits` and approve shell commands, or at least keep the insert-only
rule (§5) in `CLAUDE.md`.

---

## 4. Step 3 (Option B): `@claude` from GitHub issues and PRs

Sources: [Claude Code GitHub Actions](https://code.claude.com/docs/en/github-actions),
[with cloud providers](https://code.claude.com/docs/en/github-actions-cloud-providers).

From the day laptop you then only use github.com: open an issue or comment on a PR with `@claude ...`, and a runner
in GitHub Actions runs Claude Code (inference via your Foundry resource) and answers in a comment or pushes a branch/PR.

**One-time setup**

1. **GitHub identity**: install the official [Claude GitHub App](https://github.com/apps/claude) on `visakha/idq-cli`
   (simplest), or create a custom GitHub App with only *Contents*, *Issues*, *Pull requests* = read/write and add its
   `APP_ID` / `APP_PRIVATE_KEY` as secrets.
2. **Azure trust (OIDC, no stored key)**: Entra ID → App registrations → New (`gh-idq-cli-claude`) →
   *Certificates & secrets* → *Federated credentials* → GitHub Actions, org `visakha`, repo `idq-cli`, entity
   *Branch* `main` (add more for PR events if needed, or use entity *Pull request*). Then on the Foundry resource →
   IAM → **`Azure AI User`** → this app.
3. **Repository secrets** (Settings → Secrets and variables → Actions): `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID` (+ `APP_ID`, `APP_PRIVATE_KEY` for a custom app).
4. **Workflow** `.github/workflows/claude.yml` (shown for the official app; for a custom app add the
   `actions/create-github-app-token@v2` step and `github_token: ${{ steps.app-token.outputs.token }}`):

```yaml
name: Claude (Foundry)

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
  actions: read

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'issues' && (contains(github.event.issue.body, '@claude') || contains(github.event.issue.title, '@claude')))
    runs-on: ubuntu-latest
    timeout-minutes: 60
    concurrency: claude-${{ github.event.issue.number || github.event.pull_request.number }}
    steps:
      - uses: actions/checkout@v6

      - uses: actions/setup-java@v4          # so Claude can run ./mvnw test on the runner
        with:
          distribution: zulu
          java-version: '27'

      - name: Authenticate to Azure
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - uses: anthropics/claude-code-action@v1
        with:
          use_foundry: "true"
          claude_args: '--model claude-opus-5-5 --max-turns 40'
        env:
          ANTHROPIC_FOUNDRY_RESOURCE: idq-claude
          ANTHROPIC_DEFAULT_HAIKU_MODEL: claude-haiku-5-5
```

> **Warning (public repo).** On a public repository *anyone's* `@claude` comment starts this workflow; the action
> rejects non-writers only after Azure login has happened. Another reason to make the repo private (§0.1).

**Limits of Option B**: no Oracle (do not put DB secrets in Actions), no `infacmd`, each run starts cold (it knows only
the repo + `CLAUDE.md` + the issue text), and you review results asynchronously. Good for docs, refactors, unit tests,
mapping-doc edits, reviews.

Example asks, written in an issue:

```text
@claude Read gathered-kb-todos-and-improvements-002.md §6 "Safety rule as a check". Add a unit test that fails when
DELETE, TRUNCATE or DROP appears outside comments in src/main, src/main/resources or idq-to-oracle/*.sql.
Run ./mvnw test. Open a PR from branch insert-only-guard-test.
```

---

## 5. Carrying the session context across machines

What the home sessions "know" lives in three places. Only the first travels by Git today:

| Context | Where | Travels via GitHub? |
|---|---|---|
| Code, docs, parking notes, `docs/common_insights.md`, mapping docs | repo | **Yes** |
| Auto-memory (the rules below) | `C:\Users\vamsi\.claude\projects\C--Users-vamsi-wrk-java-idq-cli\memory\` | **No** (home laptop only) |
| Conversation history, scratchpad scripts (e.g. the `gendocs.py` mapping-doc generator) | home laptop | **No** |

**Fix: commit a `CLAUDE.md` at the repo root.** Claude Code reads it automatically on every machine, in GitHub
Actions too, and it is the closest equivalent of the home memory. Suggested content (the home memory, condensed):

```markdown
# idq-cli: rules for Claude

Read first: README.md, user-guide-cli.md, the newest gathered-kb-todos-and-improvements-NNN.md, docs/common_insights.md.

## Hard rules
- INSERT-ONLY. Never add DELETE, TRUNCATE or DROP to Java code, tests, mock fills or any SQL the code runs
  (incl. idq-to-oracle procedures). LoadMode.Append only; mock fills use MockTables.skipIfPresent/skipIfMarked/skipIf.
  IDQ truncate/DD_DELETE steps are left out and marked `-- Not performed: ...`. Only CREATE TABLE for missing objects.
  The CLI may run against production.
- Ignore tables with BAK/BKP/BACKUP or a date stamp in the name (e.g. *_20231001, *_OCT16): no entities, mocks,
  tests or report sections. Beware false positives like REF_JUNK_NAME_LIST.
- C_S_* legacy MDM timeline is stale: ignore VERSION_SEQ, version-rank loops, version = 1 filters,
  PERIOD_REFERENCE_TIME, TIMELINE_ACTION. Do not port or write them; document the omission in each mapping doc.
- Never put credentials in the repo, issues, PRs or prompts. DB: IDQ_DB_USER / IDQ_DB_PASSWORD / IDQ_WALLET_DIR env vars.

## Conventions
- STG _D_ / _H_ tables map to `<Name>Delta` / `<Name>Hist` records.
- 5 sources (TRS, ECI, FSS, TTF, WIC), 33 in-scope mappings. WIC is the 5th.
- New non-obvious IDQ behaviour (quirks/defects) goes into docs/common_insights.md and is called out in the reply.
- Mapping docs (docs/mappings/*.md) were generated; edit them directly now and keep SQL in sync with *Queries classes.
  "## Lookups" blocks between <!-- lookups:begin/end --> markers come from ext-tools/lookups.py + render_lookups.py.
  Files contain stray bare CRs: read/write with newline=''.
- One branch + PR per piece of work. Parking notes are numbered and incremental (next: 003).

## Build
- JDK 27 (Zulu). Windows home: C:\Users\vamsi\jdk\zulu27. Linux VM: $HOME/jdk/zulu27.
- `./mvnw test` (unit, no DB). `-Dtest=OracleWorkflowIT` / `SourceEntitiesIT` need OCI.
```

Then, when a new rule is learnt on any machine, **add it to `CLAUDE.md` in the same PR**, so the other machine gets
it on the next `git pull`. (At home, the auto-memory keeps working as well; `CLAUDE.md` is the shared copy.)

Also commit small helper scripts you want on both sides (e.g. the mapping-doc generator) under `ext-tools/` rather
than leaving them in a session scratchpad.

---

## 6. The daily loop

**Rule of thumb:** one branch per piece of work, push before you walk away, a short handoff note in the PR.

### Morning (day laptop → VM or GitHub)

```bash
cd ~/wrk-java/idq-cli && git switch main && git pull
git switch -c <topic>                 # or: git switch <topic> && git pull  (continuing last night's branch)
tmux new -A -s idq
claude
```

First prompt of the day:

```text
Read CLAUDE.md, the newest gathered-kb-todos-and-improvements-*.md and the description of the last merged PR
(gh pr list --state merged -L 3). Summarise where we left off and propose the next 3 tasks. Then wait.
```

### Before leaving the VM (noon / end of day)

```text
Commit what is done on this branch, push, and open (or update) a draft PR. In the PR body add a
"## Handoff" section: what is done, what is half-done (file:line), next step, open questions, and
any new rule that belongs in CLAUDE.md (add it there too).
```

Draft PRs are the handoff mechanism: nothing half-done lands on `main`, and the PR body is the note.

### Evening (home laptop, as today)

```powershell
cd C:\Users\vamsi\wrk-java\idq-cli
git fetch --all --prune
gh pr list --state open               # see what the day produced
gh pr checkout <n>                    # continue the day's branch
claude                                # Anthropic login as today; no Foundry variables needed here
```

First prompt:

```text
Read PR #<n> (gh pr view <n> --comments) and its Handoff section, then continue from "next step".
```

Before bed: push, update the PR's Handoff section, merge what is finished. Tomorrow morning starts from `main` again.

**Do not** keep `CLAUDE_CODE_USE_FOUNDRY` set on the home laptop unless you want home sessions billed to Azure too.

---

## 7. What can and cannot be done away from the home laptop

| Work (from the last 24 h of sessions) | VM (A) | GitHub `@claude` (B) | Home only |
|---|---|---|---|
| Java code, services, mock data, unit tests (`./mvnw test`, 47 tests) | ✅ | ✅ | |
| Mapping docs, `common_insights.md`, parking notes, user guide | ✅ | ✅ | |
| `ext-tools` Python (lookups, `idmc_spec.py` regeneration of `idmc/`) | ✅ | ✅ | |
| `idq-to-oracle` procedure edits | ✅ | ✅ | |
| Compile / install procedures on OCI (N1), `OracleWorkflowIT`, `SourceEntitiesIT` | ✅ (wallet on VM) | ❌ | |
| `run-etl` with `etl_process=JAVA` or `ORA_SP` against OCI | ✅ | ❌ | |
| `etl_process=IDQ`, `compare-etl-process` (needs real `infacmd`) | ❌ | ❌ | ✅ (if `infacmd` is reachable there) |
| Code review of a PR | ✅ (`/code-review`) | ✅ | |

Plan the day accordingly: build and unit-test in the morning, run IDQ comparisons in the evening.

---

## 8. Prompt cheat sheet: the work of the last 24 hours

Same kinds of requests the home sessions handled (PRs #17–#21), phrased so they work cold on another machine:

| Goal | Prompt |
|---|---|
| Restart | "Follow §9 of the newest parking note (restart checklist). Report what is blocked." |
| New engine/command | "Add `<command>` to the CLI and the REST API like `compare-etl-process` (EtlConsole, IdqShellCommands, EtlController, a `*Settings` record). Update user-guide-cli.md and README.md. Insert-only." |
| Port a procedure | "Port `sp_ors_main_<mapping>.sql` behaviour to Java in `<Src><Name>Service`; follow the mapping doc `docs/mappings/NNN_*.md`; ignore timeline columns; add the PKEY unit test." |
| Safety sweep | "Grep src/main, src/main/resources and idq-to-oracle for DELETE/TRUNCATE/DROP outside comments; replace with `-- Not performed: ...` and explain each." |
| Insights | "While doing this, list any IDQ behaviour a reader of the mapping name would get wrong, and add them to docs/common_insights.md under the right source." |
| Parking note | "Write gathered-kb-todos-and-improvements-003.md: only what changed since 002, status of 002's to-dos, new to-dos by priority, decisions needed, restart checklist. Same structure as 002." |
| Ship it | "Create branch `<topic>`, commit, push, open a PR with a summary and test results." |
| Review | "/code-review high" (VM) or "@claude review this PR for correctness and insert-only violations" (GitHub). |

---

## 9. Costs and limits

* **Tokens** are billed by Azure on the Foundry resource (Anthropic's per-token rates via the Azure Marketplace). Long
  Opus sessions like ours re-send the whole conversation each turn; prompt caching (on by default) cuts most of it.
  Use Sonnet for routine edits (`/model sonnet`), Opus for design and porting.
* **VM**: D4s_v5 is a few dollars per working day with auto-shutdown; deallocate (not just stop from the OS) when idle
  for days.
* **Actions**: minutes on GitHub-hosted runners (private repos consume the monthly allowance). `--max-turns`,
  `timeout-minutes` and the `concurrency` key in §4 keep runs bounded.
* **Quota**: Foundry deployments have tokens-per-minute limits; if Claude Code reports 429s, raise the deployment's
  TPM quota in the portal or use Sonnet.

---

## 10. Troubleshooting

| Symptom | Fix |
|---|---|
| `Failed to get token from azureADTokenProvider: ChainedTokenCredential authentication failed` | No Entra identity in the environment: on the VM check the managed identity is on and has `Azure AI User`; or `az login`; or set `ANTHROPIC_FOUNDRY_API_KEY`. |
| Repeated connection errors on the first prompt | `ANTHROPIC_FOUNDRY_RESOURCE` is wrong or a URL; it must be the bare resource name. |
| "model not found" / 404 on first request | The `ANTHROPIC_DEFAULT_*_MODEL` values must equal deployment **names**. Foundry has no startup check, so the first request is where it fails. |
| `/status` does not say Microsoft Foundry | `CLAUDE_CODE_USE_FOUNDRY=1` is not exported in this shell (`source ~/.idq-env`; inside tmux too). |
| Context window shows 200K | Deployment name is not a model ID: add `modelOverrides` (§2). |
| GitHub Action: auth error | `id-token: write` missing, or the federated credential's subject does not match the event (branch vs pull request). |
| GitHub Action does nothing | App not installed, workflow not on `main`, or the comment says `/claude` instead of `@claude`. |
| `ORA-12506` / TLS errors from the VM | OCI ACL does not include the VM's IP, or `IDQ_WALLET_DIR` points at the wrong folder. |
| Java build fails on the VM | `java -version` must say 27; `JAVA_HOME` set in the tmux shell. |

---

## 11. Checklist

**Today (home laptop, ~1 h)**

- [ ] Rotate the OCI ADMIN password and wallet; make the repo private; move secrets out of Git (§0.1).
- [ ] Ask IT what "Claude not allowed" covers and whether Claude on your Azure subscription is acceptable (§0.2).
- [ ] Commit `CLAUDE.md` (§5).
- [ ] Create the Foundry resource and three deployments; give yourself `Azure AI User` (§2).
- [ ] Test from home in a separate shell: set the §2 variables, `claude`, `/status`, one prompt.

**Option A (VM, ~1 h)**

- [ ] VM with managed identity, auto-shutdown, Bastion (§3.1–3.2).
- [ ] Toolchain, `~/.idq-env`, wallet in `~/secrets` (§3.3–3.4).
- [ ] Clone, `./mvnw test` green, `claude` → `/status` = Microsoft Foundry (§3.5).

**Option B (GitHub, ~30 min)**

- [ ] Claude GitHub App, Entra app + federated credential + `Azure AI User`, three `AZURE_*` secrets (§4).
- [ ] Commit `.github/workflows/claude.yml`; test with a "@claude summarise the newest parking note" issue.

**Every day**

- [ ] Morning: `git pull`, branch, `claude`, restart prompt (§6).
- [ ] Leaving: commit, push, draft PR with a Handoff section.
- [ ] Evening: `gh pr checkout`, continue, merge what is done, update `CLAUDE.md` with new rules.
