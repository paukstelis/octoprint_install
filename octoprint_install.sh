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
source $SCRIPTDIR/plugins.sh

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

get_settings() {
    #Get octoprint_deploy settings, all of which are written on system prepare
    if [ -f /etc/octoprint_deploy ]; then
        TYPE=$(cat /etc/octoprint_deploy | sed -n -e 's/^type: \(\.*\)/\1/p')
        STREAMER=$(cat /etc/octoprint_deploy | sed -n -e 's/^streamer: \(\.*\)/\1/p')
        HAPROXY=$(cat /etc/octoprint_deploy | sed -n -e 's/^haproxy: \(\.*\)/\1/p')
    fi
    OCTOEXEC="sudo -u $user /home/$user/OctoPrint/bin/octoprint"
    OCTOCONFIG="/home/$user"
}

#https://askubuntu.com/questions/39497
deb_packages() {
    #All extra packages needed can be added here for deb based systems. Only available will be selected.
    apt-cache --generate pkgnames |
        grep --line-regexp --fixed-strings \
            -e make \
            -e v4l-utils \
            -e python-is-python3 \
            -e python3-venv \
            -e python3.9-venv \
            -e python3.10-venv \
            -e virtualenv \
            -e python3-dev \
            -e build-essential \
            -e python3-setuptools \
            -e libyaml-dev \
            -e python3-pip \
            -e cmake \
            -e libjpeg8-dev \
            -e libjpeg62-turbo-dev \
            -e gcc \
            -e g++ \
            -e libevent-dev \
            -e libjpeg-dev \
            -e libbsd-dev \
            -e ffmpeg \
            -e uuid-runtime -e ssh -e libffi-dev -e haproxy -e ssl-cert | xargs apt-get install -y

    #pacakges to REMOVE go here
    apt-cache --generate pkgnames |
        grep --line-regexp --fixed-strings \
            -e brltty |
        xargs apt-get remove -y

}

