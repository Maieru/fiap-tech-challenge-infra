#!/usr/bin/env bash
set -euo pipefail
version=$(aws eks describe-cluster --name fiap-eks-cluster --query cluster.version --output text)
[[ "$version" =~ ^1\.[0-9]+$ ]] || exit 1
release=$(curl --fail --silent --show-error --location "https://dl.k8s.io/release/stable-$version.txt")
[[ "$release" =~ ^v1\.[0-9]+\.[0-9]+$ ]] || exit 1
folder=$(mktemp -d)
trap 'rm -f "$folder/kubectl" "$folder/kubectl.sha256"; rmdir "$folder"' EXIT
curl --fail --silent --show-error --location "https://dl.k8s.io/release/$release/bin/linux/amd64/kubectl" -o "$folder/kubectl"
curl --fail --silent --show-error --location "https://dl.k8s.io/release/$release/bin/linux/amd64/kubectl.sha256" -o "$folder/kubectl.sha256"
expected=$(cat "$folder/kubectl.sha256")
printf '%s  %s\n' "$expected" "$folder/kubectl" | sha256sum --check --status
sudo install -m 0755 "$folder/kubectl" /usr/local/bin/kubectl
aws eks update-kubeconfig --name fiap-eks-cluster --region "$AWS_REGION"
