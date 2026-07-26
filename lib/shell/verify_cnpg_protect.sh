#!/usr/bin/env bash
#
# verify_cnpg_protect.sh
#
# Static guard for the orphan-not-delete invariant (docs/13_backups.md): every CNPG DB unit a workload renders
# must carry `argocd.argoproj.io/sync-options: Prune=false,Delete=false`, so a GitOps prune ORPHANS the database
# (keeps it running on its PVCs) instead of destroying it. local-path reclaim is Delete, so the annotation is the
# ONLY data-safety net. Five of the six protected resources come from the shared pg-cluster helper automatically;
# the cnpg-backup-s3 SealedSecret is per-workload copy-paste and is the one that gets forgotten on a new DB
# workload. Workloads are enumerated dynamically so a new one can't slip past a hardcoded list.
#
# For each argo_apps/workloads/charts/* that renders a CNPG Cluster: assert every DB-unit resource it renders
# (Cluster, ObjectStore, ScheduledBackup, the cnpg.io/cluster PodMonitor + CiliumNetworkPolicy) carries both
# sync-options, and that a chart with backups on (ObjectStore present) also renders a cnpg-backup-s3 SealedSecret
# carrying them. No cluster needed. Non-zero exit on any gap.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require helm python3

WL_DIR="${REPO_ROOT}/argo_apps/workloads/charts"

say "CNPG orphan-not-delete guard: every DB unit must carry sync-options Prune=false,Delete=false"

for chart in "$WL_DIR"/*/; do
  [ -f "${chart}Chart.yaml" ] || continue
  name="$(basename "$chart")"
  render="$(helm template "$chart" 2>/dev/null)" || { bad "${name}: helm template failed"; continue; }
  printf '%s\n' "$render" | grep -q '^kind: Cluster$' || continue   # no CNPG Cluster -> nothing to guard
  detail="$(printf '%s' "$render" | python3 - <<'PY'
import sys,re
SYNC='Prune=false,Delete=false'
docs=sys.stdin.read().split('\n---\n')
def kind(d): m=re.search(r'^kind:\s*(\S+)',d,re.M); return m.group(1) if m else None
def nm(d):   m=re.search(r'^\s{0,2}name:\s*(\S+)',d,re.M); return m.group(1) if m else '?'
fails=[]; has_objectstore=False; has_sealed=False
for d in docs:
    k=kind(d)
    cnpg = k in ('Cluster','ObjectStore','ScheduledBackup') \
        or (k=='PodMonitor' and 'cnpg.io/cluster' in d) \
        or (k=='CiliumNetworkPolicy' and 'cnpg.io/podRole: instance' in d) \
        or (k=='SealedSecret' and nm(d)=='cnpg-backup-s3')
    if not cnpg: continue
    if k=='ObjectStore': has_objectstore=True
    if k=='SealedSecret': has_sealed=True
    if SYNC not in d: fails.append(f"{k}/{nm(d)}")
if has_objectstore and not has_sealed:
    fails.append("cnpg-backup-s3 SealedSecret missing (backups on, creds Secret would be pruned)")
print('; '.join(fails))
PY
)"
  if [ -z "$detail" ]; then ok "$name"; else bad "${name}: ${detail}"; fi
done

summary || exit 1
