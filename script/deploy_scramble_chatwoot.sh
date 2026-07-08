#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  deploy_scramble_chatwoot.sh <image-tag>

Environment:
  DEPLOY_DIR          Target directory on the server. Default: /opt/chatwoot
  GITHUB_REPOSITORY  Repository with deploy releases. Default: scramble-app/chatwoot
  GITHUB_TOKEN       Optional token for private GitHub release downloads.
  GHCR_TOKEN         Optional token for ghcr.io image pulls. Defaults to GITHUB_TOKEN when set.
  GHCR_USERNAME      Optional ghcr.io username. Default: GITHUB_ACTOR or scramble-app.

Example:
  GITHUB_TOKEN=... GHCR_USERNAME=... ./deploy_scramble_chatwoot.sh abc1234
USAGE
}

log() {
  printf '%s\n' "$*"
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

image_tag="${1:-}"
if [ -z "${image_tag}" ]; then
  usage
  exit 2
fi

case "${image_tag}" in
  *[!A-Za-z0-9_.-]*)
    die "image tag can contain only letters, numbers, underscore, dot, and dash"
    ;;
esac

deploy_dir="${DEPLOY_DIR:-/opt/chatwoot}"
github_repository="${GITHUB_REPOSITORY:-scramble-app/chatwoot}"
release_tag="chatwoot-deploy-${image_tag}"
asset_name="${release_tag}.tar.gz"
asset_url="https://github.com/${github_repository}/releases/download/${release_tag}/${asset_name}"

tmpdir="$(mktemp -d)"
cleanup() {
  rm -rf "${tmpdir}"
}
trap cleanup EXIT

mkdir -p "${tmpdir}/bundle"

curl_args=(-fsSL)
if [ -n "${GITHUB_TOKEN:-}" ]; then
  curl_args+=(
    -H "Authorization: Bearer ${GITHUB_TOKEN}"
    -H "X-GitHub-Api-Version: 2022-11-28"
  )
fi

log "Downloading ${asset_url}"
curl "${curl_args[@]}" -o "${tmpdir}/${asset_name}" "${asset_url}"
tar -xzf "${tmpdir}/${asset_name}" -C "${tmpdir}/bundle"

log "Installing deploy files into ${deploy_dir}"
mkdir -p "${deploy_dir}/docker/nginx/templates"
cp "${tmpdir}/bundle/docker-compose.yaml" "${deploy_dir}/docker-compose.yaml"
cp "${tmpdir}/bundle/docker/nginx/templates/scramble.conf.template" "${deploy_dir}/docker/nginx/templates/scramble.conf.template"

if [ -f "${tmpdir}/bundle/.env.example" ]; then
  cp "${tmpdir}/bundle/.env.example" "${deploy_dir}/.env.example"
fi

if [ -f "${tmpdir}/bundle/deploy_scramble_chatwoot.sh" ]; then
  cp "${tmpdir}/bundle/deploy_scramble_chatwoot.sh" "${deploy_dir}/deploy_scramble_chatwoot.sh"
  chmod +x "${deploy_dir}/deploy_scramble_chatwoot.sh"
fi

cd "${deploy_dir}"

if [ ! -f .env ]; then
  die "create ${deploy_dir}/.env from .env.example and fill secrets before running deploy"
fi

if grep -q '^CHATWOOT_IMAGE_TAG=' .env; then
  sed "s/^CHATWOOT_IMAGE_TAG=.*/CHATWOOT_IMAGE_TAG=${image_tag}/" .env > "${tmpdir}/env"
  cp "${tmpdir}/env" .env
else
  printf '\nCHATWOOT_IMAGE_TAG=%s\n' "${image_tag}" >> .env
fi

ghcr_token="${GHCR_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -n "${ghcr_token}" ]; then
  ghcr_username="${GHCR_USERNAME:-${GITHUB_ACTOR:-scramble-app}}"
  log "Logging in to ghcr.io as ${ghcr_username}"
  printf '%s' "${ghcr_token}" | docker login ghcr.io -u "${ghcr_username}" --password-stdin
fi

log "Pulling and starting Docker Compose services"
docker compose pull
docker compose up -d
docker compose ps
