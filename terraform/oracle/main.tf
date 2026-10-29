locals {
  availability_domain = var.availability_domain != null ? var.availability_domain : data.oci_identity_availability_domains.available.availability_domains[0].name
  vcn_dns_label       = "diseasepred"
  subnet_dns_label    = "k3s"
}

resource "oci_core_vcn" "project" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "${var.project_name}-vcn"
  dns_label      = local.vcn_dns_label
  freeform_tags  = { project = var.project_name }
}

resource "oci_core_internet_gateway" "project" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.project.id
  display_name   = "${var.project_name}-internet-gateway"
  enabled        = true
  freeform_tags  = { project = var.project_name }
}

resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.project.id
  display_name   = "${var.project_name}-public-routes"
  freeform_tags  = { project = var.project_name }

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
  freeform_tags  = { project = var.project_name }

  ingress_security_rules {
    description = "SSH from the configured administrator network only"
    protocol    = "6"
    source      = var.admin_ssh_cidr

    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    description = "Outbound updates and cluster image pulls"
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.project.id
  cidr_block                 = var.subnet_cidr
  display_name               = "${var.project_name}-public-subnet"
  dns_label                  = local.subnet_dns_label
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.public.id]
  prohibit_public_ip_on_vnic = false
  freeform_tags              = { project = var.project_name }
}

resource "oci_core_instance" "k3s_server" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain
  display_name        = "${var.project_name}-k3s"
  shape               = "VM.Standard.A1.Flex"
  freeform_tags       = { project = var.project_name }

  shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    assign_public_ip = true
    hostname_label   = "k3s"
  }

  source_details {
    source_type             = "image"
    source_id               = var.image_ocid
    boot_volume_size_in_gbs = var.boot_volume_size_gb
  }

  metadata = {
    ssh_authorized_keys = trimspace(file(var.ssh_public_key_path))
    user_data           = base64encode(templatefile("${path.module}/cloud-init.yaml.tftpl", { k3s_version = var.k3s_version }))
  }
}
