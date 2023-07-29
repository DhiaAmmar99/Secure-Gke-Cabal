# create VPC
resource "google_compute_network" "vpc" {
  name                    = "vpc1"
  auto_create_subnetworks = false
}

# Create Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "subnet"
  region        = local.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.0.0.0/24"
}








# Create GKE cluster with 2 nodes in our custom VPC/Subnet
resource "google_container_cluster" "primary" {
  name                     = "cabal-cluster"
  location                 =  local.zone
  network                  = google_compute_network.vpc.name
  subnetwork               = google_compute_subnetwork.subnet.name
  remove_default_node_pool = true ## create the smallest possible default node pool and immediately delete it.
  initial_node_count = 1

  private_cluster_config {
    enable_private_endpoint = true
    enable_private_nodes    = true
    master_ipv4_cidr_block  = "10.13.0.0/28"
  }
  ip_allocation_policy {
    cluster_ipv4_cidr_block  = "10.11.0.0/21"
    services_ipv4_cidr_block = "10.12.0.0/21"
  }
  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "10.0.0.7/32"
      display_name = "net1"
    }

  }
}

# Create managed node pool
resource "google_container_node_pool" "primary_nodes" {
  name       = google_container_cluster.primary.name
  location   = local.zone
  cluster    = google_container_cluster.primary.name
  node_count = 3

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = "cabal-ynov"
    }

    machine_type = "e2-standard-2"
    preemptible  = true
    #service_account = google_service_account.mysa.email

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}



## Create jump host . We will allow this jump host to access GKE cluster. the ip of this jump host is already authorized to allowin the GKE cluster

resource "google_compute_address" "my_internal_ip_addr" {
  project      = local.project_id
  address_type = "INTERNAL"
  region       = local.region
  subnetwork   = "subnet"
  name         = "my-ip"
  address      = "10.0.0.7"
  description  = "An internal IP address for my jump host"
}

resource "google_compute_instance" "default" {
  project      = local.project_id
  zone         = "europe-west9-a"
  name         = "jump-host"
  machine_type = local.type-instance

  boot_disk {
    initialize_params {
      image = local.image-instance
    }
  }
  network_interface {
    network    = "vpc1"
    subnetwork = "subnet" # Replace with a reference or self link to your subnet, in quotes
    network_ip = google_compute_address.my_internal_ip_addr.address
  }

}


## Creare Firewall to access jump hist via iap


resource "google_compute_firewall" "rules" {
  project = local.project_id
  name    = "allow-ssh"
  network = "vpc1" # Replace with a reference or self link to your network, in quotes

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"]
}



## Create IAP SSH permissions for your test instance

resource "google_project_iam_member" "project" {
  project = local.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = "serviceAccount:cabal-archi@cabal-archi.iam.gserviceaccount.com"
}

# create cloud router for nat gateway
resource "google_compute_router" "router" {
  project = local.project_id
  name    = "nat-router"
  network = "vpc1"
  region  = local.region
}

## Create Nat Gateway with module

module "cloud-nat" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 1.2"
  project_id =  local.project_id
  region     = local.region
  router     = google_compute_router.router.name
  name       = "nat-config"

}


############Output############################################
output "kubernetes_cluster_host" {
  value       = google_container_cluster.primary.endpoint
  description = "GKE Cluster Host"
}

output "kubernetes_cluster_name" {
  value       = google_container_cluster.primary.name
  description = "GKE Cluster Name"
}