prepare() {
    echo
    echo
    PS3='OS type: '
    options=("Ubuntu 20-22, Mint, Debian, Raspberry Pi OS" "Fedora/CentOS" "ArchLinux" "Quit")
    select opt in "${options[@]}"; do
        case $opt in
        "Ubuntu 20-22, Mint, Debian, Raspberry Pi OS")
            INSTALL=2
            break
            ;;
        "Fedora/CentOS")
            INSTALL=3
            break
            ;;
        "ArchLinux")
            INSTALL=4
            break
            ;;
        "Quit")
            exit 1
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done

    echo
    echo
    if prompt_confirm "Ready to begin?"; then
        #remove streamer directories, if they exist
        remove_everything

        echo 'Adding current user to dialout and video groups.'
        usermod -a -G dialout,video $user

        if [ $INSTALL -gt 1 ]; then
            OCTOEXEC="sudo -u $user /home/$user/OctoPrint/bin/octoprint"
            OCTOPIP="sudo -u $user /home/$user/OctoPrint/bin/pip"
            echo "Adding systemctl and reboot to sudo"
            echo "$user ALL=NOPASSWD: /usr/bin/systemctl" >/etc/sudoers.d/octoprint_systemctl
            echo "$user ALL=NOPASSWD: /usr/sbin/reboot" >/etc/sudoers.d/octoprint_reboot
            echo "$user ALL=NOPASSWD: /usr/sbin/shutdown" >/etc/sudoers.d/octoprint_shutdown
            echo "This will install necessary packages, download and install OctoPrint on this machine."
            #install packages
            #All DEB based
            PYVERSION=${PYVERSION:-python3}
            if [ $INSTALL -eq 2 ]; then
                apt-get update >/dev/null
                deb_packages
            fi

            #Fedora35/CentOS
            if [ $INSTALL -eq 3 ]; then
                dnf -y install gcc python3-devel cmake libjpeg-turbo-devel libbsd-devel libevent-devel haproxy openssh openssh-server openssl libffi-devel
                systemctl enable sshd.service
                PYV=$(python3 -c"import sys; print(sys.version_info.minor)")
                if [ $PYV -eq 11 ]; then
                    dnf -y install python3.10-devel
                    PYVERSION=${PYVERSION:-python3.10}
                fi
            fi

            #ArchLinux
            if [ $INSTALL -eq 4 ]; then
                pacman -S --noconfirm make cmake python python-virtualenv libyaml python-pip libjpeg-turbo python-yaml python-setuptools libffi ffmpeg gcc libevent libbsd openssh haproxy v4l-utils
                usermod -a -G uucp $user
            fi

            echo "Enabling ssh server..."
            systemctl enable ssh.service
            echo "Installing OctoPrint virtual environment in /home/$user/OctoPrint"
            #make venv
            sudo -u $user $PYVERSION -m venv /home/$user/OctoPrint
            #update pip
            sudo -u $user /home/$user/OctoPrint/bin/pip install --upgrade pip
            #pre-install wheel
            sudo -u $user /home/$user/OctoPrint/bin/pip install wheel
            #install oprint
            sudo -u $user /home/$user/OctoPrint/bin/pip install OctoPrint
            #start server and run in background
            echo 'Creating OctoPrint service...'
            cat $SCRIPTDIR/octoprint_generic.service |
                sed -e "s/OCTOUSER/$user/" \
                    -e "s#OCTOPATH#/home/$user/OctoPrint/bin/octoprint#" \
                    -e "s#OCTOCONFIG#/home/$user/#" \
                    -e "s/NEWINSTANCE/octoprint/" \
                    -e "s/NEWPORT/5000/" >/etc/systemd/system/octoprint.service

            #Haproxy
            echo
            echo
            echo 'You have the option of setting up haproxy.'
            echo 'This binds instance to a name on port 80 instead of having to type the port.'
            echo
            echo
            if prompt_confirm "Use haproxy?"; then
                systemctl stop haproxy
                #get haproxy version
                echo 'haproxy: true' >>/etc/octoprint_deploy
                HAversion=$(haproxy -v | sed -n 's/^.*version \([0-9]\).*/\1/p')
                mv /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.orig
                if [ $HAversion -gt 1 ]; then
                    cp $SCRIPTDIR/haproxy2x.basic /etc/haproxy/haproxy.cfg
                else
                    cp $SCRIPTDIR/haproxy1x.basic /etc/haproxy/haproxy.cfg
                fi
                systemctl start haproxy
                systemctl enable haproxy
            else
                systemctl stop haproxy
                systemctl disable haproxy
            fi

            echo
            echo
            echo
            PS3='Which video streamer you would like to install?: '
            options=("mjpeg-streamer" "ustreamer (Recommended)" "None")
            select opt in "${options[@]}"; do
                case $opt in
                "mjpeg-streamer")
                    VID=1
                    break
                    ;;
                "ustreamer (Recommended)")
                    VID=2
                    break
                    ;;
                "None")
                    VID=3
                    break
                    ;;
                *) echo "invalid option $REPLY" ;;
                esac
            done

            if [ $VID -eq 1 ]; then
                echo 'streamer: mjpg-streamer' >>/etc/octoprint_deploy
                #install mjpg-streamer, not doing any error checking or anything
                echo 'Installing mjpeg-streamer'
                sudo -u $user git clone --depth=1 https://github.com/jacksonliam/mjpg-streamer.git mjpeg
                #apt -y install
                sudo -u $user make -C mjpeg/mjpg-streamer-experimental >/dev/null
                sudo -u $user mv mjpeg/mjpg-streamer-experimental /home/$user/mjpg-streamer
                sudo -u $user rm -rf mjpeg
            fi

            if [ $VID -eq 2 ]; then
                echo 'streamer: ustreamer' >>/etc/octoprint_deploy
                #install ustreamer
                sudo -u $user git clone --depth=1 https://github.com/pikvm/ustreamer
                sudo -u $user make -C ustreamer >/dev/null
            fi

            if [ $VID -eq 3 ]; then
                echo 'streamer: none' >>/etc/octoprint_deploy
                echo "Good for you! Cameras are just annoying anyway."
            fi

            #Fedora has SELinux on by default (and is very annoying) so must make adjustments
            if [ $INSTALL -eq 3 ]; then
                semanage fcontext -a -t bin_t "/home/$user/OctoPrint/bin/.*"
                chcon -Rv -u system_u -t bin_t "/home/$user/OctoPrint/bin/"
                restorecon -R -v /home/$user/OctoPrint/bin

                if [ $VID -eq 1 ]; then
                    semanage fcontext -a -t bin_t "/home/$user/mjpg-streamer/.*"
                    chcon -Rv -u more sysystem_u -t bin_t "/home/$user/mjpg-streamer/"
                    restorecon -R -v /home/$user/mjpg-streamer
                fi
                if [ $VID -eq 2 ]; then
                    semanage fcontext -a -t bin_t "/home/$user/ustreamer/.*"
                    chcon -Rv -u system_u -t bin_t "/home/$user/ustreamer/"
                    restorecon -R -v /home/$user/ustreamer
                fi

            fi

            #Prompt for admin user and firstrun stuff
            firstrun
            echo 'Starting OctoPrint service on port 5000'
            #server restart commands
            $OCTOEXEC config set server.commands.serverRestartCommand 'sudo systemctl restart octoprint'
            $OCTOEXEC config set server.commands.systemRestartCommand 'sudo reboot'
            $OCTOEXEC config set server.commands.systemShutdownCommand 'sudo shutdown now'
            systemctl start octoprint.service
            systemctl enable octoprint.service
            echo
            echo

            if prompt_confirm "Would you like to install recommended plugins now?"; then
                plugin_menu
            fi
            echo

            #this restart seems necessary in some cases
            systemctl restart octoprint.service
        fi
        touch /etc/camera_ports
        echo "System preparation complete!"

    fi
    main_menu
}

