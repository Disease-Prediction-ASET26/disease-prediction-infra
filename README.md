# Disease Prediction OCI infrastructure

Terraform manages the Oracle Cloud Infrastructure (OCI) VM, its VCN and the public-subnet access rules. Kubernetes application configuration belongs in `disease-prediction-gitops`.

## Inventory checked on 2026-10-29

- Tenancy home region: `eu-frankfurt-1`; it is the only subscribed region.
- One running `VM.Standard.A1.Flex` instance in `XUCP:EU-FRANKFURT-1-AD-2`, configured for 2 OCPUs and 12 GB RAM.
- The instance uses Oracle Linux 9.8 ARM64 and a 200 GB boot volume at 10 VPUs/GB.
- No separate block volumes; one boot-volume backup exists (Always Free includes up to five).
- Existing VCN: `10.0.0.0/16`; public subnet: `10.0.0.0/24`; private subnet: `10.0.1.0/24`.
- The public subnet had a public IP and a default security list that allowed SSH from `0.0.0.0/0`, but no internet gateway or route to it.

OCI's Always Free A1 allowance is 2 OCPUs and 12 GB RAM in the tenancy home region. The 200 GB boot volume is within the 200 GB combined boot/block-volume allowance and uses all of it. Keep the instance in Frankfurt and don't add boot or block volumes unless total usage is checked first. OCI also includes 10 TB/month outbound transfer. These limits are account-wide; review Limits, Quotas and Usage before adding resources. [Always Free limits](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm)

## What Terraform manages

- Imports the existing VCN, public subnet and VM into remote state.
- Adds an internet gateway and a dedicated public-subnet route table. The private subnet remains without an internet route.
- Attaches a public security list that permits SSH only from `admin_ssh_cidr`; it does not open Kubernetes, NodePort, database or application ports.
- Removes the broad SSH rule from the VCN's default security list.
- Checks the tenancy home region and exact availability-domain name before provisioning.
- Prevents Terraform from destroying the imported VCN, public subnet or VM.

The VM's original metadata contains an SSH public key but no cloud-init `user_data`. Terraform ignores changes to that one-time field on the imported VM; it won't rerun cloud-init. The imported VM was bootstrapped in place with the pinned K3s release and server options. New VMs created by this configuration receive the same bootstrap through cloud-init.

The VM's `firewalld` needs a narrow TCP 10250 rule from the default K3s pod CIDR (`10.42.0.0/16`) so the bundled metrics server can reach kubelet. That rule is included in cloud-init for new VMs and kept local to the host firewall; the OCI security list does not expose it publicly.

## Local setup

Terraform 1.12+ and the OCI CLI are required. Configure an OCI API signing-key profile locally; Terraform and the OCI backend use that profile, so no API private key is stored in this repository.

Copy the example file and fill in the existing resource IDs, tenancy OCID, compartment OCID, current Oracle Linux image OCID, exact AD name, and SSH CIDR:

```powershell
Set-Location terraform/oracle
Copy-Item terraform.tfvars.example terraform.tfvars
```

Use the matching SSH public key path, for example `C:/Users/<user>/.ssh/disease-prediction-oci.key.pub`; the private half stays in the user's `.ssh` directory and is ignored by Git. Replace the example's administrator CIDR with your current public IPv4 `/32`. Update it if your public IP changes.

The private, versioned Object Storage bucket `disease-prediction-tfstate` was bootstrapped in the home region. Get its namespace and initialize remote state:

```powershell
$namespace = (oci os ns get | ConvertFrom-Json).data
terraform init `
  -backend-config="bucket=disease-prediction-tfstate" `
  -backend-config="namespace=$namespace" `
  -backend-config="region=eu-frankfurt-1" `
  -backend-config="key=disease-prediction/terraform.tfstate" `
  -backend-config="config_file_profile=DEFAULT"
```

The bucket is private and versioned. Keep the state bucket; Terraform state and saved plans are sensitive and must stay out of Git. Grant other maintainers least-privilege Object Storage access before they use this backend.

## Import and apply

Review the import and network changes before applying:

```powershell
terraform fmt -check -recursive
terraform validate
terraform plan -out=infra.tfplan
terraform show infra.tfplan
```

The plan should import the existing VM, VCN and public subnet; create the internet gateway, public route table and public security list; and update the subnet/default security list. It must not create, replace or destroy the VM. `prevent_destroy` guards the imported compute and network resources. If the plan proposes an instance replacement, stop and correct the configuration before applying.

Only after reviewing the plan:

```powershell
terraform apply infra.tfplan
```

## Connect and check K3s

```powershell
$ip = terraform output -raw instance_public_ip
ssh -i "$env:USERPROFILE\.ssh\disease-prediction-oci.key" opc@$ip
```

The current image's default user is `opc`. On the VM, check whether K3s is already installed:

```sh
sudo systemctl is-active k3s
sudo /usr/local/bin/k3s kubectl get nodes
sudo /usr/local/bin/k3s kubectl get pods -A
```

If K3s is absent, check `sudo cloud-init status --long` and `sudo journalctl -u cloud-init --no-pager`. Do not assume a Terraform metadata update reran cloud-init on this imported VM.
