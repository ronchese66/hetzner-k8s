output "server_id" {
  value = hcloud_server.nat_gateway.id
}

output "private_ip" {
  value = hcloud_server_network.nat_gateway_network.ip
}

output "public_ip" {
  value = hcloud_server.nat_gateway.ipv4_address
}
