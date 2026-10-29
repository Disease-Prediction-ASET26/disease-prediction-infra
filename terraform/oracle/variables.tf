variable "tenancy_ocid" {
  description = "OCI tenancy OCID."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment in which this project creates its OCI resources."
  type        = string
}

variable "region" {
  description = "OCI home region for this project."
  type        = string
}

variable "oci_profile" {
  description = "Profile name in the local OCI CLI config file."
  type        = string
  default     = "DEFAULT"
}

variable "availability_domain" {
  description = "Optional OCI availability domain name. Defaults to the first domain returned for the tenancy."
  type        = string
  default     = null
  nullable    = true
}

variable "image_ocid" {
  description = "Region-specific Ubuntu 24.04 ARM64 platform image OCID; pin this value."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to a dedicated SSH public key file. The private key is never read by Terraform."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Trusted administrator public IPv4 CIDR allowed to connect to SSH (use /32 where possible)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_ssh_cidr)) && can(regex("/(2[4-9]|3[0-2])$", var.admin_ssh_cidr))
    error_message = "admin_ssh_cidr must be a valid IPv4 CIDR no broader than /24; use your public IP with /32 when possible."
  }
}

variable "project_name" {
  description = "Lowercase project prefix used for OCI resource names and DNS labels."
  type        = string
  default     = "disease-prediction"
}

variable "vcn_cidr" {
  description = "Non-overlapping private IPv4 range for the new project VCN. Check existing VCNs before use."
  type        = string
  default     = "10.42.0.0/16"
}

variable "subnet_cidr" {
  description = "Public subnet range inside vcn_cidr. Check that it is contained by vcn_cidr and does not overlap existing networks."
  type        = string
  default     = "10.42.10.0/24"
}

variable "boot_volume_size_gb" {
  description = "Boot volume size in GB. The default 50 GB is within the current Always Free block-volume allowance."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_gb >= 50 && var.boot_volume_size_gb <= 200
    error_message = "Choose a boot volume between 50 and 200 GB, after checking the tenancy's total block-volume usage."
  }
}

variable "k3s_version" {
  description = "Pinned K3s release installed on first boot. Upgrade this deliberately after reviewing release notes."
  type        = string
  default     = "v1.37.1+k3s1"
}
