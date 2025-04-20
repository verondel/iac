// ---------------------------------------------------
// Фаза 2: Установка сервисов в кластере
// ---------------------------------------------------

// Провайдеры Kubernetes и Helm используют локальный kubeconfig,
// который мы генерируем автоматизированно во время фазы 1.
provider "kubernetes" {
  config_path = "${path.module}/kubeconfig.yaml"
}

provider "helm" {
  kubernetes {
    config_path = "${path.module}/kubeconfig.yaml"
  }
}

// Устанавливаем GitLab через Helm
resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  namespace  = "gitlab"

  create_namespace = true

  values = [
    templatefile("${path.module}/helm-values/gitlab-values.tpl.yaml", {
      domain      = var.domain
      external_ip = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
      tls_email   = var.tls_email
    })
  ]

  timeout = 600
}


// Выделяем внешний IP для GitLab
resource "yandex_vpc_address" "gitlab_ip" {
  name      = "gitlab-external-ip"
  folder_id = var.folder_id // из JSON-конфигурации

  external_ipv4_address {
    zone_id = var.zone
  }
}

output "gitlab_external_ip" {
  value = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
}

// Создаем ClusterIssuer для cert-manager (используем kubernetes_manifest)
resource "kubernetes_manifest" "letsencrypt_clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.tls_email // из конфигурации
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

// Используем null_resource для явного ожидания готовности кластера
resource "null_resource" "wait_for_cluster" {
  provisioner "local-exec" {
    command = "echo 'Кластер готов для установки сервисов'"
  }

  depends_on = [
    yandex_kubernetes_cluster.zonal_cluster,
    yandex_kubernetes_node_group.infra_node_group
  ]
}
