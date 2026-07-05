# raspi-cluster project conventions

A 3x Raspberry Pi 5 Kubernetes cluster on Talos, networked by Cilium, delivered by ArgoCD.
The repo is a numbered, ordered runbook: execute the steps in sequence to stand the cluster up.

## Repository layout

The repo is organized by kind; the numbered, ordered runbook is preserved through the file *names* (the `NN`
prefix keeps things in step order at a glance):

- `lib/shell/` — every bootstrap script (`NN_name.sh`, e.g. `03d_talos_cluster_config.sh`, plus the
  `DANGEROUS_*` orchestrators) and the shared `common.sh` library.
- `docs/` — the narrative + decision record per step (`NN_name.md`, e.g. `03_operating_system.md`).
- `lib/helm/` — shared Helm charts consumed as a dependency by other charts (see "Shared charts" below).
- `argo_apps/` — everything ArgoCD delivers (the two-tree GitOps root; see "ArgoCD apps" below).
- `Makefile` — a thin dispatcher over `lib/shell/` + the orchestrators; `make help` lists every target.
- `.env` (repo root, gitignored) — the single source of truth for configurable values + secrets.
- `docs/images/` — hardware photos embedded by `docs/01_hardware.md`.
- `secrets/` — the cluster-credential dir (`talosconfig`, `kubeconfig`, sealed-secrets key), written by `03d`.
  A symlink to an off-repo store, gitignored (`/secrets`); never committed. See "Cluster credentials location".
- `.cache/` — build scratch + output for the step-03 image build (`03a` writes, `03b` reads); gitignored,
  can grow to >100 GB. Keyed by the pinned build inputs (`BUILD_KEY` in `common.sh`) so a version bump
  lands in a fresh `.cache/<key>/`.

Run the steps in order — `02_raspi_eeprom` -> `03a..03g` -> `04_cilium` -> `05_argocd` -> ... — either by hand
(`bash lib/shell/NN_name.sh`) or via the Makefile (`make <verb-target>`). Multi-phase step 03 uses letter
sub-phases (`03a_talos_image_builder` ... `03g_k8s_upgrade`).

The `docs/*.md` holds the why; the scripts stay thin. When documenting a decision or trade-off, it goes in the
step's `docs/*.md`, not in code comments and not here. This file is only for conventions that span the whole repo.

Always record the reason for a non-obvious setting or decision. Any value, flag, or knob whose purpose isn't
self-evident gets a short why next to it: the step's `.md` for narrative decisions, or an inline comment for a
config/`values.yaml` setting (see the existing comments in the wrapper charts' `values.yaml` for the expected style).
A future reader should never have to guess why a non-default value is what it is.

## Bootstrap scripts

All step scripts follow one house style, match it when adding a new one:

- UX contract: colored `say` / `die` / `warn` / `ok` / `bad` helpers, `PASS`/`FAIL` counters, and a trailing
  `summary` line (`=============== summary: N passed, M failed ===============`), with a non-zero exit on any
  failure. These come from `lib/shell/common.sh` (see below), not redefined per script.
- Idempotent / re-run-safe. Every bootstrap script must be safe to run again (e.g. `helm upgrade --install`,
  re-checking state before acting). Re-running after a partial failure is the normal recovery path.
- `# ---- knobs ----` block near the top: script-local tunables are plain hardcoded assignments, grouped together.
  Scripts take no `${VAR:-default}` env-overridable knobs; to change a value, edit it. Shared values (versions, node
  topology, namespaces, domains, ...) live in the gitignored `.env` (template `.env.example`) instead, see "Shared
  library & config" below. Secrets (tokens, passwords, OAuth client id/secret) live in that same gitignored `.env`
  and are read from it, never prompted at runtime; `lib/shell/common.sh` defaults each to empty so an older `.env` missing
  a key doesn't trip `set -u`. Leaving a secret empty skips the feature it enables (see each key's `.env.example`
  comment).
- `set -uo pipefail` baseline, deliberately not `-e` in the PASS/FAIL scripts, so checks accumulate failures
  and report a full summary rather than aborting on the first. (One-shot scripts that should abort early use `-euo`.)
- Native vs. dockerized tooling: talos/image work (`03a-03e`) runs its tooling (talosctl, cross-builds) in
  Docker; cluster-apply scripts (`04`, `05`) use native `helm` + `kubectl` and hard-fail if either is missing.
  Rule of thumb: Talos/image -> Docker; apply-to-cluster -> native.
