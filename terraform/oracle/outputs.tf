output "instance_id" {
  description = "OCI instance OCID."
  value       = oci_core_instance.k3s_server.id
}

output "instance_public_ip" {
  description = "Public IPv4 address for SSH administration. Inbound SSH is restricted by admin_ssh_cidr."
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
