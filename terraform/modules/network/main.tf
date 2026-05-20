
resource "hcloud_network" "k8s_cluster_network" {
  name = "k8sPrivateNet"
  ip_range = "10.0.0.0/16"
  delete_protection = true

  labels = {
    managedBy = "terraform"
  }
}

resource "hcloud_network_subnet" "k8s_cluster_private_subnet" {
  ip_range = "10.0.1.0/24"
  type = "cloud"
  network_zone = "eu-central"

  network_id = hcloud_network.k8s_cluster_network.id
}

resource "hcloud_placement_group" "k8s_cluster_pg" {
  name = "k8sClusterPG"
  type = "spread"
  
  labels = {
    managedBy = "terraform"
  }
}