#!/bin/bash
# sensitive-file-guard.sh — Safeguard Guard
# Blocks writes to sensitive/credential files (.env, .ssh, keys, cloud configs).
# Input: JSON on stdin. Output: BLOCK:<reason> | empty (allow).

INPUT=$(cat)
. "$(dirname "$0")/../lib/json-field.sh"

FILE=$(json_field "file_path" "$INPUT")
[ -z "$FILE" ] && exit 0

FILE=$(printf '%s' "$FILE" | tr '\' '/')
BASENAME=$(basename "$FILE")
HOME_NORM=$(printf '%s' "${HOME:-}" | tr '\' '/')

deny() {
  printf 'BLOCK:[safeguard:sensitive-file] Blocked write to %s (%s). Edit manually if intentional.' "$BASENAME" "$1"
  exit 0
}

# Whitelist: safe .env variants
case "$BASENAME" in
  .env.example|.env.sample|.env.template|.env.test) exit 0 ;;
esac

# .env files (secrets)
case "$BASENAME" in
  .env|.env.*) deny "environment secrets file" ;;
esac

# SSH keys and config
case "$FILE" in
  */.ssh/*|"$HOME_NORM"/.ssh/*) deny "SSH directory" ;;
esac
case "$BASENAME" in
  id_rsa*|id_ed25519*|id_ecdsa*|id_dsa*) deny "SSH private key" ;;
esac

# Certificates and key files
case "$BASENAME" in
  *.pem|*.key|*.p12|*.pfx|*.jks|*.keystore) deny "certificate/key file" ;;
esac

# Cloud credential directories
case "$FILE" in
  */.aws/*|"$HOME_NORM"/.aws/*) deny "AWS credentials" ;;
  */.config/gcloud/*|"$HOME_NORM"/.config/gcloud/*) deny "GCP credentials" ;;
  */.azure/*|"$HOME_NORM"/.azure/*) deny "Azure credentials" ;;
  */.kube/*|"$HOME_NORM"/.kube/*) deny "Kubernetes config" ;;
  */.docker/config.json) deny "Docker credentials" ;;
esac

# Service account / credential files
case "$BASENAME" in
  *credentials*.json|*serviceAccount*.json|*service-account*.json) deny "service account credentials" ;;
  serviceAccountKey.json|firebase-adminsdk*.json) deny "Firebase credentials" ;;
esac

# Package registry credentials
case "$FILE" in
  */.npmrc|"$HOME_NORM"/.npmrc) deny "npm registry token" ;;
  */.pypirc|"$HOME_NORM"/.pypirc) deny "PyPI credentials" ;;
  */.git-credentials|"$HOME_NORM"/.git-credentials) deny "git credentials" ;;
  */.netrc|"$HOME_NORM"/.netrc) deny "netrc credentials" ;;
esac

# Terraform state (contains secrets)
case "$BASENAME" in
  *.tfstate|*.tfstate.backup) deny "Terraform state (contains secrets)" ;;
esac

exit 0
