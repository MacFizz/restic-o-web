# Restic-o-web
Simple installation script for restic/backrest/rclone

Restic, backrest and rclone are installed using their github latest release for the detected architecture.
Backrest is installed with the "--allow-remote-acess" parameter to allow access from another computer.
An override file is set to play nice running in backgroud of pistomp.

The script also opens firewall ports if needed and test connexion to the web-UI.
