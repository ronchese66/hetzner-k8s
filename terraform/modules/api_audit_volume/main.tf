resource "hcloud_volume" "kubernetes_audit_logs" {
  name     = "k8sAuditLogs"
  size     = 20
  location = "nbg1"
  format   = "ext4"

  delete_protection = false

  labels = {
    managedBy = "terraform"
    purpose   = "kubernetes-audit-logging"
  }
}

resource "hcloud_volume_attachment" "control_plane_attachment" {
  volume_id = hcloud_volume.kubernetes_audit_logs.id
  server_id = var.server_id
  automount = false
}
