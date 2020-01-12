#!/usr/bin/env bash

source /vault_env.sh
source /etc/container_environment.sh

./telegraf --config /etc/telegraf.conf
