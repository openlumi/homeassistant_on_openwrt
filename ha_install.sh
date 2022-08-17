#!/bin/sh
# Homeassistant installer script by @devbis

set -e

OPENWRT_VERSION=${OPENWRT_VERSION:-21.02}
HOMEASSISTANT_MAJOR_VERSION="2022.8"
export PIP_DEFAULT_TIMEOUT=100

get_ha_version()
{
  wget -q -O- https://pypi.org/simple/homeassistant/ | grep ${HOMEASSISTANT_MAJOR_VERSION} | tail -n 1 | cut -d "-" -f2 | cut -d "." -f1,2,3
}

HOMEASSISTANT_VERSION=$(get_ha_version)

if [ "${HOMEASSISTANT_VERSION}" == "" ]; then
  echo "Incorrect Home Assistant version. Exiting ...";
  exit 1;
fi

echo "=========================================="
echo " Installing Home Assistant ${HOMEASSISTANT_VERSION} ..."
echo "=========================================="

get_python_version()
{
  opkg list | grep python3-base | head -n 1 | grep -Eo '\d+\.\d+'
}

get_version()
{
  local pkg=$1
  cat /tmp/ha_requirements.txt | grep -i -m 1 "${pkg}[>=]=" | sed 's/.*==\(.*\)/\1/g'
}

version()
{
  local pkg=$1
  echo "$pkg==$(get_version $pkg)"
}

is_lumi_gateway()
{
  ls -1 /dev/ttymxc1 2>/dev/null || echo ''
}

wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/homeassistant/package_constraints.txt -O - > /tmp/ha_requirements.txt
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/requirements.txt -O - >> /tmp/ha_requirements.txt
wget -q https://raw.githubusercontent.com/home-assistant/core/${HOMEASSISTANT_VERSION}/requirements_all.txt -O - >> /tmp/ha_requirements.txt
# now we can fetch nabucasa version and its deps
wget -q https://raw.githubusercontent.com/NabuCasa/hass-nabucasa/$(get_version hass-nabucasa)/setup.py -O - | grep '[>=]=' | sed -E 's/\s*"(.*)",?/\1/' >> /tmp/ha_requirements.txt

PYCOGNITO_VER=2022.01.0  # zero is required, incorrect version in github
HOMEASSISTANT_FRONTEND_VERSION=$(get_version home-assistant-frontend)
IPP_VER=$(get_version pyipp)
PYTHON_MIIO_VER=$(get_version python-miio)
AIODISCOVER_VER=$(get_version aiodiscover)
NABUCASA_VER=$(get_version hass-nabucasa)

if [ $(ps | grep "[/]usr/bin/hass" | wc -l) -gt 0 ]; then
  echo "Stop running process of Home Assistant (and HASS Configurator) to free RAM for installation";
  exit 1;
fi

echo "Install base requirements from feed..."
opkg update

PYTHON_VERSION=$(get_python_version)
echo "Detected Python ${PYTHON_VERSION}"
LUMI_GATEWAY=$(is_lumi_gateway)

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
  python3-sqlite3 \
  python3-unittest \
  python3-urllib \
  python3-urllib3 \
  python3-xml \
  python3-yaml \
  python3-yarl \
  python3-netdisco \
  python3-pillow \
  python3-cryptodomex \
  python3-slugify

# openwrt master doesn't have this package
opkg install python3-gdbm || true
# numpy requires hard floating point support and is missing on some MIPS architectures
opkg install python3-numpy  || true

cd /tmp/

# add missing _distutils_hack from setuptools
mkdir -p /usr/lib/python${PYTHON_VERSION}/site-packages/_distutils_hack
wget https://raw.githubusercontent.com/pypa/setuptools/v56.0.0/_distutils_hack/__init__.py -O /usr/lib/python${PYTHON_VERSION}/site-packages/_distutils_hack/__init__.py
wget https://raw.githubusercontent.com/pypa/setuptools/v56.0.0/_distutils_hack/override.py -O /usr/lib/python${PYTHON_VERSION}/site-packages/_distutils_hack/override.py

