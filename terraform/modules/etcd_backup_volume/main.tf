resource "hcloud_volume" "etcd_backup_volume" {
  name = "etcd_backup"
  size = 10
  format = "ext4"
  automount = false
  delete_protection = true
  server_id = var.server_id

  labels = {
    createdBy = "terraform"
  }
}