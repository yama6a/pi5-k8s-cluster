# raspi-cluster project conventions

A 3x Raspberry Pi 5 Kubernetes cluster on Talos, networked by Cilium, delivered by ArgoCD. The repo is a numbered,
ordered runbook: execute the steps in sequence to stand the cluster up.

## Repository layout

Organized by kind. The runbook order lives in the file NAMES, where the `NN` prefix keeps things in step order at
a glance.

| Path | Holds |
|---|---|
| `lib/shell/` | every bootstrap script (`NN_name.sh`, plus the `DANGEROUS_*` orchestrators) and the shared `common.sh` |
| `docs/` | the narrative and decision record per step (`NN_name.md`) |
| `lib/helm/` | shared charts consumed as a dependency by other charts. See "Shared charts" |
| `lib/bench/` | static payloads for `lib/shell/storage_bench.sh`: the fio job files and the pgbench percentile awk. Mirrors `lib/krr/` |
| `argo_apps/` | everything ArgoCD delivers, the two-tree GitOps root. See "ArgoCD apps" |
| `Makefile` | a thin dispatcher over `lib/shell/` plus the orchestrators. `make help` lists every target |
| `versions.env` | committed. The shared, renovate-managed version recipe: upstream versions + digest pins |
| `.env` | gitignored. Your per-deployment config + secrets, in two blocks: CONFIG then SECRETS. `.env.example` is the committed template |
| `docs/images/` | hardware photos embedded by `docs/01_hardware.md` |
| `secrets/` | the cluster-credential dir (`talosconfig`, `kubeconfig`, sealed-secrets key), written by `03d`. A symlink to an off-repo store, gitignored, never committed |
| `.cache/` | scratch. `03b` caches the downloaded Talos image release under `images/<release>/`, `storage_bench.sh` writes `storage-bench/<UTC>/`. Gitignored |

Run the steps in order: `02_raspi_eeprom`, then `03b` to `03g`, then `04_cilium`, `05_argocd`, and onward. Either
by hand (`bash lib/shell/NN_name.sh`) or via the Makefile. Multi-phase step 03 uses letter sub-phases.

`docs/*.md` holds the why; the scripts stay thin. A decision or trade-off goes in the step's `docs/*.md`, not in a
code comment and not here. This file is only for conventions that span the whole repo.

Every non-obvious reason must exist somewhere, and `docs/NN_*.md` is its DEFAULT home. An inline comment is only
for a reason that belongs to ONE line and that someone editing that line would otherwise miss.

## Comment style (hard rules)

- Default is ZERO comments. The code, the key name, the file's path and the error message beside it ARE the
  documentation. A comment is an exception you justify, not a habit.
- Comment the WHY and WHAT, but ONLY when it is not self-evident. Self-evident code gets no comment.
- Keep them SHORT. A half-sentence on the SAME line as the thing it documents is ideal. Two lines is usually
  already too much. Paragraphs and walls of text never.
- Bullets over sentences. Do not care about grammar, punctuation or full sentences. Shorter is better. Nobody
  reads walls of text.
