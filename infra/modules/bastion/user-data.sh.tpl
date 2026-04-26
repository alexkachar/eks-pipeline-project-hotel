#!/bin/bash
set -eux

dnf update -y
dnf install -y awscli git tar gzip

# kubectl — pinned to the cluster's published "stable" minor.
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && mv kubectl /usr/local/bin/

# helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod +x get_helm.sh && ./get_helm.sh

# argocd CLI
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# kubeconfig for ec2-user. On a brand-new apply this can race the cluster's
# ACTIVE transition; if it does, re-run this command after first SSM login.
mkdir -p /home/ec2-user/.kube
aws eks update-kubeconfig \
  --name ${cluster_name} \
  --region ${region} \
  --kubeconfig /home/ec2-user/.kube/config || true
chown -R ec2-user:ec2-user /home/ec2-user/.kube
