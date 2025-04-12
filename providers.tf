terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
    helm = {
      source = "hashicorp/helm"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  zone                     = "ru-central1-d"
  service_account_key_file = "${path.module}/key.json"
}

# provider "kubernetes" {
#   host                   = yandex_kubernetes_cluster.zonal_cluster.master[0].external_v4_endpoint
#   cluster_ca_certificate = base64decode(yandex_kubernetes_cluster.zonal_cluster.master[0].cluster_ca_certificate)
#   token                  = yandex_kubernetes_cluster.zonal_cluster.master[0].access_token
# }

# provider "helm" {
#   kubernetes {
#     host                   = yandex_kubernetes_cluster.zonal_cluster.master[0].external_v4_endpoint
#     cluster_ca_certificate = base64decode(yandex_kubernetes_cluster.zonal_cluster.master[0].cluster_ca_certificate)
#     token                  = yandex_kubernetes_cluster.zonal_cluster.master[0].access_token
#   }
# }


provider "kubernetes" {
  host                   = yandex_kubernetes_cluster.zonal_cluster.master[0].external_v4_endpoint
  cluster_ca_certificate = base64decode(yandex_kubernetes_cluster.zonal_cluster.master[0].cluster_ca_certificate)
  token                  = kubernetes_secret.terraform_token.data.token
}

provider "helm" {
  kubernetes {
    host                   = yandex_kubernetes_cluster.zonal_cluster.master[0].external_v4_endpoint
    cluster_ca_certificate = base64decode(yandex_kubernetes_cluster.zonal_cluster.master[0].cluster_ca_certificate)
    token                  = kubernetes_secret.terraform_token.data.token
  }
}

