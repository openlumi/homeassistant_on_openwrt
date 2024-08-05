#!/bin/sh
# Homeassistant installer script by @devbis

get_ha_version()
{
  wget -q -O- https://pypi.org/simple/homeassistant/ | grep ${HOMEASSISTANT_MAJOR_VERSION} | tail -n 1 | cut -d "-" -f2 | cut -d "." -f1,2,3
}

get_python_version()
{
  opkg list | grep python3-base | head -n 1 | grep -Eo '[[:digit:]]+\.[[:digit:]]+'
}

get_version()
{
  local pkg=$1
  cat /tmp/ha_requirements.txt | grep -i -m 1 "${pkg}[<=>]=" | sed 's/.*[<=>]=\(.*\)/\1/g'
}

version()
{
  local pkg=$1
  echo "$pkg==$(get_version $pkg)"
}

is_lumi_gateway()
{
  cat /etc/board.json | grep -E '(dgnwg05lm|zhwg11lm)' | tr -s '"' | cut -d\" -f4
}

is_gtw360()
{
  cat /etc/board.json | grep 'gtw360' | tr -s '"' | cut -d\" -f4
}

int_version() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

set -e

HOMEASSISTANT_MAJOR_VERSION="2024.3"
export PIP_DEFAULT_TIMEOUT=100

HOMEASSISTANT_VERSION=$(get_ha_version)
STORAGE_TMP="/root/tmp-ha"  # /tmp in RAM too small, additional tmp on flash drive

if [ "${HOMEASSISTANT_VERSION}" = "" ]; then
  echo "Incorrect Home Assistant version. Exiting ...";
  exit 1;
fi

echo "=========================================="
echo " Installing Home Assistant ${HOMEASSISTANT_VERSION} ..."
echo "=========================================="

(
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/homeassistant/package_constraints.txt -O -
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/requirements.txt -O -
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/requirements_all.txt -O -
# now we can fetch nabucasa version and its deps
wget -q https://raw.githubusercontent.com/NabuCasa/hass-nabucasa/"$(get_version hass-nabucasa)"/setup.py -O - | grep '[>=]=' | sed -E 's/\s*"(.*)",?/\1/'
) >/tmp/ha_requirements.txt

HOMEASSISTANT_FRONTEND_VERSION=$(get_version home-assistant-frontend)
NABUCASA_VER=$(get_version hass-nabucasa)
ZIGPY_ZBOSS_VER=1.2.0

if pgrep -a -f "usr/bin/hass"; then
  echo "Stop running process of Home Assistant (and HASS Configurator) to free RAM for installation";
  exit 1;
fi

rm -rf ${STORAGE_TMP}

echo "Install base requirements from feed..."
opkg update

PYTHON_VERSION=$(get_python_version)
echo "Detected Python ${PYTHON_VERSION}"
LUMI_GATEWAY=$(is_lumi_gateway)
GTW360_GATEWAY=$(is_gtw360)
NEED_ZHA="$LUMI_GATEWAY$GTW360_GATEWAY"

# Install them first to check Openlumi feed id added
opkg install \
  python3-base \
  python3-pynacl \
  python3-ciso8601

opkg install \
  patch \
  unzip \
  libjpeg-turbo \
  python3-aiohttp \
  python3-aiohttp-cors \
  python3-async-timeout \
  python3-asyncio \
  python3-attrs \
  python3-bcrypt \
  python3-boto3 \
  python3-botocore \
  python3-certifi \
  python3-cffi \
  python3-cgi \
  python3-cgitb \
  python3-chardet \
  python3-codecs \
  python3-cryptodome \
  python3-cryptodomex \
  python3-cryptography \
  python3-ctypes \
  python3-dateutil \
  python3-dbm \
  python3-decimal \
  python3-defusedxml \
  python3-distutils \
  python3-docutils \
  python3-email \
  python3-greenlet \
  python3-idna \
  python3-jinja2 \
  python3-jmespath \
  python3-light \
  python3-logging \
  python3-lzma \
  python3-markupsafe \
  python3-multidict \
  python3-multiprocessing \
  python3-ncurses \
  python3-netdisco \
  python3-netifaces \
  python3-openssl \
  python3-pillow \
  python3-pip \
  python3-pkg-resources \
  python3-ply \
  python3-psutil \
  python3-pycparser \
  python3-pydoc \
  python3-pyopenssl \
  python3-pytz \
  python3-requests \
  python3-s3transfer \
  python3-setuptools \
  python3-six \
  python3-slugify \
  python3-sqlalchemy \
  python3-sqlite3 \
  python3-uuid \
  python3-unittest \
  python3-urllib \
  python3-urllib3 \
  python3-xml \
  python3-yaml \
  python3-yarl

