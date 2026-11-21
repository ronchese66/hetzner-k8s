resource "hcloud_server" "nat_gateway" {
  name        = "natGateway"
  image       = "debian-13"
  server_type = "cpx12"
  location    = "nbg1"

  backups                  = false
  delete_protection        = false
  rebuild_protection       = false
  shutdown_before_deletion = true

  ssh_keys = [var.ssh_key_id]

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  user_data = <<-EOF
    #cloud-config
    ssh_pwauth: false
    disable_root: true
    users:
      - name: ansible
        groups: sudo
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: true
        ssh_authorized_keys:
          - ${var.public_key}
  EOF

  labels = {
    nodeType     = "natGateway"
    managedBy    = "terraform"
    configuredBy = "ansible"
  }
}

resource "hcloud_server_network" "nat_gateway_network" {
  server_id  = hcloud_server.nat_gateway.id
  network_id = var.network_id
  ip         = "10.0.1.6"
}

resource "hcloud_network_route" "nat_gateway_route" {
  network_id  = var.network_id
  destination = "0.0.0.0/0"
  gateway     = hcloud_server_network.nat_gateway_network.ip
}

resource "hcloud_firewall" "nat_gateway_firewall" {
  name = "natGatewayFW"

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "80"
    destination_ips = ["0.0.0.0/0"]
    description     = "Allow outbound HTTP"
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "443"
    destination_ips = ["0.0.0.0/0"]
    description     = "Allow outbound HTTPS"
  }

  rule {
    direction       = "out"
    protocol        = "udp"
    port            = "53"
    destination_ips = ["0.0.0.0/0"]
    description     = "Allow outbound DNS"
  }

  rule {
    direction       = "out"
    protocol        = "tcp"
    port            = "53"
    destination_ips = ["0.0.0.0/0"]
    description     = "Allow outbound DNS TCP"
  }

  labels = {
    managedBy = "terraform"
  }
}

resource "hcloud_firewall_attachment" "nat_gateway_firewall_attachment" {
  firewall_id = hcloud_firewall.nat_gateway_firewall.id
  server_ids  = [hcloud_server.nat_gateway.id]
}
