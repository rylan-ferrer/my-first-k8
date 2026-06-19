#!/bin/bash
set -euxo pipefail

# Don't forget to "chmod +x setup-scripts/master-setup.sh"
# Run this script with: sudo ./master-setup.sh 

# Define Kubernetes version and Pod Network CIDR
K8S_VERSION="1.36"
POD_CIDR="192.168.0.0/16"

# Updating system packages 
echo "----Updating system packages----"
sudo apt-get update -y

# Allowing apt to use a repository over HTTPS
sudo apt-get install -y apt-transport-https curl

# Installing git 
echo "----Installing Git----"
sudo apt install git -y 

echo "----Git installation completed----"
git --version 

# Disable swap (required by Kubernetes)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set sysctl params required by Kubernetes networking
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF

# Apply sysctl params immediately
sudo sysctl --system

# Install containderd
echo "----Instablling containerd----"
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release containerd

mkdir -p /etc/containerd
containerd config default | sed 's/SystemdCgroup = false/SystemdCgroup = true/g' > /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# Install kubelet, kubeadm, and kubectl
echo "----Installing kubelet, kubeadm, and kubectl----"
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Configure crictl to use containerd
echo "----Configuring crictl to use containerd----"
cat <<EOF >/etc/crictl.yaml
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "----Initializing the Kubernetes Control Plane (Master)----"
# Pre-pull images to ensure kubeadm doesn't timeout inside cloud-init
kubeadm config images pull --kubernetes-version="v${K8S_VERSION}.5" || true

# Run kubeadm init safely. If it fails, it will catch it cleanly.
kubeadm init --pod-network-cidr="${POD_CIDR}" --ignore-preflight-errors=all

echo "----Configuring kubectl access for the root user----"
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chmod 600 /root/.kube/config

# Export the variable explicitly for the rest of this cloud-init session
export KUBECONFIG=/etc/kubernetes/admin.conf

# Force kubectl to use the system configuration directly via the --kubeconfig flag
/usr/bin/kubectl --kubeconfig=/etc/kubernetes/admin.conf create -f https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/tigera-operator.yaml

echo "Waiting for Tigera Operator CRDs to be established..."
/usr/bin/kubectl --kubeconfig=/etc/kubernetes/admin.conf wait --for=condition=Established --timeout=60s crd/installations.operator.tigera.io

curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.29.2/manifests/custom-resources.yaml -o /tmp/custom-resources.yaml
/usr/bin/kubectl --kubeconfig=/etc/kubernetes/admin.conf apply -f /tmp/custom-resources.yaml

echo "--- Installation Complete ---"

# 1. Check if all nodes (Manager and Joined Workers) are ready
kubectl get nodes

# 2. Check if Calico components are actively running and healthy
kubectl get pods -n calico-system

# 3. Check if the CoreDNS pods have successfully been assigned Calico IPs
kubectl get pods -n kube-system -o wide

# 4. Generate worker join token
kubeadm token create --print-join-command

# if not setup, look at logs at ...
# cat /var/log/cloud-init-output.log
