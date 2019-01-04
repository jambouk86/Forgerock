#!/usr/bin/env bash

set -e

export sharedsecret=`uuidgen`
touch scripts/.secretfile
chmod 400 scripts/.secretfile
echo $sharedsecret > scripts/.secretfile

source scripts/env.sh
source scripts/realm-env.sh

#namespace=sandpit
#namespaceContext=acp-notprod

randomUid=$(uuidgen)
LdapGroupProvider=$(uuidgen)

# Add shared secret to Drone secrets
#echo "Adding shared secret to Drone secrets..."
#!drone secret add --repository <gitlab-repo> --name sandpit_shared_secret --value $sharedsecret

#Use kubectl command to add shared secret to <secretname>
#kd --context=$namespaceContext --namespace=$namespace get secret -f <secret> -o yaml > scripts/shared.yaml
#sed -i "s/^  shared.secret.*$/  shared.secret: `echo -n $SHARED_SECRET | base64`/g" scripts/shared.yaml
#kd --context=$namespaceContext --namespace=$namespace apply -f scripts/shared.yaml

echo "Creating context specfic client json file..."
TMPFILE=scripts/ui-new.json
sed "s#<sso-url>#"$SSO_URL"#g" scripts-ui-template.json > $TMPFILE

if [[ "${DEPLOY_REALM}" = "dev" ]];
then
  echo "Realm is ${DEPLOY_REALM}, adding localhost to redirect URIs..."
  sed -i '/^    "redirectUris"/a\    "https://localhost:7000",\n    "https://localhost:7000/",\n    "https://localhost:9000/",\n    "https://localhost:9000",' $TMPFILE
fi

sleep 2

echo "Creating realm..."
scripts/kcadm.sh create realms \
--realm=master \
-s id=$REALM_ID \
-s enabled=true \
-s realm=$REALM \
--server $KEYCLOAK_SERVER \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD

sleep 3 

echo "Create a new client from json file..."
scripts/kcadm.sh create clients \
-r $REALM \
-f $TMPFILE \
-s secret=$SHARED_SECRET \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD

sleep 3

echo "Update login settings..."
scripts/kcadm.sh update realms/$REALM \
-s registrationAllowed=false \
-s registrationEmailAsUsername=false \
-s rememberMe=false \
-s verifyEmail=false \
-s resetPasswordAllowed=true \
-s editUsernameAllowed=false \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD

sleep 3

echo "Update Login Theme...."
scripts/kcadm.sh update realms/$REALM \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-s loginTheme="<themename>"

sleep 2

echo "Update SMTP settings..."
scripts/kcadm.sh update realms/$REALM \
-x \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-s "smtpServer.host=$SMTP_HOST" \
-s "smtpServer.port=$SMTP_PORT" \
-s "smtpServer.from=$SMTP_FROM" \
-s 'smtpServer.fromDisplayName=Mail Support' \
-s "smtpServer.user=$SMTP_USER" \
-s "smtpServer.password=$SMTP_PASSWORD" \
-s 'smtpServer.auth=true' \
-s 'smtpServer.starttls=false' \
-s 'smtpServer.ssl=true'

sleep 2

echo "Enabaling Brute Force Detection.."

scripts/kcadm.sh update realms/$REALM \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-s bruteForceProtected="true"

#password policy not required on keycloak end
#scripts/kcadm.sh update realms/$REALM \
#-s 'passwordPolicy="forceExpiredPasswordChange(90) and specialChars(1) and upperCase(1) and lowerCase(1) and length(10) and passwordHistory(3) and hashAlgorithm(pbkdf2-sha512) and hashIterations(27500) and digits(1)"' \
#--server $KEYCLOAK_SERVER \
#--realm=master \
#--user $KEYCLOAK_USER \
#--password $KEYCLOAK_PASSWORD

sleep 3

echo "Creating realm role common..."
scripts/kcadm.sh create roles \
-r $REALM \
-s name=common \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD

sleep 2

echo "Creating realm role admins..."
scripts/kcadm.sh create roles \
-r $REALM \
-s name=admins \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD

sleep 2

