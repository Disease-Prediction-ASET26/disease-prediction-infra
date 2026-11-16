#!/usr/bin/env bash
# Run from terraform/oracle after applying Email Delivery.
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^(dev|prod|ops)$ ]]; then
  printf 'Usage: %s dev|prod|ops\n' "$0" >&2
  exit 2
fi

mail_env="$1"
user_id="$(terraform output -json email_smtp_user_ids | jq -er --arg env "$mail_env" '.[$env]')"
user_name="$(oci iam user get --user-id "$user_id" --query 'data.name' --raw-output)"
if [[ "$user_name" != "disease-prediction-smtp-$mail_env" ]]; then
  printf 'Unexpected user name; no capabilities changed.\n' >&2
  exit 1
fi

oci iam user update-user-capabilities --user-id "$user_id" \
  --can-use-console-password false \
  --can-use-api-keys false \
  --can-use-auth-tokens false \
  --can-use-customer-secret-keys false \
  --can-use-db-credentials false \
  --can-use-o-auth2-client-credentials false \
  --can-use-smtp-credentials true \
  --query 'data.name' --raw-output >/dev/null

oci iam user get --user-id "$user_id" --output json | jq -e '
  .data.capabilities as $caps |
  $caps["can-use-console-password"] == false and
  $caps["can-use-api-keys"] == false and
  $caps["can-use-auth-tokens"] == false and
  $caps["can-use-customer-secret-keys"] == false and
  $caps["can-use-db-credentials"] == false and
  $caps["can-use-o-auth2-client-credentials"] == false and
  $caps["can-use-smtp-credentials"] == true
' >/dev/null
printf 'SMTP capabilities restricted for %s.\n' "$mail_env"
