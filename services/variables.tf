variable "zone" {
  description = "Yandex.Cloud zone"
  type        = string
}

variable "folder_id" {
  description = "Folder ID in Yandex.Cloud"
  type        = string
}

variable "domain" {
  description = "Base domain name"
  type        = string
}

variable "tls_email" {
  description = "Email for Let's Encrypt"
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = "./vera-infra-kubeconfig.yaml"
}