echo "Creating LDAP provider for users..."
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s id=$randomUid \
-s name=sdp-ldap-users \
-s providerId=ldap \
-s providerType=org.keycloak.storage.UserStorageProvider \
-s parentId=$REALM_ID \
-s 'config.priority=["0"]' \
-s 'config.fullSyncPeriod=["-1"]' \
-s 'config.changedSyncPeriod=["-1"]' \
-s 'config.cachePolicy=["DEFAULT"]' \
-s 'config.evictionDay=[]' \
-s 'config.evictionHour=[]' \
-s 'config.evictionMinute=[]' \
-s 'config.maxLifespan=[]' \
-s 'config.batchSizeForSync=["1000"]' \
-s 'config.editMode=["WRITABLE"]' \
-s 'config.syncRegistrations=["true"]' \
-s 'config.vendor=["other"]' \
-s 'config.usernameLDAPAttribute=["mail"]' \
-s 'config.rdnLDAPAttribute=["uid"]' \
-s 'config.uuidLDAPAttribute=["entryUUID"]' \
-s 'config.userObjectClasses=["inetOrgPerson, organizationalPerson, top, person, posixAccount, inetuser"]' \
-s 'config.connectionUrl=["'$LDAPHOST'"]' \
-s 'config.usersDn=["'$LDAPUSERDN'"]' \
-s 'config.authType=["simple"]' \
-s 'config.bindDn=["'$LDAPBINDDN'"]' \
-s 'config.bindCredential=["'$LDAPPASSWORD'"]' \
-s 'config.searchScope=["2"]' \
-s 'config.validatePasswordPolicy=["true"]' \
-s 'config.useTruststoreSpi=["ldapsOnly"]' \
-s 'config.connectionPooling=["true"]' \
-s 'config.pagination=["true"]' \
-s 'config.allowKerberosAuthentication=["false"]' \
-s 'config.debug=["true"]' \
-s 'config.useKerberosForPasswordAuthentication=["false"]'

sleep 2

echo "Creating LDAP provider for groups..."
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s id=$LdapGroupProvider \
-s name=sdp-ldap-groups \
-s providerId=ldap \
-s providerType=org.keycloak.storage.UserStorageProvider \
-s parentId=$REALM_ID \
-s 'config.priority=["0"]' \
-s 'config.fullSyncPeriod=["-1"]' \
-s 'config.changedSyncPeriod=["-1"]' \
-s 'config.cachePolicy=["DEFAULT"]' \
-s 'config.evictionDay=[]' \
-s 'config.evictionHour=[]' \
-s 'config.evictionMinute=[]' \
-s 'config.maxLifespan=[]' \
-s 'config.batchSizeForSync=["1000"]' \
-s 'config.editMode=["WRITABLE"]' \
-s 'config.syncRegistrations=["true"]' \
-s 'config.vendor=["other"]' \
-s 'config.usernameLDAPAttribute=["mail"]' \
-s 'config.rdnLDAPAttribute=["uid"]' \
-s 'config.uuidLDAPAttribute=["entryUUID"]' \
-s 'config.userObjectClasses=["organizationalUnit, top"]' \
-s 'config.connectionUrl=["'$LDAPHOST'"]' \
-s 'config.usersDn=["'$LDAPGROUPDN'"]' \
-s 'config.authType=["simple"]' \
-s 'config.bindDn=["'$LDAPBINDDN'"]' \
-s 'config.bindCredential=["'$LDAPPASSWORD'"]' \
-s 'config.searchScope=["2"]' \
-s 'config.useTruststoreSpi=["ldapsOnly"]' \
-s 'config.connectionPooling=["true"]' \
-s 'config.pagination=["true"]' \
-s 'config.allowKerberosAuthentication=["false"]' \
-s 'config.debug=["true"]' \
-s 'config.useKerberosForPasswordAuthentication=["false"]'

sleep 2