firstrun() {
    echo
    echo
    echo 'OctoPrint can be configured at this time.'
    echo 'This includes setting up the admin user and finishing the startup wizards.'
    echo
    echo
    if prompt_confirm "Do you want to setup your admin user now?"; then
        echo 'Enter admin user name (no spaces): '
        read OCTOADMIN
        if [ -z "$OCTOADMIN" ]; then
            echo -e "No admin user given! Defaulting to: \033[0;31moctoadmin\033[0m"
            OCTOADMIN=octoadmin
        fi
        echo "Admin user: $OCTOADMIN"
        echo 'Enter admin user password (no spaces): '
        read OCTOPASS
        if [ -z "$OCTOPASS" ]; then
            echo -e "No password given! Defaulting to: \033[0;31mfooselrulz\033[0m. Please CHANGE this."
            OCTOPASS=fooselrulz
        fi
        echo "Admin password: $OCTOPASS"
        $OCTOEXEC user add $OCTOADMIN --password $OCTOPASS --admin
    fi
    echo
    echo
    echo "The script can complete the first run wizards now. For more information on these, see the OctoPrint website."
    echo "It is standard to accept these, as no identifying information is exposed through their usage."
    echo
    echo
    if prompt_confirm "Do first run wizards now?"; then
        $OCTOEXEC config set server.firstRun false --bool
        $OCTOEXEC config set server.seenWizards.backup null
        $OCTOEXEC config set server.seenWizards.corewizard 4 --int

        if prompt_confirm "Enable online connectivity check?"; then
            $OCTOEXEC config set server.onlineCheck.enabled true --bool
        else
            $OCTOEXEC config set server.onlineCheck.enabled false --bool
        fi

        if prompt_confirm "Enable plugin blacklisting?"; then
            $OCTOEXEC config set server.pluginBlacklist.enabled true --bool
        else
            $OCTOEXEC config set server.pluginBlacklist.enabled false --bool
        fi

        if prompt_confirm "Enable anonymous usage tracking?"; then
            $OCTOEXEC config set plugins.tracking.enabled true --bool
        else
            $OCTOEXEC config set plugins.tracking.enabled false --bool
        fi

        if prompt_confirm "Use default printer (can be changed later)?"; then
            $OCTOEXEC config set printerProfiles.default _default
        fi
    fi

}