# openwrt < 22.03 doesn't have this package
opkg install python3-pycares 2>/dev/null || true
# numpy requires hard floating point support and is missing on some MIPS architectures
opkg install python3-numpy 2>/dev/null || true

cd /tmp/

rm -rf /etc/homeassistant/deps/
find /usr/lib/python${PYTHON_VERSION}/site-packages/ | grep -E "/__pycache__$" | xargs rm -rf
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/botocore/data
find /usr/lib/python${PYTHON_VERSION}/site-packages/numpy -iname tests -print0 | xargs -0 rm -rf

echo "Install base requirements from PyPI..."
pip3 install --no-cache-dir wheel
pip3 freeze > /tmp/freeze.txt
grep -E 'aiohttp|async-timeout|crypto|YAML' /tmp/freeze.txt > /tmp/owrt_constraints.txt

cat << EOF > /tmp/requirements_nodeps.txt
$(version aioesphomeapi)
$(version esphome-dashboard-api)
$(version zeroconf)
EOF

mkdir -p ${STORAGE_TMP}

TMPDIR=${STORAGE_TMP} pip3 install --no-cache-dir --no-deps -r /tmp/requirements_nodeps.txt
# add zeroconf
grep 'zeroconf' /tmp/requirements_nodeps.txt >> /tmp/owrt_constraints.txt
# fix deps
sed -i -e 's/cryptography\(.*\)/cryptography >=36.0.2/' -e 's/chacha20poly1305-reuseable\(.*\)/chacha20poly1305-reuseable >=0.10.0/' /usr/lib/python${PYTHON_VERSION}/site-packages/aioesphomeapi-*-info/METADATA

cat << EOF > /tmp/requirements.txt
tzdata>=2021.2.post0  # 2021.6+ requirement

$(version atomicwrites-homeassistant)  # nabucasa dep
$(version snitun)  # nabucasa dep
$(version astral)
$(version awesomeversion)
$(version PyJWT)
$(version voluptuous)
$(version voluptuous-serialize)
# $(version sqlalchemy)  # recorder requirement
$(version ulid-transform)  # utils
$(version packaging)
$(version aiohttp-fast-url-dispatcher)
$(version psutil-home-assistant)
$(version async-interrupt)
#$(version aiohttp-zlib-ng)

# homeassistant manifest requirements
$(version PyQRCode)
$(version pyMetno)
$(version mutagen)
$(version pyotp)
$(version gTTS)
$(version janus)  # file_upload
$(version securetar)  # backup
$(version pyudev)  # usb
$(version pycognito)
$(version python-miio)  # xiaomi_miio
$(version PyXiaomiGateway)
$(version aiodhcpwatcher)  # dhcp
$(version aiodiscover)  # dhcp
$(version httpx)  # image/http
$(version hassil)  # conversation
$(version home-assistant-intents)  # conversation
$(version paho-mqtt)  # mqtt

# fixed dependencies
python-jose[cryptography]==3.2.0  # (pycognito dep) 3.3.0 is not compatible with the python3-cryptography in the feed
fnvhash==0.1.0  # replacement for fnv-hash-fast in recorder
radios==0.1.1  # radio_browser, newer versions require orjson
async-upnp-client==0.36.2  # 0.38 requires aiohttp>=3.9

# aioesphomeapi dependencies
noiseprotocol
protobuf<5
aiohappyeyeballs
chacha20poly1305-reuseable

# extra services
hass-configurator==0.4.1
EOF

if [ $NEED_ZHA ]; then
  cat << EOF >> /tmp/requirements.txt
# zha requirements
$(version pyserial)
$(version zha-quirks)
$(version zigpy)
EOF
fi

