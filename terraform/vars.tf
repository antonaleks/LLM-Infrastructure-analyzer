# Selectel provider vars
variable "selectel_domain_name" {
  type        = string
  description = "ID Selectel аккаунта"
}

variable "selectel_user_name" {
  type        = string
  description = "Имя сервисного пользователя, необходимо создать через панель my.selectel"
}

variable "selectel_user_password" {
  type        = string
  description = "Пароль от сервисного пользователя"
}
variable "project_id" {
  type = string
}
variable "region" {
  default = "ru-7"
}
variable "availability_zone" {
  default = "ru-7a"
}
variable "volume_type" {
  default = "fast"
}
variable "volume_gb" {
  default = "100"
}
variable "gpu_az_flavors" {
  type = map(list(string))
  default = {
    a = []
    b = ["3031"]
    c = []
  }
  description = "Карта: ключ — буква зоны доступности, значение — список flavor_id для этой зоны"
}

# Openstack provider vars
variable "os_auth_url" {
  type        = string
  default     = "https://cloud.api.selcloud.ru/identity/v3"
  description = "URL до openstack api"
}

variable "nfs_share_size" {
  type        = number
  default     = 50
  description = "Размер NFS PV для шеринга (например, 100Gi)"
}
