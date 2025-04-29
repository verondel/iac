output "storage_class_name" {
  description = "The name of the Yandex.Cloud StorageClass for PostgreSQL"
  value = kubernetes_storage_class.yc_standard.metadata[
    0
  ].name
}
