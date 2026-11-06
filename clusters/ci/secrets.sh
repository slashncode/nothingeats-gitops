#!/usr/bin/env bash
# Secrets for the throwaway CI cluster (clusters/ci). A CI cluster never gets the age key:
# infrastructure/ci and apps/ci drop every SOPS secret, and this script creates the same secrets
# with random values that exist only as long as the cluster. Run it once Flux is installed and
# before the cluster syncs. PostHog and OpenAI get no secret at all: apps/ci removes their variables.
#
# A new *.sops.yaml needs a line here too; without one, the pod that reads it never starts.
# Usage: clusters/ci/secrets.sh <kube context>
set -euo pipefail

context=${1:?usage: secrets.sh <kube context>}
kube() { kubectl --context "$context" "$@"; }

# Letters and digits only, so a value never needs quoting in a URL or a config file.
password() { openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32; }
base64url() { base64 | tr '+/' '-_' | tr -d '=\n'; }

# Creates or replaces a secret: secret <name> [kubectl create secret generic flags...]
secret() {
    local name=$1
    shift
    kube -n nothingeats create secret generic "$name" "$@" --dry-run=client -o yaml | kube apply -f - >/dev/null
    echo "secret $name"
}

kube create namespace nothingeats --dry-run=client -o yaml | kube apply -f - >/dev/null

# One Postgres role per service (infrastructure/configs/postgres.yaml); CloudNativePG reloads on change.
for role in catalog identity notification ordering delivery loyalty social assistant backoffice; do
    kube -n nothingeats create secret generic "$role-db" --type=kubernetes.io/basic-auth \
        --from-literal=username="$role" --from-literal=password="$(password)" --dry-run=client -o yaml |
        kube label --local -f - cnpg.io/reload=true -o yaml | kube apply -f - >/dev/null
    echo "secret $role-db"
done

secret valkey-users --from-literal=default="$(password)"

# Garage: a 32-byte RPC secret, and a key in Garage's own format (GK + 12 bytes, 32-byte secret).
secret garage-keys \
    --from-literal=rpcSecret="$(openssl rand -hex 32)" \
    --from-literal=accessKey="GK$(openssl rand -hex 12)" \
    --from-literal=secretKey="$(openssl rand -hex 32)"

# Elasticsearch: the role is not secret but ECK only reads it from a secret; keep it the same as
# infrastructure/configs/search-service-role.sops.yaml.
secret search-service-role --from-literal=roles.yml='search_service:
  cluster: ["monitor"]
  indices:
    - names: ["dishes*", "restaurants*"]
      privileges: ["all"]
'
kube -n nothingeats create secret generic search-service-user --type=kubernetes.io/basic-auth \
    --from-literal=username=search-service --from-literal=password="$(password)" \
    --from-literal=roles=search_service --dry-run=client -o yaml | kube apply -f - >/dev/null
echo "secret search-service-user"

# identity: AES-256 key for the signing keys at rest.
secret identity-keys --from-literal=encryption-key="$(openssl rand -base64 32)"

secret backoffice-payload --from-literal=secret="$(openssl rand -hex 32)"

# Web push: a P-256 key pair as browsers use it (raw private scalar, uncompressed public point).
vapid=$(openssl ecparam -name prime256v1 -genkey -noout)
secret notification-vapid \
    --from-literal=private-key="$(openssl ec -outform DER 2>/dev/null <<<"$vapid" | head -c 39 | tail -c 32 | base64url)" \
    --from-literal=public-key="$(openssl ec -pubout -outform DER 2>/dev/null <<<"$vapid" | tail -c 65 | base64url)"
