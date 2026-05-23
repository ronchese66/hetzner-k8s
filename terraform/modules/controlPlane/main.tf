resource "hcloud_server" "control_plane" {
  name = "controlPlane"
  image = "centos-stream-10"
  server_type = "cpx22"
  location = "nbg1"

  backups = false
  delete_protection = true
  rebuild_protection = true
  shutdown_before_deletion = true

  public_net {
    ipv4_enabled = false
    ipv6_enabled = false
  }

  placement_group_id = var.placement_group_id

  ssh_keys = [ var.ssh_key_id ]

  user_data = <<-EOF
    #cloud-config
    users:
      - name: ansible
        groups: wheel
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
    nodeType = "controlPlane"
    managedBy = "terraform"
    configuredBy = "ansible"
  }
}

resource "hcloud_server_network" "control_plane_network" {
  server_id = hcloud_server.control_plane.id
  network_id = var.network_id
  ip = "10.0.1.2"
}