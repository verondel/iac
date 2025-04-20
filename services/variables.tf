variable "folder_id" {
  description = "Yandex Cloud folder ID"
  type        = string
}

variable "zone" {
  description = "Availability zone (used for external IP)"
  type        = string
}

variable "domain" {
  description = "Domain for GitLab ingress (e.g. gitlab.example.com)"
  type        = string
}

variable "tls_email" {
  description = "Email used for Let's Encrypt registration"
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file to connect to the cluster"
  type        = string
  default     = "${path.module}/kubeconfig.yaml"
}
