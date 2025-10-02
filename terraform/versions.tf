terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "2.5.1"
    }

    selectel = {
      source  = "selectel/selectel"
      version = "6.4.0"
    }

    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "2.0.0"
    }

  }
  required_version = ">= 1.8.0"
}
