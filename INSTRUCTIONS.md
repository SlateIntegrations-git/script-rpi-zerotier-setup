# Setup Instructions: RPi5 ZeroTier Bridge

**Goal:** Turn a blank Raspberry Pi 5 into a "Plug-and-Play" Network Bridge.  
**Time Required:** 15 Minutes  
**Difficulty:** Beginner (No coding required)

---

## Part 1: Prepare the Hardware

### What You Need
1. **Raspberry Pi 5**
2. **MicroSD Card** (8GB or larger)
3. **USB-C Power Supply** (Official Pi power supply recommended)
4. **Ethernet Cable**
5. **Computer** (Windows, Mac, or Linux)

### Step 1: Download the Software
1. Download **Raspberry Pi Imager** from [raspberrypi.com/software](https://www.raspberrypi.com/software/).
2. Download the **OpenWrt Firmware** for RPi 5:
   - Go to [firmware-selector.openwrt.org](https://firmware-selector.openwrt.org/)
   - Type `Raspberry Pi 5`
   - Click the **"Factory"** download button (filename ends in `.img.gz`).

### Step 2: Flash the SD Card
1. Insert your SD card into your computer.
2. Open **Raspberry Pi Imager**.
3. Click **CHOOSE OS** -> scroll down to **Use Custom** -> select the OpenWrt file you downloaded.
4. Click **CHOOSE STORAGE** -> select your SD Card.
5. Click **NEXT** -> **No** (to customization settings) -> **YES** (to warning).
6. When finished, remove the SD card and insert it into the Raspberry Pi 5.

---

## Part 2: First Connection

### Step 3: Wire It Up
*Do not plug the Pi into your Internet router yet.*

1. Connect the **Ethernet Cable** from the **Raspberry Pi** directly to your **Computer**.
2. Plug the **Power Cable** into the Raspberry Pi.
3. Wait **60 seconds** for the lights to settle.

### Step 4: Access the Dashboard
1. On your computer, turn **OFF** your Wi-Fi (temporarily).
   * *Why? This ensures your computer talks to the Pi, not your home network.*
2. Open a Web Browser (Chrome, Safari, Edge).
3. Type `192.168.1.1` in the address bar and hit Enter.
4. You should see the OpenWrt login screen.
   - **Username:** `root`
   - **Password:** (Leave blank)
   - Click **Login**.

---

## Part 3: Get Internet Access
*To install the ZeroTier software, the Pi needs to download it. We will connect the Pi to your home Wi-Fi for this step.*

1. In the Dashboard menu, go to **Network** -> **Wireless**.
2. Look for the "Master" wireless radio and click the **Scan** button.
3. Find your **Home Wi-Fi Network** in the list and click **Join Network**.
4. Entering settings:
   - **WPA Passphrase:** Your Home Wi-Fi Password.
   - **Name of the new network:** Leave as `wwan`.
   - **Firewall zone:** Select `wan`.
   - Click **Submit**.
5. Click **Save & Apply** (blue button at the bottom).
6. Wait 15 seconds. You can now turn your Computer's Wi-Fi back **ON** if you wish, but keep the Ethernet cable connected.

---

## Part 4: Run the Deployment

Now that the Pi has power, a connection to you, and a connection to the internet, we run the automated script.

1. **Open a Terminal** on your computer:
   - **Windows:** Right-click Start -> "Windows PowerShell" or "Command Prompt".
   - **Mac:** Command+Space -> Type "Terminal".
2. Log into the Pi by typing this command and hitting Enter:
   ```bash
   ssh root@192.168.1.1
