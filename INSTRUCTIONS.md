INSTRUCTIONS.txt

OpenWRT Expert — Custom Gem
RPi 5 ZeroTier Bridge Setup

GOAL
Turn a blank Raspberry Pi 5 into a plug-and-play network bridge.

TIME REQUIRED
Approximately 15 minutes

DIFFICULTY
Beginner — no coding required
___________________________________________________________________________

STEP 1 — DOWNLOAD THE SOFTWARE

Download Raspberry Pi Imager

https://www.raspberrypi.com/software/

Download OpenWrt firmware for Raspberry Pi 5:

Go to https://firmware-selector.openwrt.org/

Search for: Raspberry Pi 5

Download the Factory image (file ends in .img.gz)
____________________________________________________________________________

STEP 2 — FLASH THE SD CARD

Insert the SD card into your computer.

Open Raspberry Pi Imager.

Click CHOOSE OS → Use Custom → select the OpenWrt .img.gz file.

Click CHOOSE STORAGE → select your SD card.

Click NEXT.

Select NO for customization.

Select YES to confirm overwrite.

When complete, remove the SD card and insert it into the Raspberry Pi 5.
____________________________________________________________________________

STEP 3 — WIRE IT UP

IMPORTANT: Do NOT connect the Pi to your internet router yet.

Connect an Ethernet cable from the Raspberry Pi directly to your computer.

Plug the power cable into the Raspberry Pi.

Wait 60 seconds for the Pi to boot.

Turn OFF your computer’s Wi-Fi temporarily.
_____________________________________________________________________________

STEP 4 — CONNECT THE PI TO WI-FI

The Pi needs internet access to download ZeroTier.

Open a web browser and go to:
http://192.168.1.1

Username: root
Password: (leave blank)

Navigate to Network → Wireless.

Find the Master radio and click Scan.

Join your home Wi-Fi network:

WPA Passphrase: your Wi-Fi password

Name of new network: wwan

Firewall zone: wan

Click Submit, then Save & Apply.

Wait approximately 15 seconds.

Turn your computer’s Wi-Fi back ON.
_______________________________________________________________________________

STEP 5 — INSTALL ZEROTIER AND JOIN THE NETWORK

Open a terminal:

Windows: PowerShell

macOS/Linux: Terminal

Log into the Raspberry Pi:
ssh root@192.168.1.1

#### IF YOU GET A REMOTE HOST IDENTIFICATION HAS CHANGED MESSAGE #### see the next line
in the Terminal window, type "ssh-keygen -R 192.168.1.1". Then reattempt ssh root@192.168.1.1
#############################################################################################

Type "yes" if prompted.

Run the installer:
```
opkg update && opkg install nano curl ca-bundle ca-certificates && curl -fsSL https://raw.githubusercontent.com/SlateIntegrations-git/script-rpi-zerotier-setup/main/install.sh | sh
```
When prompted, enter your ZeroTier Network ID.

Copy your 16-character Network ID from:
[link removed]

Paste it into the terminal and press Enter.

The script will automatically:

Install ZeroTier

Create the bridge

Save the configuration
_____________________________________________________________________________________

STEP 6 — FINAL AUTHORIZATION

ZeroTier requires manual approval for new devices.

When the script finishes, note the Device ID displayed
(example: a1b2c3d4e5)

Go to:
The account's ZeroTier dashboard

Open your ZeroTier network.

Scroll to the Members section.

Find the new device and:

Check the Authorize box

Click the wrench icon (settings)

Enable "Allow Ethernet Bridging"
_______________________________________________________________________________________
DONE

You may now unplug the Raspberry Pi from your computer and connect it to any device or switch you want bridged into the VPN network.

The Raspberry Pi is now a portable, plug-and-play Layer-2 bridge.
