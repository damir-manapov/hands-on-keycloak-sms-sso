#!/usr/bin/env bash
set -euo pipefail

############################################
# Config (override via env)
############################################
SERVER_URL="${SERVER_URL:-http://localhost:8080}"
MASTER_REALM="${MASTER_REALM:-master}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_PASS="${ADMIN_PASS:-admin}"

REALM="${REALM:-research}"

# Flow aliases (no spaces to avoid URL encoding headaches)
BROWSER_FLOW_ALIAS="${BROWSER_FLOW_ALIAS:-browserPhoneOnly}"
BROWSER_SUBFLOW_ALIAS="${BROWSER_SUBFLOW_ALIAS:-browserPhoneOnlyForms}"

REG_FLOW_ALIAS="${REG_FLOW_ALIAS:-registrationPhoneOnly}"

# Add Cookie step to enable SSO reuse
ADD_COOKIE="${ADD_COOKIE:-true}"

# Create a simple public client for testing (no PKCE)
CREATE_TEST_CLIENT="${CREATE_TEST_CLIENT:-true}"

kc() { /opt/keycloak/bin/kcadm.sh "$@"; }

die() { echo "ERROR: $*" >&2; exit 1; }

############################################
# Check tools
############################################
[ -x /opt/keycloak/bin/kcadm.sh ] || die "kcadm.sh not found"
command -v curl >/dev/null || die "curl is required in the container"

############################################
# Login to kcadm (admin-cli)
############################################
echo "==> Login (kcadm) ${SERVER_URL}"
kc config credentials --server "$SERVER_URL" --realm "$MASTER_REALM" \
  --user "$ADMIN_USER" --password "$ADMIN_PASS" >/dev/null

############################################
# Ensure realm exists
############################################
if ! kc get realms/"$REALM" >/dev/null 2>&1; then
  echo "==> Create realm '$REALM'"
  kc create realms -s realm="$REALM" -s enabled=true >/dev/null
fi

############################################
# Realm basics: theme & login toggles
############################################
echo "==> Configure realm '${REALM}' (theme, login toggles)"
kc update realms/"$REALM" \
  -s 'loginTheme=phone' \
  -s 'registrationAllowed=true' \
  -s 'loginWithEmailAllowed=false' \
  -s 'duplicateEmailsAllowed=false' >/dev/null

############################################
# Disable phone charging (avoid MSG0042)
############################################
echo "==> Disable phone charging in realm (no credits required)"
kc update realms/"$REALM" \
  -s 'attributes."phone.charge.enabled"="false"' \
  -s 'attributes."phone.charge.requireBalance"="false"' \
  -s 'attributes."phone.charge.price"="0"' \
  -s 'attributes."phone.charge.resendPrice"="0"' \
  -s 'attributes."phone.charge.balance"="999999"' >/dev/null

############################################
# Create Browser flow and subflow (idempotent)
############################################
echo "==> Create Browser flow '${BROWSER_FLOW_ALIAS}' (idempotent)"
kc create authentication/flows -r "$REALM" -i \
  -s "alias=${BROWSER_FLOW_ALIAS}" \
  -s 'description=Phone-only browser login' \
  -s 'providerId=basic-flow' \
  -s 'topLevel=true' \
  -s 'builtIn=false' >/dev/null || true

echo "==> Create Browser subflow '${BROWSER_SUBFLOW_ALIAS}' (idempotent)"
kc create "authentication/flows/${BROWSER_FLOW_ALIAS}/executions/flow" -r "$REALM" -i \
  -s "alias=${BROWSER_SUBFLOW_ALIAS}" \
  -s 'description=Phone OTP forms' \
  -s 'provider=form-flow' \
  -s 'type=form' \
  -s 'builtIn=false' >/dev/null || true

############################################
# Add executions: Phone number, OTP, Cookie
############################################
echo "==> Add 'Provide phone number' (idempotent)"
kc create "authentication/flows/${BROWSER_FLOW_ALIAS}/executions/execution" -r "$REALM" -i \
  -s 'provider=phone-number-authenticator' >/dev/null || true

