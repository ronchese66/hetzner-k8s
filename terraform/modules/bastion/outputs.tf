output "bastion_public_ip" {
  value = hcloud_primary_ip.bastion_ip.ip_address
}
