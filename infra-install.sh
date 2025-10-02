#!/bin/bash

help()
{
  echo "Script to install minikube cluster and aviflow for local debug"
  echo
  echo "commands"
  echo "help                      print help"
  echo "terraform                 install k8s cluster with terraform"
  echo "system                    install gpu-operator and prometheus-stack"
  echo "jupyterlab                install jupyterlab"
  echo "argoworkflow              install argoworkflow"
  echo "vllm                      install vllm"
  echo "all                       install all"
  echo "clear                     delete all infra"
  echo
}

# Paths
K8S_DIR="kubernetes"
PROM_STACK_DIR="$K8S_DIR/0-prometheus-stack"
GPU_OPERATOR_DIR="$K8S_DIR/1-gpu-operator"
JUPYTERLAB_DIR="$K8S_DIR/2-jupyterlab"
VLLM_DIR="$K8S_DIR/3-vllm"
ARGO_DIR="$K8S_DIR/4-argoworkflows"
NFS_MANIFEST="$K8S_DIR/nfs-pv-pvc.yaml"
KUBECONFIG_FILE="$K8S_DIR/kubeconfig"

# Target namespace for vLLM/Jupyter/NFS PVC
VLLM_INFRA_NS="default"

ensure_kube()
{
  if [ -f "$KUBECONFIG_FILE" ]; then
    export KUBECONFIG="$KUBECONFIG_FILE"
  fi
}

ensure_ns()
{
  kubectl get ns "$VLLM_INFRA_NS" >/dev/null 2>&1 || kubectl create ns "$VLLM_INFRA_NS"
}

add_helm_repos()
{
  helm repo add nvidia https://nvidia.github.io/gpu-operator >/dev/null 2>&1 || true
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null 2>&1 || true
  helm repo add vllm https://vllm-project.github.io/production-stack >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
}

create_hf_secret_if_present()
{
  if [ -n "$HF_TOKEN" ]; then
    kubectl create secret generic hf-token-secret \
      -n "$VLLM_INFRA_NS" \
      --from-literal=hf-token="$HF_TOKEN" \
      --dry-run=client -o yaml | kubectl apply -f -
  fi
}

install_system()
{
  ensure_kube
  add_helm_repos

  # Prometheus Stack (as per help)
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    -f "$PROM_STACK_DIR/values.yaml"

  # GPU Operator (per README)
  helm upgrade --install gpu-operator nvidia/gpu-operator \
    --namespace gpu-operator \
    --create-namespace \
    -f "$GPU_OPERATOR_DIR/values.yaml"

  # NFS PV/PVC in vllm-infra
  if [ -f "$NFS_MANIFEST" ]; then
    ensure_ns
    kubectl apply -n "$VLLM_INFRA_NS" -f "$NFS_MANIFEST"
  fi
}

install_jupyterlab()
{
  ensure_kube
  ensure_ns
  kubectl apply -n "$VLLM_INFRA_NS" -f "$JUPYTERLAB_DIR/jupyterlab-deployment.yaml"
}

install_argoworkflow()
{
  ensure_kube
  add_helm_repos
  helm upgrade --install argo-workflows argo/argo-workflows \
    --namespace argo \
    --create-namespace \
    -f "$ARGO_DIR/values.yaml"
}

install_vllm()
{
  ensure_kube
  ensure_ns
  create_hf_secret_if_present
  # Install vLLM production stack into vllm-infra
  VALUES_FILE="$VLLM_DIR/production-stack-values.yaml"
  if [ -f "$VALUES_FILE" ]; then
    helm upgrade --install vllm vllm/vllm-stack \
      --namespace "$VLLM_INFRA_NS" \
      --create-namespace \
      -f "$VALUES_FILE"
  else
    helm upgrade --install vllm vllm/vllm-stack \
      --namespace "$VLLM_INFRA_NS" \
      --create-namespace
  fi
}

terraform_apply()
{
  # Source local env if present (per README step 1)
  if [ -f terraform/.envrc.local ]; then
    # shellcheck disable=SC1091
    source terraform/.envrc.local
  fi

  terraform -chdir=terraform init -upgrade
  # Use vars.tfvars per README step 3
  if [ -f terraform/vars.tfvars ]; then
    terraform -chdir=terraform apply -auto-approve -var-file=vars.tfvars
  else
    terraform -chdir=terraform apply -auto-approve
  fi

  # Save kubeconfig to ~/.kube/config per README; also mirror to kubernetes/kubeconfig
  mkdir -p "$HOME/.kube"
  terraform -chdir=terraform output -raw kubeconfig 2>/dev/null > "$HOME/.kube/config" || true
  terraform -chdir=terraform output -raw kubeconfig 2>/dev/null > "$KUBECONFIG_FILE" || true
  ensure_kube
}

terraform_destroy()
{
  terraform -chdir=terraform destroy -auto-approve || true
}

clear_all()
{
  # Destroy cluster via terraform
  terraform_destroy
}

case $1 in
  help)
    help
    exit;;
  terraform)
    terraform_apply
    exit;;
  system)
    install_system
    exit;;
  jupyterlab)
    install_jupyterlab
    exit;;
  argoworkflow)
    install_argoworkflow
    exit;;
  vllm)
    install_vllm
    exit;;
  all)
    terraform_apply
    install_system
    install_jupyterlab
    install_argoworkflow
    install_vllm
    exit;;
  clear)
    clear_all
    exit;;
  "")
    help
    exit;;
  *)
    echo "Unknown command: $1"
    help
    exit 1;;
esac
