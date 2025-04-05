#!/bin/bash

# CONFIGURAÇÕES DA VM
VMID=120
VM_NAME="deepstack-hass"
STORAGE="local-lvm"
ISO_URL="https://releases.ubuntu.com/22.04/ubuntu-22.04.4-live-server-amd64.iso"
ISO_FILE="ubuntu-22.04.4-live-server-amd64.iso"
DISK_SIZE="10G"
RAM="2048"
CORES="2"
BRIDGE="vmbr0"
USER="deepstack"
PASS="deepstack123"

# CONFIGURAÇÕES DO HOME ASSISTANT
HA_IP="192.168.31.209"
HA_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI0YTljOTJiNDFlYjc0YTQxYWNkYmQ2ZmQ0OGI4YTNmYiIsImlhdCI6MTc0MzgxOTEwNiwiZXhwIjoyMDU5MTc5MTA2fQ.f6BOgmZTEtVQgx5nD1A-o_ykWkmIvek4do7Jpr3kRSo"
CAMERA_ENTITY_ID="camera.campainha"

echo "📦 Verificando ISO..."
ISO_PATH="/var/lib/vz/template/iso/$ISO_FILE"
if [ ! -f "$ISO_PATH" ]; then
  wget -O "$ISO_PATH" "$ISO_URL"
else
  echo "✅ ISO já existe"
fi

echo "⚙️ Criando VM $VMID..."
qm create $VMID \
  --name $VM_NAME \
  --memory $RAM \
  --cores $CORES \
  --net0 virtio,bridge=$BRIDGE \
  --serial0 socket --vga serial0 \
  --scsihw virtio-scsi-pci \
  --ide2 $STORAGE:cloudinit \
  --boot order=scsi0 \
  --ostype l26

qm importdisk $VMID "$ISO_PATH" $STORAGE --format qcow2
qm set $VMID --scsi0 $STORAGE:vm-$VMID-disk-0

# CLOUD-INIT
qm set $VMID \
  --ciuser $USER \
  --cipassword $PASS \
  --ipconfig0 ip=dhcp

CLOUD_INIT_SCRIPT=$(cat <<EOF
#cloud-config
package_update: true
packages:
  - docker.io
runcmd:
  - docker run -d --name deepstack -e VISION-FACE=True -v deepstack:/datastore -p 5000:5000 --restart always deepquestai/deepstack
EOF
)

CLOUD_DISK="cloudinit-$VMID.yaml"
echo "$CLOUD_INIT_SCRIPT" > /tmp/$CLOUD_DISK
cloud-localds /var/lib/vz/snippets/$CLOUD_DISK /tmp/$CLOUD_DISK
qm set $VMID --ide3 local:snippets/$CLOUD_DISK,media=cdrom

echo "🚀 Iniciando VM..."
qm start $VMID

echo "⏳ Aguardando VM pegar IP e Deepstack subir..."

# Esperar IP (via Proxmox guest-agent seria melhor, mas vamos pingar até responder na porta 5000)
sleep 30

VM_IP=""
for ip in $(seq 2 254); do
  TEST_IP="192.168.31.$ip"
  if curl -s --connect-timeout 2 http://$TEST_IP:5000 > /dev/null; then
    VM_IP=$TEST_IP
    break
  fi
done

if [ -z "$VM_IP" ]; then
  echo "❌ Deepstack não respondeu na rede local. Tente acessar manualmente."
  exit 1
fi

echo "✅ Deepstack está rodando em $VM_IP:5000"

# ENVIA A CONFIG PRO HA
echo "📡 Enviando configuração pro Home Assistant..."

curl -X POST "http://$HA_IP:8123/api/config/config_entries/flow" \
  -H "Authorization: Bearer $HA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "handler": "deepstack_face",
    "show_advanced_options": false
  }' > /dev/null 2>&1

# CONFIGURAÇÃO VIA YAML (temporária até flow finalizar):
CONF_YAML="
image_processing:
  - platform: deepstack_face
    ip_address: $VM_IP
    port: 5000
    source:
      - entity_id: $CAMERA_ENTITY_ID
"

echo "$CONF_YAML" > /tmp/deepstack_hass_config.yaml

echo "✅ Pronto! Adicione isso ao seu configuration.yaml, se a integração não aparecer automaticamente:"
cat /tmp/deepstack_hass_config.yaml
"Adiciona script de instalação automatizada do Deepstack".
