Updated May 5th, 2023.  
Want to support this work? Buy Me a Coffee. https://www.buymeacoffee.com/ppaukstelis. Don't like to give money to inviduals over the internet, but want to show support? Consider donating to the Sanjay Mortimer Foundation: https://www.sanjaymortimerfoundation.org/
Need help with octoprint_install or octoprint_deploy? You can open issues here or ask on Discord: https://discord.gg/6vgSjgvR6u
# octoprint_install
These files provide a simple script that will install OctoPrint and a video streamer (mjpg-streamer or ustreamer) on virtually any linux based system. The system must use systemd.

# How to use
* All commands assume you are operating out of your home directory using a terminal directly on the machine or by ssh.
* Install Ubuntu 20+, Mint 20.3+, Debian, DietPi, RPiOS, Armbian, Fedora35+, or ArchLinux on your system (make sure your user is admin for sudo).
* WARNING: SELinux (Fedora) adds significant complications. Either don't use Fedora or disable SELinux
* Install git if it isn't already: `sudo apt install git` or `sudo dnf install git` or `sudo pacman -S git`.
* run the command `git clone https://github.com/paukstelis/octoprint_install.git`.
* run the command `sudo octoprint_install/octoprint_install.sh`.
* Choose `Install OctoPrint`
* You will asked if you want to install haproxy and if you want to establish the admin user and do the first run settings with the command-line.
* You will be asked if you want to install recommended plugins.
* You can now connect to your OctoPrint instance (http://ipaddress:5000, http://hostname.local:5000, or if you used haproxy, no need to include port 5000)
* OctoPrint will always be started at boot.
* You can add a USB webcam by choosing the selection in the menu. Your camera service will be setup in /etc/systemd/system/cam_octoprint.service, and will be started upon boot
* There is now support of multiple cameras! Run through the camera install script a second time and it will prompt you to include a number designation for the next camera.
* To use a Raspberry Pi camera, run the script with the picam commandline option (`sudo octoprint_install/octoprint_install.sh picam`)

# Other
* Remove everything and start over: `sudo octoprint_install/octoprint_install.sh remove`

# What's New (0.2.0)
* Multi-camera support
* Pi camera, command line option
* ustreamer as recommended streamer
* camera snapshot path default to localhost
