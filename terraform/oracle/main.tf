data "oci_identity_tenancy" "current" {
  tenancy_id = var.tenancy_ocid
}

data "oci_identity_regions" "all" {}

locals {
  home_region = one([
    for region in data.oci_identity_regions.all.regions : region.name
    if region.key == data.oci_identity_tenancy.current.home_region_key
  ])
  availability_domain_names = [
    for domain in data.oci_identity_availability_domains.available.availability_domains : domain.name
  ]
}

import {
  to = oci_core_vcn.project
  id = var.vcn_ocid
}

import {
  to = oci_core_subnet.public
  id = var.subnet_ocid
}

import {
  to = oci_core_instance.k3s_server
  id = var.instance_ocid
}

resource "oci_core_vcn" "project" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "vcn-free"
  dns_label      = var.vcn_dns_label

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = var.region == local.home_region
      error_message = "The A1 Always Free allowance is for the tenancy home region (${local.home_region}); set region to that value."
    }
  }
}

resource "oci_core_internet_gateway" "project" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.project.id
  display_name   = "${var.project_name}-internet-gateway"
  enabled        = true
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.project.id
  display_name   = "${var.project_name}-public-routes"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.project.id
  }
}

resource "oci_core_security_list" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.project.id
  display_name   = "${var.project_name}-public-access"

  ingress_security_rules {
    description = "SSH from the administrator IPv4 CIDR only"
    protocol    = "6"
    source      = var.admin_ssh_cidr

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    description = "ICMP within the VCN"
    protocol    = "1"
    source      = var.vcn_cidr
  }

  egress_security_rules {
    description = "Outbound updates and image pulls"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_default_security_list" "private" {
  manage_default_resource_id = oci_core_vcn.project.default_security_list_id

  ingress_security_rules {
    description = "ICMP within the VCN"
    protocol    = "1"
    source      = var.vcn_cidr
  }

  egress_security_rules {
    description = "Outbound traffic"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.project.id
  cidr_block                 = var.subnet_cidr
  display_name               = "subnet-public"
  dns_label                  = var.subnet_dns_label
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_core_instance" "k3s_server" {
  compartment_id      = var.compartment_ocid
  availability_domain = var.availability_domain
  display_name        = "vm"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = var.instance_hostname_label
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_gb
    boot_volume_vpus_per_gb = 10
  }

  metadata = {
    ssh_authorized_keys = trimspace(file(var.ssh_public_key_path))
    user_data           = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", { k3s_version = var.k3s_version }))
  }

  lifecycle {
    prevent_destroy = true

    # OCI cloud-init user_data only runs at first boot; changing it cannot bootstrap an imported VM.
    ignore_changes = [metadata["user_data"]]

    precondition {
      condition     = contains(local.availability_domain_names, var.availability_domain)
      error_message = "availability_domain must exactly match one of the tenancy's availability-domain names in var.region."
    }
  }
}
