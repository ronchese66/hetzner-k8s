variable "worker_nodes" {
  type = map(object({
    ip = string
  }))

  default = {
    "worker-01" = { ip = "10.0.1.3" }
    "worker-02" = { ip = "10.0.1.4" }
  }
}

variable "placement_group_id" {}

variable "network_id" {}

variable "ssh_key_id" {}

variable "public_key" {}