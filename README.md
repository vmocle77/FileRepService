File Repository Service — README.md
Overview
This repository contains the installation and uninstallation scripts for the File Repository Service, a lightweight web application powered by Python and Flask. The intended use case is to provide the ability to back up and distribute important information for devices connected to a home or small organization network. Since it is a web service , the clients can be any device that has a web browser and has files that must be saved or shared. The service has been tested on Windows and Linux servers and windows,linux and android clients.
The service is designed to run automatically in the background as a user-level service:
    • Windows: Runs as a Windows Scheduled Task triggered at user logon.
    • Linux: Runs as a systemd User Unit managed by systemctl --user.
The installation scripts deploy the application files (FileServerApp.py, index.html, and favicon.png) into a designated Repository Root directory, create a shared_files folder for repository storage, install missing dependencies (Python 3 and Flask), and register the service to start automatically. The Repository Root directory must exist before the installation scripts are run . It can be a folder anywhere in the server , whether on the root disc drive or a separate mounted drive. Note that if the Root directory is on an external USB 2.0 ( USB-A) drive upload failures may happen  because of the USB bottleneck.
🖥️ Windows Installation & Uninstallation
1. Requirements & Prerequisites
    • Operating System: Windows 10, Windows 11, or Windows Server.
    • Privileges: Administrator permissions (recommended) when setting up the Scheduled Task.
    • Python Environment: The installer checks for an existing Python 3 installation. If missing, it automatically attempts to download and install Python 3.11 using winget or the official installer.
