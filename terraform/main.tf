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
  description = "Yandex s3 bucket name"
}


variable "dns_domain" {
  description = "App dns domain"
}

variable "momo_store_dns_name" {
  description = "Momo store dns name"
}

variable "argocd_dns_name" {
  description = "Argocd store dns name"
}

variable "dockerconfigjson" {
  description = "Docker config to pull images"
}

variable "momo_s3_terraform_state_key" {
  description = "SA key to s3"
}

variable "momo_s3_terraform_state_secret" {
  description = "SA secret to s3"
}

variable "argocd_secret_repo_url" {
  description = "Argocd secret with app repo url"
}

variable "argocd_secret_repo_password" {
  description = "Argocd secret with app repo password"
}

variable "argocd_secret_repo_username" {
  description = "Argocd secret with app repo username"
}

terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
	kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
  }
  
  backend "s3" {}  

}

locals {
  cloud_id           = var.cloud_id
  folder_id          = var.folder_id
  k8s_version        = "1.23"
  sa_name            = "momo-store"
  momo_s3_terraform_state_key = var.momo_s3_terraform_state_key
  momo_s3_terraform_state_secret = var.momo_s3_terraform_state_secret
}

provider "yandex" {
 token       = var.token
 cloud_id    = var.cloud_id
 folder_id   = var.folder_id
 zone        = "ru-central1-a"
} 

resource "yandex_kubernetes_cluster" "momo-store" {
  name = "momo-store"
  description = "terraform"
  network_id = yandex_vpc_network.momo-net.id
  master {
    version = local.k8s_version
    zonal {
      zone      = yandex_vpc_subnet.momo-subnet.zone
      subnet_id = yandex_vpc_subnet.momo-subnet.id
    }
	public_ip = true
    security_group_ids = [
      yandex_vpc_security_group.k8s-main-sg.id,
      yandex_vpc_security_group.k8s-master-whitelist.id
    ]
  }
  service_account_id      = yandex_iam_service_account.momo-store.id
  node_service_account_id = yandex_iam_service_account.momo-store.id
    depends_on = [
    yandex_resourcemanager_folder_iam_binding.k8s-clusters-agent,
    yandex_resourcemanager_folder_iam_binding.vpc-public-admin,
    yandex_resourcemanager_folder_iam_binding.images-puller
  ]
  kms_provider {
    key_id = yandex_kms_symmetric_key.kms-key.id
  }
}

resource "yandex_vpc_network" "momo-net" {
  name = "momo-net"
}

resource "yandex_vpc_subnet" "momo-subnet" {
  name = "momo-subnet"
  v4_cidr_blocks = ["10.1.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.momo-net.id
  depends_on = [
    yandex_vpc_network.momo-net,
  ]
}

resource "yandex_vpc_address" "addr" {
  name = "static-ip"
  external_ipv4_address {
    zone_id = "ru-central1-a"
  }
}

resource "yandex_iam_service_account" "momo-store" {
  name        = local.sa_name
  description = "Momo store service account"
}

resource "yandex_resourcemanager_folder_iam_binding" "k8s-clusters-agent" {
  # Сервисному аккаунту назначается роль "k8s.clusters.agent".
  folder_id = local.folder_id
  role      = "k8s.clusters.agent"
  members = [
    "serviceAccount:${yandex_iam_service_account.momo-store.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "vpc-public-admin" {
  # Сервисному аккаунту назначается роль "editor".
  folder_id = local.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.momo-store.id}"
  ]
}

resource "yandex_resourcemanager_folder_iam_binding" "images-puller" {
  # Сервисному аккаунту назначается роль "container-registry.images.puller".
  folder_id = local.folder_id
  role      = "container-registry.images.puller"
  members = [
    "serviceAccount:${yandex_iam_service_account.momo-store.id}"
  ]
}

resource "yandex_kms_symmetric_key" "kms-key" {
  # Ключ для шифрования важной информации, такой как пароли, OAuth-токены и SSH-ключи.
  name              = "kms-key"
  default_algorithm = "AES_128"
  rotation_period   = "8760h" # 1 год.
}

