# Kubernetes cluster on Hetzner Cloud
#### kubeadm-based cluster. Infrastructure managed by Terraform, configuration managed by Ansible.

### Architecture

**Single Control Plane, multiple workers, and a dedicated bastion host - all deployed in a single private subnet in Hetzner Cloud.**

*The bastion host is the only server accepting public inbound connections and acts as the single entry point for cluster provisioning, operations, Ansible execution.*

*External traffic enters through a Hetzner Load Balancer with PROXY protocol enabled and is forwarded to NGINX Ingress Controller running on worker nodes.*
> *Load Balancer > NodePort > NGINX Ingress Controller > Service > Pod*

*Outbound traffic from Kubernetes nodes and the monitoring server is routed through a NAT Gateway. Kubernetes nodes and the monitoring server have neither public IPv4 nor IPv6 addresses.*

| Node           | Private IP | Server type | 
| -------------- | ---------- | ----------- | 
| Bastion        | 10.0.1.5   | CX23        
| Control Plane  | 10.0.1.2   | CPX22       
| Worker-01      | 10.0.1.3   | CPX22       
| Worker-02      | 10.0.1.4   | CPX22       
| Load Balancer  | 10.0.1.10  | LB11        
| NAT Gateway    | 10.0.1.6   | CPX12
| Monitoring     | 10.0.1.7   | CX33        

| Scope          | CIDR |
| -------------- | ---- |
| Hetzner Network | 10.0.0.0/16 |
| Private Subnet | 10.0.1.0/24 |
| Pod CIDR       | 10.244.0.0/16 |
| Service CIDR   | 10.96.0.0/12 |



### Infrastructure provisioning

**[Terraform](./terraform/) >** *Hetzner Cloud provider (1.60.1). Infrastructure is split into independent modules:*

- **network** - private network, subnet, spread placement group.
- **controlPlane / workerNodes** - Kubernetes nodes with static private IP addresses.
- **bastion** - public entry point with a dedicated Primary IP and Cloud Firewall.
- **natGateway** - outbound gateway, default network route and egress firewall.
- **loadBalancer** - public Load Balancer, TCP listeners, health checks and worker targets.
- **monitoring** - dedicated private monitoring server.
- **etcd_backup_volume / api_audit_volume** - separate persistent Hetzner Volumes attached to the Control Plane.

*Worker nodes are provisioned using Terraform **for_each**, with node names and private IP addresses defined in the worker module variables. Load Balancer targets are selected dynamically by the **nodeType=worker** label.*

*Cloud-init provisions administrative users and SSH authorized keys during server creation.*

**[Ansible](./ansible/) >** *Dynamic inventory based on the Hetzner Cloud API. Hosts are grouped by their **nodeType** label. Private hosts are accessed through the bastion using SSH ProxyJump.*

*Component versions, network parameters and database configuration are centralized in [group_vars/all/all.yml](./ansible/group_vars/all/all.yml). Sensitive variables are stored separately using Ansible Vault.*

*Playbooks cover host preparation, networking, Kubernetes bootstrap, cluster components, database deployment, audit logging and monitoring.*

### Networking

**[NAT Gateway](./ansible/playbooks/ops/nat_gateway.yml) >** *Dedicated Debian host with IPv4 forwarding and nftables masquerading. Hetzner Network has a default route (0.0.0.0/0) pointing to the NAT Gateway.*

- *Outbound TCP 80/443 and TCP/UDP 53 only.*
- *Forwarding restricted to explicitly allowed private hosts.*
- *Default drop policy on input and forward hooks.*
- *SSH access through the private interface from bastion only.*

**[Private egress](./ansible/playbooks/ops/private_egress.yml) >** *Persistent default route configured through a systemd oneshot service, using the Hetzner Network gateway (10.0.0.1). DNS resolution uses Hetzner resolvers.*

