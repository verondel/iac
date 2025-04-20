terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.0"
    }
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.80"
    }
  }

  required_version = ">= 1.3"
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path
  }
}

provider "yandex" {
  zone                     = var.zone
  service_account_key_file = "${path.module}/key.json"
}
