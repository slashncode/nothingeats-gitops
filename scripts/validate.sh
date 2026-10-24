#!/usr/bin/env bash
# Builds every kustomization, validates all objects against Kubernetes and CRD schemas,
# and refuses any Secret that is not SOPS-encrypted.
set -euo pipefail

cd "$(dirname "$0")/.."
k8s_version="${K8S_VERSION:-1.36.0}"
schemas=(
    -schema-location default
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
)

echo "== secrets"
status=0
while IFS= read -r file; do
    if [[ "$file" != *.sops.yaml ]] || ! yq -e '.sops.mac' "$file" >/dev/null 2>&1; then
        echo "::error file=$file::Secret is not SOPS-encrypted (name it *.sops.yaml and run sops --encrypt --in-place)"
        status=1
    fi
done < <(grep -rlE '^kind: Secret' --include='*.yaml' clusters infrastructure apps || true)
[[ $status -eq 0 ]] || exit $status

echo "== clusters"
find clusters -name '*.yaml' -not -path '*/flux-system/*' -print0 |
    xargs -0 kubeconform -strict -summary -kubernetes-version "$k8s_version" "${schemas[@]}"

find infrastructure apps -name kustomization.yaml -print0 | while IFS= read -r -d '' file; do
    dir=$(dirname "$file")
    echo "== $dir"
    # Secrets are encrypted in git; their schema is checked after decryption by Flux.
    kubectl kustomize "$dir" | kubeconform -strict -summary -skip Secret -kubernetes-version "$k8s_version" "${schemas[@]}"
done