# Add mappers to LDAP Provider for users
echo "Creating LDAP Mapper for homeDirectory"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=homeDirectory \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["homeDirectory"]' \
-s 'config."ldap.attribute"=["homeDirectory"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for uid"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=ldap-uid \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["ldap-uid"]' \
-s 'config."ldap.attribute"=["uid"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for uidNumber"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=uidNumber \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["uidNumber"]' \
-s 'config."ldap.attribute"=["uidNumber"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for gidNumber"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=gidNumber \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["gidNumber"]' \
-s 'config."ldap.attribute"=["gidNumber"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for loginShell"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=loginShell \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["loginShell"]' \
-s 'config."ldap.attribute"=["loginShell"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for defaultmode"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=defaultmode \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["defaultmode"]' \
-s 'config."ldap.attribute"=["defaultmode"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for employeeNumber"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=employeeNumber \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["employeeNumber"]' \
-s 'config."ldap.attribute"=["employeeNumber"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for memberof"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=memberof \
-s providerId=user-attribute-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."user.model.attribute"=["memberOf"]' \
-s 'config."ldap.attribute"=["memberOf"]' \
-s 'config."read.only"=["false"]' \
-s 'config."always.read.value.from.ldap"=["false"]' \
-s 'config."is.mandatory.in.ldap"=["false"]'

sleep 2

echo "Creating LDAP Mapper for group"
scripts/kcadm.sh create components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name=group \
-s providerId=role-ldap-mapper \
-s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper \
-s parentId=$randomUid \
-s 'config."mode"=["LDAP_ONLY"]' \
-s 'config."membership.attribute.type"=["DN"]' \
-s 'config."user.roles.retrieve.strategy"=["LOAD_ROLES_BY_MEMBER_ATTRIBUTE"]' \
-s 'config."roles.dn"=["'$LDAPGROUPDN'"]' \
-s 'config."membership.ldap.attribute"=["member"]' \
-s 'config."membership.user.ldap.attribute"=["memberOf"]' \
-s 'config."role.name.ldap.attribute"=["cn"]' \
-s 'config."use.realm.roles.mapping"=["true"]' \
-s 'config."role.object.classes"=["groupOfNames"]'

sleep 2

echo "Update FirstName mapper"

value=$(scripts/kcadm.sh get components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM | sed -n '/"name" : "sdp-ldap-users",/{x;p;d;}; x' | cut -d'"' -f4)

# Returns ID value of the component
replace=$(scripts/kcadm.sh get components \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-q name='first name' | awk -v N=4 -v pattern='"*'$value'".' '{i=(1+(i%N));if (buffer[i]&& $0 ~ pattern) print buffer[i]; buffer[i]=$0;}' | cut -d'"' -f4)

sleep 2

echo "Replace cn value to givenName"
scripts/kcadm.sh update components/$replace \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s name='first name' \
-s 'config."ldap.attribute"=["givenName"]'

sleep 2

echo "Triggering synchronization of all users for sdp-ldap-users"
scripts/kcadm.sh create user-storage/$randomUid/sync?action=triggerFullSync \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM

sleep 2

echo "Periodic Changed Users Sync & Periodic Full Sync"
scripts/kcadm.sh update components/$randomUid \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s 'config.fullSyncPeriod=[ "86400" ]' \
-s 'config.changedSyncPeriod=["300"]'

sleep 2

echo "Configuring event logging for realm"
scripts/kcadm.sh update events/config \
--server $KEYCLOAK_SERVER \
--realm=master \
--user $KEYCLOAK_USER \
--password $KEYCLOAK_PASSWORD \
-r $REALM \
-s 'eventsListeners=["jboss-logging","events-console","com.larscheidschmitzhermes:keycloak-monitoring-prometheus"]' \
-s eventsEnabled=true \
-s 'enabledEventTypes=["SEND_RESET_PASSWORD","REMOVE_TOTP","REVOKE_GRANT","UPDATE_TOTP","LOGIN_ERROR","CLIENT_LOGIN","RESET_PASSWORD_ERROR","IMPERSONATE_ERROR","CODE_TO_TOKEN_ERROR","CUSTOM_REQUIRED_ACTION","RESTART_AUTHENTICATION","IMPERSONATE","UPDATE_PROFILE_ERROR","LOGIN","UPDATE_PASSWORD_ERROR","CLIENT_INITIATED_ACCOUNT_LINKING","TOKEN_EXCHANGE","LOGOUT","REGISTER","CLIENT_REGISTER","IDENTITY_PROVIDER_LINK_ACCOUNT","UPDATE_PASSWORD","CLIENT_DELETE","FEDERATED_IDENTITY_LINK_ERROR","IDENTITY_PROVIDER_FIRST_LOGIN","CLIENT_DELETE_ERROR","VERIFY_EMAIL","CLIENT_LOGIN_ERROR","RESTART_AUTHENTICATION_ERROR","EXECUTE_ACTIONS","REMOVE_FEDERATED_IDENTITY_ERROR","TOKEN_EXCHANGE_ERROR","PERMISSION_TOKEN","SEND_IDENTITY_PROVIDER_LINK_ERROR","EXECUTE_ACTION_TOKEN_ERROR","SEND_VERIFY_EMAIL","EXECUTE_ACTIONS_ERROR","REMOVE_FEDERATED_IDENTITY","IDENTITY_PROVIDER_POST_LOGIN","IDENTITY_PROVIDER_LINK_ACCOUNT_ERROR","UPDATE_EMAIL","REGISTER_ERROR","REVOKE_GRANT_ERROR","EXECUTE_ACTION_TOKEN",
"LOGOUT_ERROR","UPDATE_EMAIL_ERROR","CLIENT_UPDATE_ERROR","UPDATE_PROFILE","CLIENT_REGISTER_ERROR","FEDERATED_IDENTITY_LINK","SEND_IDENTITY_PROVIDER_LINK","SEND_VERIFY_EMAIL_ERROR","RESET_PASSWORD","CLIENT_INITIATED_ACCOUNT_LINKING_ERROR","REMOVE_TOTP_ERROR","VERIFY_EMAIL_ERROR","SEND_RESET_PASSWORD_ERROR","CLIENT_UPDATE","CUSTOM_REQUIRED_ACTION_ERROR","IDENTITY_PROVIDER_POST_LOGIN_ERROR","UPDATE_TOTP_ERROR","CODE_TO_TOKEN","IDENTITY_PROVIDER_FIRST_LOGIN_ERROR"]' \
-s eventsExpiration=259200 \
-s adminEventsEnabled=true \
-s adminEventsDetailsEnabled=true

echo "Keycloak config complete."
