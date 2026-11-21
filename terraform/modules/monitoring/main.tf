resource "hcloud_server" "monitoring" {
  name        = "monitoring"
  image       = "centos-stream-10"
  server_type = "cx33"
  location    = "nbg1"

  backups                  = false
  delete_protection        = false
  rebuild_protection       = false
  shutdown_before_deletion = false

  placement_group_id = var.placement_group_id
  ssh_keys           = [var.ssh_key_id]

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  network {
    network_id = var.network_id
    ip         = "10.0.1.7"
  }

  user_data = <<-EOF
#cloud-config
ssh_pwauth: false
disable_root: true
users:
  - name: ansible
    groups: wheel
    shell: /bin/bash
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    lock_passwd: true
    ssh_authorized_keys:
      - ${var.public_key}
EOF

  labels = {
    nodeType     = "monitoring"
    managedBy    = "terraform"
    configuredBy = "ansible"
  }
}