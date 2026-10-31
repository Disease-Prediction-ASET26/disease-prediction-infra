output "instance_id" {
  description = "OCI instance OCID."
  value       = oci_core_instance.k3s_server.id
}

output "instance_public_ip" {
  description = "Public IPv4 address assigned to the VM; SSH is controlled separately by admin_ssh_cidr."
  value       = oci_core_instance.k3s_server.public_ip
}

output "vcn_id" {
  description = "OCI VCN OCID managed by Terraform."
  value       = oci_core_vcn.project.id
}

output "subnet_id" {
  description = "OCI public subnet OCID managed by Terraform."
  value       = oci_core_subnet.public.id
}

output "secrets_vault_id" {
  description = "Non-secret OCI Vault OCID for External Secrets Operator configuration."
  value       = oci_kms_vault.secrets.id
}

output "secrets_vault_region" {
  description = "OCI region containing the project secrets Vault."
  value       = var.region
}
