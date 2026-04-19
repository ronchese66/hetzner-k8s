data "hcloud_ssh_key" "k8s_cluster_key" {
  name = "k8s-cluster-key"
}

module "controlPlane" {
  source = "./modules/controlPlane"
  placement_group_id = module.network.placement_group_id
  network_id = module.network.network_id
  ssh_key_id = data.hcloud_ssh_key.k8s_cluster_key.id
  public_key = data.hcloud_ssh_key.k8s_cluster_key.public_key
}

module "workerNodes" {
  source = "./modules/workerNodes"
  placement_group_id = module.network.placement_group_id
  network_id = module.network.network_id
  ssh_key_id = data.hcloud_ssh_key.k8s_cluster_key.id
  public_key = data.hcloud_ssh_key.k8s_cluster_key.public_key
}

module "bastion" {
  source = "./modules/bastion"
  ssh_key_id = data.hcloud_ssh_key.k8s_cluster_key.id
  network_id = module.network.network_id
  public_key = data.hcloud_ssh_key.k8s_cluster_key.public_key
}

module "loadBalancer" {
  source = "./modules/loadBalancer"
  network_id = module.network.network_id
  subnet_id = module.network.subnet_id
}

module "network" {
  source = "./modules/network"
}   