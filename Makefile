network-config:
	@echo "--- 1. Configuring eth0 (in 01-netcfg.yaml) ---"
	sudo chmod 600 /etc/netplan/01-netcfg.yaml
	sudo netplan set ethernets.eth0.gateway4=NULL
	sudo netplan set ethernets.eth0.routes='[{"to":"default", "via": "133.125.238.1"}]'

	@echo "\n--- 2. Configuring eth1 (from template) ---"
	@if [ ! -f 99-eth1.yaml.template ]; then \
		echo "ERROR: Template file '99-eth1.yaml.template' not found."; \
		exit 1; \
	fi

	@IP="UNKNOWN"; \
	HOSTNAME=$$(hostname); \
	case $$HOSTNAME in \
		microservices-demo-01) IP="192.168.10.101";; \
		microservices-demo-02) IP="192.168.10.102";; \
		microservices-demo-03) IP="192.168.10.103";; \
		*) \
			echo "ERROR: Unknown hostname '$$HOSTNAME'. Cannot create 99-eth1.yaml."; \
			exit 1; \
			;; \
	esac; \
	echo "Hostname '$$HOSTNAME' found, setting eth1 IP to $$IP"; \
	\
	sed "s/__IP_ADDRESS__/$$IP/" 99-eth1.yaml.template | sudo tee /etc/netplan/99-eth1.yaml > /dev/null

	sudo chmod 600 /etc/netplan/99-eth1.yaml
	@echo "\n--- Configuration complete ---"
	@echo "Run 'make apply' to activate settings."

network-apply:
	@echo "Applying network configurations..."
	sudo netplan apply

# --- k8s setup ---

# define を使ってヒアドキュメントの内容を変数に格納
define K8S_MODULES_CONF
overlay
br_netfilter
endef

define K8S_SYSCTL_CONF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
endef

# export してシェルから参照できるようにする
export K8S_MODULES_CONF
export K8S_SYSCTL_CONF

k8s-set-up:
	@echo "--- 1. Disabling swap ---"
	sudo swapoff -a

	@echo "\n--- 2. Configuring container runtime modules ---"
	@echo "$$K8S_MODULES_CONF" | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
	sudo modprobe overlay
	sudo modprobe br_netfilter

	@echo "\n--- 3. Configuring sysctl for Kubernetes ---"
	@echo "$$K8S_SYSCTL_CONF" | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
	sudo sysctl --system

	@echo "\n--- 4. Installing Containerd (Container Runtime) ---"
	@echo "Installing prerequisites (curl, gpg...)"
	sudo apt-get update
	sudo apt-get install -y apt-transport-https ca-certificates curl gpg
	@echo "Adding Docker GPG key..."
	sudo install -m 0755 -d /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	sudo chmod a+r /etc/apt/keyrings/docker.gpg
	@echo "Removing old/malformed docker.list (if any)..."
	sudo rm -f /etc/apt/sources.list.d/docker.list
	@echo "Adding Docker repository..."
	echo "deb [arch=$$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	@echo "Installing containerd.io..."
	sudo apt-get update
	sudo apt-get install -y containerd.io
	@echo "Configuring containerd for Kubernetes (SystemdCgroup)..."
	sudo mkdir -p /etc/containerd
	sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
	sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
	@echo "Restarting and enabling containerd service..."
	sudo systemctl restart containerd
	sudo systemctl enable containerd

	@echo "\n--- 5. Installing kubeadm, kubelet, and kubectl ---"
	@echo "Adding Kubernetes GPG key..."
	curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	@echo "Adding Kubernetes repository..."
	echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
	@echo "Installing Kubernetes packages (kubelet, kubeadm, kubectl)..."
	sudo apt-get update
	sudo apt-get install -y kubelet kubeadm kubectl
	sudo apt-mark hold kubelet kubeadm kubectl

	@echo "\n--- 6. Enabling kubelet service ---"
	sudo systemctl enable --now kubelet
	@echo "\n--- Kubernetes setup complete ---"

.PHONY: network-config network-apply k8s-set-up
