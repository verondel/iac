// ---------------------------------------------------
// Фаза 1: Создание инфраструктуры в Yandex Cloud
// ---------------------------------------------------

// Создаем папку в Yandex Cloud
resource "yandex_resourcemanager_folder" "infra-folder" {
  cloud_id    = var.cloud_id
  name        = var.folder_name
  description = var.folder_description
}

# data "yandex_resourcemanager_folder" "infra-folder" {
#   folder_id = "b1gg0dja6g46n9md2r67"
# }


// Создаем VPC сеть
resource "yandex_vpc_network" "infra-vpc-network" {
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
  name        = var.network_name
  description = "infra vpc network description"
  labels = {
    tf-label = "tf-label-value"
  }
}

// Создаем подсеть
resource "yandex_vpc_subnet" "infra-subnet" {
  name           = var.subnet_name
  description    = "main subnet"
  v4_cidr_blocks = var.subnet_cidr
  zone           = var.zone
  network_id     = yandex_vpc_network.infra-vpc-network.id
  folder_id      = yandex_resourcemanager_folder.infra-folder.id
}

// ---------------------------------------------------
// Создаем security group, logging group и KMS ключ
// ---------------------------------------------------

# resource "yandex_vpc_security_group" "infra-security-group" {
#   folder_id   = yandex_resourcemanager_folder.infra-folder.id
#   name        = var.security_group_name
#   description = "description for my security group"
#   network_id  = yandex_vpc_network.infra-vpc-network.id
#   labels = {
#     "my-label" = "my-label-value"
#   }
# }

resource "yandex_vpc_security_group" "infra-security-group" {
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
  name        = var.security_group_name
  description = "Security group for Kubernetes cluster nodes and master"
  network_id  = yandex_vpc_network.infra-vpc-network.id

  labels = {
    "my-label" = "my-label-value"
  }

  # Allow kube-apiserver -> kubelet (managed by control plane)
  ingress {
    protocol          = "TCP"
    description       = "API server to kubelet"
    port              = 10250
    predefined_target = "self_security_group"
  }

  # Allow inter-node traffic
  ingress {
    protocol          = "ANY"
    description       = "Node-to-node communication"
    predefined_target = "self_security_group"
  }

  # TEMP: Allow full access from the internet (TODO: debugging only!)
  ingress {
    protocol       = "ANY"
    description    = "TEMP: Allow all incoming for debug"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic (for pulling images, accessing services, etc.)
  egress {
    protocol       = "ANY"
    description    = "Allow all outbound traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}


# 6443 (API server)
# 10250 (kubelet API)


# resource "yandex_logging_group" "infra-logging-group" {
#   name      = var.logging_group_name
#   folder_id = yandex_resourcemanager_folder.infra-folder.id
# }

resource "yandex_kms_symmetric_key" "infra-kms-key" {
  name              = var.kms_key_name
  description       = "infra key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" // equal to 1 year
  folder_id         = yandex_resourcemanager_folder.infra-folder.id
}

// ---------------------------------------------------
// Создаем сервисные аккаунты и назначаем им IAM политики
// ---------------------------------------------------

// SA для кластера (мастер)
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

// SA для нод
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

// IAM binding для SA (мастер) – выдаем необходимые роли для работы кластера
variable "infra_sa_roles" {
  type = list(string)
  default = [
    "kms.keys.encrypterDecrypter",
    "logging.writer",
    "editor",
    "compute.admin",
    "vpc.admin",
    "iam.serviceAccounts.user",
    "vpc.publicAdmin"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "infra-sa-bindings" {
  for_each = toset(var.infra_sa_roles)

  folder_id = yandex_resourcemanager_folder.infra-folder.id
  role      = each.key

  members = [
    "serviceAccount:${yandex_iam_service_account.infra-service-account.id}"
  ]
}



// ---------------------------------------------------
// Создаем Managed Kubernetes кластер и нод группу
// ---------------------------------------------------

resource "yandex_kubernetes_cluster" "zonal_cluster" {
  folder_id   = yandex_resourcemanager_folder.infra-folder.id
  name        = var.cluster_name
  description = "zonal infra cluster"
  network_id  = yandex_vpc_network.infra-vpc-network.id

  master {
    version = var.k8s_version
    zonal {
      zone      = var.zone
      subnet_id = yandex_vpc_subnet.infra-subnet.id
    }
    public_ip = true

    security_group_ids = [yandex_vpc_security_group.infra-security-group.id]

    maintenance_policy {
      auto_upgrade = true
      maintenance_window {
        start_time = "18:00"
        duration   = "3h"
      }
    }

    master_logging {
      enabled = true
      # log_group_id               = yandex_logging_group.infra-logging-group.id
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

  depends_on = [
    # yandex_resourcemanager_folder_iam_binding.infra-sa-vpc-admin,
    # yandex_resourcemanager_folder_iam_binding.infra-sa-compute-admin,
    # yandex_resourcemanager_folder_iam_binding.infra-sa-sa-user
    yandex_resourcemanager_folder_iam_binding.infra-sa-bindings
  ]
}

resource "yandex_kubernetes_node_group" "infra_node_group" {
  cluster_id  = yandex_kubernetes_cluster.zonal_cluster.id
  name        = var.node_group_name
  description = "main node group"
  version     = var.k8s_version

  labels = {
    "key" = "value"
  }

  instance_template {
    # platform_id = "standard-v2"
    network_interface {
      nat        = true
      subnet_ids = [yandex_vpc_subnet.infra-subnet.id]
    }
    resources {
      memory = 16
      cores  = 4
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

    network_interface {
      subnet_ids         = [yandex_vpc_subnet.infra-subnet.id]
      nat                = true
      security_group_ids = [yandex_vpc_security_group.infra-security-group.id]
    }
  }

  scale_policy {
    fixed_scale {
      size = 3
    }
  }

  allocation_policy {
    location {
      zone = var.zone
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
