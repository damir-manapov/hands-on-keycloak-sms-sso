# Keycloak Sms SSO Sandbox

## TODO

* Update it to use latest keycloak

## Manual configuration

### Registration:
* http://localhost:8080/admin/master/console/#/research/authentication
* Dublicate "registration" -> "Registration phone only"
* Del "Registration user creation"
* At "Registration phone only registration form" add step "Registration Phone User Creation"
* Make it required (!), set first
* At settings enable "Phone number as username"
* Add step "Phone validation"
* Make it required (!), set after "Registration Phone User Creation"
* Delete "Password Validation" step
* In action bind flow to "Registration flow"
* http://localhost:8080/admin/master/console/#/research/realm-settings/themes
* Set login theme "phone", save
* http://localhost:8080/admin/master/console/#/research/realm-settings/login
* Enable "User registration"
* Check registration at http://localhost:8080/realms/research/account
* You will get registration code in keycloak's logs

* Rm "Profile Validation"

"Phone number as username"

Login:
* http://localhost:8080/admin/master/console/#/research/authentication
* Dublicate "browser" -> "Browser phone only"
* Set "Browser phone only forms" required (!)
* Delete "Username Password Form" and "Browser phone only Browser - Conditional OTP"
* Add "Authentication everybody by phone" step to "Browser phone only forms"
* Make it required (!)
* "Actions" -> bind flow to "Browser flow"
* http://localhost:8080/admin/master/console/#/research/realm-settings/login
* Disable "Login with email"
* Check login at http://localhost:8080/realms/research/account
* You will get registration code in keycloak's logs

Identity Provider Redirector deleted

curl http://localhost:8080/realms/research/protocol/openid-connect/auth?client_id=account-console&redirect_uri=http%3A%2F%2Flocalhost%3A8080%2Frealms%2Fresearch%2Faccount%2F&response_type=code

"Provide phone number" instead of "Authentication everybody by phone"
"OTP over SMS" → set Required.
Delete "Kerberos"


docker compose cp keycloak:/opt/keycloak/providers/keycloak-phone-provider.resources.jar ./
unzip -p keycloak-phone-provider.resources.jar META-INF/keycloak-phone-realm.json > phone-realm.json

unzip -l keycloak-phone-provider.resources.jar | grep -i phone


## Things to check

* registration by phone number
* user cannot register with the same phone number
* user can register with the same phone number that was provided by ither user but it is not verified
* user can resend code to the phone number
* Impossible to login by phone that wasn't registered


/opt/keycloak/bin/kcadm.sh update realms/research \
  -s 'attributes."phone.charge.enabled"="false"' \
  -s 'attributes."phone.charge.requireBalance"="false"' \
  -s 'attributes."phone.charge.price"="0"' \
  -s 'attributes."phone.charge.resendPrice"="0"' \
  -s 'attributes."phone.charge.balance"="999999"'


## Debug from inside of container

### Enter

```sh
docker compose --file compose/docker-compose.yml exec keycloak bash
```

### Check user's attributer

```sh
/opt/keycloak/bin/kcadm.sh get users -r research --fields username,attributes
```

### Check config's of realm

```sh
/opt/keycloak/bin/kcadm.sh get realms/research
```