rm -rf /etc/homeassistant/deps/
find /usr/lib/python${PYTHON_VERSION}/site-packages/ | grep -E "/__pycache__$" | xargs rm -rf
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/botocore/data

echo "Install base requirements from PyPI..."
pip3 install wheel
cat << EOF > /tmp/requirements.txt
tzdata==2021.2.post0  # 2021.6+ requirement

$(version atomicwrites-homeassistant)  # nabucasa dep
$(version snitun)  # nabucasa dep
$(version astral)
$(version awesomeversion)
$(version PyJWT)
$(version voluptuous)
$(version voluptuous-serialize)
$(version sqlalchemy)  # recorder requirement

# homeassistant manifest requirements
$(version async-upnp-client)
$(version fnvhash)
$(version PyQRCode)
$(version pyMetno)
$(version mutagen)
$(version pyotp)
$(version gTTS)
$(version aioesphomeapi)
$(version zeroconf)

# fixed dependencies
python-jose[cryptography]==3.2.0  # (pycognito dep) 3.3.0 is not compatible with the python3-cryptography in the feed

# extra services
hass-configurator==0.4.1
EOF

if [ $LUMI_GATEWAY ]; then
  cat << EOF >> /tmp/requirements.txt
# zha requirements
$(version pyserial)
$(version zha-quirks)
$(version zigpy)
$(version zigpy-zigate)
EOF
fi

pip3 install -r /tmp/requirements.txt

# patch async_upnp_client to support older aiohttp
sed -i 's/CIMultiDictProxy\[str\]/CIMultiDictProxy/' /usr/lib/python${PYTHON_VERSION}/site-packages/async_upnp_client/ssdp.py

if [ $LUMI_GATEWAY ]; then
  # show internal serial ports for Xiaomi Gateway
  sed -i 's/ttyXRUSB\*/ttymxc[1-9]/' /usr/lib/python${PYTHON_VERSION}/site-packages/serial/tools/list_ports_linux.py
  sed -i 's/if info.subsystem != "platform"]/]/' /usr/lib/python${PYTHON_VERSION}/site-packages/serial/tools/list_ports_linux.py
fi

# fix deps
sed -i 's/urllib3<1.25,>=1.20/urllib3>=1.20/' /usr/lib/python${PYTHON_VERSION}/site-packages/botocore-*.egg-info/requires.txt
sed -i 's/botocore<1.13.0,>=1.12.135/botocore<1.13.0,>=1.12.0/' /usr/lib/python${PYTHON_VERSION}/site-packages/boto3-*.egg-info/requires.txt

echo "Download files"

wget https://github.com/pvizeli/pycognito/archive/${PYCOGNITO_VER}.tar.gz -O - > pycognito-${PYCOGNITO_VER}.tgz
wget https://github.com/ctalkington/python-ipp/archive/${IPP_VER}.tar.gz -O - > python-ipp-${IPP_VER}.tgz
wget https://pypi.python.org/packages/source/p/python-miio/python-miio-${PYTHON_MIIO_VER}.tar.gz -O - > python-miio-${PYTHON_MIIO_VER}.tar.gz
wget https://pypi.python.org/packages/source/a/aiodiscover/aiodiscover-${AIODISCOVER_VER}.tar.gz -O - > aiodiscover-${AIODISCOVER_VER}.tar.gz
echo "Installing pycognito..."

tar -zxf pycognito-${PYCOGNITO_VER}.tgz
cd pycognito-${PYCOGNITO_VER}
sed -i 's/boto3>=[0-9\.]*/boto3/' setup.py
python3 setup.py install
cd ..
rm -rf pycognito-${PYCOGNITO_VER} pycognito-${PYCOGNITO_VER}.tgz

echo "Installing python-ipp..."
tar -zxf python-ipp-${IPP_VER}.tgz
cd python-ipp-${IPP_VER}
sed -i 's/aiohttp>=[0-9\.]*/aiohttp/' requirements.txt
sed -i 's/yarl>=[0-9\.]*/yarl/' requirements.txt
python3 setup.py install
cd ..
rm -rf python-ipp-${IPP_VER} python-ipp-${IPP_VER}.tgz