echo "==> Add 'OTP over SMS' (idempotent)"
kc create "authentication/flows/${BROWSER_FLOW_ALIAS}/executions/execution" -r "$REALM" -i \
  -s 'provider=sms-otp-authenticator' >/dev/null || true

if [ "$ADD_COOKIE" = "true" ]; then
  echo "==> Add 'Cookie' (SSO) (idempotent)"
  kc create "authentication/flows/${BROWSER_FLOW_ALIAS}/executions/execution" -r "$REALM" -i \
    -s 'provider=auth-cookie' >/dev/null || true
fi

############################################
# Collect execution ids (no jq)
############################################
EXEC_JSON="$(kc get "authentication/flows/${BROWSER_FLOW_ALIAS}/executions" -r "$REALM")"

find_id_by_field () {
  local json="$1" field="$2" value="$3"
  local cleaned block id
  cleaned=$(printf '%s' "$json" | tr -d '\n' | sed -e 's/^\[//' -e 's/\]$//' -e 's/},[[:space:]]*{/}\n{/g')
  while IFS= read -r block; do
    block="${block#\{}"; block="${block%\}}"
    if printf '%s' "$block" | grep -q "\"$field\"[[:space:]]*:[[:space:]]*\"$value\""; then
      id=$(printf '%s' "$block" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
      [ -n "$id" ] && { echo "$id"; return 0; }
    fi
  done <<EOF
$cleaned
EOF
  return 1
}

EXEC_SUBFLOW="$(find_id_by_field "$EXEC_JSON" displayName "$BROWSER_SUBFLOW_ALIAS" || true)"
EXEC_PHONE="$(find_id_by_field "$EXEC_JSON" providerId "phone-number-authenticator" || true)"
EXEC_OTP="$(find_id_by_field "$EXEC_JSON" providerId "sms-otp-authenticator" || true)"
EXEC_COOKIE="$(find_id_by_field "$EXEC_JSON" providerId "auth-cookie" || true)"

echo "   Browser flow executions:"
echo "     subflow: ${EXEC_SUBFLOW:-<not found>}"
echo "     phone  : ${EXEC_PHONE:-<not found>}"
echo "     otp    : ${EXEC_OTP:-<not found>}"
echo "     cookie : ${EXEC_COOKIE:-<not found>}"

############################################
# Use REST API (curl) to set requirements reliably
############################################
echo "==> Acquire admin token"
TOKEN="$(curl -s -X POST "${SERVER_URL}/realms/${MASTER_REALM}/protocol/openid-connect/token" \
  -d grant_type=password -d client_id=admin-cli \
  -d username="${ADMIN_USER}" -d password="${ADMIN_PASS}" \
  | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
[ -n "$TOKEN" ] || die "Cannot obtain admin token"

put_req () {
  local id="$1" req="$2"
  curl -s -o /dev/null -w "%{http_code}\n" \
    -X PUT "${SERVER_URL}/admin/realms/${REALM}/authentication/flows/${BROWSER_FLOW_ALIAS}/executions" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"id\":\"${id}\",\"requirement\":\"${req}\"}"
}

echo "==> Set Browser requirements"
[ -n "${EXEC_SUBFLOW:-}" ] && echo "   subflow -> REQUIRED:   $(put_req "$EXEC_SUBFLOW" REQUIRED)"
[ -n "${EXEC_PHONE:-}"   ] && echo "   phone   -> REQUIRED:   $(put_req "$EXEC_PHONE" REQUIRED)"
[ -n "${EXEC_OTP:-}"     ] && echo "   otp     -> REQUIRED:   $(put_req "$EXEC_OTP" REQUIRED)"
if [ "$ADD_COOKIE" = "true" ] && [ -n "${EXEC_COOKIE:-}" ]; then
  echo "   cookie  -> ALTERNATIVE: $(put_req "$EXEC_COOKIE" ALTERNATIVE)"
fi

############################################
# Bind Browser flow
############################################
echo "==> Bind '${BROWSER_FLOW_ALIAS}' as Browser flow"
kc update realms/"$REALM" -s "browserFlow=${BROWSER_FLOW_ALIAS}" >/dev/null

############################################
# Registration flow (phone-only, username = phone)
############################################
echo "==> Create Registration flow '${REG_FLOW_ALIAS}' (copy built-in, idempotent)"
kc create "authentication/flows/registration/copy" -r "$REALM" \
  -s "newName=${REG_FLOW_ALIAS}" >/dev/null || true

echo "==> Add 'Registration Phone User Creation' (username = phone)"
kc create "authentication/flows/${REG_FLOW_ALIAS}/executions/execution" -r "$REALM" -i \
  -s 'provider=registration-phone-username-creation' >/dev/null || true

REG_EXEC_JSON="$(kc get "authentication/flows/${REG_FLOW_ALIAS}/executions" -r "$REALM")"

find_reg_id () {
  find_id_by_field "$REG_EXEC_JSON" "$1" "$2"
}

EXEC_REG_PHONE_VALIDATION="$(find_reg_id displayName 'Phone validation' || true)"
EXEC_REG_PHONE_CREATION="$(find_reg_id providerId 'registration-phone-username-creation' || true)"

disable_if_present () {
  local name="$1" id
  id="$(find_reg_id displayName "$name" || true)"
  if [ -n "$id" ]; then
    kc update "authentication/flows/${REG_FLOW_ALIAS}/executions" -r "$REALM" \
      -b '{"id":"'"${id}"'","requirement":"DISABLED"}' >/dev/null || true
    echo "   Disabled: $name"
  fi
}

echo "==> Disable Password/Profile in Registration (if present)"
disable_if_present "Password Validation"
disable_if_present "Profile Validation"
disable_if_present "User Profile"

if [ -n "$EXEC_REG_PHONE_VALIDATION" ]; then
  kc update "authentication/flows/${REG_FLOW_ALIAS}/executions" -r "$REALM" \
    -b '{"id":"'"${EXEC_REG_PHONE_VALIDATION}"'","requirement":"REQUIRED"}' >/dev/null || true
  echo "   Phone validation -> REQUIRED"
else
  echo "   (warn) 'Phone validation' not found; continuing"
fi

if [ -n "$EXEC_REG_PHONE_CREATION" ]; then
  kc update "authentication/flows/${REG_FLOW_ALIAS}/executions" -r "$REALM" \
    -b '{"id":"'"${EXEC_REG_PHONE_CREATION}"'","requirement":"REQUIRED"}' >/dev/null
  echo "   Registration Phone User Creation -> REQUIRED"
else
  echo "   (warn) 'registration-phone-username-creation' not found; ensure phone provider jar is loaded"
fi

echo "==> Bind '${REG_FLOW_ALIAS}' as Registration flow"
kc update realms/"$REALM" -s "registrationFlow=${REG_FLOW_ALIAS}" >/dev/null

############################################
# Optional test client (no PKCE)
############################################
if [ "$CREATE_TEST_CLIENT" = "true" ]; then
  echo "==> Create test client 'test-web' (public, no PKCE)"
  kc create clients -r "$REALM" -i \
    -s clientId='test-web' \
    -s protocol='openid-connect' \
    -s publicClient=true \
    -s 'redirectUris=["http://localhost/*","http://localhost:5173/*","http://localhost:3000/*"]' \
    -s 'attributes."pkce.code.challenge.method"="none"' >/dev/null || true
fi

############################################
# Show final flows
############################################
echo "==> Final Browser executions:"
kc get "authentication/flows/${BROWSER_FLOW_ALIAS}/executions" -r "$REALM"

echo "==> Final Registration executions:"
kc get "authentication/flows/${REG_FLOW_ALIAS}/executions" -r "$REALM"

cat <<EOF

✅ Done!

Browser login (phone-only):
  ${SERVER_URL}/realms/${REALM}/account

If you enabled the test client:
  ${SERVER_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=test-web&redirect_uri=http%3A%2F%2Flocalhost%2Fcb&response_type=code&prompt=login

Notes:
- Keep 'KC_SMS_PROVIDER=dummy' and 'KC_SMS_FROM=dummy' for dev; OTP codes show in logs.
- Cookie step is ALTERNATIVE to preserve SSO reuse; set ADD_COOKIE=false to skip it.
- All operations are idempotent; you can re-run the script safely.

EOF
