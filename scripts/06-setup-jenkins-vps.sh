#!/usr/bin/env bash
# Run on the VPS (Jenkins controller). Requires Docker.
set -euo pipefail

echo "=== Jenkins controller on VPS (Docker) ==="

if ! command -v docker &>/dev/null; then
  echo "Install Docker first, e.g.: curl -fsSL https://get.docker.com | sudo sh"
  exit 1
fi

mkdir -p "${HOME}/jenkins_home"

if docker ps -a --format '{{.Names}}' | grep -q '^jenkins$'; then
  echo "Container 'jenkins' already exists. Remove with: docker rm -f jenkins"
  exit 1
fi

docker run -d --name jenkins --restart unless-stopped \
  -p 8080:8080 -p 50000:50000 \
  -v "${HOME}/jenkins_home:/var/jenkins_home" \
  jenkins/jenkins:lts

echo ""
echo "Jenkins starting on http://<vps-ip>:8080"
echo "Initial admin password:"
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
echo ""
echo "Recommended plugins: Git, Pipeline, SSH Build Agents, Pipeline Utility Steps (readYaml)"
