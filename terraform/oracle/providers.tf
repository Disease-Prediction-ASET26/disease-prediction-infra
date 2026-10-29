provider "oci" {
  region              = var.region
  config_file_profile = var.oci_profile
}

data "oci_identity_availability_domains" "available" {
  compartment_id = var.tenancy_ocid
}