write_camera() {

    get_settings
    if [ -z "$STREAMER" ]; then
        STREAMER="mjpg-streamer"
    fi

    #mjpg-streamer
    if [ "$STREAMER" == mjpg-streamer ]; then
        cat $SCRIPTDIR/octocam_mjpg.service |
            sed -e "s/OCTOUSER/$user/" \
                -e "s/OCTOCAM/cam_$INSTANCE/" \
                -e "s/RESOLUTION/$RESOLUTION/" \
                -e "s/FRAMERATE/$FRAMERATE/" \
                -e "s/CAMPORT/$CAMPORT/" >$SCRIPTDIR/cam_$INSTANCE.service
    fi

    #ustreamer
    if [ "$STREAMER" == ustreamer ]; then
        cat $SCRIPTDIR/octocam_ustream.service |
            sed -e "s/OCTOUSER/$user/" \
                -e "s/OCTOCAM/cam_$INSTANCE/" \
                -e "s/RESOLUTION/$RESOLUTION/" \
                -e "s/FRAMERATE/$FRAMERATE/" \
                -e "s/CAMPORT/$CAMPORT/" >$SCRIPTDIR/cam_$INSTANCE.service
    fi

    mv $SCRIPTDIR/cam_$INSTANCE.service /etc/systemd/system/
    echo $CAMPORT >>/etc/camera_ports

    #config.yaml modifications
    echo "webcam:" >>$OCTOCONFIG/.$INSTANCE/config.yaml
    echo "    snapshot: http://localhost:$CAMPORT?action=snapshot" >>$OCTOCONFIG/.$INSTANCE/config.yaml
    if [ -z "$CAMHAPROXY" ]; then
        echo "    stream: http://$(hostname).local:$CAMPORT?action=stream" >>$OCTOCONFIG/.$INSTANCE/config.yaml
    else
        echo "    stream: /cam_$INSTANCE/?action=stream" >>$OCTOCONFIG/.$INSTANCE/config.yaml
    fi

    $OCTOEXEC --basedir /home/$user/.octoprint config append_value --json system.actions "{\"action\": \"Reset video streamer\", \"command\": \"sudo systemctl restart cam_$INSTANCE\", \"name\": \"Restart webcam\"}"
    #Either Serial number or USB port
    #Serial Number
    if [ -n "$CAM" ]; then
        echo SUBSYSTEM==\"video4linux\", ATTRS{serial}==\"$CAM\", ATTR{index}==\"0\", SYMLINK+=\"cam_$INSTANCE\" >>/etc/udev/rules.d/99-octoprint.rules
    fi

    #USB port camera
    if [ -n "$USBCAM" ]; then
        echo SUBSYSTEM==\"video4linux\",KERNELS==\"$USBCAM\", SUBSYSTEMS==\"usb\", ATTR{index}==\"0\", DRIVERS==\"uvcvideo\", SYMLINK+=\"cam_$INSTANCE\" >>/etc/udev/rules.d/99-octoprint.rules
    fi

    if [ -n "$CAMHAPROXY" ]; then
        HAversion=$(haproxy -v | sed -n 's/^.*version \([0-9]\).*/\1/p')
        #find frontend line, do insert
        sed -i "/option forwardfor except 127.0.0.1/a\        use_backend cam_$INSTANCE if { path_beg /cam_$INSTANCE/ }" /etc/haproxy/haproxy.cfg
        echo "#cam_$INSTANCE start" >>/etc/haproxy/haproxy.cfg
        echo "backend cam_$INSTANCE" >>/etc/haproxy/haproxy.cfg
        if [ $HAversion -gt 1 ]; then
            echo "       http-request replace-path /cam_$INSTANCE/(.*)   /\1" >>/etc/haproxy/haproxy.cfg
            echo "       server webcam1 127.0.0.1:$CAMPORT" >>/etc/haproxy/haproxy.cfg
        else
            echo "       reqrep ^([^\ :]*)\ /cam_$INSTANCE/(.*) \1\ /\2" >>/etc/haproxy/haproxy.cfg
            echo "       server webcam1 127.0.0.1:$CAMPORT" >>/etc/haproxy/haproxy.cfg
        fi
        echo "#cam_$INSTANCE stop" >>/etc/haproxy/haproxy.cfg
        systemctl restart haproxy
    fi

    udevadm control --reload-rules
    udevadm trigger

    if prompt_confirm "OctoPrint must restart for camera changes to take affect. Restart now?"; then
        systemctl restart octoprint
    fi
}

