variable "token" {
  description = "Yandex token"
}

variable "cloud_id" {
  description = "Yandex cloud id"
}

variable "folder_id" {
  description = "Yandex folder id"
}

variable "s3_bucket_name" {
  description = "Bucket name"
}

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
}

provider "yandex" {
 token       = var.token
 cloud_id    = var.cloud_id
 folder_id   = var.folder_id
 zone        = "ru-central1-a"
} 

resource "yandex_iam_service_account" "s3_terraform_backend" {
  name = "s3-terraform-backend"
}

resource "yandex_resourcemanager_folder_iam_member" "s3_terraform_editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.s3_terraform_backend.id}"
}

resource "yandex_iam_service_account_static_access_key" "s3_terraform_static_key" {
  service_account_id = yandex_iam_service_account.s3_terraform_backend.id
  description        = "static access key for object storage"
}

resource "yandex_storage_bucket" "momo_terraform_backend" {
  access_key = yandex_iam_service_account_static_access_key.s3_terraform_static_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.s3_terraform_static_key.secret_key
  bucket = var.s3_bucket_name

  anonymous_access_flags {
    read = false
    list = false
    config_read = false
  }
}


output "s3-bucket-name" {
  value = var.s3_bucket_name
}

output "s3-access-key" {
  sensitive = true
  value = yandex_iam_service_account_static_access_key.s3_terraform_static_key.access_key
}

output "s3-secret-key" {
  sensitive = true
  value = yandex_iam_service_account_static_access_key.s3_terraform_static_key.secret_key
}