- NEVER restate a version number in markdown or a comment. Point at where it lives (`versions.env`, or the
  chart's `Chart.yaml`): "bump X in `versions.env`", not the digits. And NEVER explain what a version did or
  changed ("10.0.0 flipped X", "since 1.15"): we only ever roll forward, so version history is dead weight that
  also goes stale. State the CURRENT why, not the diff. The only version worth naming is a forward constraint on
  future bumps: a floor ("needs >=X") or a ceiling ("broken in X, pin <X").

## Language (hard rules)

### The one threshold

Write for a competent developer who does NOT know this particular stack. They know bash, YAML and Kubernetes
basics. Then, line by line:

- Obvious to that developer? **No comment.** `replicas: 1`, `enabled: false`, `namespace: monitoring`.
- Needs expertise in Cilium, Talos, CNPG, shellcheck, Envoy Gateway or Renovate to understand? **Explain it, as
  briefly as you can manage without falling back on jargon.**

`masquerade: true` is the second kind: you have to know Cilium to have any idea what it does, and saying it
plainly takes about three lines. `priorityClassName: system-node-critical` is the first kind, and takes none.

Jargon and assumed knowledge are the problem, not word count. Still aim for the shortest version, but measure
"shortest" against a reader who does not know the term. One line that only lands if you already knew the answer is
not shorter, it just fails faster. Every extra word has to buy comprehension; none of this licenses rambling,
restating, listing or narrating.

### The rules

- **Be right before you're brief.** A confidently wrong comment is worse than no comment, because the next person
  trusts it. Check the mechanism before you describe it. "Talos does not auto-mount cgroup v2" was exactly
  backwards: Talos DOES mount it, which is why cilium must not.
- **Name it in plain words.** Never drop a code, flag, error ID, metric, field or function name and move on.
  `-e SC2034` means nothing by itself; say it turns off the "this variable is never used" check. Same for
  `oom_score_adj`, `rshared`, `noeviction`, `mergeGateways`. If you can't say what an identifier means, you don't
  actually know why the line is there.
- **When it isn't obvious, say what it DOES before why we chose it.** Lead with the plain mechanics.
  `masquerade: true` gets "rewrites pod source IPs to the node IP, which is what lets pods reach the internet"
  FIRST; only then the point about which datapath does it. Rationale is useless to someone who doesn't know the
  term yet. But if the name already tells the reader what it does, skip straight to the why, or write nothing.
- **Finish the sentence with "so ...".** A fact with no consequence is noise. "the source path is dynamic" is
  noise. "the path has a variable in it, so shellcheck can't find the file and fails every script" is
  information. If nothing follows the "so", delete the line.
- **Say what to DO, not what category it belongs to.** "Flip when this project is stable" beats "a rollout net,
  not a steady state". The reader wants an action, not a taxonomy.
- **Don't inflate the stakes.** No shouted labels. State the real consequence even when it turns out mild: "it
  self-heals, this just avoids the churn" is the honest version of what I once called GITOPS-CRITICAL.
- **Name the gap.** If a security or durability feature only half-covers, say so. WireGuard encrypts node-to-node
  traffic; pod-to-pod on the SAME node stays plaintext.
- **Comment the line, not the mechanism.** A short trailing note on the key beats a block above the structure
  explaining how Helm merges it.
- **Don't reach into another file for a reason the local line already carries.** Cross-references go stale and
  cost a jump.
- **If the only thing worth saying is "this is redundant", delete the redundant thing instead.** That is how
  `-e SC1091` left the shellcheck command.

Keep the terms that carry real weight here: "source of truth", "invariant", "idempotent", "trade-off", and
"deliberately X: <reason>". But drop a bare "deliberately" or "by design" with no reason after it. Being told
someone meant to do it is not something the reader can act on.

Banned as empty filler: idiom, house style, posture, load-bearing, cardinal, moot, orthogonal, nuance, semantics,
non-trivial, canonical (unless it literally means the one true copy), "the whole point", "reads as", "earns its
keep". Reach for the concrete verb: "shellcheck can't follow it" beats "is not statically resolvable".

### The test, in order

Would a developer who doesn't know this stack already understand the line? If yes, write nothing. If no, write the
shortest comment that leaves them able to DO something. Anything past that is decoration.

### Earns a comment (about the only cases)

- An outside constraint that explains a weird construction: `RE2 has no negative lookahead, so stamp then drop`.
- A value that looks wrong, dummy or arbitrary: `size: 45Gi # NO-OP under local-path, but the CR requires it`.
- A footgun for whoever edits THAT line next: `# PDB on a single instance would block node upgrades`.
- A non-default picked over the upstream default, phrased as the CURRENT reason: `# default was zone, we have none`.
- A coupling invisible from here: another chart, the script that writes this file, an operator-injected label.
- A manual procedure or ordering: `# to delete: set false, push, let Argo sync, THEN remove in a follow-up commit`.

### Never a comment

- Restating the line. `name` is the name, `enabled: false` is off.
- Teaching the tool. Assume Helm, Kubernetes, bash and Terraform fluency. No "a library chart renders nothing", no
  "default-deny means ...".
- History. What it used to be, what an upstream bug did, what we migrated off, why the old approach failed. We
  only roll forward: state the CURRENT reason or say nothing.
- Anything an adjacent message already says: a Helm `fail` or `required`, a `die`/`warn` string, a Terraform
  `error_message`, a `description`. Write it ONCE, in the message.
- Rationale, trade-offs, alternatives considered, decision records. Those live in `docs/NN_*.md`.
- Counts and measurements ("~848 series", "~90 GUCs"). Stale on arrival and they change nothing.
- Cross-reference schemes between comments ("(c2), symmetric with (h2)"). Every comment stands alone.
- Doc pointers everywhere. At most ONE `See docs/NN_x.md` per file, at the spot with a real runbook.

### Form

- Trailing on the same line beats a block above it. A block above is for a whole file or a whole template.
- File header, when it earns one at all: ONE line saying what the file renders or does. Not an abstract, not a
  feature list, not the file's interface.
- Attach it to the exact line it is about, not to the block that line sits in.
- Group with a blank line, not a comment banner. `# ---- knobs ----` in `lib/shell/` is the one exception.
- Show the result instead of describing it: `# s3://<bucket>/cnpg/<ns>/<name>/{wals,base}` beats a sentence.

### Per file type

- `values.yaml`, `.env.example` and `variables.tf` are the API, so every knob gets ONE column-aligned trailing
  comment: `REQUIRED|OPTIONAL: (type) allowed values, or an e.g.`. Defaulted knobs nobody tunes get nothing, and
  collapse them, e.g. flow-style YAML. The why goes to `docs/`.
- Helm templates: one-line header at most. A `_helpers.tpl` define gets one line or nothing; a one-line define
  gets nothing.
- `Chart.yaml`: `description` is ONE line. Not the place for the chart's interface, its knobs or its design.
- `lib/shell/`: the `die`/`warn`/`say` string IS the comment. One trailing comment per non-obvious knob. Never a
  banner over a function, never a narration of the pipeline below it.
- Terraform: a one-line `description` on variables and outputs instead of a comment above them. Comment only
  non-obvious argument values.
- `docs/*.md`: where the WHY belongs, and still fragments, bullets and tables. Never paragraphs.

## Bootstrap scripts

Every step script follows the same shape. Match it when you add one:

- UX contract: coloured `say`/`die`/`warn`/`ok`/`bad` helpers, `PASS`/`FAIL` counters, and a trailing `summary`
  line, with a non-zero exit on any failure. These come from `lib/shell/common.sh`, not redefined per script.
- Idempotent and re-run-safe (`helm upgrade --install`, re-checking state before acting). Re-running after a
  partial failure is the normal recovery path.
- A `# ---- knobs ----` block near the top: script-local tunables as plain hardcoded assignments, grouped
  together. Scripts take no `${VAR:-default}` env-overridable knobs; to change a value, edit it.
- `set -uo pipefail` baseline, deliberately NOT `-e` in the PASS/FAIL scripts, so checks accumulate failures and
  report a full summary rather than aborting on the first. One-shot scripts that should abort early use `-euo`.
- Native vs dockerized tooling: talos work (`03c` to `03e`) runs its tooling in Docker; cluster-apply
  scripts use native `helm` and `kubectl` and hard-fail if either is missing. Rule of thumb: Talos or image work
  goes in Docker, apply-to-cluster goes native.
- A `DANGEROUS_` prefix on anything that wipes or resets state, so it cannot be run by reflex.

### Where a value lives

Helpers and values each live in exactly one place.

| Kind of value | Lives in |
|---|---|
| Versions and digest pins | `versions.env`, committed |
| Per-deployment scalars (node topology, domains) and all secrets | `.env`, gitignored. Template: `.env.example` |
| Fixed identifiers that are not per-deployment config (namespaces, operator names, the Pi 5 NIC and disk, the Talos API port) | constants in `lib/shell/common.sh` |
| Build-machinery internals used by one script (registry and builder names, the gmake path, the staged-image filename, a step's own check expectations) | that script |

Secrets live in `.env` and are read from it, never prompted at runtime. `common.sh` defaults each to empty so an
older `.env` missing a key does not trip `set -u`. Leaving a secret empty skips the feature it enables; each
key's `.env.example` comment says which.

`.env.example` is the committed template: copy it to `.env` and edit. Personal and network values (IPs, domains,
emails, GHCR user, repo URL) are fake placeholders there, and every secret is an EMPTY placeholder, never a real
value. The version and digest recipe in `versions.env` is real.

`.env` is plain `KEY=value` only: no logic, arrays or command substitution. Anything derived is derived in
`common.sh`.

### `lib/shell/common.sh`

Sourced near the top of every script (`source "${SCRIPT_DIR}/common.sh"`; every script lives beside it). It:

- Self-locates the repo root, loads the committed `versions.env` then the gitignored `.env`, dying with a `cp
  .env.example .env` hint if `.env` is missing.
- Derives the values that cannot live in a flat file: the `CLUSTER_NODES[]` array plus the `NODES` IP list,
  `IFACE`, `INSTALL_DISK`, `TALOS_VERSION` (from `TALOS_IMAGE_RELEASE`) and the `*_VERSION` aliases, plus
  `INSTALLER_REF` and the `IMAGE_CACHE` download path.
- Defines the fixed cluster-identifier constants.
- Provides the `say`/`die`/`warn` plus `ok`/`bad`/`summary` output helpers; `require <tools...>` (preflight, dies
  with an install hint); `CLUSTER_DIR` plus `use_kubeconfig` and `assert_api`; a dockerized `talosctl()`;
  `seal_secret <name> <ns> <key> <value> <out>`; and `ys_set`/`ys_set_list`, the line-surgical values writers.

Never write a tracked YAML file with `yq -i`. It rewrites the whole document and drops the blank line before a
comment block, so even a no-op write leaves the file dirty, which aborts the rebuild at `05_argocd`'s
uncommitted-changes gate. Use `ys_set <file> <value> <key...>` (or `ys_set_list` for a block sequence of
scalars) and assert the result with a `yq -r` read-back. `yq` is still the right tool for reads.

It never sets shell options; each script keeps its own `set` line.

### Cluster credentials location

`secrets/` is the one place `talosconfig` and `kubeconfig` are written, by `03d`. It is a symlink to an off-repo
credential store on a synced drive, so the live secrets stay backed up and out of git, and the `/secrets` ignore
rule keeps them uncommittable. A `.gitkeep` cannot live inside a symlink, which is why there is none.

Downstream scripts reach it via `common.sh`'s `CLUSTER_DIR` constant plus the `use_kubeconfig` helper, which
exports `KUBECONFIG` from there. Read from this path, do not scatter copies.

## Helm wrapper-chart pattern

Every app ArgoCD manages is a thin wrapper chart under its tree's `charts/` dir:
`argo_apps/platform/charts/NN_name/` for platform, `argo_apps/workloads/charts/name/` for workloads.

- `Chart.yaml` pins the upstream chart as a dependency. That version lives here, nowhere else.
- `values.yaml` holds all configuration.
- A first-party chart's OWN `version:` field is inert and stays `0.1.0` forever, marked inline `# local chart,
  never bump version`. Nothing publishes these to a registry, ArgoCD renders from the git path, and every consumer
  pins the `file://` dep at `version: "*"`. NEVER bump it: a bump changes nothing and only churns diffs. The only
  version that moves is the upstream dependency version in `dependencies:`.

The imperative bootstrap script and ArgoCD consume the same chart, release name and namespace, so when Argo adopts
the running release it sees it in-sync: no pod churn, no fighting. No version or value is ever hardcoded in a
script. To change config, edit the chart's `values.yaml`; to upgrade, bump the dependency in `Chart.yaml`.

### `Chart.lock`: commit it only for a REMOTE dependency

This is the one rule with two branches, and it decides several other things:

- A chart with a REMOTE (`https`/`oci`) dependency, meaning the platform operator, CRD and stack charts, COMMITS
  its `Chart.lock`. The lock pins the upstream version and digest against drift, and ArgoCD's repo-server runs
  `helm dependency build`, so a missing or stale lock breaks sync. `make fix-chart-locks` regenerates a stale one.
- A chart whose deps are ALL `file://` (in-repo) is LOCKLESS and gitignores `Chart.lock`. The git commit already
  fixes the deps, so a lock pins nothing and only breaks sync when a hand-edit makes it stale. repo-server
  resolves the in-repo paths at render time.

Either way, gitignore `charts/*.tgz`. NEVER commit one.

### Shared charts (`lib/helm/`)

Charts consumed as a dependency by other charts, rather than by ArgoCD directly, live under `lib/helm/`, outside
the `argo_apps/` trees, because charts in both trees consume them.

All four are `type: application` and pin NO upstream, so each renders its own manifests when included as a
dependency and ships no `Chart.lock` and no vendored tgz. Rule of thumb: render first-party or CR manifests from
values, no lock, no tgz.

| Chart | Renders | Consumer's interface |
|---|---|---|
| `ingress` | the ingress edge: per host a Gateway, HTTPRoute and ReferenceGrant, plus one multi-SAN Certificate per ingress | just `ingresses[]` in values. Per-ingress the only cert knob is `issuer` |
| `pg-cluster` | the CNPG `Cluster`, `PodMonitor`, a default-deny CNP pair, and when backups are on the Barman `ObjectStore` + `ScheduledBackup` | a flat set of REQUIRED knobs: `name`, `postgresVersion`, `highAvailability`, `resources`, `allowedClients`, `deletionProtection`. Plus optional `alertCritical` |
| `redis-instance` | one standalone `Redis` CR, its ServiceMonitor, and a default-deny CNP | REQUIRED: `name`, `redisVersion`, `resources`, `allowedClients`, `persistence`, `deletionProtection`. Plus optional `alertCritical` and a create-time `initialFixedDiskSize` |
| `rabbitmq-topology` | one `User` with operator-GENERATED credentials, the Exchanges/Queues/Bindings it owns, a `<queue>.dlx`/`.dlq` pair per consumer queue, and ONE aggregated `Permission` | a `rabbitmq-topology:` values block |

Notes that matter when consuming them:

- The cluster wiring is hardcoded in each chart as a platform invariant, NOT a per-consumer value: `ingress`'s
  gateway namespace `gateway`, gateway class `eg` and fallback issuer; `rabbitmq-topology`'s broker `rabbitmq` and
  vhost `apps`, which are rejected as overrides.
- `ingress` renders NO SSO. Google-SSO is applied centrally per domain by `04_google_sso`, one SecurityPolicy per
  domain with per-host allowlists.
- `pg-cluster` is Postgres only, no postgis. The image repo is fixed and only `postgresVersion`, the tag, varies,
  owned per workload. `highAvailability` is one bool: true means 2 instances plus a PDB plus switchover, false
  means a single instance with the PDB off and in-place restart. There is no separate
  instances/enablePDB/primaryUpdateMethod knob.
- `redis-instance` is a single standalone instance, no HA or replication. `persistence` is one bool: true means
  durable plus an S3 RDB backup, false means an ephemeral cache with no backup. Every PVC uses the one Longhorn
  class `longhorn-r2-ephemeral` shipped by `02_longhorn`; reclaim is not the prune guard, `deletionProtection` is.
- `rabbitmq-topology` encodes the two patterns as intent: publishEvents/subscribeEvents for an event topic (1
  publisher, N consumers) and consumeCommands/sendCommands for a command topic (N publishers, 1 consumer).
- `pg-cluster` and `redis-instance` are aliased once per instance, so a workload can run one or more.

Consumer rule: declare a local `file://` dependency (`repository: "file://../../../../lib/helm/<name>"`) and
gitignore both `charts/*.tgz` and `Chart.lock`, per the lock rule above. Each shared chart's `values.yaml` holds
the defaults every consumer inherits, merged under the dependency-name key.

All four render from values, so a consumer needs NO template for them at all. The one exception is
`04_google_sso`, which calls `{{ include "ingress.renderIngress" ... }}` inline because it interleaves callback
edges with its own SecurityPolicy. Named templates are global across the chart tree, which is what makes that
work.

## ArgoCD apps: two trees, naming, sync-waves

```
argo_apps/
  root.yaml                 # root-of-roots, applied once by 05_argocd.sh; recurses roots/
  roots/
    0_platform.yaml         #   Application "platform"  (sync-wave 0) -> recurses platform/apps
    1_workloads.yaml        #   Application "workloads" (sync-wave 1) -> recurses workloads/apps
  platform/{apps,charts}/   # CNI, operators, CRDs, storage, gateway, SSO, monitoring, platform-ingress
  workloads/{apps,charts}/  # the actual apps (sample_user_manager, sample_user_signup, sample_audit_logger)
```

The four shared dependency charts live outside this tree, in `lib/helm/`.

### Waves order creation, not health

The root-of-roots creates the platform root first at wave 0, then the workloads root at wave 1 about 5s later. It
does NOT wait for platform health, because there is NO `argoproj.io/Application` health gate, on purpose.

So the platform-to-workloads boundary is advisory creation-ordering, not a hard barrier. A workload that races
ahead of a not-yet-present platform CRD fails its sync and converges via unbounded `syncPolicy.retry`. The same
applies within the platform tree: a wave gets its dependencies' apps applied first, but still retries if it races
ahead. Full reasoning in `05_gitops.md`.

The gap is `ARGOCD_SYNC_WAVE_DELAY`, set in `01_argocd` values. It is a fixed timer, not a readiness gate.

### Platform apps: keep three things in agreement

1. the `platform/apps/NN_name.yaml` filename prefix,
2. the `platform/charts/NN_name/` dir prefix,
3. the `argocd.argoproj.io/sync-wave: "N"` annotation in the manifest.

So a one-glance `ls argo_apps/platform/apps/` reads in deploy order. The prefix is technically mutable, being just
the wave, but we treat it as stable. Do not renumber casually.

Pick the lowest wave that sits after everything the app depends on.

| Wave | App | Why |
|------|-----|-----|
| `0` | cilium, priorityclass, prometheus-operator-crds, vm-operator-crds | the CNI underpins all pod networking, plus the monitoring CRDs everything else's ServiceMonitors land on and the PriorityClasses later pods reference by name |
| `1` | argocd, envoy-gateway, vm-operator | need the CNI. argocd adopts itself; envoy-gateway owns the Gateway API CRDs, before cert-manager, plus the `eg` class |
| `2` | cert-manager, sealed-secrets, longhorn, local-path-provisioner, nic-keeper, cnpg-operator, metrics-server | independent leaves once the CNI and engine are in place |
| `3` | gateway, redis-operator, rabbitmq, barman-cloud-plugin, argocd-webhook-secret | the shared `:80` Gateway + ClusterIssuers need the `eg` class and cert-manager. redis-operator only needs the CNI, so wave 2 would do; it stays at 3 to avoid renumbering. The webhook secret needs sealed-secrets (wave 2) |
| `4` | google-sso | one SecurityPolicy per domain with per-host allowlists, matched by `:authority`, that targetRefs the app routes plus the shared callback host, and the sealed OAuth secret |
| `5` | grafana, victoria-logs, vm-k8s-stack, ntfy, orphan-exporter | the monitoring stack. Their UIs are exposed at wave 6 |
| `6` | platform-ingress | the platform UIs' EDGES. Last, so all backends exist. No SSO here; google-sso at wave 4 gates these routes |
| `7` | redis-backup | the central Redis RDB backup CronJob. Needs the instances and the sealed writer creds |
| `8` | vm-backup | the central VM/VL export CronJob. Needs the monitoring stores from wave 5 |

### Workloads carry no wave

`workloads/apps/name.yaml` and `workloads/charts/name/`, deliberately un-numbered and wave-less. They have nothing
to order among themselves and all reconcile in parallel. Do not add a `sync-wave` annotation or an `NN_` prefix to
a workload. If a workload genuinely depends on another workload, it belongs in platform instead.

Their ingress hosts are gated centrally by `04_google_sso`, not per workload.

### The one hard rule

Keep every app `automated` (auto-sync) with unbounded retry (`retry.limit: -1` plus `refresh: true`). With no
health gate, an OutOfSync or Degraded app no longer stalls later waves or the roots, but auto-sync plus unbounded
retry is the ONLY thing that converges an app on its own: ArgoCD will not re-drive a FAILED revision, yet `limit:
-1` keeps the within-operation retry re-attempting until the dependency lands. A manual-sync app would simply
never converge without a human.

Cilium is the one app that can cut the cluster, and Argo with it, off its own network, yet it auto-syncs with FULL
`selfHeal` and `prune`, the same as every leaf, for convenience and knowingly accepting the danger:

- `selfHeal: true` means an out-of-band break-glass fix (`04_cilium.sh`) IS reverted unless you commit it fast.
- `prune: true` means a resource or CRD removed from the chart IS cascade-deleted on the next sync.
- Price: a bad Cilium change pushed to git applies unattended AND is self-healed in place. Mind your pushes, and
  after any break-glass, commit the fix back to git before `selfHeal` drags the cluster back to the bad state.

See `05_gitops.md` ("sync-wave convention") and `04_networking.md` for the full reasoning.

### Cross-cutting app conventions

Stated here once, not repeated per app doc.

- **Default sync settings: automated leaf.** Unless a doc says otherwise, a platform app is
  `syncPolicy.automated` with `prune: true` plus `selfHeal: true`, plus `ServerSideApply=true` where its CRDs are
  too big for client-side apply's manifest annotation. A safe leaf cannot cut the cluster off its own network, so
  drift just auto-corrects.
- **Every pod-running app carries an explicit `CiliumNetworkPolicy`** unless it is on the deliberately-unpoliced
  list in `04_networking.md`, which is infra that cannot be policed without risking the cluster's own network.
  Hand-written per chart in `templates/networkpolicy.yaml`, default-deny both ways, rolled out audit-first. Two
  Cilium gotchas: a cross-namespace peer needs `matchExpressions: [{key: k8s:io.kubernetes.pod.namespace,
  operator: Exists}]`, because an omitted namespace label, or the empty `{}` selector, is same-namespace-only. And
  disable any upstream-bundled vanilla `NetworkPolicy`: they default to allow-all-egress and Cilium UNIONs them
  with our CNP, blowing default-deny open. See argocd's `global.networkPolicy.create: false`.
- **Push before you expect a sync.** ArgoCD reconciles the pushed git REMOTE, not your working tree. Commit and
  push `argo_apps/**`, including any `Chart.lock`, or the app reports `ComparisonError: path does not exist`.
- **Every Application carries the `resources-finalizer`.** The root-of-roots, both roots, and every
  `platform/apps/**` and `workloads/apps/**` leaf set `metadata.finalizers:
  [resources-finalizer.argocd.argoproj.io]`, so removing or renaming an app cascade-deletes its resources instead
  of orphaning them. `prune` is within-app; it does NOT cascade on Application deletion. Add it to any new app.
  See `05_gitops.md` ("Removing or renaming an app").
- **Alerting is Grafana-only; the cluster carries NO rule CRs.** `vmalert` and `alertmanager` are off, so any
  `PrometheusRule` or `VMRule` is inert because nothing evaluates it, recording rules included. Never enable a
  chart's bundled alerts (`defaultRules`, `prometheusRule.enabled`, and so on); add a Grafana alert file under
  `argo_apps/platform/charts/05_grafana/files/alerts/` instead, which is auto-globbed. Invariant: `kubectl get
  vmrule -A` stays empty. WATCH chart bumps: the vm-k8s-stack renamed `defaultRules.create` to
  `defaultRules.enabled` and silently ignores the old key. See `09_monitoring.md`.
- **Roll-forward only, no rollback history.** Recovery is always a git revert re-synced by Argo, never `argocd app
  rollback` or `kubectl rollout undo`, so retained revision history is dead weight. Every `Application` and every
  first-party workload sets `spec.revisionHistoryLimit: 0`; upstream charts set it via their values knob where one
  exists. The charts that expose no usable knob stay at the default. Do not add a postRenderer just for this. Full
  list in `05_gitops.md`.
- **Runbook doc number is not the sync-wave number.** The top-level `NN_name.md` prefix is runbook step order; the
  `argo_apps/**` `NN_` prefix is the sync-wave. They are independent, and one doc can cover several argo apps at
  different waves. For example `07_ingress.md` documents `01_envoy_gateway` (wave 1), `02_cert_manager` (2),
  `03_gateway` (3), `04_google_sso` (4) and `06_platform_ingress` (6). Never renumber under `argo_apps/` to match
  a doc.