if [ $LUMI_GATEWAY ]; then
  cat << EOF >> /tmp/requirements.txt
$(version zigpy-zigate)
EOF
fi

TMPDIR=${STORAGE_TMP} pip3 install --no-cache-dir -c /tmp/owrt_constraints.txt -r /tmp/requirements.txt

if [ $GTW360_GATEWAY ]; then
  pip3 install --no-deps zigpy-zboss==${ZIGPY_ZBOSS_VER}
  sed -i -E 's/Requires-.*(jsonschema|coloredlogs)//g' /usr/lib/python${PYTHON_VERSION}/site-packages/zigpy_zboss-*-info/METADATA
fi

if [ $NEED_ZHA ]; then
  # show internal serial ports for Xiaomi Gateway
  sed -i 's/ttyXRUSB\*/ttymxc[1-9]/' /usr/lib/python${PYTHON_VERSION}/site-packages/serial/tools/list_ports_linux.py
  sed -i 's/if info.subsystem != "platform"]/]/' /usr/lib/python${PYTHON_VERSION}/site-packages/serial/tools/list_ports_linux.py
fi

# fix deps
# shellcheck disable=SC2144
if [ -f /usr/lib/python${PYTHON_VERSION}/site-packages/botocore-*-info/METADATA ]; then
  sed -i 's/urllib3 \(.*\)/urllib3 (>=1.20)/' /usr/lib/python${PYTHON_VERSION}/site-packages/botocore-*-info/METADATA
  sed -i 's/botocore \(.*\)/botocore (>=1.12.0)/' /usr/lib/python${PYTHON_VERSION}/site-packages/boto3-*-info/METADATA
else
  sed -i 's/urllib3<1.25,>=1.20/urllib3>=1.20/' /usr/lib/python${PYTHON_VERSION}/site-packages/botocore-*.egg-info/requires.txt
  sed -i 's/botocore<1.13.0,>=1.12.135/botocore<1.13.0,>=1.12.0/' /usr/lib/python${PYTHON_VERSION}/site-packages/boto3-*.egg-info/requires.txt
fi
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/pycountry/{locales,tests}

echo "Install hass_nabucasa and ha-frontend..."
wget https://github.com/NabuCasa/hass-nabucasa/archive/${NABUCASA_VER}.tar.gz -O - > hass-nabucasa-${NABUCASA_VER}.tar.gz
tar -zxf hass-nabucasa-${NABUCASA_VER}.tar.gz
cd hass-nabucasa-${NABUCASA_VER}
sed -i 's/[<=>]=.*"/"/' setup.py
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/hass_nabucasa-*.egg
pip3 install . --no-cache-dir -c /tmp/owrt_constraints.txt
cd ..
rm -rf hass-nabucasa-${NABUCASA_VER}.tar.gz hass-nabucasa-${NABUCASA_VER}

# cleanup
find /usr/lib/python${PYTHON_VERSION}/site-packages -iname tests -print0 | xargs -0 rm -rf

# tmp might be small for frontend
cd ${STORAGE_TMP}
rm -rf home-assistant-frontend.zip home-assistant-frontend-${HOMEASSISTANT_FRONTEND_VERSION}
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/hass_frontend
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/home_assistant_frontend-*
wget https://pypi.org/simple/home-assistant-frontend/ -O - | grep home_assistant_frontend-${HOMEASSISTANT_FRONTEND_VERSION}-py3 | cut -d '"' -f2 | xargs wget -O /tmp/home-assistant-frontend.zip
unzip -qqo /tmp/home-assistant-frontend.zip -d home-assistant-frontend
rm -rf /tmp/home-assistant-frontend.zip
cd home-assistant-frontend
find ./hass_frontend/frontend_es5 -name '*.js' -exec rm -rf {} \;
find ./hass_frontend/frontend_es5 -name '*.map' -exec rm -rf {} \;
find ./hass_frontend/frontend_es5 -name '*.txt' -exec rm -rf {} \;
find ./hass_frontend/frontend_latest -name '*.js' -exec rm -rf {} \;
find ./hass_frontend/frontend_latest -name '*.map' -exec rm -rf {} \;
find ./hass_frontend/frontend_latest -name '*.txt' -exec rm -rf {} \;