add_camera() {
    get_settings
    if [ $SUDO_USER ]; then user=$SUDO_USER; fi
    echo 'Adding USB camera'
    INSTANCE='octoprint'

    if [ "$HAPROXY" == true ]; then
        if prompt_confirm "Add cameras to haproxy?"; then
            CAMHAPROXY=1
        fi
    fi

    dmesg -C
    echo "Plug your camera in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$CAM" ]] && [[ $counter -lt 60 ]]; do
        CAM=$(dmesg | sed -n -e 's/^.*SerialNumber: //p')
        TEMPUSBCAM=$(dmesg | sed -n -e 's|^.*input:.*/\(.*\)/input/input.*|\1|p')
        counter=$(($counter + 1))
        if [[ -n "$TEMPUSBCAM" ]] && [[ -z "$CAM" ]]; then
            break
        fi
        sleep 1
    done
    dmesg -C
    #Failed state. Nothing detected
    if [ -z "$CAM" ] && [ -z "$TEMPUSBCAM" ]; then
        echo
        echo -e "\033[0;31mNo camera was detected during the detection period.\033[0m"
        echo
        return
    fi

    if [ -z "$CAM" ]; then
        echo "Camera Serial Number not detected"
        echo -e "Camera will be setup with physical USB address of \033[0;34m $TEMPUSBCAM.\033[0m"
        echo "The camera will have to stay plugged into this location."
        USBCAM=$TEMPUSBCAM
    else
        echo -e "Camera detected with serial number: \033[0;34m $CAM \033[0m"
    fi
    echo "Camera Port (ENTER will increment last value in /etc/camera_ports):"
    read CAMPORT
    if [ -z "$CAMPORT" ]; then
        CAMPORT=$(tail -1 /etc/camera_ports)

        if [ -z "$CAMPORT" ]; then
            CAMPORT=8000
        fi

        CAMPORT=$((CAMPORT + 1))
        echo Selected port is: $CAMPORT
    fi
    echo "Settings can be modified after initial setup in /etc/systemd/system/cam_$INSTANCE"
    echo
    while true; do
        echo "Camera Resolution [default: 640x480]:"
        read RESOLUTION
        if [ -z $RESOLUTION ]; then
            RESOLUTION="640x480"
            break
        elif [[ $RESOLUTION =~ ^[0-9]+x[0-9]+$ ]]; then
            break
        fi
        echo "Invalid resolution"
    done
    echo "Selected camera resolution: $RESOLUTION"
    echo "Camera Framerate (use 0 for ustreamer hardware) [default: 5]:"
    read FRAMERATE
    if [ -z "$FRAMERATE" ]; then
        FRAMERATE=5
    fi
    echo "Selected camera framerate: $FRAMERATE"

    write_camera
    systemctl daemon-reload
    systemctl start cam_$INSTANCE.service
    systemctl enable cam_$INSTANCE.service
    main_menu

}

remove_everything() {
    get_settings
    if [ -f "/etc/octoprint_deploy" ]; then
        rm -f /etc/octoprint_deploy
    fi
    if [ -d "/home/$user/mjpg-streamer" ]; then
        rm -rf /home/$user/mjpg-streamer
    fi
    if [ -d "/home/$user/ustreamer" ]; then
        rm -rf /home/$user/ustreamer
    fi
    if [ -d "/home/$user/.octoprint" ]; then
        rm -rf /home/$user/.octoprint
    fi
    if [ -f "/etc/systemd/system/octoprint.service" ]; then
        systemctl stop octoprint
        systemctl disable octoprint
        rm -f /etc/systemd/system/octoprint.service
    fi
    if [ -f "/etc/systemd/system/cam_octoprint.service" ]; then
        systemctl stop cam_octoprint
        systemctl disable cam_octoprint
        rm -f /etc/systemd/system/cam_octoprint.service
    fi
    if [ -d "/home/$user/OctoPrint" ]; then
        rm -rf /home/$user/OctoPrint
    fi
    if [ -f "/etc/udev/rules.d/99-octoprint.rules" ]; then
        rm -f /etc/udev/rules.d/99-octoprint.rules
    fi
    if [ -f "/etc/camera_ports" ]; then
        rm -f /etc/camera_ports
    fi
}

main_menu() {
    VERSION=0.1.7
    CAM=''
    TEMPUSBCAM=''
    echo
    echo
    echo "*************************"
    echo "octoprint_install $VERSION"
    echo "*************************"
    echo
    PS3='Select operation: '
    if [ -f "/etc/octoprint_deploy" ]; then
        options=("Add USB Camera" "Quit")
    else
        options=("Install OctoPrint" "Quit")
    fi

    select opt in "${options[@]}"; do
        case $opt in
        "Install OctoPrint")
            prepare
            break
            ;;
        "Add USB Camera")
            add_camera
            break
            ;;
        "Quit")
            exit 1
            ;;
        *) echo "invalid option $REPLY" ;;
        esac
    done
}

#command line arguments
if [ "$1" == remove ]; then
    if prompt_confirm "Remove everything?"; then
        remove_everything
    fi
fi

main_menu
