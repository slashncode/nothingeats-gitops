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

# Apps use the shared charts through an OCIRepository (chartRef). Render them with their values
# and make sure every image tag is a plain CI tag, so a bad tag fails here and not in the cluster.
grep -rlE '^kind: HelmRelease' --include='*.yaml' apps | while read -r file; do
    release=$(yq ea 'select(.kind == "HelmRelease" and .spec.chartRef.kind == "OCIRepository")' "$file")
    [[ -z "$release" ]] && continue
    name=$(yq '.metadata.name' <<<"$release")
    source=$(yq '.spec.chartRef.name' <<<"$release")
    source_file=$(grep -rlE "^  name: $source\$" apps/base/sources)
    url=$(yq '.spec.url' "$source_file")
    range=$(yq '.spec.ref.semver' "$source_file")
    tag=$(yq '.spec.values.image.tag | select(tag == "!!str")' <<<"$release")
    if [[ ! "$tag" =~ ^main-[0-9a-f]+-[0-9]+$ ]]; then
        echo "::error file=$file::$name: image.tag must look like main-<sha>-<unix time>, got: $(yq -o=json -I=0 '.spec.values.image.tag' <<<"$release")"
        exit 1
    fi
    yq '.spec.values // {}' <<<"$release" > "$work/$name-values.yaml"
    echo "== $name ($url $range)"
    helm template "$name" "$url" --version "$range" -f "$work/$name-values.yaml" > /dev/null
done
