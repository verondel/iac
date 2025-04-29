output "storage_class_name" {
  description = "The name of the Yandex.Cloud StorageClass for PostgreSQL"
  value = kubernetes_storage_class.yc_standard.metadata[
    0
  ].name
}

output "gitlab_external_ip" {
  value = yandex_vpc_address.gitlab_ip.external_ipv4_address[0].address
}
