data "selectel_mks_kube_versions_v1" "versions" {
  project_id = var.project_id
  region     = var.region
}

resource "selectel_mks_cluster_v1" "ha_cluster" {
  name         = "cluster-infra-analyzer"
  project_id   = var.project_id
  region       = var.region
  kube_version = data.selectel_mks_kube_versions_v1.versions.latest_version
  oidc {
    enabled = false
    issuer_url = ""
    provider_name = ""
    client_id = ""
  }
}

resource "selectel_mks_nodegroup_v1" "nodegroup_system" {
  cluster_id        = selectel_mks_cluster_v1.ha_cluster.id
  project_id        = var.project_id
  region            = var.region
  availability_zone = var.availability_zone
  nodes_count       = 2
  volume_type       = "${var.volume_type}.${var.availability_zone}"
  volume_gb         = 40
  cpus              = 2
  ram_mb            = 4096

  labels = {
    role = "system"
  }

  install_nvidia_device_plugin = false
}

locals {
  gpu_nodegroups = flatten([
    for az, flavors in var.gpu_az_flavors : [
      for flavor in flavors : {
        az     = az
        flavor = flavor
      }
    ]
  ])
}

resource "selectel_mks_nodegroup_v1" "nodegroup_gpu" {
  for_each = { for o in local.gpu_nodegroups : "${o.az}_${o.flavor}" => o }

  cluster_id        = selectel_mks_cluster_v1.ha_cluster.id
  project_id        = var.project_id
  region            = var.region
  availability_zone = "${var.region}${each.value.az}"
  nodes_count       = 1
  volume_type       = "${var.volume_type}.${var.region}${each.value.az}"
  volume_gb         = var.volume_gb
  preemptible       = true

  flavor_id = each.value.flavor

  install_nvidia_device_plugin = true

  enable_autoscale    = false
  autoscale_min_nodes = 0
  autoscale_max_nodes = 0
}

data "selectel_mks_kubeconfig_v1" "kubeconfig" {
  cluster_id = selectel_mks_cluster_v1.ha_cluster.id
  project_id = var.project_id
  region     = var.region
}

resource "local_file" "kube_config_file" {
  content  = data.selectel_mks_kubeconfig_v1.kubeconfig.raw_config
  filename = "../kubernetes/kubeconfig"
}

### ----SFS----

module "sfs" {
  source               = "./sfs"
  os_network_id        = selectel_mks_cluster_v1.ha_cluster.network_id
  os_subnet_id         = selectel_mks_cluster_v1.ha_cluster.subnet_id
  sfs_size             = var.nfs_share_size
  sfs_volume_type      = "${var.volume_type}"
  os_availability_zone = var.availability_zone
}

resource "local_file" "nfs_share" {
  content = <<EOT
apiVersion: v1
kind: PersistentVolume
metadata:
  name: nfs-pv
spec:
  capacity:
    storage: ${var.nfs_share_size}
  accessModes:
    - ReadWriteMany
  nfs:
    server: "${split(":", module.sfs.sfs_address)[0]}"
    path: "${split(":", module.sfs.sfs_address)[1]}"
  persistentVolumeReclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nfs-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: ${var.nfs_share_size}
  volumeName: nfs-pv
EOT
  filename = "../kubernetes/nfs-pv-pvc.yaml"
}