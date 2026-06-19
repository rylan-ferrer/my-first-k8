#!/bin/bash
set -euxo pipefail

# Don't forget to "chmod +x setup-scripts/node-setup.sh"
# Run this script with: sudo ./node-setup.sh 

K8S_VERSION="1.36"

# Updating system packages 
echo "----Updating system packages----"
sudo apt-get update -y

# Allowing apt to use a repository over HTTPS
sudo apt-get install -y apt-transport-https curl

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

echo "----containerd Installation Completed"
sudo crictl version

# Add the Kubernetes signing key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes APT repository
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

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

# Enabling kubelet service 
echo "----Enabling kubelet service----"
sudo systemctl enable kubelet

echo "--- Installation Complete ---"
echo "Worker node software installed and ready to join the cluster."
echo ""
echo "Once your control plane is ready, join this node using the command printed by: (must be executed on manager node)"
echo "   sudo kubeadm token create --print-join-command"
echo ""
echo "Example:"
echo "   sudo kubeadm join <CONTROL_PLANE_IP>:6443 --token <TOKEN> --discovery-token-ca-cert-hash sha256:<HASH>"