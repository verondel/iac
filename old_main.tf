// ---------------------------------------------------
// Creating folder in Yandex Cloud
// ---------------------------------------------------

resource "yandex_resourcemanager_folder" "infra-folder" {
  cloud_id    = "b1gbah01iq91a144cu4m"
  name        = "infraa"
  description = "main folder"
}

// ---------------------------------------------------
// NETWORK
// ---------------------------------------------------

resource "yandex_vpc_network" "infra-vpc-network" {
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
  name        = "infra_vpc_network"
  description = "infra vpc network description"
  labels = {
    tf-label = "tf-label-value"
  }
}

resource "yandex_vpc_subnet" "infra-subnet" {
  name           = "infra-subnet"
  description    = "main subnet"
  v4_cidr_blocks = ["192.168.0.0/16"]
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.infra-vpc-network.id
  folder_id      = yandex_resourcemanager_folder.infra-folder.id
}


// ----------------------------------------------------
// FOR KUBER
// ----------------------------------------------------

resource "yandex_vpc_security_group" "infra-security-group" {
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
  name        = "infra-security-group"
  description = "description for my security group"
  network_id  = yandex_vpc_network.infra-vpc-network.id

  labels = {
    my-label = "my-label-value"
  }
}

resource "yandex_logging_group" "infra-logging-group" {
  name      = "infra-logging-group"
  folder_id = yandex_resourcemanager_folder.infra-folder.id
}

resource "yandex_kms_symmetric_key" "infra-kms-key" {
  name              = "infra-symetric-key"
  description       = "infra key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" // equal to 1 year
  folder_id         = yandex_resourcemanager_folder.infra-folder.id
}


// -------------------------------------------------------------------------------
// SA 1
// -------------------------------------------------------------------------------

resource "yandex_iam_service_account" "infra-service-account" {
  name        = "infra-service-account"
  description = "service account for master"
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
}


data "yandex_iam_policy" "editor-infra-policy" {
  binding {
    role = "editor"

    members = [
      "serviceAccount:${yandex_iam_service_account.infra-service-account.id}",
    ]
  }
}

resource "yandex_iam_service_account_iam_policy" "editor-infra-account-iam" {
  service_account_id = yandex_iam_service_account.infra-service-account.id
  policy_data        = data.yandex_iam_policy.editor-infra-policy.policy_data
}


// -------------------------------------------------------------------------------
// SA 2 
// -------------------------------------------------------------------------------

resource "yandex_iam_service_account" "node-service-account" {
  name        = "node-service-account"
  description = "service account for nodes"
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
}

data "yandex_iam_policy" "editor-node-policy" {
  binding {
    role = "editor"

    members = [
      "serviceAccount:${yandex_iam_service_account.node-service-account.id}",
    ]
  }
}

resource "yandex_iam_service_account_iam_policy" "editor-node-account-iam" {
  service_account_id = yandex_iam_service_account.node-service-account.id
  policy_data        = data.yandex_iam_policy.editor-node-policy.policy_data
}



// -------------------------------------------------------------------------------
// IAM binding for kuber (Выдаем три роли)
// -------------------------------------------------------------------------------