**[Load Balancer](./terraform/modules/loadBalancer/) >** *Terraform-managed Hetzner LB11 with public and private interfaces. Least-connections balancing algorithm.*

| Listener | Destination | Protocol |
| -------- | ----------- | -------- |
| 80       | 30080       | TCP |
| 443      | 30443       | TCP |

*Traffic is forwarded exclusively to worker nodes using their private IP addresses. TLS termination at NGINX Ingress Controller.*

### Cluster components

**[Kubernetes](./ansible/playbooks/cluster/init_cluster.yml) >** *Kubernetes 1.35, bootstrapped using kubeadm. Single Control Plane with local etcd. API Server endpoint and advertise address use the private IP of the Control Plane.*\
**[CNI](./ansible/playbooks/cluster/calico_cni.yml) >** *Calico via Tigera Operator. Configured in VXLANCrossSubnet mode, native routing within single subnet, VXLAN encapsulation only between subnets.*\
**[Ingress](./ansible/playbooks/cluster/ingress_nginx.yml) >** *NGINX Ingress Controller as DaemonSet*.
- *externalTrafficPolicy: Local*
- *real client IP preserved via PROXY protocol*
- *Hetzner LB operates in the TCP Proxy Mode*
- *TLS enabled*
- *Read-only root filesystem*

**[Storage](./ansible/playbooks/cluster/hetzner_csi.yml) >** *Hetzner CSI driver, **hcloud-volumes** StorageClass, WaitForFirstConsumer policy.*\
**[Cloud integration](./ansible/playbooks/cluster/hetzner_ccm.yml) >** *Hetzner Cloud Controller Manager handles cloud provider integration, node metadata and removes the **node.cloudprovider.kubernetes.io/uninitialized** taint on node registration. Kubelet is configured with an external cloud provider and Hetzner provider ID. The existing public Load Balancer is managed independently by Terraform.*\
**[Secrets](./ansible/playbooks/cluster/k8s_infisical_eso.yml) >** *External Secrets Operator (ESO) syncs from Infisical storage. CCM requires the **hcloud** Secret before ESO is available - a bootstrap playbook creates it directly, ownership transferred to ESO post-installation.*\
**[Certificates](./ansible/playbooks/cluster/cert_manager.yml) >** *cert-manager with ClusterIssuer, Let's Encrypt. DNS-01 via CloudFlare API - requires domain NS delegation to CloudFlare. Certs are stored as Kubernetes Secrets and renewed automatically.*\
**[Runtime](./ansible/playbooks/cluster/containerd.yml) >** *containerd with Systemd cgroup driver.*\
**[etcd](./ansible/playbooks/cluster/etcd_backup_plan.yml) >** *Managed by Kubernetes as a static Pod. Snapshots are taken via etcdctl using a dedicated Ansible playbook and written to a separate 10 GB **Hetzner Volume** mounted at /var/backups/etcd on the CP node, persisted independently of node lifecycle.*

### Application

