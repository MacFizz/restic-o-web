# restic-o-web
Simple installation script for restic/backrest

Both restic and backrest are installed using their github latest release for the detected architecture.
Backrest is installed with the "--allow-remote-acess" parameter to allow access from another computer.

The script also opens firewall ports if needed and test connexion to the web-UI.
