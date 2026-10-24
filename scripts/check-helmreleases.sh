#!/usr/bin/env bash
# Renders every HelmRelease that uses a HelmRepository with its values against the pinned chart,
# so chart schema errors fail in CI instead of in the cluster.
set -euo pipefail

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

grep -rlE '^kind: HelmRelease' --include='*.yaml' infrastructure apps | while read -r file; do
    count=$(yq ea '[select(.kind == "HelmRelease" and .spec.chart.spec.sourceRef.kind == "HelmRepository")] | length' "$file")
    for ((i = 0; i < count; i++)); do
        release=$(yq ea "[select(.kind == \"HelmRelease\" and .spec.chart.spec.sourceRef.kind == \"HelmRepository\")] | .[$i]" "$file")
        name=$(yq '.metadata.name' <<<"$release")
        chart=$(yq '.spec.chart.spec.chart' <<<"$release")
        version=$(yq '.spec.chart.spec.version' <<<"$release")
        repo_name=$(yq '.spec.chart.spec.sourceRef.name' <<<"$release")
        url=$(yq ea "select(.kind == \"HelmRepository\" and .metadata.name == \"$repo_name\") | .spec.url" "$file")
        if [[ -z "$url" ]]; then
            echo "::error file=$file::HelmRepository $repo_name for $name must be in the same file"
            exit 1
        fi
        yq '.spec.values // {}' <<<"$release" > "$work/$name-values.yaml"
        echo "== $name ($chart $version)"
        helm template "$name" "$chart" --repo "$url" --version "$version" -f "$work/$name-values.yaml" > /dev/null
    done
done
