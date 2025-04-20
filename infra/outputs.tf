output "cloud_id" {
  value = var.cloud_id
}

output "folder_id" {
  value = yandex_resourcemanager_folder.infra-folder.id
}

output "cluster_name" {
  value = yandex_kubernetes_cluster.zonal_cluster.name
}

output "cluster_id" {
  value = yandex_kubernetes_cluster.zonal_cluster.id
}

output "kubeconfig_path" {
  value = "${path.module}/../kubeconfig.yaml"
}