find ./hass_frontend/static/mdi -name '*.json' -maxdepth 1 -exec rm -rf {} \;
find ./hass_frontend/static/polyfills -name '*.js' -maxdepth 1 -exec rm -rf {} \;
find ./hass_frontend/static/polyfills -name '*.map' -maxdepth 1 -exec rm -rf {} \;
find ./hass_frontend/static/locale-data -name '*.json' -exec rm -rf {} \;
find ./hass_frontend/static/translations -name '*.json' -exec rm -rf {} \;

# gzip all translations (and that removes unarchived files)
for subdir in ./hass_frontend/static/translations/*; do
  if [ -d $subdir ]; then
    gzip -f $subdir/*.json || true
  fi
done

mv hass_frontend /usr/lib/python${PYTHON_VERSION}/site-packages/
mv home_assistant_frontend-${HOMEASSISTANT_FRONTEND_VERSION}.dist-info /usr/lib/python${PYTHON_VERSION}/site-packages/
cd ..
rm -rf home-assistant-frontend

echo "Install HASS"
pip3 install --no-cache-dir --upgrade typing-extensions || true

cd /tmp
rm -rf homeassistant.tar.gz homeassistant-${HOMEASSISTANT_VERSION} .cache pip-*
wget https://pypi.python.org/packages/source/h/homeassistant/homeassistant-${HOMEASSISTANT_VERSION}.tar.gz -O homeassistant.tar.gz

cat << EOF > /tmp/ha_components.txt
__init__.py
air_quality
alarm_control_panel
alert
alexa
analytics
api
application_credentials
assist_pipeline
auth
automation
backup
binary_sensor
blueprint
brother
button
calendar
camera
climate
cloud
command_line
config
conversation
counter
cover
date
datetime
default_config
device_automation
device_tracker
dhcp
diagnostics
energy
esphome
event
fan
file_upload
frontend
geo_location
google_assistant
google_translate
group
hassio
hardware
history
homeassistant
homeassistant_alerts
http
humidifier
image
image_processing
image_upload
input_boolean
input_button
input_datetime
input_number
input_select
input_text
integration
intent
lawn_mower
light
local_todo
lock
logbook
logger
lovelace
mailbox
manual
map
media_player
media_source
met
min_max
mobile_app
mpd
mqtt
my
network
notify
number
onboarding
panel_custom
panel_iframe
persistent_notification
person
proximity
python_script
radio_browser
recorder
remote
repairs
rest
safe_mode
scene
schedule
script
search
select
sensor
shopping_list
siren
ssdp
stream
stt
sun
switch
switch_as_x
system_health
system_log
tag
telegram
telegram_bot
template
text
time
time_date
timer
todo
trace
tts
update
upnp
usb
vacuum
valve
wake_on_lan
wake_word
water_heater
weather
webhook
websocket_api
workday
xiaomi_aqara
xiaomi_miio
yeelight
zeroconf
zone
EOF
if [ $NEED_ZHA ]; then
  echo "zha" >> /tmp/ha_components.txt
fi

# create fake structure tu get full list of components in /tmp/t/
TMPSTRUCT=${STORAGE_TMP}/t
rm -rf ${TMPSTRUCT}
cd ${STORAGE_TMP}
tar -ztf /tmp/homeassistant.tar.gz | grep '/homeassistant/components/' | sed 's/^/t\//' | xargs mkdir -p
rx=$(sed -e 's/^/^/' -e 's/$/$/' /tmp/ha_components.txt | head -c -1 | tr '\n' '|')
ls -1 ${TMPSTRUCT}/homeassistant-*/homeassistant/components/ | grep -v -E $rx | sed 's/^/*\/homeassistant\/components\//' > /tmp/ha_exclude.txt
rm -rf ${TMPSTRUCT} /tmp/ha_components.txt

cd /tmp

# extract without components to reduce space
tar -zxf homeassistant.tar.gz -X /tmp/ha_exclude.txt
rm -rf /tmp/ha_exclude.txt