2. Windows Installation (Repo_Install.bat)
Script Workflow:
    1. Repository Target Setup: Accepts a Repository Root folder path as a command-line parameter or prompts you to enter one interactively.
    2. Environment & Python Check:
        ◦ Searches for existing valid Python executables (filtering out non-functional WindowsApp stubs).
        ◦ If Python is missing, it attempts an automated silent installation of Python 3.11 via winget or by downloading the official installer from python.org.
        ◦ Enables pip if necessary and automatically installs the Flask package.
    3. File Deployment:
        ◦ Copies FileServerApp.py, index.html, and uninstall.bat to the selected Repository Root.
        ◦ Creates the shared_files subfolder and copies favicon.png into it.
        ◦ Generates a execution wrapper script (Run_FileRepository.cmd) inside the Repository Root.
    4. Service Registration:
        ◦ Registers a Windows Scheduled Task named FileRepositoryService using schtasks to automatically run Run_FileRepository.cmd upon user logon.
    5. Network Notice:
        ◦ Resolves your local IPv4 address using ipconfig and displays the browser access URL (e.g., http://\<your-ip>:5000).
How to Run:
Click Start, type cmd and select Run as administrator:
DOS
:: Navigate to to the folder containing the installation files – whether you cloned the Github URI or downloaded and unpacked the zip file.

Cd ~\Downloads\Repo_install



:: Option A: Interactive prompt

Repo_Install.bat


:: Option B: Specify repository path directly

Repo_Install.bat "C:\Services\FileRepository"
3. First run and validation
Even though the FileRepositoryService task has been created , it is not running yet. The service should be started once before loging out . There are 2 ways provided to start it :
    • Open the Task Scheduler ( START tyoe Task select Task Scheduler ) . Once it is running , navigate to Task Scheduler Library , select FileRepositoryService and in the Actions pane select Run
    • In the Repository folder, a batch file named Run_FileRepositor.cmd is provided . Right cklick on it and select Run As Administrator . This will start python with the FileServerApp.py argument
In both cases ,  message from the fire wall should pop up warning about the requested access. Allow it. Once that is done you should be able to open a tab in your browser and type in the URL printed at the end of the install process.
4. Windows Uninstallation (uninstall.bat)
Script Workflow:
    1. Task Validation: Reads the FileRepositoryService Scheduled Task properties via PowerShell to locate the repository root path.
    2. Task Removal: Safely unregisters and deletes the FileRepositoryService scheduled task.
    3. Application File Cleanup: Removes FileServerApp.py and index.html from the repository directory.
    4. Data Preservation: Leaves all user repository data untouched. The shared_files folder, deleted_files archive, created subfolders, and uploaded user files are intentionally preserved.
How to Run:
Execute uninstall.bat directly from within your installed Repository Root folder . Running uninstall.bat from the installer source directory will result in an error message. The uninstaller can be run from the CMD window or directly from explorer by right clicking it and selecting Run As Administrator.
DOS
uninstall.bat
🐧 Linux Installation & Uninstallation
1. Requirements & Prerequisites
    • Operating System: Any systemd-based Linux distribution (Debian, Ubuntu, Fedora, RHEL, Arch Linux, openSUSE, Alpine, etc.).
    • Permissions: Do NOT run the script as root or with sudo. Run as the unprivileged user who will own and execute the service. The script will ask for your password when sudo priviledges are required.
    • Package Management: The installer uses sudo only if it needs to install python3 or python3-flask via system package managers (apt-get, dnf, yum, pacman, zypper, or apk).
2. Linux Installation (Repo_Install.sh)
Script Workflow:
    1. Safety & Validation Checks: Ensures the script is run as a non-root user, validates that systemctl is available, and checks that a systemd user session is active.
    2. Target Setup: Accepts a Repository Root folder path as an argument or prompts for one interactively.
    3. Dependency Installation: Detects the host distribution and uses the appropriate system package manager (with sudo) to install python3 and flask if they are not already installed.
    4. File Deployment:
        ◦ Copies FileServerApp.py, index.html, and uninstall.sh to the Repository Root.
        ◦ Creates shared_files/ and copies favicon.png into it.
    5. Systemd User Unit Creation:
        ◦ Creates a user unit file at ~/.config/systemd/user/file-repository.service.
        ◦ Configures automatic restarts on failure (Restart=on-failure, RestartSec=5s).
        ◦ Records the installation path in ~/.local/share/file-repository-service/install-root.
    6. Service Activation: Reloads the systemd user daemon, enables the service, and starts it immediately (systemctl --user enable --now file-repository.service).
    7. Network Notice: Detects the system's local IPv4 address and prints the service endpoint URL (e.g., http://\<your-ip>:5000).
How to Run:
Make the script executable and run it as your standard user:
Bash
chmod +x Repo_Install.sh


# Option A: Interactive prompt

./Repo_Install.sh


# Option B: Pass target directory path directly

./Repo_Install.sh /home/username/file_repository
3. Linux Uninstallation (uninstall.sh)
Script Workflow:
    1. Installation Record Verification: Reads ~/.local/share/file-repository-service/install-root to verify that the uninstallation request matches the recorded installation path.
    2. Service Deactivation: Stops and disables the file-repository.service user unit and deletes ~/.config/systemd/user/file-repository.service.
    3. Daemon Reload: Calls systemctl --user daemon-reload to update systemd.
    4. Application File Cleanup: Removes FileServerApp.py, index.html, uninstall.sh, and the tracking record.
    5. Data Preservation: Leaves user data untouched. All user files inside shared_files/ and deleted_files/ are strictly preserved.
How to Run:
Run uninstall.sh from inside your installed Repository Root directory:
Bash
chmod +x uninstall.sh

./uninstall.sh


🛠️ **Operational Summary & Port Configuration**

 **Windows Deployment  **             

Service Engine  :  Windows Task Scheduler(schtasks)    

Service Name  :      FileRepositoryService	           

Execution Trigger :	User Logon (ONLOGON)	           

** Linux Deployment**

Service Engine  :  systemd User Manager (systemctl --user)

Service Name   :   file-repository.service

Execution Trigger	:  User Session Start (default.target)

Default Port	:	5000 (TCP)

Auto-Dependency Install	Python 3.11 & Flask via winget/installer	Python 3 & Flask via distro package manager

Data Safety on Uninstall	Retains all files in shared_files/	Retains all files in shared_files/

Note: Ensure port 5000 is allowed through your system or network firewall (e.g., Windows Defender Firewall, ufw, or firewalld) so other devices on your local network can access the service.
