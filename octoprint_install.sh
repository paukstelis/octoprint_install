#!/bin/bash

#all operations must be with root/sudo
if (($EUID != 0)); then
    echo "Please run with sudo"
    exit
fi

#this is a weak check, but will catch most cases
if [ $SUDO_USER ]; then
    user=$SUDO_USER
else
    echo "You should not run this script as root. Use sudo as a normal user"
    exit
fi

if [ "$user" == root ]; then
    echo "You should not run this script as root. Use sudo as a normal user"
    exit
fi

SCRIPTDIR=$(dirname $(readlink -f $0))

# from stackoverflow.com/questions/3231804
prompt_confirm() {
    while true; do
        read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
        case $REPLY in
            [yY])
                echo
                return 0
            ;;
            [nN])
                echo
                return 1
            ;;
            *) printf " \033[31m %s \n\033[0m" "invalid input" ;;
        esac
    done
}

echo "octoprint_install has reached end-of-life and has been replaced by octoprint_deploy"
if prompt_confirm "Do you want to use octoprint_deploy instead?"; then
    sudo -u $user git clone https://github.com/paukstelis/octoprint_deploy /home/$user/octoprint_deploy
    echo "Cloning octoprint_deploy into /home/$user/octoprint_deploy"
    echo "To use octoprint_deploy, run the command sudo octoprint_deploy/octoprint_deploy.sh and follow the instructions"
fi