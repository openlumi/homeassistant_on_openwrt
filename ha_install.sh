#!/bin/sh
# Homeassistant installer script by @devbis

set -e

echo "Install base requirements from feed..."
opkg update

# Install them first to check Openlumi feed id added
opkg install \
  python3-base \
  python3-pynacl \
  python3-ciso8601

opkg install \
  patch \
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
  python3-cryptography \
  python3-ctypes \
  python3-dateutil \
  python3-dbm \
  python3-decimal \
  python3-defusedxml \
  python3-distutils \
  python3-docutils \
  python3-email \
  python3-gdbm \
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
  python3-netifaces \
  python3-openssl \
  python3-pip \
  python3-pkg-resources \
  python3-ply \
  python3-pycparser \
  python3-pydoc \
  python3-pyopenssl \
  python3-pytz \
  python3-requests \
  python3-s3transfer \
  python3-setuptools \
  python3-six \
  python3-sqlalchemy \
  python3-sqlite3 \
  python3-unittest \
  python3-urllib \
  python3-urllib3 \
  python3-xml \
  python3-yaml \
  python3-yarl \
  python3-netdisco \
  python3-zeroconf \
  python3-pillow \
  python3-cryptodomex

cd /tmp/


echo "Install base requirements from PyPI..."
pip3 install wheel
cat << "EOF" > /tmp/requirements.txt
acme==1.8.0
appdirs==1.4.4
astral==2.2
atomicwrites==1.4.0
attr==0.3.1
distlib==0.3.1
filelock==3.0.12
PyJWT==1.7.1
python-slugify==4.0.1
text-unidecode==1.3
voluptuous==0.12.1
voluptuous-serialize==2.4.0
importlib-metadata
snitun==0.20

# homeassistant manifest requirements
async-upnp-client==0.16.2
PyQRCode==1.2.1
pyMetno==0.8.3
mutagen==1.45.1
pyotp==2.3.0
gTTS==2.2.1

# zha requirements
pyserial==3.5
zha-quirks==0.0.51
zigpy==0.30.0
zigpy-zigate==0.7.3
EOF

pip3 install -r /tmp/requirements.txt

# show internal serial ports for Xiaomi
sed -i 's/ttyXRUSB\*/ttymxc[1-9]/' /usr/lib/python3.7/site-packages/serial/tools/list_ports_linux.py
sed -i 's/if info.subsystem != "platform"]/]/' /usr/lib/python3.7/site-packages/serial/tools/list_ports_linux.py

# fix deps
sed -i 's/urllib3<1.25,>=1.20/urllib3<1.26,>=1.20/' /usr/lib/python3.7/site-packages/botocore-1.12.66-py3.7.egg-info/requires.txt
sed -i 's/botocore<1.13.0,>=1.12.135/botocore<1.13.0,>=1.12.66/' /usr/lib/python3.7/site-packages/boto3-1.9.135-py3.7.egg-info/requires.txt

echo "Download files"

wget https://github.com/pvizeli/pycognito/archive/0.1.4.tar.gz -O - > pycognito-0.1.4.tgz
wget https://github.com/ctalkington/python-ipp/archive/0.11.0.tar.gz -O - > python-ipp-0.11.0.tgz
wget https://files.pythonhosted.org/packages/b8/ad/31d10dbad025a8411029c5041129de14f9bb9f66a990de21be0011e19041/python-miio-0.5.4.tar.gz -O - > python-miio-0.5.4.tar.gz
echo "Installing pycognito..."

tar -zxf pycognito-0.1.4.tgz
cd pycognito-0.1.4
sed -i 's/boto3>=1.10.49/boto3>=1.9.135/' setup.py
python3 setup.py install
cd ..
rm -rf pycognito-0.1.4 pycognito-0.1.4.tgz

echo "Installing python-ipp..."
tar -zxf python-ipp-0.11.0.tgz
cd python-ipp-0.11.0
sed -i 's/aiohttp>=3.6.2/aiohttp>=3.5.4/' requirements.txt
sed -i 's/yarl>=1.4.2/yarl>=1.3.0/' requirements.txt
python3 setup.py install
cd ..
rm -rf python-ipp-0.11.0 python-ipp-0.11.0.tgz


echo "Installing python-miio..."
tar -zxf python-miio-0.5.4.tar.gz
cd python-miio-0.5.4
sed -i 's/cryptography>=3,<4/cryptography>=2,<4/' setup.py
python3 setup.py install
cd ..
rm -rf python-miio-0.5.4 python-miio-0.5.4.tar.gz
pip3 install PyXiaomiGateway==0.13.4