resource "yandex_resourcemanager_folder_iam_binding" "infra-sa-vpc-admin" {
  folder_id = yandex_resourcemanager_folder.infra-folder.id
  role      = "vpc.publicAdmin"

  members = [
    "serviceAccount:${yandex_iam_service_account.infra-service-account.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "infra-sa-compute-admin" {
  folder_id = yandex_resourcemanager_folder.infra-folder.id
  role      = "compute.admin"

  members = [
    "serviceAccount:${yandex_iam_service_account.infra-service-account.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "infra-sa-sa-user" {
  folder_id = yandex_resourcemanager_folder.infra-folder.id
  role      = "iam.serviceAccounts.user"

  members = [
    "serviceAccount:${yandex_iam_service_account.infra-service-account.id}"
  ]
}


// --------------------------------------------------------------------------
// Create a new Managed Kubernetes zonal Cluster.
// --------------------------------------------------------------------------

resource "yandex_kubernetes_cluster" "zonal_cluster" {
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
  name        = "zonal-infra-cluster"
  description = "zonal infra cluster"

  network_id = yandex_vpc_network.infra-vpc-network.id

  master {
    version = "1.30"
    zonal {
      zone      = yandex_vpc_subnet.infra-subnet.zone
      subnet_id = yandex_vpc_subnet.infra-subnet.id
    }

    public_ip = true

    security_group_ids = ["${yandex_vpc_security_group.infra-security-group.id}"]

    maintenance_policy {
      auto_upgrade = true

      maintenance_window {
        start_time = "18:00"
        duration   = "3h"
      }
    }

    master_logging {
      enabled                    = true
      log_group_id               = yandex_logging_group.infra-logging-group.id
      kube_apiserver_enabled     = true
      cluster_autoscaler_enabled = true
      events_enabled             = true
      audit_enabled              = true
    }
  }

  service_account_id      = yandex_iam_service_account.infra-service-account.id
  node_service_account_id = yandex_iam_service_account.node-service-account.id

  labels = {
    my_key       = "my_value"
    my_other_key = "my_other_value"
  }

  release_channel         = "RAPID"
  network_policy_provider = "CALICO"

  kms_provider {
    key_id = yandex_kms_symmetric_key.infra-kms-key.id
  }
}

//
// Create a new Managed Kubernetes Node Group.
//
resource "yandex_kubernetes_node_group" "infra_node_group" {
  cluster_id  = yandex_kubernetes_cluster.zonal_cluster.id
  name        = "infra_node_group"
  description = "main node group"
  version     = "1.30"

  labels = {
    "key" = "value"
  }

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat        = true
      subnet_ids = ["${yandex_vpc_subnet.infra-subnet.id}"]
    }

    resources {
      memory = 2
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    scheduling_policy {
      preemptible = false
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-d"
    }
  }

  maintenance_policy {
    auto_upgrade = false
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "18:00"
      duration   = "3h"
    }
  }
}


// ---------------------------------------------------------------------
// GITLAB
// ---------------------------------------------------------------------

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  namespace  = "gitlab"

  create_namespace = true

  values = [
    file("${path.module}/helm-values/gitlab-values.yaml")
  ]

  timeout = 600
  depends_on = [
    yandex_kubernetes_cluster.zonal_cluster,
    yandex_kubernetes_node_group.infra_node_group
  ]
}


resource "yandex_vpc_address" "gitlab_ip" {
  name      = "gitlab-external-ip"
  folder_id = yandex_resourcemanager_folder.infra-folder.id

  external_ipv4_address {
    zone_id = "ru-central1-d"
  }
}

output "gitlab_external_ip" {
  value = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
}


resource "kubernetes_manifest" "letsencrypt_clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = "v.a.skryl@yandex.ru"
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod"
        }
        solvers = [{
          http01 = {
            ingress = {
              class = "nginx"
            }
          }
        }]
      }
    }
  }

  depends_on = [
    helm_release.gitlab
  ]
}


// ------------------------------------------------------------
// Подключение Terraform к Kubernetes через Service Account
// ------------------------------------------------------------

// Создаём namespace (если не создан)
resource "kubernetes_namespace" "terraform_ns" {
  metadata {
    name = "terraform-system"
  }

  depends_on = [
    yandex_kubernetes_cluster.zonal_cluster
  ]
}

// Создаём ServiceAccount для Terraform
resource "kubernetes_service_account" "terraform_sa" {
  metadata {
    name      = "terraform"
    namespace = kubernetes_namespace.terraform_ns.metadata[0].name
  }

  depends_on = [
    kubernetes_namespace.terraform_ns
  ]
}

// Привязываем SA к роли cluster-admin
resource "kubernetes_cluster_role_binding" "terraform_admin" {
  metadata {
    name = "terraform-cluster-admin"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.terraform_sa.metadata[0].name
    namespace = kubernetes_namespace.terraform_ns.metadata[0].name
  }

  depends_on = [
    kubernetes_service_account.terraform_sa
  ]
}

// Создаём токен (secret) для SA
resource "kubernetes_secret" "terraform_token" {
  metadata {
    name      = "terraform-sa-token"
    namespace = kubernetes_namespace.terraform_ns.metadata[0].name
    annotations = {
      "kubernetes.io/service-account.name" = kubernetes_service_account.terraform_sa.metadata[0].name
    }
  }

  type = "kubernetes.io/service-account-token"

  depends_on = [
    kubernetes_service_account.terraform_sa
  ]
}
