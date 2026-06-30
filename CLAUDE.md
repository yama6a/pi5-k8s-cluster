# raspi-cluster — project conventions

A 3× Raspberry Pi 5 Kubernetes cluster on Talos, networked by Cilium, delivered by ArgoCD.
The repo is a **numbered, ordered runbook**: you execute the steps in sequence to stand the cluster up.

## Repository layout

Each stage is a numbered pair:

- `NN_name/` — the executable bits (scripts, generated config).
- `NN_name.md` — the narrative + **decision record** for that step.

Run them in order: `01_hardware` → `02_raspi_eeprom` → `03_operating_system` → `04_networking` → `05_gitops`.
Multi-phase steps use letter sub-phases (e.g. `03a_talos_image_builder` … `03e_nic_hardening`).

**The `.md` holds the "why"; the scripts stay thin.** When documenting a decision or trade-off, it goes in the step's
`.md`, not in code comments and not here. This file is only for conventions that span the whole repo.

## Bootstrap scripts

All step scripts follow one house style — match it when adding a new one:

- **UX contract:** colored `say` / `die` / `warn` / `ok` / `bad` helpers, `PASS`/`FAIL` counters, and a trailing
  `summary` line (`=============== summary: N passed, M failed ===============`), with a **non-zero exit on any
  failure**. These are **not redefined per script** — they come from `lib/common.sh` (see below).
- **Idempotent / re-run-safe.** Every bootstrap script must be safe to run again (e.g. `helm upgrade --install`,
  re-checking state before acting). Re-running after a partial failure is the normal recovery path.