- `DANGEROUS_` prefix for destructive scripts (e.g. `DANGEROUS_reset_talos_cluster.sh`): anything that wipes or
  resets state carries the prefix so it can't be run by reflex.

### Shared library & config

Helpers and values each live in exactly one place: the library, plus a gitignored `.env` (with a committed template):

- `lib/shell/common.sh`, sourced near the top of every script (`source "${SCRIPT_DIR}/common.sh"` — every
  script lives beside it in `lib/shell/`). It self-locates the repo root, loads the gitignored `.env`
  (dies with a `cp .env.example .env` hint if it's missing), derives the values that can't live in a flat `.env`
  (the `CLUSTER_NODES[]` array + `NODES` IP list, `IFACE`, `INSTALL_DISK`, the `*_VERSION` aliases, and the
  `BUILD_KEY`/`BUILD_DIR`/`OUT_DIR` build-cache paths), and provides: the `say`/`die`/`warn` + `ok`/`bad`/`summary`
  output helpers; `require <tools...>` (preflight, dies with an install hint); `CLUSTER_DIR` + `use_kubeconfig` /
  `assert_api` (the 03d secrets credentials); a dockerized `talosctl()`; and
  `seal_secret <name> <ns> <key> <value> <out>` (used by 07/09). It never sets shell options; each script keeps
  its own `set` line.
- `.env` (repo root, gitignored) is the single source of truth for the repo's configurable scalar values
  (versions, node topology, domains, namespaces, ...) **and its secrets** (tokens, passwords, OAuth client
  id/secret, in a dedicated section). Plain `KEY=value` only, no logic, arrays, or command substitution (those are
  derived in `lib/shell/common.sh`). `.env.example` is the committed template: copy it to `.env` and edit. Personal/network
  values (IPs, domains, emails, GHCR user, repo URL) are fake placeholders in the template, and every secret is an
  **empty** placeholder there (never a real value); the version/digest/identifier recipe is real. Build-machinery
  internals used by a single script (registry/builder names, the gmake path, the staged-image filename, a step's own
  check expectations) live in that script, not here.

### Cluster credentials location

`secrets/` (repo root) is the canonical output dir for `talosconfig` + `kubeconfig` (written by `03d`). It is a
symlink to an off-repo credential store (a synced drive), so the live secrets stay backed up and out of git —
the `/secrets` ignore rule keeps them uncommittable (a `.gitkeep` can't live "inside" a symlink).
Downstream scripts reach it via `lib/shell/common.sh`'s `CLUSTER_DIR` constant + `use_kubeconfig` helper (which
exports `KUBECONFIG` from there). Read from this path, don't scatter copies.

## Helm wrapper-chart pattern (single source of truth)

Every app ArgoCD manages is a thin wrapper Helm chart under its tree's `charts/` dir:
`argo_apps/platform/charts/NN_name/` for platform, `argo_apps/workloads/charts/name/` for workloads:

- `Chart.yaml` pins the upstream chart as a dependency (the version lives here, nowhere else).
- `values.yaml` holds all configuration.
- `Chart.lock` pins the resolved dependency and must be committed (ArgoCD's repo-server runs `helm dependency build`,
  which requires it; a missing/stale lock breaks sync).

The imperative bootstrap script and ArgoCD consume the same chart, release name, and namespace, so when Argo
adopts the running release it sees it in-sync: no pod churn, no fighting. No versions or values are ever hardcoded in
a script. To change config, edit the chart's `values.yaml`; to upgrade, bump the dependency in `Chart.yaml` and refresh
the lock.

### Shared charts (`lib/helm/`)

Charts consumed as a dependency by other charts (rather than by ArgoCD directly) live under `lib/helm/`,
outside the `argo_apps/` GitOps trees — they belong to neither tree because charts in both trees consume them.
Two live here:

- `lib/helm/ingress-edge/` (`type: library`) — renders the ingress edge (per host a Gateway + HTTPRoute +
  ReferenceGrant, one multi-SAN Certificate per ingress) for a list of ingresses; the platform-ingress chart, each
  workload chart, and `04_google_sso` (its callback hosts) all consume it. It renders NO SSO — Google-SSO is applied
  centrally per domain by `04_google_sso` (one SecurityPolicy per domain with per-host allowlists).
- `lib/helm/pg-cluster/` (`type: application`) — the curated CNPG Postgres wrapper: pins the upstream
  `cnpg/cluster` chart and pre-bakes all its boilerplate, exposing a workload only the REQUIRED knobs
  (`type`/`instances`/`resources`) + a few defaulted ones. Consumed by each Postgres-backed workload
  (`sample_workload`).

Convention for a shared chart + its consumers:

- A **`type: library`** chart (ingress-edge) pins no upstream and ships no `Chart.lock` (it renders nothing itself;
  its `values.yaml` holds the shared defaults every consumer inherits — merged under the dependency-name key, e.g.
  `ingress-edge`, the repo's usual "config under the dependency name" convention).
- A **`type: application`** shared chart (pg-cluster) is the deliberate deviation: because it must pin a real
  upstream dependency it can't be a library, so it DOES ship a committed `Chart.lock` AND commits its vendored
  `charts/*.tgz` (overriding the usual tgz gitignore) — a `file://` consumer's `helm dependency build` won't fetch
  this transitive REMOTE dependency over the network, so it has to travel in git. See its `.gitignore` for the why.
- A consumer declares either as a **local `file://` dependency** (`repository: "file://../../../../lib/helm/<name>"`),
  commits the resulting `Chart.lock` (run `helm dependency update`), and gitignores its own `charts/*.tgz`. ArgoCD's
  repo-server runs `helm dependency build`, which resolves the relative path inside the repo checkout — so the lock
  MUST be committed.
- A consumer's whole template is often one line (`{{ include "ingress-edge.render" . }}`); config is all values
  (pg-cluster renders via its dependency, so a consumer needs no template for it at all — just the values block).

## ArgoCD apps: two trees + naming & sync-wave convention

Everything ArgoCD manages lives under `argo_apps/`, split into a platform tree and a workloads tree, gated by a
root-of-roots:

```
argo_apps/
  root.yaml                 # root-of-roots, applied once by 05_argocd.sh; recurses roots/
  roots/
    0_platform.yaml         #   Application "platform"  (sync-wave 0) -> recurses platform/apps
    1_workloads.yaml        #   Application "workloads" (sync-wave 1) -> recurses workloads/apps
  platform/{apps,charts}/   # CNI, operators, CRDs, storage, gateway, SSO, monitoring, platform-ingress
  workloads/{apps,charts}/  # the actual apps (sample-workload)
```
(Shared dependency charts — the ingress edge + the pg-cluster wrapper — live outside this tree in `lib/helm/`.)

The root-of-roots creates the platform root first and waits for it to be Healthy (which aggregates every
platform app's health) before creating the workloads root. So workloads never reconcile against missing
CRDs/namespaces on a cold boot; the platform -> workloads ordering is enforced once, here.

Platform apps keep the numbered convention. The `NN` prefix is the app's sync-wave number, keep three things in
agreement:

1. the `platform/apps/NN_name.yaml` filename prefix,
2. the `platform/charts/NN_name/` dir prefix,
3. the `argocd.argoproj.io/sync-wave: "N"` annotation in the manifest.

So a one-glance `ls argo_apps/platform/apps/` reads in deploy order. The prefix is technically mutable (it's just the
wave) but we treat it as stable, don't renumber casually.

Workloads apps are deliberately un-numbered and wave-less (`workloads/apps/name.yaml`, `workloads/charts/name/`):
the whole platform is already Healthy by the time the workloads root is created, so they have nothing left to order among
themselves and all reconcile in parallel. Don't add a `sync-wave` annotation or an `NN_` prefix to a workload; if a
workload genuinely depends on another workload, it belongs in platform instead.

### How to choose a wave (platform only)

`sync-wave` orders how the platform root creates its child Application objects: lower runs first, and the root waits
for a wave to be Synced + Healthy before creating the next. Pick the lowest wave that sits after everything the app
depends on. (Workloads don't use waves, see above.)

Current platform waves:

| Wave | App                                                    | Why                                                                        |
|------|--------------------------------------------------------|----------------------------------------------------------------------------|
| `0`  | cilium, prometheus-operator-crds, vm-operator-crds     | the CNI (underpins all pod networking), plus the monitoring CRDs everything else's ServiceMonitors land on. |
| `1`  | argocd, envoy-gateway, vm-operator                     | need the CNI; argocd adopts itself, envoy-gateway owns the Gateway API CRDs (before cert-manager) + the `eg` class. |
| `2`  | cert-manager, sealed-secrets, longhorn, local-path-provisioner, nic-keeper, cnpg-operator | independent leaves after the platform (CNI + engine) is in place. |
| `3`  | gateway                                                | the shared :80 Gateway + ClusterIssuers (needs the `eg` class + cert-manager). |
| `4`  | google-sso                                             | CENTRAL Google-SSO: one SecurityPolicy per domain (per-host allowlists, matched by `:authority`) that targetRefs the app routes + the shared callback host google-sso.<domain> + the sealed OAuth secret. |
| `7`  | grafana, victoria-logs, vm-k8s-stack                   | the monitoring stack (workloads only now); their UIs are exposed by the platform-ingress app at wave 8. |
| `8`  | platform-ingress                                       | the platform UIs' EDGES (argocd/grafana/vmui/vlogs): per-host Gateway + HTTPRoute + ReferenceGrant + one shared multi-SAN Certificate. No SSO here — google-sso (wave 4) gates these routes. Last so all backends (argocd wave 1, monitoring wave 7) exist. |

Every ingress edge (per host a Gateway + HTTPRoute + ReferenceGrant, one multi-SAN Certificate per ingress) is
rendered by ONE shared Helm library chart, `lib/helm/ingress-edge/` (see the wrapper-chart section). The
platform-ingress app, each workload chart, and `04_google_sso` (its callback hosts) consume it. SSO is NOT an
edge concern — it's central per domain in `04_google_sso` (one SecurityPolicy with per-host allowlists), so a
workload's ingress is just plain edges and its hosts are gated by listing them in `04_google_sso` domains[].hosts.

Workloads (`sample-workload`, the sample app + its CNPG Postgres + its open/SSO ingress) carry no wave; they live
in the workloads tree, which the root-of-roots only creates after the entire platform above is Healthy. A workload's
ingress (rendered by the same library) carries its OWN SSO allowlist, independent of the platform ingress.

### Cross-cutting app conventions (stated here once, not repeated per app doc)

- **Default sync posture: automated leaf.** Unless a doc says otherwise, a platform app is
  `syncPolicy.automated` with `prune: true` + `selfHeal: true` (plus `ServerSideApply=true` where its CRDs
  blow the client-side last-applied-annotation limit). A "safe leaf" can't cut the cluster off its own
  network, so drift just auto-corrects. The only exception is Cilium (auto-sync *without* `selfHeal`/`prune`),
  called out in `04_networking.md` / `05_gitops.md`.
- **Commit `Chart.lock` before an app syncs.** Any wrapper chart with dependencies needs its resolved
  `Chart.lock` committed: ArgoCD's repo-server runs `helm dependency build`, which requires it. Run
  `helm dependency update <chart>` and commit the lock, or the app sits `OutOfSync` with a
  `helm dependency build` error.
- **Push before you expect a sync.** ArgoCD reconciles the pushed git *remote*, not your working tree.
  Commit + push `argo_apps/**` (incl. `Chart.lock`) or the app reports `ComparisonError: path does not exist`.
- **Runbook doc number ≠ sync-wave number.** The top-level `NN_name.md` prefix is *runbook step order*; the
  `argo_apps/**` `NN_` prefix is the *sync-wave*. The two are independent: one doc can cover several argo apps
  at different waves — e.g. `07_ingress.md` documents argo apps `01_envoy_gateway` (wave 1), `02_cert_manager`
  (wave 2), `03_gateway` (wave 3), `04_google_sso` (wave 4) and `08_platform_ingress` (wave 8). Never renumber
  under `argo_apps/` to match a doc.

### The one hard rule

Never put a manual-sync (or otherwise perpetually-`OutOfSync`) app at an earlier wave than apps that depend on it. A
manual app starts OutOfSync and its wave never clears, so the root never creates later-wave apps, self-management stalls.

This is why Cilium auto-syncs despite being the app that can cut the cluster (and Argo) off its own network. To keep
that safe it auto-syncs without `selfHeal` and with `prune: false`:

- `selfHeal: false` -> an out-of-band break-glass fix (`04_cilium.sh`) is never auto-reverted mid-incident.
- `prune: false` -> a removed CRD is never cascade-deleted.
- Price: a bad Cilium change pushed to git applies unattended. Mind your pushes, and after any break-glass commit the
  fix back to git (otherwise its app sits OutOfSync at wave 0 and blocks later waves).

See `05_gitops.md` ("sync-wave convention") and `04_networking.md` (circular-dependency caveat) for the full reasoning.
