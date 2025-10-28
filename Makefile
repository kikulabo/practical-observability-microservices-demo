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

.PHONY: network-config network-apply

