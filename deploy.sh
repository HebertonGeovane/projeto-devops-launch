#!/usr/bin/env bash

set -Eeuo pipefail

# Uso:
# ./deploy.sh URI_DA_IMAGEM_ECR
#
# Exemplo:
# ./deploy.sh 123456789012.dkr.ecr.us-east-1.amazonaws.com/devops-launch:latest

IMAGE_URI="${1:-}"
CONTAINER_NAME="${CONTAINER_NAME:-devops-launch}"
HOST_PORT="${HOST_PORT:-80}"
METADATA_FILE="$(pwd)/metadata.json"

if [[ -z "$IMAGE_URI" ]]; then
  echo "Uso: ./deploy.sh URI_DA_IMAGEM_ECR"
  exit 1
fi

for command in aws docker curl python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Erro: o comando '$command' não está instalado."
    exit 1
  fi
done

REGISTRY="$(echo "$IMAGE_URI" | cut -d/ -f1)"
REGION="$(echo "$REGISTRY" | cut -d. -f4)"

echo "Autenticando o Docker no Amazon ECR..."

aws ecr get-login-password --region "$REGION" |
  docker login \
    --username AWS \
    --password-stdin "$REGISTRY"

echo "Baixando a imagem do Amazon ECR..."

docker pull "$IMAGE_URI"

echo "Removendo container anterior, caso exista..."

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

# O arquivo deve existir antes de ser montado no container.
printf '{}\n' > "$METADATA_FILE"

echo "Executando o container..."

docker run -d \
  --name "$CONTAINER_NAME" \
  --restart unless-stopped \
  -p "${HOST_PORT}:80" \
  -v "${METADATA_FILE}:/usr/share/nginx/html/metadata.json:ro" \
  "$IMAGE_URI"

echo "Coletando os metadados da instância EC2..."

IMDS_BASE="http://169.254.169.254/latest"

TOKEN="$(
  curl -fsS \
    -X PUT \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" \
    "${IMDS_BASE}/api/token" 2>/dev/null || true
)"

metadata_get() {
  local path="$1"

  if [[ -z "$TOKEN" ]]; then
    printf 'Não disponível'
    return
  fi

  curl -fsS \
    -H "X-aws-ec2-metadata-token: ${TOKEN}" \
    "${IMDS_BASE}/meta-data/${path}" 2>/dev/null ||
    printf 'Não disponível'
}

identity_document="$(
  if [[ -n "$TOKEN" ]]; then
    curl -fsS \
      -H "X-aws-ec2-metadata-token: ${TOKEN}" \
      "${IMDS_BASE}/dynamic/instance-identity/document" 2>/dev/null || true
  fi
)"

json_value() {
  local key="$1"
  local fallback="${2:-Não disponível}"

  if [[ -z "$identity_document" ]]; then
    printf '%s' "$fallback"
    return
  fi

  python3 - "$key" "$fallback" "$identity_document" <<'PY'
import json
import sys

key = sys.argv[1]
fallback = sys.argv[2]
raw = sys.argv[3]

try:
    document = json.loads(raw)
    print(document.get(key, fallback))
except Exception:
    print(fallback)
PY
}

INSTANCE_ID="$(metadata_get instance-id)"
INSTANCE_TYPE="$(metadata_get instance-type)"
PRIVATE_IP="$(metadata_get local-ipv4)"
PUBLIC_IP="$(metadata_get public-ipv4)"
AVAILABILITY_ZONE="$(json_value availabilityZone)"
EC2_REGION="$(json_value region "$REGION")"

CONTAINER_STATUS="$(
  docker inspect \
    --format '{{if .State.Running}}Ativo{{else}}Inativo{{end}}' \
    "$CONTAINER_NAME"
)"

SERVER_VERSION="$(
  docker exec "$CONTAINER_NAME" nginx -v 2>&1 |
    sed 's#nginx version: nginx/##'
)"

DEPLOY_DATE="$(date '+%d/%m/%Y às %H:%M:%S')"

if curl -fsS "http://localhost:${HOST_PORT}/" >/dev/null; then
  APPLICATION_STATUS="Online"
else
  APPLICATION_STATUS="Indisponível"
fi

export CONTAINER_NAME
export CONTAINER_STATUS
export SERVER_VERSION
export HOST_PORT
export DEPLOY_DATE
export EC2_REGION
export AVAILABILITY_ZONE
export INSTANCE_ID
export INSTANCE_TYPE
export PRIVATE_IP
export PUBLIC_IP
export APPLICATION_STATUS

python3 <<'PY'
import json
import os
from pathlib import Path

metadata = {
    "containerName": os.environ["CONTAINER_NAME"],
    "containerStatus": os.environ["CONTAINER_STATUS"],
    "server": f'Nginx {os.environ["SERVER_VERSION"]}',
    "port": os.environ["HOST_PORT"],
    "deployDate": os.environ["DEPLOY_DATE"],
    "cloudProvider": "AWS EC2",
    "region": os.environ["EC2_REGION"],
    "availabilityZone": os.environ["AVAILABILITY_ZONE"],
    "instanceId": os.environ["INSTANCE_ID"],
    "instanceType": os.environ["INSTANCE_TYPE"],
    "privateIp": os.environ["PRIVATE_IP"],
    "publicIp": os.environ["PUBLIC_IP"],
    "applicationStatus": os.environ["APPLICATION_STATUS"],
}

Path("metadata.json").write_text(
    json.dumps(metadata, ensure_ascii=False, indent=2),
    encoding="utf-8",
)
PY

echo
echo "Deploy finalizado com sucesso."
echo "Container: $CONTAINER_NAME"
echo "Status: $CONTAINER_STATUS"
echo "Servidor: Nginx $SERVER_VERSION"
echo "Porta: $HOST_PORT"
echo "Região: $EC2_REGION"
echo "Zona: $AVAILABILITY_ZONE"
echo "Instância: $INSTANCE_ID"
echo "IP público: $PUBLIC_IP"
echo "Aplicação: $APPLICATION_STATUS"