rm -rf homeassistant.tar.gz
cd homeassistant-${HOMEASSISTANT_VERSION}/homeassistant/
echo '' > requirements.txt
sed -i "s/[>=]=.*//g" package_constraints.txt

# replace LRU with simple dict
sed -i -e 's/from lru import LRU/LRU = lambda x: dict()/' -e 's/lru.get_size()/128/' -e 's/lru.set_size/pass  # \0/' helpers/template.py

cd components

# serve static with gzipped files
sed -i -E 's/^( *)filepath.*?= (.*).joinpath\(filename\).resolve\(\)/\1try:\n\1    filepath = \2.joinpath(Path(str(filename) + ".gz")).resolve()\n\1    if not filepath.exists():\n\1        raise FileNotFoundError()\n\1except Exception as e:\n\1    filepath = \2.joinpath(filename).resolve()/' http/static.py
sed -i -E 's/^( *)headers=\{/\0\n\1    **({hdrs.CONTENT_ENCODING: "gzip"} if filepath.suffix == ".gz" else {}),/' http/static.py

# replace LRU with simple dict
sed -i 's/, "lru-dict==[0-9\.]*"//' recorder/manifest.json
sed -i 's/from lru import LRU/LRU = lambda x: dict()/' recorder/core.py
sed -i 's/from lru import LRU/LRU = lambda x: dict()/' recorder/table_managers/event_types.py
sed -i -e 's/from lru import LRU/LRU = lambda x: dict()/' -e 's/lru.get_size()/128/' -e 's/lru.set_size/pass  # \0/' recorder/table_managers/__init__.py
sed -i -e 's/from lru import LRU/LRU = lambda x: dict()/' -e 's/lru.get_size()/128/' -e 's/lru.set_size/pass  # \0/' recorder/table_managers/statistics_meta.py
sed -i 's/from lru import LRU/LRU = lambda x: dict()/' http/static.py
sed -i 's/from lru import LRU/LRU = lambda x: dict()/' esphome/entry_data.py

# relax dependencies
sed -i 's/sqlalchemy==[0-9\.]*/sqlalchemy/i' recorder/manifest.json
sed -i 's/pillow==[0-9\.]*/pillow/i' image_upload/manifest.json
sed -i 's/, UnidentifiedImageError//' image_upload/__init__.py
sed -i 's/except UnidentifiedImageError/except OSError/' image_upload/__init__.py
sed -i 's/zeroconf==[0-9\.]*/zeroconf/i' zeroconf/manifest.json
#sed -i 's/netdisco==[0-9\.]*/netdisco/' discovery/manifest.json
sed -i 's/PyNaCl==[0-9\.]*/PyNaCl/i' mobile_app/manifest.json
sed -i 's/defusedxml==[0-9\.]*/defusedxml/i' ssdp/manifest.json
sed -i 's/netdisco==[0-9\.]*/netdisco/i' ssdp/manifest.json
sed -i 's/radios==[0-9\.]*/radios/i' radio_browser/manifest.json
sed -i 's/"webrtc-noise-gain==[0-9\.]*"//i' assist_pipeline/manifest.json

# relax async-upnp-client versions
sed -i 's/async-upnp-client==[0-9\.]*/async-upnp-client/i' yeelight/manifest.json
sed -i 's/async-upnp-client==[0-9\.]*/async-upnp-client/i' upnp/manifest.json
sed -i 's/async-upnp-client==[0-9\.]*/async-upnp-client/i' ssdp/manifest.json

# remove bluetooth support from esphome
cat esphome/manifest.json | tr '\n' '\r' | sed -E -e 's/, "bluetooth"//g' -e 's/(, )?"bleak[-_]esphome"//' -e 's/,\r    "bleak-esphome==[0-9.]*"//g' | tr '\r' '\n' > esphome/manifest-new.json
mv esphome/manifest-new.json esphome/manifest.json
sed -i -e 's/    config_entry.unique_id/    False/' -e 's/from homeassistant.components.bluetooth/#from homeassistant.components.bluetooth/' -e 's/async_scanner_by_source//' esphome/diagnostics.py
sed -i 's/from.*ESPHomeBluetoothDevice.*/ESPHomeBluetoothDevice = None/' esphome/entry_data.py
sed -i 's/from.*ESPHomeBluetoothCache.*/ESPHomeBluetoothCache = dict/' esphome/domain_data.py
sed -i -E 's/from.*async_connect_scanner.*/async def async_connect_scanner(*args, **kwargs): pass/' esphome/manager.py

