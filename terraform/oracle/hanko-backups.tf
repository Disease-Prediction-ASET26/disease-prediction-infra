# Hanko backups are stored off-node and expire after seven days.
data "oci_objectstorage_namespace" "hanko_backups" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "hanko_backups" {
  compartment_id = var.compartment_ocid
  namespace      = data.oci_objectstorage_namespace.hanko_backups.namespace
  name           = "${var.project_name}-hanko-backups"
  access_type    = "NoPublicAccess"
  storage_tier   = "Standard"

  lifecycle {
    prevent_destroy = true
  }
}

resource "oci_identity_policy" "hanko_backup_lifecycle" {
  compartment_id = var.tenancy_ocid
  name           = "${var.project_name}-hanko-backup-lifecycle"
  description    = "Allow Object Storage to expire Hanko backups in this bucket."
  statements = [
    "Allow service objectstorage-${var.region} to manage object-family in compartment id ${var.compartment_ocid} where target.bucket.name = '${oci_objectstorage_bucket.hanko_backups.name}'"
  ]
}

resource "oci_objectstorage_object_lifecycle_policy" "hanko_backups" {
  bucket    = oci_objectstorage_bucket.hanko_backups.name
  namespace = oci_objectstorage_bucket.hanko_backups.namespace

  rules {
    action      = "DELETE"
    is_enabled  = true
    name        = "expire-hanko-backups"
    time_amount = 7
    time_unit   = "DAYS"
    target      = "objects"
  }

  depends_on = [oci_identity_policy.hanko_backup_lifecycle]
}