- **`# ---- knobs ----` block** near the top: script-local tunables are **plain hardcoded assignments** — scripts take
  **no `${VAR:-default}` env-overridable knobs**; to change a value, edit it. They're grouped together. **Shared** values
  (versions, node topology, namespaces, domains, …) instead live in the gitignored `.env` (template `.env.example`) —
  see "Shared library & config" below. The sole runtime-injected value is a **secret** (ArgoCD's `GIT_TOKEN`), which is
  **prompted**, never an env knob.
- **`set -uo pipefail` baseline** — deliberately *not* `-e` in the PASS/FAIL scripts, so checks accumulate failures
  and report a full summary rather than aborting on the first. (One-shot scripts that should abort early use `-euo`.)
- **Native vs. dockerized tooling:** talos/image work (`03a–03e`) runs its tooling (talosctl, cross-builds) **in
  Docker**; cluster-apply scripts (`04`, `05`) use **native `helm` + `kubectl` and hard-fail if either is missing**.
  Rule of thumb: Talos/image → Docker; apply-to-cluster → native.
- **`DANGEROUS_` prefix** for destructive scripts (e.g. `DANGEROUS_reset_talos_cluster.sh`) — anything that wipes or
  resets state carries the prefix so it can't be run by reflex.

### Shared library & config

Helpers and values each live in exactly one place — the library, plus a gitignored `.env` (with a committed template):

- **`lib/common.sh`** — sourced near the top of every script (`source "${SCRIPT_DIR}/../lib/common.sh"`, or
  `${SCRIPT_DIR}/lib/common.sh` for repo-root scripts). It self-locates the repo root, **loads the gitignored `.env`**
  (dies with a `cp .env.example .env` hint if it's missing), **derives** the values that can't live in a flat `.env`
  (the `CLUSTER_NODES[]` array + `NODES` IP list, `IFACE`, `INSTALL_DISK`, the `*_VERSION` aliases, and the
  `BUILD_KEY`/`BUILD_DIR`/`OUT_DIR` build-cache paths), and provides: the `say`/`die`/`warn` + `ok`/`bad`/`summary`
  output helpers; `require <tools…>` (preflight — dies with an install hint); `CLUSTER_DIR` + `use_kubeconfig` /
  `assert_api` (the 03d talos-cluster credentials); a dockerized `talosctl()`; and
  `seal_secret <name> <ns> <key> <value> <out>` (used by 12/15/16). It **never sets shell options** — each script keeps
  its own `set` line.
- **`.env`** (repo root, **gitignored**) — the single source of truth for the repo's **configurable** scalar values
  (versions, node topology, domains, namespaces, …). Plain `KEY=value` only — no logic, arrays, or command
  substitution (those are derived in `lib/common.sh`). **`.env.example`** is the committed template: copy it to `.env`
  and edit. Personal/network values (IPs, domains, emails, GHCR user, repo URL) are fake placeholders in the template;
  the version/digest/identifier recipe is real. Build-machinery internals used by a single script — registry/builder
  names, the gmake path, the staged-image filename, a step's own check expectations — live in **that script**, not here.
  This `.env` + derivations replaced the former `lib/config.sh` (itself a merge of the per-folder
  `config.sh` / `03_config.sh` files).

### Cluster credentials location

`03_operating_system/talos-cluster/` is the canonical output dir for `talosconfig` + `kubeconfig` (written by `03d`).
Downstream scripts reach it via `lib/common.sh`'s `CLUSTER_DIR` constant + `use_kubeconfig` helper (which exports
`KUBECONFIG` from there) — read from this path, don't scatter copies.

## Helm wrapper-chart pattern (single source of truth)

Every app ArgoCD manages is a **thin wrapper Helm chart** under its tree's `charts/` dir —
`argo_apps/platform/charts/NN_name/` for platform, `argo_apps/workloads/charts/name/` for workloads:

- `Chart.yaml` pins the **upstream chart as a dependency** (the version lives here, nowhere else).
- `values.yaml` holds **all** configuration.
- `Chart.lock` pins the resolved dependency — **must be committed** (ArgoCD's repo-server runs `helm dependency build`,
  which requires it; a missing/stale lock breaks sync).

The imperative bootstrap script **and** ArgoCD consume the **same chart, release name, and namespace**, so when Argo
adopts the running release it sees it in-sync — no pod churn, no fighting. **No versions or values are ever hardcoded in
a script.** To change config, edit the chart's `values.yaml`; to upgrade, bump the dependency in `Chart.yaml` and refresh
the lock.

## ArgoCD apps: two trees + naming & sync-wave convention

Everything ArgoCD manages lives under `argo_apps/`, split into a **platform** tree and a **workloads** tree, gated by a
**root-of-roots**:

```
argo_apps/
  root.yaml                 # root-of-roots — applied once by 05_argocd.sh; recurses roots/
  roots/
    0_platform.yaml         #   Application "platform"  (sync-wave 0) -> recurses platform/apps
    1_workloads.yaml        #   Application "workloads" (sync-wave 1) -> recurses workloads/apps
  platform/{apps,charts}/   # CNI, operators, CRDs, storage, gateway, SSO, monitoring
  workloads/{apps,charts}/  # the actual apps (sample-workload)
```

The root-of-roots creates the **platform** root first and waits for it to be **Healthy** (which aggregates every
platform app's health) before creating the **workloads** root. So workloads never reconcile against missing
CRDs/namespaces on a cold boot — the platform→workloads ordering is enforced **once, here**.

**Platform** apps keep the numbered convention. **The `NN` prefix IS the app's sync-wave number** — keep three things in
agreement:

1. the `platform/apps/NN_name.yaml` filename prefix,
2. the `platform/charts/NN_name/` dir prefix,
3. the `argocd.argoproj.io/sync-wave: "N"` annotation in the manifest.

So a one-glance `ls argo_apps/platform/apps/` reads in deploy order. The prefix is technically mutable (it's just the
wave) but we treat it as stable — don't renumber casually.

**Workloads** apps are deliberately **un-numbered and wave-less** (`workloads/apps/name.yaml`, `workloads/charts/name/`):
the whole platform is already Healthy by the time the workloads root is created, so they have nothing left to order among
themselves and all reconcile **in parallel**. Don't add a `sync-wave` annotation or an `NN_` prefix to a workload — if a
workload genuinely depends on another workload, it belongs in platform instead.

### How to choose a wave (platform only)

`sync-wave` orders how the **platform** root creates its child Application objects: lower runs first, and the root waits
for a wave to be **Synced + Healthy** before creating the next. Pick the lowest wave that sits *after* everything the app
depends on. (Workloads don't use waves — see above.)

Current platform waves:

| Wave | App                                                    | Why                                                                        |
|------|--------------------------------------------------------|----------------------------------------------------------------------------|
| `0`  | cilium, prometheus-operator-crds, vm-operator-crds     | the CNI — underpins all pod networking — plus the monitoring CRDs everything else's ServiceMonitors land on. |
| `1`  | argocd, envoy-gateway, vm-operator                     | need the CNI; argocd adopts itself, envoy-gateway owns the Gateway API CRDs (before cert-manager) + the `eg` class. |
| `2`  | cert-manager, sealed-secrets, longhorn, local-path-provisioner, nic-keeper, cnpg-operator | independent leaves after the platform (CNI + engine) is in place. |
| `3`  | gateway                                                | the shared Gateway + ClusterIssuers (needs the `eg` class + cert-manager). |
| `4`  | google-sso                                             | SecurityPolicies + callback hosts (needs the gateway + sealed-secrets).    |
| `6`  | argocd-ingress                                         | exposes argocd via the gateway.                                            |
| `7`  | grafana, victoria-logs, vm-k8s-stack                   | the monitoring stack — each app now ships its **own** SSO ingress edge (Gateway + Certificate + HTTPRoute + ReferenceGrant) beside the Service it fronts. |

**Workloads** (`sample-workload` — the sample app + its CNPG Postgres + its open/SSO ingress) carry **no wave** — they live
in the workloads tree, which the root-of-roots only creates after the entire platform above is Healthy.

### The one hard rule

**Never put a manual-sync (or otherwise perpetually-`OutOfSync`) app at an earlier wave than apps that depend on it.** A
manual app starts OutOfSync and its wave never clears, so the root never creates later-wave apps — self-management stalls.

This is why **Cilium auto-syncs** despite being the app that can cut the cluster (and Argo) off its own network. To keep
that safe it auto-syncs **without `selfHeal` and with `prune: false`**:

- `selfHeal: false` → an out-of-band break-glass fix (`04_cilium.sh`) is **never auto-reverted** mid-incident.
- `prune: false` → a removed CRD is **never cascade-deleted**.
- Price: a bad Cilium change *pushed to git* applies unattended — mind your pushes, and **after any break-glass commit the
  fix back to git** (otherwise its app sits OutOfSync at wave 0 and blocks later waves).

See `05_gitops.md` ("sync-wave convention") and `04_networking.md` (circular-dependency caveat) for the full reasoning.
