#!/usr/bin/env bash

# Copyright (C) 2015-2016 Wazuh, Inc.All rights reserved.
# Wazuh.com
# This program is a free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public
# License (version 2) as published by the FSF - Free Software
# Foundation.

# Installer for Wazuh-API
# Wazuh Inc.
#
# Instructions:
#  List dependencies.
#    ./install_api.sh dependencies
#  Install last release (download lastest release)
#    ./install_api.sh
#  Install API from path
#    ./install_api.sh /path/to/api
#  Install API development mode
#    git clone https://github.com/wazuh/wazuh-API.git
#    cd wazuh-API
#    [git checkout <branch>]
#    ./install_api.sh dev  : Install API from current path, development mode


arg=$1  # emtpy, path or dev

# Aux functions
print() {
    echo -e $1
}

error_and_exit() {
    print "Error executing command: '$1'.\nExiting."
    exit 1
}

exec_cmd() {
    eval $1 > /dev/null 2>&1 || error_and_exit "$1"
}

exec_cmd_bash() {
    bash -c "$1" || error_and_exit "$1"
}

get_configuration_value () { # $1 setting
    cat "$API_PATH/configuration/config.js" | grep -P "config.$1\s*=\s*\"" | grep -P '".*"' -o | tr -d '"'
}

edit_configuration() { # $1 -> setting,  $2 -> value
    sed -i "s/^config.$1\s=.*/config.$1 = \"$2\";/g" "$API_PATH/configuration/config.js" || error_and_exit "sed (editing configuration)"
}

get_type_service() {
    if [ -n "$(ps -e | egrep ^\ *1\ .*systemd$)" ]; then
        echo "systemctl"
    else
        echo "service"
    fi
}

