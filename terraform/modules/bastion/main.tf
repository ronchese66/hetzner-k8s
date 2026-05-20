resource "hcloud_primary_ip" "bastion_ip" {
  name = "bastionPrimaryIP"
  type = "ipv4"
  location = "nbg1"
  assignee_type = "server"
  auto_delete = false

  labels = {
    managedBy = "terraform"
  }
}

resource "hcloud_server" "bastion" {
  name = "bastion"
  image = "centos-stream-10"
  server_type = "cx23"
  location = "nbg1"

  backups = false
  delete_protection = true
  rebuild_protection = true
  shutdown_before_deletion = true

  ssh_keys = [ var.ssh_key_id ]

  public_net {
    ipv4_enabled = true
    ipv4 = hcloud_primary_ip.bastion_ip.id
    ipv6_enabled = false
  }

  user_data = <<-EOF
    #cloud-config
    users:
      - name: ansible
        groups: sudo
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: true
        ssh_authorized_keys: 
          - ${var.public_key}
      - name: admin
        groups: wheel
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: true
        ssh_authorized_keys:
          - ${var.public_key}
  EOF

  labels = {
    nodeType = "bastion"
    managedBy = "terraform"
    configuredBy = "ansible"
  }
}

resource "hcloud_server_network" "bastion_net" {
  server_id = hcloud_server.bastion.id
  network_id = var.network_id
  ip = "10.0.1.5"
}

resource "hcloud_firewall" "bastion_firewall" {
  name = "bastionFW"

  rule {
    direction = "in"
    protocol = "tcp"
    port = "22"
    source_ips = [ "0.0.0.0/0" ]
    description = "Allow SSH"
  }

  labels = {
    managedBy = "terraform"
  }
}

resource "hcloud_firewall_attachment" "bastion_firewall_att" {
  firewall_id = hcloud_firewall.bastion_firewall.id
  server_ids = [hcloud_server.bastion.id]
}