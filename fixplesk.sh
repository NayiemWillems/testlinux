#!/usr/bin/env bash

set -eo pipefail

###############################################################################
# This script restores permissions of a target domain in Plesk
# Requirements : bash 3.x, mysql-client
# Version      : 1.0.1
# Maintainer   : Aleksandr Bashurov
#########

export LANG=C
export LC_ALL=C

###########################################################
# Function `err()`
# Echoes to the `stderr` and finishes script execution
# Input   : $* any number of strings (will be concatenated)
# Output  : None
# Globals : None
err() {
  echo -e "\e[31mERROR\e[m: $*" >&2
  exit 1
}

###########################################################
# Function `warn()`
# Echoes to the `stderr` and continues script execution
# Input   : $* any number of strings (will be concatenated)
# Output  : None
# Globals : None
warn() {
  echo -e "\e[33mWARNING\e[m: $*" >&2
}

###########################################################
# Function `usage()`
# Shows help message
# Input   : None
# Output  : None
# Globals : None
usage() {
    cat <<HELP
Restore permissions of a target domain in Plesk.

Usage:
  $0 [[domain] ...]
    Check if the domain exists in Plesk and restore default permissions for it.
    Note: mode 644 will be used by default for files and 755 for folders.    

HELP
}

###########################################################
# Function `sanity_check_before()`
# Performs crucial sanity checks required for `init()`
# Input   : None
# Output  : None
# Globals : None
sanity_check_before() {
  if [[ ! -e /etc/psa/.psa.shadow ]]; then
    err "Could not find Plesk MySQL password file."
  fi
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root"
  fi
}

###########################################################
# Function `init()`
# Initializes main globals and runs sanity checks
# Input   : None
# Output  : None
# Globals : +FILE_MODE, +DIR_MODE, +DOCROOT_MODE
init() {
  sanity_check_before

  [[ -z ${DIR_MODE}     ]] && DIR_MODE="755"
  [[ -z ${FILE_MODE}    ]] && FILE_MODE="644"
  [[ -z ${DOCROOT_MODE} ]] && DOCROOT_MODE="750"
}

###########################################################
# Function `mysql_query()`
# Runs MySQL query to the Plesk database
# Input   : $1 string (MySQL query)
# Output  : >1 string (results of the MySQL query)
# Globals : None
mysql_query() {
  local query="$1"
  MYSQL_PWD="$(cat /etc/psa/.psa.shadow)" mysql -Ns -uadmin -Dpsa -e"${query}"
}

###########################################################
# Function `permission_restore()`
# Restores ownership and permissions
# Input   : $1 string (domain)
# Output  : None
# Globals : FILE_MODE, DIR_MODE, DOCROOT_MODE
permissions_restore() {
  local query domain="$1" sys_user www_root
  read -r sys_user www_root < <(mysql_query "SELECT s.login, h.www_root \
    FROM domains d, hosting h, sys_users s WHERE s.id = h.sys_user_id   \
    AND h.dom_id = d.id AND d.name = \"${domain}\"")
  sys_user="${sys_user/ /}"
  www_root="${www_root/ /}"
  if [[ -z ${sys_user} || -z ${www_root} ]]; then
    warn "Could not retrieve information about ${domain} from the database"
  else
    find "${www_root}" -type f -exec chown -ch "${sys_user}":psacln {} +
    find "${www_root}" -type d -exec chown -ch "${sys_user}":psacln {} +
    chown "${sys_user}":psaserv "${www_root}"
    find "${www_root}" -type f -exec chmod -c "${FILE_MODE}" {} +
    find "${www_root}" -type d -exec chmod -c "${DIR_MODE}" {} +
    chmod -c "${DOCROOT_MODE}" "${www_root}"
  fi
}

###########################################################
# Function `main()`
# Checks arguments and executes corresponding functions
# Input   : $@ array (Initial args)
# Output  : None
# Globals : None
main() {
  if [[ "$1" == "--help" || "$1" == "-h" || -z "$*" ]]; then
    usage
    exit 1
  fi
  for domain in "$@"; do
    permissions_restore "${domain}"
  done
}

init
main "$@"