url_lastest_release () {
    LATEST_RELEASE=$(curl -L -s -H 'Accept: application/json' https://github.com/$1/$2/releases/latest)
    LATEST_VERSION=$(echo $LATEST_RELEASE | sed -e 's/.*"tag_name":"\(.*\)".*/\1/')
    ARTIFACT_URL="https://github.com/$1/$2/archive/$LATEST_VERSION.tar.gz"
    echo $ARTIFACT_URL
}

check_program_installed() {
    hash $1 > /dev/null 2>&1
    if [ "$?" != "0" ]; then
        print "$1 not found. is it installed?."
        print "Check the dependencies executing: ./install_api.sh dependencies"
        exit 1
    fi
}

# END Aux functions

show_info () {
    https=$(get_configuration_value "https")
    port=$(get_configuration_value "port")
    basic_auth=$(get_configuration_value "basic_auth")

    if [ "X${https}" == "Xyes" ]; then
        proto="https"
    else
        proto="http"
    fi

    print "\nAPI URL: $proto://localhost:$port/"
    if [ "X${update}" != "Xyes" ]; then
        print "user: 'foo'"
        print "password: 'bar'"
    fi
    if [ "X${basic_auth}" == "Xno" ]; then
        print "Authentication disabled (not secure)."
    fi
    print "Configuration: $API_PATH/configuration"
}

required_packages() {
    print "\nDebian and Ubuntu based Linux distributions:"
    print "\tsudo apt-get install -y python-pip"
    print "\tNodeJS 4.x or newer:"
    print "\t\tcurl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash -"
    print "\t\tsudo apt-get install -y nodejs"

    print "\nRed Hat, CentOS and Fedora:"
    print "\tsudo yum install -y python-pip"
    print "\tNodeJS 4.x or newer:"
    print "\t\tcurl --silent --location https://rpm.nodesource.com/setup_4.x | bash -"
    print "\t\tsudo yum -y install nodejs"
}

previous_checks() {
    # Arguments
    if [ "X${arg}" == "Xdependencies" ]; then
        required_packages
        exit 0
    elif [ "X${arg}" == "Xdev" ]; then  # Dev argument
        API_SOURCES=`pwd`
    elif [ "X${arg}" == "X" ]; then   # No argument
        API_SOURCES="/root"
        DOWNLOAD_PATH=$(url_lastest_release "wazuh" "Wazuh-API")
    else
        API_SOURCES=$arg  # Path argument
    fi

    # Test root permissions
    if [ "$USER" != "root" ]; then
        print "Please run this script with root permissions.\nExiting."
        exit 1
    fi

    # Paths
    OSSEC_CONF="/etc/ossec-init.conf"
    DEF_OSSDIR="/var/ossec"

    if ! [ -f $OSSEC_CONF ]; then
        print "Can't find $OSSEC_CONF. Is OSSEC installed?.\nExiting."
        exit 1
    fi

    . $OSSEC_CONF

    if [ -z "$DIRECTORY" ]; then
        DIRECTORY=$DEF_OSSDIR
    fi

    API_PATH="${DIRECTORY}/api"
    API_PATH_BACKUP="${DIRECTORY}/~api"
    FRAMEWORK_PATH="${DIRECTORY}/framework"
    serv_type=$(get_type_service)

    # Dependencies
    check_program_installed "tar"
    check_program_installed "curl"
    check_program_installed "pip"

    NODE_DIR=$(which nodejs 2> /dev/null)

    if [ "X$NODE_DIR" = "X" ]; then
        NODE_DIR=$(which node 2> /dev/null)

        if [ "X$NODE_DIR" = "X" ]; then
            echo "NodeJS binaries not found. Is NodeJS installed?"
            exit 1
        fi
    fi

    NODE_VERSION=`$NODE_DIR --version | grep -P '^v\d+' -o | grep -P '\d+' -o`

    if [ $NODE_VERSION -lt 4 ]; then
        print "The current version of NodeJS installed is not supported. Wazuh-API requires NodeJS 4.x or newer."
        print "Review the dependencies executing: ./install_api.sh dependencies"
        exit 1
    fi

    check_program_installed "npm"
}

get_api () {
    if [ "X$DOWNLOAD_PATH" != "X" ]; then
        print "\nDownloading API from $DOWNLOAD_PATH"

        if [ -d "$API_SOURCES/wazuh-API" ]; then
            exec_cmd "rm -rf $API_SOURCES/wazuh-API"
        fi

        exec_cmd "mkdir -p $API_SOURCES/wazuh-API && curl -sL $DOWNLOAD_PATH | tar xvz -C $API_SOURCES/wazuh-API"

        API_SOURCES="$API_SOURCES/wazuh-API/wazuh-API-*.*"
    else
        if [ "X${arg}" == "Xdev" ]; then
            print "\nInstalling Wazuh-API from current directory [$API_SOURCES] [DEV MODE]"
        else
            print "\nInstalling Wazuh-API from current directory [$API_SOURCES]"
        fi
    fi
}

install_framework() {
    print "\nInstalling dependencies: xmljson."
    print "-----------------------------------------------------------------"
    exec_cmd_bash "pip install xmljson"
    print "-----------------------------------------------------------------"
    #FRAMEWORK_SOURCES="$API_SOURCES/framework"

    #print "\nFramework."
    #print "-----------------------------------------------------------------"
    #if [ "X${arg}" == "Xdev" ]; then
    #    exec_cmd_bash "pip install -e $FRAMEWORK_SOURCES"
    #else
    #    exec_cmd_bash "pip install $FRAMEWORK_SOURCES --ignore-installed"
    #fi
    #print "-----------------------------------------------------------------"

    ## Check
    #`python -c 'import wazuh'`
    #RC=$?
    #if [[ $RC != 0 ]]; then
    #    print "Error installing Wazuh Framework.\nExiting."
    #    exit 1
    #fi

    #print "Framework ready."
}

backup_api () {
    if [ -e $API_PATH_BACKUP ]; then
        exec_cmd "rm -rf $API_PATH_BACKUP"
    fi

    exec_cmd "cp -rLfp $API_PATH $API_PATH_BACKUP"
    exec_cmd "chown root:root $API_PATH_BACKUP"
}

restore_configuration () {
    API_OLD_VERSION=`cat $API_PATH_BACKUP/package.json | grep "version\":" | grep -P "\d+(?:\.\d+){0,2}" -o`

    if [ "X${API_OLD_VERSION}" == "X1.3.0" ]; then
        exec_cmd "rm -rf $API_PATH/configuration"
        exec_cmd "cp -rfp $API_PATH_BACKUP/configuration $API_PATH/configuration"
    elif [ "X${API_OLD_VERSION}" == "X1.1" ] || [ "X${API_OLD_VERSION}" == "X1.2.0" ] || [ "X${API_OLD_VERSION}" == "X1.2.1" ]; then
        exec_cmd "cp -rfp $API_PATH_BACKUP/ssl/htpasswd $API_PATH/configuration/auth/htpasswd"
        exec_cmd "cp -p $API_PATH_BACKUP/ssl/*.key $API_PATH_BACKUP/ssl/*.crt $API_PATH/configuration/ssl/"
        RESTORE_WARNING="1"
    else
        RESTORE_WARNING="2"
    fi
}

setup_api() {
    # Check if API is installed
    update="no"
    if [ -d $API_PATH ]; then
        backup_api
        print ""
        while true; do
            read -p "Wazuh-API is already installed. Do you want to update it? [y/n]: " yn
            case $yn in
                [Yy] ) update="yes"; break;;
                [Nn] ) update="no"; break;;
            esac
        done

        if [ "X${update}" == "Xno" ]; then
            while true; do
                print ""
                read -p "The installation directory already exists. Should I delete it? [y/n]: " yn
                case $yn in
                    [Yy] ) break;;
                    [Nn] ) print "Not possible to install the API.\nExiting."; exit 1; break;;
                esac
            done
        fi

        exec_cmd "rm -rf $API_PATH"
    fi

    # Copy files
    if [ "X${update}" == "Xyes" ]; then
        print "\nUpdating API ['$API_PATH']."
        e_msg="updated"
    else
        print "\nInstalling API ['$API_PATH']."
        e_msg="installed"
    fi
    if [ "X${arg}" == "Xdev" ]; then
        exec_cmd "ln -s $API_SOURCES $API_PATH"
    else
        exec_cmd "mkdir $API_PATH"
        exec_cmd "cp --parents -r app.js configuration controllers examples framework/examples framework/wazuh helpers models package.json scripts $API_PATH"

        # General permissions
        exec_cmd "chown -R ossec:ossec $API_PATH"
        exec_cmd "chown -R root:root $API_PATH/scripts"
        exec_cmd "chmod -R 500 $API_PATH"

        # Remove execution permissions
        exec_cmd "chmod u-x $API_PATH/package.json"
        exec_cmd "chmod u-x $API_PATH/configuration/ssl/*"
        exec_cmd "chmod u-x $API_PATH/scripts/wazuh-api*"
    fi

    if [ "X${update}" == "Xyes" ]; then
        restore_configuration
    fi

    install_framework

    print "\nInstalling NodeJS modules."
    if [ "X${arg}" == "Xdev" ]; then
        exec_cmd "cd $API_PATH && npm install"
    else
        exec_cmd "cd $API_PATH && npm install --production"
    fi
    exec_cmd "chown -R ossec:ossec $API_PATH/node_modules"
    exec_cmd "chmod -R go-rwx $API_PATH/node_modules"
    exec_cmd "chmod -R u-w $API_PATH/node_modules"


    # Set OSSEC directory in API configuration
    if [ "X${DIRECTORY}" != "X/var/ossec" ]; then
        repl="\\\/"
        escaped_ossec_path=`echo "$DIRECTORY" | sed -e "s#\/#$repl#g"`
        edit_configuration "ossec_path" $escaped_ossec_path
    fi

    print "\nInstalling service."
    echo "----------------------------------------------------------------"
    exec_cmd_bash "$API_PATH/scripts/install_daemon.sh"
    echo "----------------------------------------------------------------"
}

main() {
    print "### Wazuh-API ###"
    previous_checks
    get_api
    setup_api
    show_info

    if [ "X${RESTORE_WARNING}" == "X1" ]; then
        print "\nWarning: Some problems occured when restoring your previous configuration ($API_PATH/configuration/config.js). Please, review it manually. Backup directory: $API_PATH_BACKUP."
    elif [ "X${RESTORE_WARNING}" == "X2" ]; then
        print "\nWarning: Some problems occured when restoring your previous configuration. Please, review it manually. Backup directory: $API_PATH_BACKUP."
    fi

    print "Note: You can configure the API executing $API_PATH/scripts/configure_api.sh"

    print "\n### [API $e_msg successfully] ###"
    exit 0
}

# Main
main
