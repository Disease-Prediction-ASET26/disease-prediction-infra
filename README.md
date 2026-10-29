# Disease Prediction Oracle infrastructure

This repository contains Terraform for one Oracle Cloud Infrastructure (OCI) VM and its project network. It does not manage Kubernetes application manifests; those belong in `disease-prediction-gitops`.

## What Terraform creates

- A new VCN, public subnet, internet gateway and route.
- An ingress rule for SSH from `admin_ssh_cidr` only. Kubernetes, database, NodePort and application ports are not opened.
- One `VM.Standard.A1.Flex` instance with 2 OCPUs and 12 GB RAM, using a pinned regional Ubuntu 24.04 ARM64 image OCID.
- Cloud-init that installs the pinned K3s version with Kubernetes Secret encryption enabled on first start, and disables the unused Traefik and ServiceLB components.

This configuration does **not** import, change or delete the VM or subnet already in the tenancy. It creates a separate project VCN and VM. Inventory the existing resources and review the Terraform plan before applying so that the existing VM does not consume capacity unexpectedly. Do not delete the old VM until its OCID, attached volumes and data have been checked.

## Prerequisites

- Terraform 1.12 or newer (the native OCI state backend requires it).
- OCI CLI configured with an API signing key profile that can manage the target compartment, compute and networking resources, and the Terraform state bucket.
- A private OCI Object Storage bucket for Terraform state, with object versioning enabled and access restricted to infrastructure maintainers. Create this bootstrap bucket in the tenancy's home region before initializing Terraform.
- A dedicated SSH key pair for this VM. Keep the private key out of the repository and use only the `.pub` path in Terraform variables.
- The tenancy OCID, target compartment OCID, home region, trusted public SSH CIDR and a region-specific Ubuntu 24.04 ARM64 image OCID.
- Confirmation that the selected VCN/subnet CIDRs do not overlap networks already in use, and that compute and block-volume limits have room for this VM.

Use the OCI Console to add an API key to a dedicated OCI user, then configure the local OCI CLI profile. Do not commit the private API key, local OCI config, kubeconfig or Terraform state. Provider and backend authentication read the selected profile from the local OCI CLI config; no OCI private key is placed in Terraform variables or cloud-init.

Find the image OCID in the OCI Console for the selected region and verify the image is **Ubuntu 24.04 ARM64**. Pin the OCID in the local variables file; image identifiers are region-specific and should not float to a different image on a later plan.

## Prepare locally

From PowerShell:

```powershell
cd terraform/oracle
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with the tenancy, compartment, region, profile, image OCID, SSH public key path and trusted SSH CIDR. Use `/32` for a fixed administrator public IP when possible. The example file is safe to commit; `terraform.tfvars` is ignored.

Check all existing VCN CIDRs before using the example `10.42.0.0/16` and `10.42.10.0/24`. If the administrator's public IP changes, update `admin_ssh_cidr` and apply the security-list change before attempting SSH again.

## Initialize shared state

Use the same OCI Object Storage bucket, namespace and state key for all maintainers. The OCI backend provides remote shared state and locking. Do not switch to local state for routine work.

```powershell
terraform init `
  -backend-config="bucket=YOUR_STATE_BUCKET" `
  -backend-config="namespace=YOUR_OBJECT_STORAGE_NAMESPACE" `
  -backend-config="region=YOUR_HOME_REGION" `
  -backend-config="key=disease-prediction/terraform.tfstate" `
  -backend-config="config_file_profile=DEFAULT"
```

Use the profile name from your local OCI config if it is not `DEFAULT`. Backend values are configuration, not credentials; do not pass API private keys on the command line.

## Review before provisioning

```powershell
terraform fmt -check -recursive
terraform validate
terraform plan -out=infra.tfplan
terraform show infra.tfplan
```

Confirm the plan only creates the intended project VCN, subnet, security list, gateway, route and one A1 instance. Verify the ARM image OCID, `2` OCPUs, `12` GB RAM, boot volume size, SSH CIDR and overall tenancy quota. The plan must not propose changes to unrelated existing resources. Saved plan files can contain sensitive values; keep them local, protect them and never commit them.

Only after a human reviews the displayed plan:

```powershell
terraform apply infra.tfplan
```

No plan or apply should run from an untrusted pull request. Pull requests can run formatting, provider initialization without a backend and validation without OCI credentials.

## Connect to the VM

After applying, get the VM's public address with:

```powershell
terraform output -raw instance_public_ip
```

Use the private half of the dedicated SSH key and Ubuntu's default account:

```powershell
ssh -i "$env:USERPROFILE\.ssh\disease-prediction-oci" ubuntu@<public-ip>
```

The VCN security list limits SSH to `admin_ssh_cidr`; the instance has no public Kubernetes API or application listener. Check the VM's cloud-init log if K3s is not ready:

```sh
sudo cloud-init status --long
sudo journalctl -u k3s --no-pager
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

## State and teardown

Terraform state and saved plans are sensitive. The Object Storage state bucket must remain private and versioned; keep local plans out of Git. No secret values should be added to this configuration or cloud-init.

This is a single-node cluster and is not highly available. Back up application data separately before relying on the VM. A Terraform destroy removes the resources in this state; it does not clean up resources created outside Terraform. Review any destroy plan and verify backups before approving it.
