Updated November 12, 2022.  
Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis.
Need help with this or octoprint_deploy? You can open issues here or ask on Discord: https://discord.gg/6vgSjgvR6u
# octoprint_install
These files provide a simple script that will install OctoPrint and a video streamer (mjpg-streamer or ustreamer) on virtually any linux based system. The system must use systemd.

# How to use
* All commands assume you are operating out of your home directory using a terminal directly on the machine or by ssh.
* Install Ubuntu 20+, Mint 20.3+, Debian, DietPi, RPiOS, Armbian, Fedora35+, or ArchLinux on your system (make sure your user is admin for sudo).
* Install git if it isn't already: `sudo apt install git` or `sudo dnf install git` or `sudo pacman -S git`.
* run the command `git clone https://github.com/paukstelis/octoprint_install.git`.
* run the command `sudo octoprint_install/octoprint_install.sh`.
* Choose `Install OctoPrint`
* You will asked if you want to install haproxy and if you want to establish the admin user and do the first run settings with the command-line.
* You will be asked if you want to install recommended plugins.
* You can now connect to your OctoPrint instance (http://ipaddress:5000, http://hostname.local:5000, or if you used haproxy, no need to include port 5000)
* OctoPrint will always be started at boot.
* You can add a USB webcam by choosing the selection in the menu. Your camera service will be setup in /etc/systemd/system/cam_octoprint.service, and will be started upon boot
* NOTE: RPi cameras are not supported through this method, but can be installed manually.

# What's New (0.1.4)
* Reload USB rules after adding camera
* Remove existing ~/.octoprint if it already exists at install
* Using dmesg instead of journalctl for detecting cameras
* Remove existing streamer installations, if they exist
* Add system shutdown command and appropriate sudo permissions