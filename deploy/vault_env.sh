#!/usr/bin/env bash

# Put in the directory used by /sbin/my_init to read env variables from
CONTAINER_ENV_DIR=/etc/container_environment/

if [ -z "${VAULT_ADDR+x}" ]; then
    VAULT_ADDR=http://internal-ops-vault-399726596.eu-west-1.elb.amazonaws.com:8200
    echo "Setting VAULT_ADDR to default value: $VAULT_ADDR"
fi
if [ -z "${VAULT_VERSION+x}" ]; then
    VAULT_VERSION=v1
    echo "Setting VAULT_VERSION to default value: $VAULT_VERSION"
fi

if [ -z"${VAULT_AWS_ENV+x}" ]; then
    VAULT_AWS_ENV=$(echo ${VAULT_PATH} | cut -d'/' -f2)
fi

if [ "$VAULT_AWS_ENV" = "production" ]; then
    VAULT_AWS_MOUNT="prod"
elif [ "$VAULT_AWS_ENV" = "stage" ]; then
    VAULT_AWS_MOUNT="stage"
fi

if [ -f ~/.vault_nonce ]; then
    VAULT_NONCE=$(echo "\"nonce\": \"$(cat ~/.vault_nonce)\",")
else
    VAULT_NONCE=""
fi

# If VAULT variables are not set then do nothing
if [ -n "${VAULT_AWS_MOUNT}" ] && [ -n "${VAULT_PATH}" ]; then
    echo "Starting VAULT environment fetch..."

    RESPONSE=$(curl -sX PUT ${VAULT_ADDR}/${VAULT_VERSION}/auth/aws-dubizzle-${VAULT_AWS_MOUNT}/login -d "{\"role\":\"dubizzle-${VAULT_AWS_MOUNT}-readonly\",${VAULT_NONCE}\"pkcs7\":\"$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/pkcs7 | tr -d \\n)\"}")
    ERROR=$(echo $RESPONSE | jq -r '.errors')
    if [ "${ERROR}" != "null" ]; then
        echo "Error: Provided incorrect credentials (${ERROR})"
        exit 1
    fi
    VAULT_ACCESS_TOKEN=$(echo ${RESPONSE} | jq -r '.auth.client_token')
    echo "Storing nonce in ~/.vault_nonce"
    echo ${RESPONSE} | jq -r '.auth.metadata.nonce' > ~/.vault_nonce

    RESPONSE=$(curl -sH 'X-Vault-Token:'${VAULT_ACCESS_TOKEN}'' ${VAULT_ADDR}/${VAULT_VERSION}/${VAULT_PATH}?list=true)
    ERROR=$(echo $RESPONSE | jq -r '.errors')
    if [ "${ERROR}" != "null" ]; then
        echo "Error: Provided incorrect vault path"
        exit 1
    fi
    KEYS=$(echo ${RESPONSE} | jq -r '.data.keys')

    echo $KEYS | jq -r '.[]' | while read KEY; do
        RESPONSE=$(curl -sH 'X-Vault-Token:'${VAULT_ACCESS_TOKEN}'' ${VAULT_ADDR}/${VAULT_VERSION}/${VAULT_PATH}/${KEY})
        ERROR=$(echo $RESPONSE | jq -r '.errors')
        if [ "${ERROR}" != "null" ]; then
            echo "Something wrong with setting $KEY"
            exit 1
        else
            VALUE=$(echo ${RESPONSE} | jq -r '.data.value')
            echo "Exporting ${KEY}"
            if [ ${KEY} == "TARGETS" ]; then
                VALUE=$(sed -r 's/"/\\"/g' <<< ${VALUE})
            fi
            echo "export ${KEY}=\"${VALUE}\"" >> /etc/container_environment.sh
        fi
    done
    echo "VAULT environment fetch is finished!"
else
    echo "No VAULT credentials found, skipping import."
fi