echo "Installing python-miio..."
tar -zxf python-miio-${PYTHON_MIIO_VER}.tar.gz
cd python-miio-${PYTHON_MIIO_VER}
sed -i 's/cryptography[0-9><=]*/cryptography>=2/' setup.py
sed -i 's/click[0-9><=]*/click/' setup.py
sed -i "s/'extras_require'/# 'extras_require'/" setup.py
find . -type f -exec touch {} +
python3 setup.py install
cd ..
rm -rf python-miio-${PYTHON_MIIO_VER} python-miio-${PYTHON_MIIO_VER}.tar.gz
pip3 install $(version PyXiaomiGateway)

echo "Installing aiodiscover..."
tar -zxf aiodiscover-${AIODISCOVER_VER}.tar.gz
cd aiodiscover-${AIODISCOVER_VER}
sed -i 's/netifaces[0-9.><=]*/netifaces/' setup.py
find . -type f -exec touch {} +
python3 setup.py install
cd ..
rm -rf aiodiscover-${AIODISCOVER_VER} aiodiscover-${AIODISCOVER_VER}.tar.gz

echo "Install hass_nabucasa and ha-frontend..."
wget https://github.com/NabuCasa/hass-nabucasa/archive/${NABUCASA_VER}.tar.gz -O - > hass-nabucasa-${NABUCASA_VER}.tar.gz
tar -zxf hass-nabucasa-${NABUCASA_VER}.tar.gz
cd hass-nabucasa-${NABUCASA_VER}
sed -i 's/==.*"/"/' setup.py
sed -i 's/>=.*"/"/' setup.py
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/hass_nabucasa-*.egg
python3 setup.py install
cd ..
rm -rf hass-nabucasa-${NABUCASA_VER}.tar.gz hass-nabucasa-${NABUCASA_VER}

# tmp might be small for frontend
cd /root
rm -rf home-assistant-frontend.zip home-assistant-frontend-${HOMEASSISTANT_FRONTEND_VERSION}
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/hass_frontend
rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/home_assistant_frontend-*
wget https://pypi.org/simple/home-assistant-frontend/ -O - | grep home_assistant_frontend-${HOMEASSISTANT_FRONTEND_VERSION}-py3 | cut -d '"' -f2 | xargs wget -O home-assistant-frontend.zip
unzip -qqo home-assistant-frontend.zip -d home-assistant-frontend
rm -rf home-assistant-frontend.zip
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

# gzip all translations (and that removes unarchived files)
for subdir in ./hass_frontend/static/translations/*; do
  if [ -d $subdir ]; then
    gzip -f $subdir/*.json
  fi
done

mv hass_frontend /usr/lib/python${PYTHON_VERSION}/site-packages/
mv home_assistant_frontend-${HOMEASSISTANT_FRONTEND_VERSION}.dist-info /usr/lib/python${PYTHON_VERSION}/site-packages/
cd ..
rm -rf home-assistant-frontend

echo "Install HASS"
pip3 install --upgrade typing-extensions || true

cd /tmp
rm -rf homeassistant.tar.gz homeassistant-${HOMEASSISTANT_VERSION} .cache pip-*
wget https://pypi.python.org/packages/source/h/homeassistant/homeassistant-${HOMEASSISTANT_VERSION}.tar.gz -O homeassistant.tar.gz
tar -zxf homeassistant.tar.gz
rm -rf homeassistant.tar.gz
cd homeassistant-${HOMEASSISTANT_VERSION}/homeassistant/
echo '' > requirements.txt
sed -i "s/[>=]=.*//g" package_constraints.txt