resource "yandex_kms_symmetric_key_iam_binding" "viewer" {
  symmetric_key_id = yandex_kms_symmetric_key.kms-key.id
  role             = "viewer"
  members = [
    "serviceAccount:${yandex_iam_service_account.momo-store.id}",
  ]
}

resource "yandex_vpc_security_group" "k8s-main-sg" {
  name        = "k8s-main-sg"
  description = "Правила группы обеспечивают базовую работоспособность кластера. Примените ее к кластеру и группам узлов."
  network_id  = yandex_vpc_network.momo-net.id
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает проверки доступности с диапазона адресов балансировщика нагрузки. Нужно для работы отказоустойчивого кластера и сервисов балансировщика."
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие мастер-узел и узел-узел внутри группы безопасности."
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol       = "ANY"
    description    = "Правило разрешает взаимодействие под-под и сервис-сервис. Укажите подсети вашего кластера и сервисов."
    v4_cidr_blocks = ["10.96.0.0/16", "10.112.0.0/16", "10.1.0.0/16"]
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "ICMP"
    description    = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks = ["172.16.0.0/12", "10.0.0.0/8", "192.168.0.0/16"]
  }
  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Object Storage, Docker Hub и т. д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "k8s-public-services" {
  name        = "k8s-public-services"
  description = "Правила группы разрешают подключение к сервисам из интернета. Примените правила только для групп узлов."
  network_id  = yandex_vpc_network.momo-net.id

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавьте или измените порты на нужные вам."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
}

resource "yandex_vpc_security_group" "k8s-master-whitelist" {
  name        = "k8s-master-whitelist"
  description = "Правила группы разрешают доступ к API Kubernetes из интернета. Примените правила только к кластеру."
  network_id  = yandex_vpc_network.momo-net.id

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к API Kubernetes через порт 6443 из указанной сети."
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 6443
  }

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к API Kubernetes через порт 443 из указанной сети."
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }
}

resource "yandex_kubernetes_node_group" "momo-node-group" {
  cluster_id  = "${yandex_kubernetes_cluster.momo-store.id}"
  name        = "momo"
  description = "description"
  version     = "1.23"

  labels = {
    "key" = "value"
  }

  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.momo-subnet.id}"]
	  security_group_ids = [
        yandex_vpc_security_group.k8s-main-sg.id,
        yandex_vpc_security_group.k8s-public-services.id
      ]
    }

    resources {
      memory = 8
      cores  = 4
	  core_fraction = 50
    }

    boot_disk {
      type = "network-hdd"
      size = 30
    }

    scheduling_policy {
      preemptible = false
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
    }
  }

  allocation_policy {
    location {
      zone = "ru-central1-a"
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true

    maintenance_window {
      day        = "monday"
      start_time = "15:00"
      duration   = "3h"
    }

    maintenance_window {
      day        = "friday"
      start_time = "10:00"
      duration   = "4h30m"
    }
  }
}

resource "yandex_dns_zone" "dns_domain" {
  name        = "momo-store"
  description = "Momo store dns zone"
  zone   = join("", [var.dns_domain, "."])
  public  = true
}

resource "yandex_dns_recordset" "momo-store-dns-domain" {
  zone_id = yandex_dns_zone.dns_domain.id
  name    = join("", [var.momo_store_dns_name, "."])
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

resource "yandex_dns_recordset" "argocd-dns-domain" {
  zone_id = yandex_dns_zone.dns_domain.id
  name    = join("", [var.argocd_dns_name, "."])
  type    = "A"
  ttl     = 200
  data    = [yandex_vpc_address.addr.external_ipv4_address[0].address]
}

provider "kubernetes" {
  host                   = yandex_kubernetes_cluster.momo-store.master[0].external_v4_endpoint
  cluster_ca_certificate = yandex_kubernetes_cluster.momo-store.master[0].cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["k8s", "create-token"]
    command     = "yc"
  }
}

