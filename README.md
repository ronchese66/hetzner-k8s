# Kubernetes cluster on Hetzner Cloud
#### kubeadm-based cluster. Infrastructure managed by Terraform, configuration managed by Ansible.

### Architecture

**Single Control Plane, multiple workers, and a dedicated bastion host - all deployed in a single private subnet in Hetzner Cloud. Workers are not autoscaled by Kubernetes. Node scaling is handled externally via Terraform**

*The bastion host is the only publicly reachable server and acts as the single entry point for cluster provisioning, operations, Ansible execution.*

*External traffic enters through a Hetzner Load Balancer with PROXY protocol enabled and is forwarded to NGINX Ingress Controller running on worker nodes.*
> *Load Balancer > NodePort > NGINX Ingress Controller > Service*

| Node  | Private IP |
|  ------------- | -------------  |
| bastion        | 10.0.1.5  |
| Control Plane  | 10.0.1.2  |
| Worker-01      | 10.0.1.3  |
| Worker-02      | 10.0.1.4  |
| Load Balancer  | 10.0.1.10 |

| Scope  | CIDR |
|  ------------- | -------------  |
| Private Subnet | 10.0.1.0/24
| Pod CIDR       | 10.244.0.0/16
| Service CIDR   | 10.96.0.0/12


### Cluster components

**[CNI](./ansible/playbooks/cluster/calico_cni.yml) >** *Calico via Tigera Operator. Configured in VXLANCrossSubnet mode, native routing within single subnet, VXLAN encapsulation only between subnets.*\
**[Ingress](./ansible/playbooks/cluster/ingress_nginx.yml) >** *NGINX Ingress Controller (F5) as DaemonSet*.
- *externalTrafficPolicy: Local*
- *real client IP preserved via PROXY protocol*
- *Hetzner LB operates in the TCP Proxy Mode*

**[Storage](./ansible/playbooks/cluster/hetzner_csi.yml) >** *Hetzner CSI driver, **hcloud-volumes** StorageClass, WaitForFirstConsumer policy.*\
**[Cloud integration](./ansible/playbooks/cluster/hetzner_ccm.yml) >** *Hetzner Cloud Controller Manager manages Load Balancer lifecycle and removes the **node.cloudprovider.kubernetes.io/uninitialized** taint on node registration.*\
**[Secrets](./ansible/playbooks/cluster/k8s_infisical_eso.yml) >** *External Secret Operator (ESO) syncs from Infisical storage. CCM requires the **hcloud** Secret before ESO is available - a bootstrap playbook creates it directly, ownership transferred to ESO post-installation.*\
**[Certificates](./ansible/playbooks/cluster/cert_manager.yml) >** *cert-manager with ClusterIssuer, Let's Encrypt. DNS-01 via CloudFlare API - requires domain NS delegation to CloudFlare. Certs are stored as Kubernetes Secrets and renewed automatically.*\
**[Runtime](./ansible/playbooks/cluster/containerd.yml) >** *containerD with Systemd cgroup driver.*\
**[etcd](./ansible/playbooks/cluster/etcd_backup_plan.yml) >** *Managed by Kubernetes as a static Pod. Snapshots are taken via etcdctl and written to a dedicated **Hetzner Volume** mounted on the CP node, persisted independently of node lifecycle.*

### Security

***Hetzner Cloud Firewall** attached to bastion allows **TCP 22** only on public interface. SSH key auth only, password and root login disabled cluster-wide.*

***[nftables](./ansible/templates/nftables/)** on all nodes with default **drop** policy on input hook. Permits required Kubernetes ports within the private subnet. SSH from **bastion only**.*

*Sensitive Ansible variables encrypted with Ansible Vault.*

### Access

*All administration access from bastion.*

*A Python daemon runs as a systemd service, polls Hetzner API every 60 seconds and maintains **/etc/hosts** with cluster node hostnames.*

#### Naming pattern
*The main pattern is - **node-purpose.k8s.internal***\
*Examples:*
- *Control Plane > **cp-main.k8s.internal** (single CP). Additional CP nodes uses **cp-2.k8s.internal**, etc.*
- *Workers > **worker-1.k8s.internal**, **worker-02.k8s.internal**, etc.*
- *Bastion > **bastion.k8s.internal**.*
- *Unlabeled hosts > **node-\<id>.k8s.internal***
