# Email compartments isolate sending permissions and quota consumption.
locals {
  email_senders = {
    dev = {
      domain       = "mail-dev.pocket-doc.app"
      daily_limit  = 20
      minute_limit = 5
    }
    prod = {
      domain       = "mail.pocket-doc.app"
      daily_limit  = 40
      minute_limit = 5
    }
    ops = {
      domain       = "ops-mail.pocket-doc.app"
      daily_limit  = 10
      minute_limit = 5
    }
  }
}

resource "oci_identity_compartment" "email" {
  for_each       = local.email_senders
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-mail-${each.key}"
  description    = "Email Delivery sender and quota for ${each.key}."
  enable_delete  = false
}

resource "oci_email_email_domain" "sender" {
  for_each       = local.email_senders
  compartment_id = oci_identity_compartment.email[each.key].id
  name           = each.value.domain
}

# OCI generates and retains the private signing key; do not supply private_key.
resource "oci_email_dkim" "sender" {
  for_each        = local.email_senders
  email_domain_id = oci_email_email_domain.sender[each.key].id
  name            = "oci"
}

resource "oci_email_sender" "sender" {
  for_each       = local.email_senders
  compartment_id = oci_identity_compartment.email[each.key].id
  email_address  = "no-reply@${each.value.domain}"
}

resource "oci_identity_group" "smtp" {
  for_each       = local.email_senders
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-smtp-${each.key}"
  description    = "SMTP send permission for the ${each.key} sender."
}

resource "oci_identity_user" "smtp" {
  for_each       = local.email_senders
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-smtp-${each.key}"
  description    = "Service identity for ${each.key} SMTP."
  email          = "no-reply@${each.value.domain}"
}

resource "oci_identity_user_capabilities_management" "smtp" {
  for_each                     = local.email_senders
  user_id                      = oci_identity_user.smtp[each.key].id
  can_use_api_keys             = false
  can_use_auth_tokens          = false
  can_use_console_password     = false
  can_use_customer_secret_keys = false
  can_use_smtp_credentials     = true
}

resource "oci_identity_user_group_membership" "smtp" {
  for_each = local.email_senders
  user_id  = oci_identity_user.smtp[each.key].id
  group_id = oci_identity_group.smtp[each.key].id
}

resource "oci_identity_policy" "smtp" {
  for_each       = local.email_senders
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-smtp-${each.key}"
  description    = "Allow the ${each.key} SMTP identity to use its own approved senders."
  statements = [
    "Allow group ${oci_identity_group.smtp[each.key].name} to use approved-senders in compartment id ${oci_identity_compartment.email[each.key].id}"
  ]
}

# Quotas are separate per sender compartment, and apply only to this region.
# They do not constitute a monthly spending cap.
resource "oci_limits_quota" "email" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-email-quotas"
  description    = "Restrict the rate and daily count of project mail sends."
  statements = flatten([
    for key, sender in local.email_senders : [
      "set email-delivery quota max-emails-day to ${sender.daily_limit} in compartment ${oci_identity_compartment.email[key].name} where request.region = '${var.region}'",
      "set email-delivery quota sendrate to ${sender.minute_limit} in compartment ${oci_identity_compartment.email[key].name} where request.region = '${var.region}'"
    ]
  ])
}
