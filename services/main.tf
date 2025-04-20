// ---------------------------------------------------
// Фаза 2: Установка сервисов в кластере
// ---------------------------------------------------

// Выделяем внешний IP для GitLab
resource "yandex_vpc_address" "gitlab_ip" {
  name      = "gitlab-external-ip"
  folder_id = var.folder_id

  external_ipv4_address {
    zone_id = var.zone
  }
}

// ---------------------------------------------------
// DNS-зона и A-записи (ДОЛЖНЫ идти раньше GitLab)
// ---------------------------------------------------

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
// cert-manager и ClusterIssuer
// ---------------------------------------------------

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = "cert-manager"

  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  version = "v1.14.2"
}

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

  depends_on = [
    helm_release.cert_manager
  ]
}

// ---------------------------------------------------
// Установка GitLab
// ---------------------------------------------------

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

  depends_on = [
    helm_release.clusterissuer,
    yandex_dns_recordset.gitlab,
    yandex_dns_recordset.registry,
    yandex_dns_recordset.minio
  ]
}
