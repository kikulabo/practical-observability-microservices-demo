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

k8s-set-up:
	@echo "--- 1. Disabling swap ---"
	sudo swapoff -a
	sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

	@echo "\n--- 2. Configuring container runtime modules ---"
	@cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
	sudo modprobe overlay
	sudo modprobe br_netfilter

	@echo "\n--- 3. Configuring sysctl for Kubernetes ---"
	@cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
	sudo sysctl --system

	@echo "\n--- 4. Installing kubeadm, kubelet, and kubectl ---"
	sudo apt-get install -y apt-transport-https ca-certificates curl gpg
	curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.34/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
	echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.34/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubelet kubeadm kubectl
	sudo apt-mark hold kubelet kubeadm kubectl

	@echo "\n--- 5. Enabling kubelet service ---"
	sudo systemctl enable --now kubelet
	@echo "\n--- Kubernetes setup complete ---"

.PHONY: network-config network-apply k8s-set-up