mv components components-orig
mkdir components
cd components-orig
mv \
  __init__.py \
  air_quality \
  alarm_control_panel \
  alert \
  alexa \
  analytics \
  api \
  application_credentials \
  auth \
  automation \
  backup \
  binary_sensor \
  blueprint \
  bluetooth \
  brother \
  button \
  camera \
  climate \
  cloud \
  command_line \
  config \
  counter \
  cover \
  default_config \
  device_automation \
  device_tracker \
  dhcp \
  diagnostics \
  discovery \
  energy \
  esphome \
  fan \
  frontend \
  geo_location \
  google_assistant \
  google_translate \
  group \
  hassio \
  history \
  homeassistant \
  homeassistant_alerts \
  http \
  humidifier \
  image \
  image_processing \
  input_boolean \
  input_button \
  input_datetime \
  input_number \
  input_select \
  input_text \
  ipp \
  light \
  lock \
  logbook \
  logger \
  lovelace \
  manual \
  map \
  media_player \
  media_source \
  met \
  mobile_app \
  mpd \
  mqtt \
  my \
  network \
  notify \
  number \
  onboarding \
  panel_custom \
  panel_iframe \
  persistent_notification \
  person \
  proximity \
  python_script \
  radio_browser \
  recorder \
  remote \
  repairs \
  rest \
  safe_mode \
  scene \
  script \
  search \
  select \
  sensor \
  shopping_list \
  siren \
  ssdp \
  stream \
  sun \
  switch \
  switch_as_x \
  system_health \
  system_log \
  tag \
  telegram \
  telegram_bot \
  template \
  time_date \
  timer \
  trace \
  tts \
  upnp \
  usb \
  vacuum \
  wake_on_lan \
  water_heater \
  weather \
  webhook \
  websocket_api \
  workday \
  xiaomi_aqara \
  xiaomi_miio \
  yeelight \
  zeroconf \
  zone \
  ../components

if [ $LUMI_GATEWAY ]; then
  mv zha ../components
fi
cd ..
rm -rf components-orig
cd components

# serve static with gzipped files
sed -i 's/^\( *\)filepath = \(.*\).joinpath(filename).resolve()/\1try:\n\1    filepath = \2.joinpath(Path(str(filename) + ".gz")).resolve()\n\1    if not filepath.exists():\n\1        raise FileNotFoundError()\n\1except Exception as e:\n\1    filepath = \2.joinpath(filename).resolve()/' http/static.py

# replace LRU with simple dict
sed -i 's/from lru import LRU/#/' recorder/core.py
sed -i 's/: LRU.*/: dict = {}/' recorder/core.py
sed -i 's/, "lru-dict==[0-9\.]*"//' recorder/manifest.json
sed -i 's/from lru import LRU/#/' http/static.py
sed -i 's/ LRU.*/ {}/' http/static.py

# relax dependencies
sed -i 's/sqlalchemy==[0-9\.]*/sqlalchemy/' recorder/manifest.json
sed -i 's/pillow==[0-9\.]*/pillow/' image/manifest.json
sed -i 's/, UnidentifiedImageError//' image/__init__.py
sed -i 's/except UnidentifiedImageError/except OSError/' image/__init__.py
sed -i 's/zeroconf==[0-9\.]*/zeroconf/' zeroconf/manifest.json
sed -i 's/netdisco==[0-9\.]*/netdisco/' discovery/manifest.json
sed -i 's/PyNaCl==[0-9\.]*/PyNaCl/' mobile_app/manifest.json
sed -i 's/defusedxml==[0-9\.]*/defusedxml/' ssdp/manifest.json
sed -i 's/netdisco==[0-9\.]*/netdisco/' ssdp/manifest.json

if [ $LUMI_GATEWAY ]; then
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
  sed -i -E 's/"(bellows|zigpy_deconz|zigpy_xbee|zigpy_znp)":/# "\1":/' zha/diagnostics.py
  sed -i -E 's/import (bellows|zigpy_deconz|zigpy_xbee|zigpy_znp)/# import \1/' zha/diagnostics.py
  sed -i -e '/znp = (/,/)/d' -e '/ezsp = (/,/)/d' -e '/deconz = (/,/)/d' -e '/ti_cc = (/,/)/d' -e '/xbee = (/,/)/d' zha/core/const.py
fi