echo "Install hass_nabucasa and ha-frontend..."
wget https://github.com/NabuCasa/hass-nabucasa/archive/0.39.0.tar.gz -O - > hass-nabucasa-0.39.0.tar.gz
tar -zxf hass-nabucasa-0.39.0.tar.gz
cd hass-nabucasa-0.39.0
sed -i 's/==.*"/"/' setup.py
sed -i 's/>=.*"/"/' setup.py
python3 setup.py install
cd ..
rm -rf hass-nabucasa-0.39.0.tar.gz hass-nabucasa-0.39.0

# tmp might be small for frontend
cd /root
wget https://files.pythonhosted.org/packages/5d/04/35f06c52b6d00dc104479d0fa7e425f790c5612bfc407cd2edf85d1ce4ae/home-assistant-frontend-20210504.0.tar.gz -O home-assistant-frontend-20210504.0.tar.gz
tar -zxf home-assistant-frontend-20210504.0.tar.gz
cd home-assistant-frontend-20210504.0
find ./hass_frontend/frontend_es5 -name '*.js' -exec rm -rf {} \;
find ./hass_frontend/frontend_es5 -name '*.map' -exec rm -rf {} \;
find ./hass_frontend/frontend_es5 -name '*.txt' -exec rm -rf {} \;
find ./hass_frontend/frontend_latest -name '*.js' -exec rm -rf {} \;
find ./hass_frontend/frontend_latest -name '*.map' -exec rm -rf {} \;
find ./hass_frontend/frontend_latest -name '*.txt' -exec rm -rf {} \;

find ./hass_frontend/static/mdi -name '*.json' -maxdepth 1 -exec rm -rf {} \;
find ./hass_frontend/static/polyfills -name '*.js' -maxdepth 1 -exec rm -rf {} \;
find ./hass_frontend/static/polyfills -name '*.map' -maxdepth 1 -exec rm -rf {} \;

# shopping list and calendar missing gzipped
#gzip ./hass_frontend/static/translations/calendar/*
gzip ./hass_frontend/static/translations/shopping_list/*

find ./hass_frontend/static/translations -name '*.json' -exec rm -rf {} \;

mv hass_frontend /usr/lib/python3.7/site-packages/hass_frontend
python3 setup.py install
cd ..
rm -rf home-assistant-frontend-20210504.0.tar.gz home-assistant-frontend-20210504.0
cd /tmp

echo "Install HASS"
wget https://files.pythonhosted.org/packages/40/bd/8e55cacc78782b44474ba7c5510fb9dac63adad75e7fd97cd13254f50bf8/homeassistant-2021.5.1.tar.gz -O /tmp/homeassistant-2021.5.1.tar.gz
tar -zxf homeassistant-2021.5.1.tar.gz
rm -rf homeassistant-2021.5.1.tar.gz
cd homeassistant-2021.5.1/homeassistant/
echo '' > requirements.txt

mv components components-orig
mkdir components
cd components-orig
mv \
  __init__.py \
  alarm_control_panel \
  alert \
  alexa \
  api \
  auth \
  automation \
  binary_sensor \
  camera \
  climate \
  cloud \
  config \
  cover \
  default_config \
  device_automation \
  device_tracker \
  fan \
  frontend \
  google_assistant \
  google_translate \
  group \
  hassio \
  history \
  homeassistant \
  http \
  humidifier \
  image_processing \
  input_boolean \
  input_datetime \
  input_number \
  input_select \
  input_text \
  ipp \
  light \
  lock \
  logger \
  logbook \
  lovelace \
  map \
  media_player \
  met \
  mobile_app \
  notify \
  number \
  onboarding \
  persistent_notification \
  person \
  recorder \
  scene \
  script \
  search \
  sensor \
  shopping_list \
  ssdp \
  stream \
  sun \
  switch \
  system_health \
  system_log \
  template \
  timer \
  tts \
  updater \
  vacuum \
  weather \
  webhook \
  websocket_api \
  xiaomi_aqara \
  xiaomi_miio \
  zeroconf \
  zha \
  zone \
  blueprint \
  counter \
  image \
  media_source \
  tag \
  panel_custom \
  brother \
  discovery \
  mqtt \
  mpd \
  telegram \
  telegram_bot \
  trace \
  analytics \
  my \
  safe_mode \
  upnp \
  ../components
cd ..
rm -rf components-orig
cd components

# serve static with gzipped files
sed -i 's/filepath = self._directory.joinpath(filename).resolve()/try:\n                filepath = self._directory.joinpath(Path(rel_url + ".gz")).resolve()\n                if not filepath.exists():\n                    raise FileNotFoundError()\n            except Exception as e:\n                filepath = self._directory.joinpath(filename).resolve()/' http/static.py

sed -i 's/sqlalchemy==[0-9\.]*/sqlalchemy/' recorder/manifest.json
sed -i 's/pillow==[0-9\.]*/pillow/' image/manifest.json
sed -i 's/, UnidentifiedImageError//' image/__init__.py
sed -i 's/except UnidentifiedImageError/except OSError/' image/__init__.py
sed -i 's/zeroconf==[0-9\.]*/zeroconf/' zeroconf/manifest.json
sed -i 's/netdisco==[0-9\.]*/netdisco/' discovery/manifest.json
sed -i 's/PyNaCl==[0-9\.]*/PyNaCl/' mobile_app/manifest.json
sed -i 's/"defusedxml==[0-9\.]*", "netdisco==[0-9\.]*"/"defusedxml", "netdisco"/' ssdp/manifest.json
# remove unwanted zha requirements
sed -i 's/"bellows==[0-9\.]*",//' zha/manifest.json
sed -i 's/"zigpy-cc==[0-9\.]*",//' zha/manifest.json
sed -i 's/"zigpy-deconz==[0-9\.]*",//' zha/manifest.json
sed -i 's/"zigpy-xbee==[0-9\.]*",//' zha/manifest.json
sed -i 's/"zigpy-znp==[0-9\.]*"//' zha/manifest.json
sed -i 's/"zigpy-zigate==[0-9\.]*",/"zigpy-zigate"/' zha/manifest.json
sed -i 's/import bellows.zigbee.application//' zha/core/const.py
sed -i 's/import zigpy_cc.zigbee.application//' zha/core/const.py
sed -i 's/import zigpy_deconz.zigbee.application//' zha/core/const.py
sed -i 's/import zigpy_xbee.zigbee.application//' zha/core/const.py
sed -i 's/import zigpy_znp.zigbee.application//' zha/core/const.py
sed -i -e '/znp = (/,/)/d' -e '/ezsp = (/,/)/d' -e '/deconz = (/,/)/d' -e '/ti_cc = (/,/)/d' -e '/xbee = (/,/)/d' zha/core/const.py

