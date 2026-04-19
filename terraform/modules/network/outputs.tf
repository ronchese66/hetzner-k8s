output "placement_group_id" {
  value = hcloud_placement_group.k8s_cluster_pg.id
}

output "network_id" {
  value = hcloud_network.k8s_cluster_network.id
}

output "subnet_id" {
  value = hcloud_network_subnet.k8s_cluster_private_subnet.id 
}