**[Healthchecks](https://github.com/kaaalim/django-sample-app) >** *Django-based Healthchecks 4.3 application deployed in the **healthchecks** namespace using a custom Helm chart.*

**Endpoint:** https://ronchese.pp.ua

*The application is deployed as two replicas behind a ClusterIP Service on port 8000. External access is provided through NGINX Ingress Controller with a dedicated TLS certificate issued by the letsencrypt-prod ClusterIssuer.*

> *Client > Hetzner LB > NGINX Ingress > ClusterIP Service > Healthchecks Pods > PostgreSQL*

*HTTP requests are redirected to HTTPS using status code 308.*

#### Deployment

*The Helm chart uses a two-stage deployment approach controlled by the **stage** value:*

- **bootstrap** - creates the application ConfigMap and ExternalSecret.
- **app** - deploys the application, Service, Ingress and database migration Job.

*Database migrations are executed as a Helm **pre-upgrade** hook, using the same container image and configuration as the application. Successful migration Jobs are removed automatically.*

*Container images are pinned by SHA256 digest. ConfigMap checksum annotation triggers application rollout when configuration changes.*

#### Container configuration

- *Two application replicas.*
- *CPU request: 250m, limit: 2 cores.*
- *Memory request: 256Mi, limit: 1Gi.*
- *HTTP readiness probe: /api/v1/status/.*
- *TCP liveness probe on the application port.*

*Application containers and migration Jobs run as a non-root user (UID/GID 10001), with a read-only root filesystem, RuntimeDefault seccomp profile, all Linux capabilities dropped and privilege escalation disabled.*

*ServiceAccount token automount is disabled.*

#### Application configuration

*Non-sensitive configuration is provided through a ConfigMap. Application secrets are synchronized from Infisical and mounted as read-only files rather than passed directly through environment variables.*

*Django DEBUG mode, public registration and webhooks are disabled.*

*Database connections use TLS with **verify-full** certificate verification. The PostgreSQL CA certificate is mounted from the CloudNativePG-generated Secret.*

### Database

**[CloudNativePG](./ansible/playbooks/cluster/cnpg_operator.yml) >** *PostgreSQL operator deployed via Helm in the **cnpg-system** namespace.*

**[PostgreSQL Cluster](./ansible/playbooks/db/postgresql.yml) >** *PostgreSQL 17, deployed as a CloudNativePG Cluster resource using an Ansible-rendered [manifest](./ansible/templates/postgresql/cluster.yml.j2).*

| Parameter | Value |
| --------- | ----- |
| Cluster name | healthchecks-db |
| Namespace | healthchecks |
| Instances | 2 |
| Database | healthchecks |
| Database owner | healthchecks |
| StorageClass | hcloud-volumes |
| Storage per instance | 10Gi |
| Superuser access | Disabled |

*One primary and one replica, with replication and failover managed by CloudNativePG. Each instance uses its own persistent volume provisioned through Hetzner CSI.*

*Application connections use the operator-managed read/write Service:*

`healthchecks-db-rw.healthchecks.svc.cluster.local:5432`

*Database credentials are synchronized from Infisical through an ExternalSecret into the **postgres-app** Secret (kubernetes.io/basic-auth). Database initialization is performed through CloudNativePG initdb bootstrap.*


### Security

***Hetzner Cloud Firewall** attached to bastion allows **TCP 22** only on public interface. SSH key auth only, password and root login disabled cluster-wide.*

***[nftables](./ansible/templates/nftables/)** configurations are separated by host role, with default **drop** policies on input hooks. Private SSH access is restricted to bastion. Kubernetes API and node management ports are restricted to internal network access.*

*The NAT Gateway additionally enforces outbound forwarding restrictions. Monitoring server firewall rules restrict both inbound and outbound connections.*

*Sensitive Ansible variables encrypted with Ansible Vault.*

#### Secrets management

*Infisical is configured as the external secret storage backend. ESO authenticates using Universal Auth credentials and a shared ClusterSecretStore named **infisical-store**.*


*ExternalSecrets use **creationPolicy: Owner** and a one-hour refresh interval. The initial hcloud bootstrap Secret is replaced by an ESO-managed Secret.*

#### Kubernetes API audit

**[Audit configuration](./ansible/playbooks/cluster/api_audit.yml) >** *Kubernetes API Server audit logging configured through kubeadm ClusterConfiguration. API Server static Pod manifest is regenerated using kubeadm after configuration validation and dry-run.*

*Audit logs are written in JSON format to a dedicated 20 GB Hetzner Volume mounted at **/var/log/kubernetes/audit**. Volume availability is verified before applying the audit configuration.*

**[Audit Policy](./ansible/kubernetes/audit-policy.yaml) >** *Audit levels are selected by resource type, operation and requester.*

- *Health checks, coordination leases and selected repetitive system requests are excluded.*
- *Secrets, TokenReviews, exec, attach and port-forward requests are logged at Metadata level.*
- *Selected workload and RBAC modification requests are logged at Request level.*
- *Remaining requests are logged at Metadata level.*

*Local audit logs are rotated at 512 MB, compressed, with a maximum age of seven days and up to 30 backup files.*

### Monitoring

*The monitoring stack is deployed outside the Kubernetes cluster on a dedicated private server. Core monitoring services run as systemd services.*

| Component | Version | Placement |
| --------- | ------- | --------- |
| Prometheus | 3.16.0 | Monitoring |
| Alertmanager | 0.35.1 | Monitoring |
| Grafana OSS | 13.3.1 | Monitoring |
| Loki | 3.7.10 | Monitoring |
| Grafana Alloy | 1.21.3 | Control Plane |
| Node Exporter | 1.13.1 | Kubernetes nodes, Monitoring |
| kube-state-metrics | 2.20.0 | Control Plane |
| Kubernetes Events Exporter | 0.2.0 | Control Plane |

**[Prometheus](./ansible/playbooks/monitoring/prometheus.yml) >** *Collects Node Exporter, API Server, kubelet, cAdvisor, kube-state-metrics, Kubernetes Events and CloudNativePG metrics. Static targets are combined with Kubernetes Pod service discovery and API Server Pod Proxy endpoints.*

**[Alertmanager](./ansible/playbooks/monitoring/prometheus/alertmanager.yml) >** *Receives Prometheus alerts evaluated against 46 Kubernetes alerting rules. Alerts are grouped by alertname and namespace. External notification integrations are omitted.*

**[Loki](./ansible/playbooks/monitoring/loki/) >** *Single-instance deployment using TSDB and filesystem storage. Seven-day retention.*

**[Grafana Alloy](./ansible/playbooks/monitoring/grafana/alloy.yml) >** *Reads Kubernetes API audit logs from the Control Plane, extracts event timestamps and forwards records to Loki over the private network.*

> *Kubernetes API Server > Audit log > Grafana Alloy > Loki > Grafana*

**[Grafana](./ansible/playbooks/monitoring/grafana.yml) >** *Connected to Prometheus, Loki and Alertmanager. Anonymous access disabled. Includes a Grafana-managed alert for Kubernetes API HTTP 5XX responses based on Loki audit logs.*

#### Dashboards

*Dashboard definitions are stored in [grafana/dashboards/](./grafana/dashboards/).*

| Dashboard | Scope |
| --------- | ----- |
| [Infrastructure Overview](./grafana/dashboards/infra_overview.json) | CPU, memory, filesystem, disk I/O, network and system load |
| [Kubernetes Workloads & Events](./grafana/dashboards/k8s_workloads_and_events.json) | Pod restarts, resource limits, OOMKilled, workload state and Kubernetes Events |
| [PostgreSQL (CloudNativePG)](./grafana/dashboards/psql_cnpg_db.json) | Database instances, replication lag, connections, storage and resource utilization |
| [K8s HTTP Codes & Errors](./grafana/dashboards/k8s-http-responses-and-codes.json) | API response codes, HTTP 4XX/5XX and API operations |
| [AlertsOverview](./grafana/dashboards/alerts.json) | Active alerts, severity counters, Pending and Firing states |

*Prometheus and Alertmanager listen on localhost. Grafana and Loki listen on the monitoring server's private IP. Grafana is accessed through an SSH tunnel via bastion.*

#### Naming pattern
*The main pattern is - **node-purpose.k8s.internal***\
*Examples:*
- *Control Plane > **cp-main.k8s.internal** (single CP). Additional CP nodes use **cp-2.k8s.internal**, etc.*
- *Workers > **worker-1.k8s.internal**, **worker-2.k8s.internal**, etc.*
- *Bastion > **bastion.k8s.internal**.*
- *Other hosts > **node-\<id>.k8s.internal***
- *NAT Gateway > **nat.k8s.internal***
- *Monitoring > **monitor.k8s.internal***
