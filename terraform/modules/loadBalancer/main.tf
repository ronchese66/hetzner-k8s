resource "hcloud_load_balancer" "k8s_lb" {
  name = "k8sLoadBalancer"
  load_balancer_type = "lb11"
  location = "nbg1"
  delete_protection = true

  algorithm {
    type = "least_connections"
  }

  labels = {
    managedBy = "terraform"
  }
}

resource "hcloud_load_balancer_network" "k8s_lb_network" {
  ip = "10.0.1.10"

  enable_public_interface = true
  
  load_balancer_id = hcloud_load_balancer.k8s_lb.id
  network_id = var.network_id
  subnet_id = var.subnet_id
}  

resource "hcloud_load_balancer_service" "lb_http_service" {
  load_balancer_id = hcloud_load_balancer.k8s_lb.id

  protocol = "tcp"
  listen_port = 80
  destination_port = 30080
  proxyprotocol = true

  health_check {
    protocol = "tcp"
    port = 30080
    interval = 15
    timeout = 10
    retries = 5
  }
}

resource "hcloud_load_balancer_service" "lb_https_service" {
  load_balancer_id = hcloud_load_balancer.k8s_lb.id

  protocol = "tcp"
  listen_port = 443
  destination_port = 30443
  proxyprotocol = true

  health_check {
    protocol = "tcp"
    port = 30443
    interval = 15
    timeout = 10
    retries = 5
  }
}

resource "hcloud_load_balancer_target" "lb_target_workers" {
  load_balancer_id = hcloud_load_balancer.k8s_lb.id

  type = "label_selector"
  label_selector = "nodeType=worker"
  use_private_ip = true

  depends_on = [ hcloud_load_balancer_network.k8s_lb_network ]
}