// ---------------------------------------------------
// Фаза 0: Storage Class
// ---------------------------------------------------


resource "kubernetes_storage_class" "yc_standard" {
  metadata {
    name = "yc-standard"
  }

  storage_provisioner = "disk-csi-driver.mks.yandex.net"

  parameters = {
    type = "network-ssd"
    zone = "ru-central1-a"
  }

  reclaim_policy      = "Retain"
  volume_binding_mode = "WaitForFirstConsumer"
}


// ---------------------------------------------------
// Фаза 1: Внешний IP
// ---------------------------------------------------

// Выделяем внешний IP для GitLab
resource "yandex_vpc_address" "gitlab_ip" {
  name      = "gitlab-external-ip"
  folder_id = var.folder_id

  external_ipv4_address {
    zone_id = var.zone
  }
}

// DNS-зона и A-записи (ДОЛЖНЫ идти раньше GitLab)
resource "yandex_dns_zone" "main_zone" {
  name        = "verondello-zone"
  description = "DNS zone for ${var.domain}"
  zone        = "${var.domain}."
  public      = true
  folder_id   = var.folder_id
}

resource "yandex_dns_recordset" "gitlab" {
  zone_id = yandex_dns_zone.main_zone.id
  name    = "gitlab"
  type    = "A"
  ttl     = 300
  data    = [yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "registry" {
  zone_id = yandex_dns_zone.main_zone.id
  name    = "registry"
  type    = "A"
  ttl     = 300
  data    = [yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "minio" {
  zone_id = yandex_dns_zone.main_zone.id
  name    = "minio"
  type    = "A"
  ttl     = 300
  data    = [yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address]
}

output "gitlab_external_ip" {
  value = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
}

// ---------------------------------------------------
// Фаза 2: gitlab NS + Ingress Nginx for certs
// ---------------------------------------------------

resource "kubernetes_namespace" "gitlab" {
  metadata {
    name = "gitlab"
  }
}


resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = "gitlab"

  create_namespace = false

  set {
    name  = "controller.ingressClassResource.name"
    value = "gitlab-nginx"
  }
  set {
    name  = "controller.ingressClass"
    value = "gitlab-nginx"
  }


  set {
    name  = "controller.ingressClassResource.enabled"
    value = "true"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = "false"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
  set {
    name  = "controller.service.loadBalancerIP"
    value = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
  }

  depends_on = [
    kubernetes_namespace.gitlab
  ]
}


// ---------------------------------------------------
// Фаза 3: cert-manager + ClusterIssuer
// ---------------------------------------------------

# Установка CRD до Helm-релиза
locals {
  cert_manager_crds = split("\n---\n", file("${path.module}/helm-values/cert-manager.crds.yaml"))
}

resource "kubernetes_manifest" "cert_manager_crds" {
  for_each = { for idx, doc in local.cert_manager_crds : idx => yamldecode(doc) }

  manifest = each.value
}

// Устанавливаем cert-manager (управляет TLS-сертификатами через Let's Encrypt)
resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"

  create_namespace = true

  // Обязательно устанавливаем CRD (CustomResourceDefinitions)
  set {
    name  = "installCRDs"
    value = "false" # уже применили вручную
  }

  version = "v1.14.2"

  # depends_on = [null_resource.cert_manager_crds]
  depends_on = [
    kubernetes_manifest.cert_manager_crds,
    helm_release.nginx_ingress
  ]
}

// Создаём ClusterIssuer (сущность, выпускающая сертификаты Let's Encrypt)
resource "helm_release" "clusterissuer" {
  name       = "clusterissuer"
  namespace  = "cert-manager"
  repository = "https://charts.helm.sh/incubator"
  chart      = "raw"
  version    = "0.2.5"

  values = [
    templatefile("${path.module}/helm-values/letsencrypt-clusterissuer.tpl.yaml", {
      tls_email = var.tls_email
    })
  ]
}


resource "local_file" "gitlab_cert_manifest" {
  content = templatefile("${path.module}/helm-values/gitlab-certificate.yaml.tpl", {
    domain = var.domain
  })
  filename = "${path.module}/rendered/gitlab-certificate.yaml"
}

resource "null_resource" "apply_gitlab_cert" {
  depends_on = [
    helm_release.clusterissuer,
    kubernetes_namespace.gitlab,
    local_file.gitlab_cert_manifest,
    helm_release.nginx_ingress
  ]

  provisioner "local-exec" {
    command = "kubectl apply -f ${local_file.gitlab_cert_manifest.filename} --kubeconfig=vera-infra-kubeconfig.yaml"
  }

  triggers = {
    cert_hash = sha1(local_file.gitlab_cert_manifest.content)
  }
}

resource "null_resource" "wait_cert_ready" {
  depends_on = [null_resource.apply_gitlab_cert]

  provisioner "local-exec" {
    environment = {
      KUBECONFIG = "vera-infra-kubeconfig.yaml"
    }
    command     = <<EOT
      echo "⏳ Ждём, пока сертификат gitlab-tls будет готов..."
      for i in {1..30}; do
        STATUS=$(kubectl get certificate gitlab-tls -n gitlab -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        if [ "$STATUS" = "True" ]; then
          echo "✅ Сертификат готов!"
          exit 0
        fi
        echo "⏳ Ещё не готов, подождём 10 сек... ($i/30)"
        sleep 10
      done
      echo "❌ Время ожидания истекло. Сертификат не готов."
      kubectl describe certificate gitlab-tls -n gitlab
      exit 1
    EOT
    interpreter = ["bash", "-c"]
  }
}




// ---------------------------------------------------
// Фаза 5: Установка GitLab
// ---------------------------------------------------

resource "helm_release" "gitlab" {
  name       = "gitlab"
  repository = "https://charts.gitlab.io"
  chart      = "gitlab"
  namespace  = "gitlab"

  create_namespace = false

  values = [
    templatefile("${path.module}/helm-values/gitlab-values.tpl.yaml", {
      domain      = var.domain
      external_ip = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
      tls_email   = var.tls_email
    })
  ]

  timeout = 600

  depends_on = [
    # helm_release.gitlab_certificate
    # null_resource.apply_gitlab_cert
    null_resource.wait_cert_ready
  ]
}
