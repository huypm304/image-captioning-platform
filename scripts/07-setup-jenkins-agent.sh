#!/usr/bin/env bash
# Run on the laptop (Jenkins SSH agent). Ubuntu/Debian-oriented; adjust for other distros.
set -euo pipefail

echo "=== Laptop prep for Jenkins SSH agent + ECR/EKS pipeline ==="

if command -v apt-get &>/dev/null; then
  sudo apt-get update -y
  sudo apt-get install -y openjdk-17-jre-headless openssh-server curl unzip ca-certificates
else
  echo "No apt-get found; install JDK 17 + OpenSSH manually."
fi

if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
fi
sudo usermod -aG docker "${USER}" || true

if ! command -v aws &>/dev/null; then
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64) AWS_CLI_ARCH=awscli-exe-linux-x86_64.zip ;;
    aarch64) AWS_CLI_ARCH=awscli-exe-linux-aarch64.zip ;;
    *) echo "Unsupported arch for bundled AWS CLI: ${ARCH}"; exit 1 ;;
  esac
  curl -fsSL "https://awscli.amazonaws.com/${AWS_CLI_ARCH}" -o /tmp/awscliv2.zip
  unzip -q -o /tmp/awscliv2.zip -d /tmp
  sudo /tmp/aws/install --update
fi

if ! command -v kubectl &>/dev/null; then
  KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64) K_ARCH=amd64 ;;
    aarch64) K_ARCH=arm64 ;;
    *) echo "Unsupported arch for kubectl: ${ARCH}"; exit 1 ;;
  esac
  curl -fsSLO "https://dl.k8s.io/release/${KVER}/bin/linux/${K_ARCH}/kubectl"
  sudo install -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
fi

if ! command -v helm &>/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v terraform &>/dev/null; then
  TF_VERSION="1.9.5"
  ARCH=$(uname -m)
  case "${ARCH}" in
    x86_64) TF_ARCH=amd64 ;;
    aarch64) TF_ARCH=arm64 ;;
    *) echo "Unsupported arch for terraform: ${ARCH}"; exit 1 ;;
  esac
  curl -fsSLo /tmp/tf.zip "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_${TF_ARCH}.zip"
  sudo unzip -qo /tmp/tf.zip terraform -d /usr/local/bin
  rm -f /tmp/tf.zip
fi

echo ""
echo "Done. Next:"
echo "  1) Create Linux user jenkins-agent (or use your user)."
echo "  2) From VPS Jenkins, add SSH credential and New Node: label=laptop, Launch via SSH."
echo "  3) On Jenkins: create AWS credential id 'aws-creds-id' (ECR + EKS + Terraform/S3 as needed)."
echo "  4) For GitOps commits from the App pipeline: credential id 'gitops-git-pat' (Git user + PAT), origin = HTTPS."
echo "  5) For infra-as-code: run scripts/00-bootstrap-tf-backend.sh once, then Jenkins job Script Path = jenkins/Jenkinsfile.infra."