# Patch mqtt component in 2022.12
sed -i -e 's/import mqtt/\0\nfrom .util import */g' -e 's/mqtt\.util\.//' mqtt/trigger.py

# drop ffmpeg requirement from tts
sed -i 's/, "ffmpeg"//' tts/manifest.json
sed -i 's/ ffmpeg,//' tts/__init__.py

# drop numpy dep from stream
sed -i -e 's/"ha-av[^"]*", //' -e 's/, "numpy[^"]*"//' stream/manifest.json

# soft float, like mips32 don't have numpy. Cut it off
if ( ! ls /usr/lib/python${PYTHON_VERSION}/site-packages/ | grep -q numpy ); then
  sed -i -e 's/import numpy as np/np = None/' -e 's/np\.ndarray/Any/g' -e 's/TRANSFORM_IMAGE_FUNCTION[orientation]//' stream/core.py
fi
#sed -i -e 's/import av/#/' -e 's/av.logging/#/' stream/__init__.py
sed -i 's/import av/av = None/' stream/__init__.py
sed -i 's/import av/av = None/' stream/worker.py
sed -i 's/import av/av = None/' stream/recorder.py

# replace c-based fnv hash
sed -i 's/fnv-hash-fast==[0-9\.]*/fnvhash/i' recorder/manifest.json
sed -i 's/from fnv_hash_fast/from fnvhash/' recorder/db_schema.py

if [ $NEED_ZHA ]; then
  # remove unwanted zha requirements
  sed -i 's/"bellows==[0-9\.]*",//i' zha/manifest.json
  sed -i 's/"zigpy-cc==[0-9\.]*",//i' zha/manifest.json
  sed -i 's/"zigpy-deconz==[0-9\.]*",//i' zha/manifest.json
  sed -i 's/"zigpy-xbee==[0-9\.]*",//i' zha/manifest.json
  sed -i 's/"zigpy-znp==[0-9\.]*",//i' zha/manifest.json
  sed -i 's/"universal-silabs-flasher==[0-9\.]*",//i' zha/manifest.json
  sed -i 's/RadioType.ezsp/object()  # \0/' zha/__init__.py

  sed -i -E -e 's/import (bellows|zigpy_deconz|zigpy_cc|zigpy_xbee|zigpy_znp|zigpy_zigate).*application/# \0/' -e 's/([ ]*)([a-z_.]*.ControllerApplication,)/\1None # \2/g' zha/core/const.py
  sed -i -E 's/"(bellows|zigpy_deconz|zigpy_xbee|zigpy_znp|zigpy_zigate)":/# "\1":/' zha/diagnostics.py
  # sed -i -E 's/import (bellows|zigpy_deconz|zigpy_xbee|zigpy_znp)/# import \1/' zha/diagnostics.py
  sed -i -e '/from homeassistant.components.homeassistant_hardware.silabs_multiprotocol_addon/,/] = 15/d' zha/core/gateway.py
  sed -i 's/    RadioType\./    # RadioType./' zha/radio_manager.py
  sed -i 's/from bellows.config import CONF_USE_THREAD/from .core.const import CONF_USE_THREAD/' zha/radio_manager.py
  sed -i -e 's/from homeassistant.components.homeassistant_hardware import silabs_multiprotocol_addon/silabs_multiprotocol_addon = None  #/' -e 's/from homeassistant.components.homeassistant_yellow/yellow_hardware = None  #/' -e 's/ports = await hass/return await hass/' zha/config_flow.py

  cp zha/repairs/wrong_silabs_firmware.py zha/repairs/__wrong_silabs_firmware.py
cat <<'EOF' > zha/repairs/wrong_silabs_firmware.py
ISSUE_WRONG_SILABS_FIRMWARE_INSTALLED = "wrong_silabs_firmware_installed"
async def warn_on_wrong_silabs_firmware(hass, device_path): return False
class AlreadyRunningEZSP(Exception): pass
EOF
fi