resource "kubernetes_secret" "docker-config-secret" {
  metadata {
    name = "docker-config-secret"
  }
  binary_data = {
    ".dockerconfigjson" = var.dockerconfigjson
  }
  type = "kubernetes.io/dockerconfigjson"
}

resource "kubernetes_secret" "momo-helm" {
  metadata {
    name = "momo-helm"
	namespace = "argocd"
	labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    url = var.argocd_secret_repo_url
    name = "momo-helm"
	type = "helm"
	password = var.argocd_secret_repo_password
	username = var.argocd_secret_repo_username
  }

  type = "Opaque"
}

resource "yandex_iam_service_account" "s3_sa" {
  name = "s3-sa"
}

resource "yandex_resourcemanager_folder_iam_member" "s3_editor" {
  folder_id = var.folder_id
  role      = "storage.editor"
  member    = "serviceAccount:${yandex_iam_service_account.s3_sa.id}"
}

resource "yandex_iam_service_account_static_access_key" "s3_static_key" {
  service_account_id = yandex_iam_service_account.s3_sa.id
  description        = "static access key for object storage"
}

resource "yandex_storage_bucket" "static_content" {
  access_key = yandex_iam_service_account_static_access_key.s3_static_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.s3_static_key.secret_key
  bucket = var.s3_bucket_name

  anonymous_access_flags {
    read = true
    list = false
    config_read = false
  }
}

resource "yandex_storage_object" "images" {
  access_key = yandex_iam_service_account_static_access_key.s3_static_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.s3_static_key.secret_key
  for_each = fileset("../images/", "*")
  bucket   = yandex_storage_bucket.static_content.id
  key      = each.value
  source   = "../images/${each.value}"
}

provider "helm" {
  kubernetes {
    host                   = yandex_kubernetes_cluster.momo-store.master[0].external_v4_endpoint
    cluster_ca_certificate = yandex_kubernetes_cluster.momo-store.master[0].cluster_ca_certificate
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["k8s", "create-token"]
      command     = "yc"
    }
  }
}

provider "kubectl" {
  load_config_file = "false"
  host                   = yandex_kubernetes_cluster.momo-store.master[0].external_v4_endpoint
  cluster_ca_certificate = yandex_kubernetes_cluster.momo-store.master[0].cluster_ca_certificate
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["k8s", "create-token"]
    command     = "yc"
  }
}

resource "helm_release" "vpa" {
  name             = "vpa"
  namespace        = "vpa"
  create_namespace = true
  repository       = "https://stevehipwell.github.io/helm-charts/"
  chart            = "vertical-pod-autoscaler"
  version          = "1.0.0"
  wait             = true
  depends_on = [
    yandex_kubernetes_node_group.momo-node-group
  ]
}

resource "helm_release" "argocd" {
  name  = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "5.22.1"
  depends_on = [
    yandex_kubernetes_node_group.momo-node-group
  ]
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.5.2"
  wait       = true
  depends_on = [
    yandex_kubernetes_node_group.momo-node-group
  ]
  set {
    name  = "controller.service.loadBalancerIP"
    value = yandex_vpc_address.addr.external_ipv4_address[0].address
  }
}

resource "helm_release" "cert-manager" {
  namespace        = "cert-manager"
  create_namespace = true
  name             = "jetstack"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.10.2"
  wait             = true
  depends_on = [
    yandex_kubernetes_node_group.momo-node-group
  ]
  set {
    name  = "installCRDs"
    value = true
  }
}

resource "kubectl_manifest" "cert_issuer" {
  yaml_body = file("../kubernetes/certmanager/cert_issuer.yaml")
  depends_on = [
    helm_release.cert-manager
  ]  
}

resource "kubectl_manifest" "argocd-ingress" {
  yaml_body = file("../kubernetes/argocd/ingress.yaml")
  depends_on = [
    helm_release.argocd
  ]  
}

resource "kubectl_manifest" "argocd-momo-application" {
  yaml_body = file("../kubernetes/argocd/application.yaml")
  depends_on = [
    helm_release.argocd
  ]   
}
