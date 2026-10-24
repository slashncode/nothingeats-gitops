# CLAUDE.md

Flux GitOps repo for NothingEats. The cross-repo plan and session rules live in `../CLAUDE.md` (workspace root), if present — read it first.

## Commands

- `scripts/validate.sh` — kustomize build + kubeconform for everything, plus the unencrypted-secret guard. Run before every commit.
- `sops --encrypt --in-place <file>.sops.yaml` / `sops <file>.sops.yaml` — needs `SOPS_AGE_KEY_FILE` (set by the workspace `mise.toml`)
- From the hub repo: `just up`, `just sops-key`, `just flux-bootstrap`, `just flux-status`
- Always pass `--context k3d-nothingeats` to kubectl/flux; never rely on the current context.

## Rules

- `main` is what runs. Never edit `clusters/*/flux-system/` by hand (bootstrap owns it).
- Every `Secret` lives in a `*.sops.yaml` file and is encrypted before commit. Never write a plaintext secret to disk inside this repo.
- Image tags in `release.yaml` are written by Flux image automation (setter markers); do not change them by hand except for the very first deploy.
- Pin chart versions exactly; Renovate bumps them.
- Infrastructure goes through the stages crds → controllers → configs; apps depend on configs.
