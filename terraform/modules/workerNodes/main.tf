resource "hcloud_server" "worker_nodes" {
  for_each = var.worker_nodes

  name = each.key
  image = "centos-stream-10"
  server_type = "cpx22"
  location = "nbg1"
  backups = false

  placement_group_id = var.placement_group_id

  ssh_keys = [ var.ssh_key_id ]

  delete_protection = false
  rebuild_protection = false 
  shutdown_before_deletion = true

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
    nodeType = "worker"
    managedBy = "terraform"
    configuredBy = "ansible"
  }
}

resource "hcloud_server_network" "workers_network" {
  for_each = var.worker_nodes

  server_id = hcloud_server.worker_nodes[each.key].id 
  network_id = var.network_id
  ip = each.value.ip
}