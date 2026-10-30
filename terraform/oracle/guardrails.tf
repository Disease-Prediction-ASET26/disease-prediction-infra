locals {
  budget_alert_rules = {
    actual_50 = {
      threshold = 50
      type      = "ACTUAL"
    }
    actual_100 = {
      threshold = 100
      type      = "ACTUAL"
    }
    forecast_50 = {
      threshold = 50
      type      = "FORECAST"
    }
    forecast_100 = {
      threshold = 100
      type      = "FORECAST"
    }
  }
}

# These quotas apply across the tenancy. They allow A1 compute only in the
# selected home-region AD and block other compute shapes and ADs.
resource "oci_limits_quota" "always_free_compute" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-always-free-compute"
  description    = "Allow only the Always Free A1 compute allocation in the selected home-region AD."
  statements = [
    "zero compute quotas in tenancy",
    "zero compute-core quotas in tenancy",
    "set compute-core quota standard-a1-core-count to 2 in tenancy where request.ad = '${var.availability_domain}'",
    "zero compute-memory quotas in tenancy",
    "set compute-memory quota standard-a1-memory-count to 12 in tenancy where request.ad = '${var.availability_domain}'",
  ]

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = local.always_free_scope_valid
      error_message = "Always Free compute quotas require the tenancy home region and an availability domain in that region."
    }
  }
}

# Block-volume capacity is AD-scoped; backup count is regional. Zeroing each
# quota family first keeps the free allocation in the selected region and AD.
resource "oci_limits_quota" "always_free_block_storage" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-always-free-block-storage"
  description    = "Limit boot and block volumes to 200 GB and backups to five in the home region."
  statements = [
    "zero block-storage quotas in tenancy",
    "set block-storage quota total-storage-gb to 200 in tenancy where request.ad = '${var.availability_domain}'",
    "set block-storage quota backup-count to 5 in tenancy where request.region = '${var.region}'",
  ]

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = local.always_free_scope_valid
      error_message = "Always Free block-storage quotas require the tenancy home region and an availability domain in that region."
    }
  }
}

# Object Storage quotas are regional and include versioned objects. The 20 GB
# ceiling is the conservative Always Free allowance for the tenancy.
resource "oci_limits_quota" "always_free_object_storage" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-always-free-object-storage"
  description    = "Limit Object Storage to 20 GB in the home region."
  statements = [
    "zero object-storage quotas in tenancy",
    "set object-storage quota storage-bytes to 20000000000 in tenancy where request.region = '${var.region}'",
  ]

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = var.region == local.home_region
      error_message = "Always Free Object Storage quota requires the tenancy home region."
    }
  }
}

# Budgets are alerting controls, not spend caps. Target the root compartment so
# this budget observes all compartments in the tenancy.
resource "oci_budget_budget" "root_monthly" {
  amount                               = 1
  compartment_id                       = var.tenancy_ocid
  display_name                         = "${var.project_name}-monthly-cost-alert"
  description                          = "Alert on unexpected tenancy spend; OCI budgets do not stop usage."
  processing_period_type               = "MONTH"
  reset_period                         = "MONTHLY"
  budget_processing_period_start_offset = 1
  target_type                          = "COMPARTMENT"
  targets                              = [var.tenancy_ocid]

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_budget_alert_rule" "root_monthly" {
  for_each = local.budget_alert_rules

  budget_id      = oci_budget_budget.root_monthly.id
  display_name   = "${var.project_name}-${each.key}"
  description    = "Notify when actual or forecast tenancy spend reaches ${each.value.threshold}% of the monthly budget."
  message        = "Review OCI Cost Analysis. Budget alerts do not stop resource usage or charges."
  recipients     = var.budget_alert_email
  threshold      = each.value.threshold
  threshold_type = "PERCENTAGE"
  type           = each.value.type

  lifecycle {
    prevent_destroy = true
  }
}
