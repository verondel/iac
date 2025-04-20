variable "cloud_id" {
  description = "Yandex Cloud ID"
  type        = string
}

variable "folder_name" {
  description = "Name of the Yandex Cloud folder"
  type        = string
}

variable "folder_description" {
  description = "Description for the folder"
  type        = string
}

variable "network_name" {
  description = "VPC network name"
  type        = string
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR block(s) for the subnet"
  type        = list(string)
}

variable "zone" {
  description = "Availability zone"
  type        = string
}

variable "security_group_name" {
  description = "Security group name"
  type        = string
}

variable "logging_group_name" {
  description = "Logging group name"
  type        = string
}

variable "kms_key_name" {
  description = "Name of the KMS key"
  type        = string
}

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
}

variable "node_group_name" {
  description = "Name of the Kubernetes node group"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
}