if [ $LUMI_GATEWAY ]; then
  sed -i 's/"zigpy-zigate[<=>]=[0-9\.]*"/"zigpy-zigate"/i' zha/manifest.json
  sed -i -E -e 's/#[ ]*(.*zigate.*application)/\1/' -e 's/None # (zigpy_zigate)/\1/' zha/core/const.py
  sed -i -E 's/# ("zigpy_zigate")/\1/' zha/diagnostics.py
  sed -i 's/    # RadioType\.zigate/    RadioType.zigate/' zha/radio_manager.py
fi
if [ $GTW360_GATEWAY ]; then
  sed -i 's/"zigpy-zigate[<=>]=[0-9\.]*"/"zigpy-zboss"/i' zha/manifest.json
  sed -i -E -e 's/import.*zigpy_znp.*application/\0\nimport zigpy_zboss.zigbee.application/' -e 's/([ ]*)xbee = [(]/\1zboss = ("ZBOSS = Nordic ZBOSS Zigbee radios: nRF52840, nrf5340", zigpy_zboss.zigbee.application.ControllerApplication)\n\0/' zha/core/const.py
fi

sed -i 's/"cloud",//' default_config/manifest.json
sed -i 's/"dhcp",//' default_config/manifest.json
sed -i 's/"mobile_app",//' default_config/manifest.json
sed -i 's/"updater",//' default_config/manifest.json
sed -i 's/"usb",//' default_config/manifest.json
sed -i 's/"bluetooth",//' default_config/manifest.json
sed -i 's/"assist_pipeline",//' default_config/manifest.json
sed -i 's/"stream",//' default_config/manifest.json
sed -i 's/==[0-9\.]*//g' frontend/manifest.json

cd ../..
# integrations and helper sections leave as is, only nested items
sed -i 's/        "/        # "/' homeassistant/generated/config_flows.py
sed -i 's/    # "mqtt"/    "mqtt"/' homeassistant/generated/config_flows.py
sed -i 's/    # "esphome"/    "esphome"/' homeassistant/generated/config_flows.py
sed -i 's/    # "met"/    "met"/' homeassistant/generated/config_flows.py
sed -i 's/    # "radio_browser"/    "radio_browser"/' homeassistant/generated/config_flows.py
if [ $NEED_ZHA ]; then
  sed -i 's/    # "zha"/    "zha"/' homeassistant/generated/config_flows.py
fi

# disabling all zeroconf services
sed -i 's/^    "_/    "_disabled_/' homeassistant/generated/zeroconf.py
# re-enable required ones
sed -i 's/_disabled_esphomelib./_esphomelib./' homeassistant/generated/zeroconf.py
sed -i 's/_disabled_miio./_miio./' homeassistant/generated/zeroconf.py

# disabling all supported_brands
if [ -f homeassistant/generated/supported_brands.py ]; then  # 2022.8
  sed -i 's/^    /    # /' homeassistant/generated/supported_brands.py
else
  mkdir -p homeassistant/brands-disabled/
  mv homeassistant/brands/* homeassistant/brands-disabled/
fi

# backport orjson to classic json
# helpers
sed -i -e 's/orjson/json/' -e 's/\.decode(.*)//' -e 's/option=.*,/\n/' -e 's/.as_posix/.as_posix()\n    if isinstance(obj, (datetime.date, datetime.time)):\n        return obj.isoformat/' -e 's/json_bytes /json_bytes_old /' -e 's/return json_bytes(data)/return _json_default_encoder(data)/' -e 's/json_fragment = .*/json_fragment = json.loads/' -e 's/mode = "wb"/mode = "w"/' homeassistant/helpers/json.py
echo 'def json_bytes(data): return json.dumps(data, default=json_encoder_default).encode("utf-8")' >> homeassistant/helpers/json.py
# util
sed -i -e 's/orjson/json/' -e 's/\.decode(.*)//' -e 's/option=.*/\n/' homeassistant/util/json.py
# aiohttp_client.py
sed -i -e 's/orjson/json/' -e 's/\.decode(.*)//' homeassistant/helpers/aiohttp_client.py
sed -i -E -e 's/orjson/json/g' -e 's/\.decode(.*)//' -e 's/(b64(de|en)code.*?)/\1.decode("utf-8")/' -e 's/option=option/#option=option/' -e 's/json.OPT_[A-Z_0-9]*/0/g'  homeassistant/helpers/template.py

