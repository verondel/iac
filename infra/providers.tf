terraform {
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.80" # или новее
    }
  }
  required_version = ">= 1.3"
}

provider "yandex" {
  zone = var.zone
  # folder_id                = "b1gg0dja6g46n9md2r67"
  service_account_key_file = "${path.module}/key.json"
}