sed -i 's/"cloud",//' default_config/manifest.json
sed -i 's/"dhcp",//' default_config/manifest.json
sed -i 's/"mobile_app",//' default_config/manifest.json
sed -i 's/"updater",//' default_config/manifest.json
sed -i 's/"usb",//' default_config/manifest.json
sed -i 's/"bluetooth",//' default_config/manifest.json
sed -i 's/==[0-9\.]*//g' frontend/manifest.json

cd ../..
# integrations and helper sections leave as is, only nested items
sed -i 's/        "/        # "/' homeassistant/generated/config_flows.py
sed -i 's/    # "mqtt"/    "mqtt"/' homeassistant/generated/config_flows.py
sed -i 's/    # "esphome"/    "esphome"/' homeassistant/generated/config_flows.py
sed -i 's/    # "met"/    "met"/' homeassistant/generated/config_flows.py
sed -i 's/    # "radio_browser"/    "radio_browser"/' homeassistant/generated/config_flows.py
if [ $LUMI_GATEWAY ]; then
  sed -i 's/    # "zha"/    "zha"/' homeassistant/generated/config_flows.py
fi

# disabling all zeroconf services
sed -i 's/^    "_/    "_disabled_/' homeassistant/generated/zeroconf.py
# re-enable required ones
sed -i 's/_disabled_esphomelib./_esphomelib./' homeassistant/generated/zeroconf.py
sed -i 's/_disabled_ipps./_ipps./' homeassistant/generated/zeroconf.py
sed -i 's/_disabled_ipp./_ipp./' homeassistant/generated/zeroconf.py
sed -i 's/_disabled_printer./_printer./' homeassistant/generated/zeroconf.py
sed -i 's/_disabled_miio./_miio./' homeassistant/generated/zeroconf.py

# disabling all supported_brands
sed -i 's/^    /    # /' homeassistant/generated/supported_brands.py

# backport jinja2<3.0 decorator
sed -i 's/from jinja2 import contextfunction, pass_context/from jinja2 import contextfunction, contextfilter as pass_context/' homeassistant/helpers/template.py

# backport orjson to classic json
# helpers
sed -i -e 's/orjson/json/' -e 's/.decode(.*)//' -e 's/option=.*,/\n/' -e 's/.as_posix/.as_posix()\n    if isinstance(obj, (datetime.date, datetime.time)):\n        return obj.isoformat/' -e 's/json_bytes/json_bytes_old/' homeassistant/helpers/json.py
echo 'def json_bytes(data): return json.dumps(data, default=json_encoder_default).encode("utf-8")' >> homeassistant/helpers/json.py
# util
sed -i -e 's/orjson/json/' -e 's/.decode(.*)//' -e 's/option=.*/\n/' homeassistant/util/json.py
# aiohttp_client.py
sed -i -e 's/orjson/json/' -e 's/.decode(.*)//' homeassistant/helpers/aiohttp_client.py

# Patch installation type
sed -i 's/"installation_type": "Unknown"/"installation_type": "Home Assistant on OpenWrt"/' homeassistant/helpers/system_info.py
find . -type f -exec touch {} +
sed -i "s/[>=]=.*//g" setup.cfg

rm -rf /usr/lib/python${PYTHON_VERSION}/site-packages/homeassistant*

if [ ! -f setup.py ]; then
  awk -v RS='dependencies[ ]*=.*?\n\]' -v ORS= '1;NR==1{printf "dependencies = []"}' pyproject.toml > pyproject-new.toml && mv pyproject-new.toml pyproject.toml
  python3 -m pip install .
else
  sed -i 's/install_requires=REQUIRES/install_requires=[]/' setup.py
  python3  setup.py install
fi
cd ../
rm -rf homeassistant-${HOMEASSISTANT_VERSION}/

IP=$(ip a | grep "inet " | cut -d " " -f6 | tail -1 | cut -d / -f1)

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
      - sensor.illuminance_*
      - sensor.btn0_*
      - sensor.temperature_*
      - sensor.humidity_*
      - sensor.presence_*
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