# disable aiohttp_zlib_ng
sed -i -E -e 's/"aiohttp-zlib-ng[^"]*"//' -e 's/(dispatcher[^,]*?),/\1/' homeassistant/components/http/manifest.json
sed -i -e 's/from aiohttp_zlib_ng/#from aiohttp_zlib_ng/' -e 's/enable_zlib_ng/#enable_zlib_ng/' homeassistant/components/http/__init__.py

# fix for aiohttp < 3.9 (3.8.5 in 23.05)
# TODO: revert https://github.com/home-assistant/core/pull/104175
sed -i 's/, handler_cancellation=True/,  # \0/' homeassistant/components/http/__init__.py

# Patch installation type
sed -i 's/"installation_type": "Unknown"/"installation_type": "Home Assistant on OpenWrt"/' homeassistant/helpers/system_info.py
find . -type f -exec touch {} +
sed -i "s/[>=]=.*//g" setup.cfg

rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/homeassistant*

if [ ! -f setup.py ]; then
  awk -v RS='dependencies[^\]]*?\n\]' -v ORS= '1;NR==1{printf "dependencies = []"}' pyproject.toml > pyproject-new.toml && mv pyproject-new.toml pyproject.toml
  sed -i -E -e 's/(setuptools)[~=]{1,2}[\.0-9]*/\1/' -e 's/(wheel)[~=]{1,2}[\.0-9]*/\1/' pyproject.toml
else
  sed -i 's/install_requires=REQUIRES/install_requires=[]/' setup.py
fi
HA_BUILD=${STORAGE_TMP}/ha-build
mkdir -p ${HA_BUILD}
ln -s ${HA_BUILD} ./build
TMPDIR=${STORAGE_TMP} pip3 install . --no-cache-dir -c /tmp/owrt_constraints.txt
cd ../
rm -rf homeassistant-${HOMEASSISTANT_VERSION}/ ${HA_BUILD} ${STORAGE_TMP}

IP=$(ip a | grep "inet .*br-lan" | cut -d " " -f6 | tail -1 | cut -d / -f1)
if [ -z "$IP" ]; then
  IP=$(ip a | grep "inet " | cut -d " " -f6 | tail -1 | cut -d / -f1)
fi

if [ ! -f '/etc/homeassistant/configuration.yaml' ]; then
  mkdir -p /etc/homeassistant
  ln -s /etc/homeassistant /root/.homeassistant
  cat << EOF > /etc/homeassistant/configuration.yaml
# Configure a default setup of Home Assistant (frontend, api, etc)
default_config:

# Text to speech
tts:
  - platform: google_translate
    language: ru

recorder:
  purge_keep_days: 1
  db_url: 'sqlite:////tmp/homeassistant.db'
  include:
    entity_globs:
      - sensor.*illuminance_*
      - sensor.*btn0_*
      - sensor.*temperature_*
      - sensor.*humidity_*
      - sensor.*presence_*
      - light.*

panel_iframe:
  configurator:
    title: Configurator
    icon: mdi:square-edit-outline
    url: http://${IP}:3218

group: !include groups.yaml
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF

  touch /etc/homeassistant/groups.yaml
  touch /etc/homeassistant/automations.yaml
  touch /etc/homeassistant/scripts.yaml
  touch /etc/homeassistant/scenes.yaml
fi

echo "Create starting script in init.d"
cat << "EOF" > /etc/init.d/homeassistant
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service()
{
    procd_open_instance
    procd_set_param command hass --config /etc/homeassistant --log-file /var/log/home-assistant.log --log-rotate-days 3
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
chmod +x /etc/init.d/homeassistant
/etc/init.d/homeassistant enable

cat << "EOF" > /etc/init.d/hass-configurator
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service()
{
    procd_open_instance
    procd_set_param command hass-configurator -b /etc/homeassistant
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
chmod +x /etc/init.d/hass-configurator
/etc/init.d/hass-configurator enable

echo "Done."