sed -i 's/"cloud",//' default_config/manifest.json
sed -i 's/"dhcp",//' default_config/manifest.json
sed -i 's/"mobile_app",//' default_config/manifest.json
sed -i 's/"updater",//' default_config/manifest.json

cd ../..
sed -i 's/    "/    # "/' homeassistant/generated/config_flows.py
sed -i 's/    # "mqtt"/    "mqtt"/' homeassistant/generated/config_flows.py
sed -i 's/    # "zha"/    "zha"/' homeassistant/generated/config_flows.py

  sed -i 's/"installation_type": "Unknown"/"installation_type": "HomeAssistant on OpenWrt"/' homeassistant/helpers/system_info.py

sed -i 's/REQUIRED_PYTHON_VER = \(3, [0-9], [0-9]\)/REQUIRED_PYTHON_VER = \(3, 7, 0\)/' homeassistant/const.py

sed -i 's/install_requires=REQUIRES/install_requires=[]/' setup.py
find . -type f -exec touch {} +

# downgrade using python 3.8 to be compatible with 3.7
wget https://raw.githubusercontent.com/openlumi/homeassistant_on_openwrt/downgrade_python/ha_py37.patch -O /tmp/ha_py37.patch
patch -p1 < /tmp/ha_py37.patch
rm -rf /tmp/ha_py37.patch

python3 setup.py install
cd ../
rm -rf homeassistant-2021.1.5/

mkdir -p /etc/homeassistant
ln -s /etc/homeassistant /root/.homeassistant
cat << "EOF" > /etc/homeassistant/configuration.yaml
# Configure a default setup of Home Assistant (frontend, api, etc)
default_config:

# Text to speech
tts:
  - platform: google_translate
    language: ru

recorder:
  purge_keep_days: 2
  db_url: 'sqlite:///:memory:'

group: !include groups.yaml
automation: !include automations.yaml
script: !include scripts.yaml
scene: !include scenes.yaml
EOF

touch /etc/homeassistant/groups.yaml
touch /etc/homeassistant/automations.yaml
touch /etc/homeassistant/scripts.yaml
touch /etc/homeassistant/scenes.yaml

echo "Create starting script in init.d"
cat << "EOF" > /etc/init.d/homeassistant
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service()
{
    procd_open_instance
    procd_set_param command hass --config /etc/homeassistant
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
chmod +x /etc/init.d/homeassistant
/etc/init.d/homeassistant enable

echo "Done."
