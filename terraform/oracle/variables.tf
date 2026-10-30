variable "tenancy_ocid" {
  description = "OCI tenancy OCID used for home-region and availability-domain checks."
  type        = string
}

variable "compartment_ocid" {
  description = "Compartment containing the existing k3s resources."
  type        = string
}

variable "region" {
  description = "OCI region for the existing cluster; must be the tenancy home region for Always Free A1 compute."
  type        = string
}

variable "oci_profile" {
  description = "Profile name in the local OCI CLI config file."
  type        = string
  default     = "DEFAULT"
}

variable "budget_alert_email" {
  description = "Email address for OCI monthly actual-spend and forecast budget alerts."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.budget_alert_email))
    error_message = "budget_alert_email must be a valid email address."
  }
}

variable "availability_domain" {
  description = "Exact tenancy-specific availability-domain name for the VM."
  type        = string
}

variable "image_ocid" {
  description = "Region-specific Always Free-eligible ARM64 Linux image OCID used by this VM."
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the VM's SSH public key; the private key is never read by Terraform."
  type        = string
}

variable "admin_ssh_cidr" {
  description = "Optional temporary public IPv4 CIDR allowed to connect to SSH; set null after private access is verified."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.admin_ssh_cidr == null || (can(cidrnetmask(var.admin_ssh_cidr)) && can(regex("/(2[4-9]|3[0-2])$", var.admin_ssh_cidr)))
    error_message = "admin_ssh_cidr must be null or a valid IPv4 CIDR no broader than /24; use your public IP with /32 when possible."
  }
}

variable "project_name" {
  description = "Lowercase prefix used for Terraform-managed OCI resource names."
  type        = string
  default     = "disease-prediction"
}

variable "vcn_cidr" {
  description = "CIDR block of the existing VCN; check for overlap before changing it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block of the existing public subnet."
  type        = string
  default     = "10.0.0.0/24"
}

variable "vcn_dns_label" {
  description = "Immutable DNS label already assigned to the existing VCN."
  type        = string
}

variable "subnet_dns_label" {
  description = "Immutable DNS label already assigned to the existing public subnet."
  type        = string
}

variable "instance_hostname_label" {
  description = "Hostname label already assigned to the instance VNIC."
  type        = string
}

variable "boot_volume_size_gb" {
  description = "Boot-volume size in GB; all boot and block volumes combined must stay within 200 GB for Always Free."
  type        = number
  default     = 50

  validation {
    condition     = var.boot_volume_size_gb >= 50 && var.boot_volume_size_gb <= 200
    error_message = "Choose a boot volume between 50 and 200 GB, after checking total home-region volume usage."
  }
}

variable "k3s_version" {
  description = "Pinned K3s release installed by cloud-init on first boot."
  type        = string
  default     = "v1.37.1+k3s1"
}
