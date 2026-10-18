#!/usr/bin/env bash
#
# Checks that every ${...} a component Kustomization renders is a variable that
# cluster-vars provides.
#
# Each component Kustomization substitutes ${...} from the cluster-vars
# ConfigMap after it builds its overlay (postBuild.substituteFrom). Flux
# replaces a variable it does not know with an empty string, so a
# ${S3_ACCESS_KEY_ID} meant for a container at runtime is silently blanked.
# Escape such a variable as $${S3_ACCESS_KEY_ID}, or mark the object with
# kustomize.toolkit.fluxcd.io/substitute: disabled.
#
# This script mirrors what kustomize-controller does: for every Kustomization in
# clusters/<cluster>/infrastructure it builds spec.path and runs
# `flux envsubst --strict` with the keys of docs/cluster-vars.example.yaml set.
# --strict fails on any variable that is not set, which is exactly the variable
# that would be blanked on the cluster. Objects with substitution disabled are
# skipped, as Flux skips them.
#
# Two cases --strict does not catch, so this script checks them too:
#   - ${NAME:=default} and the other operators: Flux uses the default without
#     an error, even in strict mode. Any ${NAME...} whose NAME is not a
#     cluster-vars key fails.
#   - An object with substitution disabled that uses a cluster-vars key: Flux
#     leaves ${domain} there as written.
#
# Requires kustomize, yq (v4) and flux.
#
# Usage: scripts/check-substitutions.sh [cluster]   (default: vanilla)

set -o errexit
set -o nounset
set -o pipefail

cluster="${1:-vanilla}"
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

# Export every key of the example cluster-vars, so the allowed variables have
# one source of truth.
keys=()
while IFS='=' read -r key value; do
  export "$key=$value"
  keys+=("$key")
  echo "INFO - cluster-vars provides \${$key}"
done < <(yq 'select(.kind == "ConfigMap") | .data | to_entries | .[] | .key + "=" + .value' docs/cluster-vars.example.yaml)

failed=0
rendered="$(mktemp)"
built="$(mktemp)"
trap 'rm -f "$rendered" "$built"' EXIT
while IFS=' ' read -r name path; do
  if ! kustomize build --load-restrictor=LoadRestrictionsNone "$path" > "$built"; then
    echo "FAIL - $name ($path): kustomize build failed"
    failed=1
    continue
  fi
  disabled='.metadata.annotations["kustomize.toolkit.fluxcd.io/substitute"] == "disabled" or .metadata.labels["kustomize.toolkit.fluxcd.io/substitute"] == "disabled"'
  yq e "select(($disabled) | not)" "$built" > "$rendered"
  if ! out="$(flux envsubst --strict < "$rendered" 2>&1 >/dev/null)"; then
    echo "FAIL - $name ($path): $out"
    failed=1
    continue
  fi
  # ${NAME...} not preceded by another $ (that is an escape).
  unknown="$(grep -oE '(^|[^$])\$\{#?[A-Za-z_][A-Za-z0-9_]*' "$rendered" | sed -E 's/.*\$\{#?//' | sort -u | grep -vxF -f <(printf '%s\n' "${keys[@]}") || true)"
  if [[ -n $unknown ]]; then
    echo "FAIL - $name ($path): Flux substitutes variables that cluster-vars does not provide: $(echo $unknown)"
    failed=1
    continue
  fi
  if yq e "select($disabled)" "$built" | grep -qE "(^|[^\$])\\$\\{($(IFS='|'; echo "${keys[*]}"))[^A-Za-z0-9_]"; then
    echo "FAIL - $name ($path): an object with substitution disabled uses a cluster-vars variable"
    failed=1
    continue
  fi
  echo "OK   - $name"
done < <(yq -N e 'select(.kind == "Kustomization" and .apiVersion == "kustomize.toolkit.fluxcd.io/*") | .metadata.name + " " + .spec.path' \
  "clusters/$cluster"/infrastructure/*.yaml)

if [[ $failed != 0 ]]; then
  echo
  echo "Escape a variable that the container expands at runtime as \$\${NAME},"
  echo "or set kustomize.toolkit.fluxcd.io/substitute: disabled on the object."
  exit 1
fi
