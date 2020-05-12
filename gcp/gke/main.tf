locals {
  cluster_type = "earthcube"
}

provider "google-beta" {
  version = "~> 3.19.0"
  region  = var.region
}

# https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/issues/423#issuecomment-583146389
# module "gcp-network" {
#   source       = "terraform-google-modules/network/google"
#   version      = "~> 2.0"
#   project_id   = var.project_id
#   network_name = var.network

#   subnets = [
#     {
#       subnet_name   = var.subnetwork
#       subnet_ip     = "10.0.0.0/17"
#       subnet_region = var.region
#     },
#   ]

#   secondary_ranges = {
#     "${var.subnetwork}" = [
#       {
#         range_name    = var.ip_range_pods
#         ip_cidr_range = "192.168.0.0/18"
#       },
#       {
#         range_name    = var.ip_range_services
#         ip_cidr_range = "192.168.64.0/18"
#       },
#     ]
#   }
# }

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 2.3"

  project_id   = var.project_id
  network_name = var.network
  subnets = [
    {
      subnet_name : var.subnet.name,
      subnet_ip : var.subnet.ip,
      subnet_region : var.region
    }
  ]

  secondary_ranges = {
    "${var.subnet.name}" = [
      {
        range_name    = var.ip_range_pods
        ip_cidr_range = "192.168.0.0/18"
      },
      {
        range_name    = var.ip_range_services
        ip_cidr_range = "192.168.64.0/18"
      },
    ]
  }
}

module "gke" {
  source                            = "terraform-google-modules/kubernetes-engine/google//modules/beta-public-cluster"
  project_id                        = var.project_id
  name                              = var.cluster_name
  region                            = var.region
  zones                             = var.zones
  network                           = var.network
  subnetwork                        = var.subnetwork
  ip_range_pods                     = var.ip_range_pods
  ip_range_services                 = var.ip_range_services
  create_service_account            = false
  remove_default_node_pool          = true
  disable_legacy_metadata_endpoints = false
  #   cluster_autoscaling               = var.cluster_autoscaling

  node_pools = [
    {
      name         = "scheduler-pool"
      machine_type = "n1-standard-8"
      min_count    = 0
      max_count    = 2
      # service_account = var.compute_engine_service_account
      auto_upgrade       = true
      initial_node_count = 1
      preemptible        = false
    },
    {
      name         = "worker-pool"
      machine_type = "n1-standard-8"
      min_count    = 0
      max_count    = 40
      # service_account   = var.compute_engine_service_account
      preemptible = true
    },
    {
      name               = "gateway"
      machine_type       = "n1-standard-8"
      auto_upgrade       = true
      initial_node_count = 1
      preemptible        = false
    }
  ]

  #   node_pools_metadata = {
  #     pool-01 = {
  #       shutdown-script = file("${path.module}/data/shutdown-script.sh")
  #     }
  #   }

  node_pools_labels = {
    all = {
      all-pools-example = true
    }
  }

  node_pools_taints = {
    all = [
      {
        key    = "all-pools-example"
        value  = true
        effect = "PREFER_NO_SCHEDULE"
      },
    ]
    scheduler-pool = [
      {
        key    = "k8s.dask.org/dedicated"
        value  = "scheduler"
        effect = "NO_SCHEDULE"
      },
    ],
    worker-pool = [
      {
        key    = "k8s.dask.org/dedicated"
        value  = "worker"
        effect = "NO_SCHEDULE"
      },
    ]
  }
}


resource "kubernetes_cluster_role_binding" "example" {
  metadata {
    name = "terraform-example"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }
  subject {
    kind      = "User"
    name      = "admin"
    api_group = "rbac.authorization.k8s.io"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "default"
    namespace = "kube-system"
  }
  subject {
    kind      = "Group"
    name      = "system:masters"
    api_group = "rbac.authorization.k8s.io"
  }
}
