# Homeassistant on OpenWrt

This repo provides tools to install the latest version of Home Assistant that supports python 3.7 (2021.1.5)
on a system with OpenWrt 19.07 installed. It provides the reduced version of HA with only minimal list of components 
included. Additionally, it keeps MQTT and ZHA components as they are 
widely used with smart home solutions.

It is distributed with a shell script that downloads and installs everything that required for a clean start.

### Requirements:
- 120 MB storage space (256 recommended)
- 128 MB RAM
- OpenWrt 19.07 installed


## Xiaomi Gateway installation

Add the openlumi feed to gain access to a few precompiled python requirements.
Skip this step if you have already added this feed.

```sh
(! grep -q openlumi /etc/opkg/customfeeds.conf) && (
wget -q https://openlumi.github.io/openwrt-packages/public.key -O /tmp/public.key && 
opkg-key add /tmp/public.key && rm /tmp/public.key &&
echo 'src/gz openlumi https://openlumi.github.io/openwrt-packages/packages/19.07/arm_cortex-a9_neon' >> /etc/opkg/customfeeds.conf &&
echo "Feed added successfully!"
) || echo "Feed added already. Skip."
```

Then go to generic installation

## Other devices

You have to compile ipk packages for `python3-ciso8601` and `python3-pynacl` or get it for your system from
any sources. This repo provides makefiles for these packages.
OpenWrt 21.2 and master branches already have this packages.
Compilation process is widely described on the site of the OpenWrt project.


## Generic installation
Then, download the installer and run it.

```sh
wget https://raw.githubusercontent.com/adisik/homeassistant_on_openwrt/main/ha_install.sh -O - | sh
```

After script prints `Done.` you have Home Assistant installed. 
Start the service or reboot the device to get it start automatically.
The web interface will be on 8123 port after all components load.

![Home Assitant](homeassistant.png)

The only components with flows included are MQTT and ZHA.
After adding a component in the interface or via the config
HA could install dependencies and fails on finding them after installation.
In this case restarting HA could work.

Other components are not tested and may require additional changed in 
requirement versions or python libraries.

## ZHA usage on Xiaomi Gateway

The component uses internal UART to communicate with ZigBee chip.
The chip has to be flashed with a proper firmware to be able to 
communicate with the HA. The recommended firmware is 

https://github.com/openlumi/ZiGate/releases/download/snapshot-20201008/ZiGate_3.1_cd_fix_leak__JN5169_COORDINATOR_115200.bin

You could try another Zigate firmwares for JN5169 chip. The baud rate
must be 115200 as it is hardcoded in zigpy-zigate.

## Enabling other components and installing custom

You may want to add more components to your HA installation.
In this case you have to copy the directory with component to 
`/usr/lib/python3.7/site-packages/homeassistant-2021.1.5-py3.7.egg/homeassistant/components/`

or create `custom_components` directory in `/etc/homeassistant` and
copy it there.

Try to install requirements from `manifest.json` with `pip3` manually
to check it installs and doesn't require pre-compiled C libraries.
Otherwise, you have to cross-compile python3 dependencies and install
them as `ipk` packages.
