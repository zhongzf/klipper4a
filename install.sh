#!/bin/bash
clear
set -e

### set color variables
yellow=$(echo -en "\e[93m")
default=$(echo -en "\e[39m")

### base variables
klipper_cfg_loc="${HOME}/klipper_config"

KLIPPY_ENV="${HOME}/klippy-env"
KLIPPER_DIR="${HOME}/klipper"
KLIPPER_REPO="https://github.com/Klipper3d/klipper.git"

MOONRAKER_ENV="${HOME}/moonraker-env"
MOONRAKER_DIR="${HOME}/moonraker"
MOONRAKER_REPO="https://github.com/Arksine/moonraker.git"

#fluidd
FLUIDD_DIR=${HOME}/fluidd
FLUIDD_REPO_API="https://api.github.com/repos/fluidd-core/fluidd/releases"
FLUIDD_PORT="8081"

#mainsail
MAINSAIL_DIR=${HOME}/mainsail
MAINSAIL_REPO_API="https://api.github.com/repos/mainsail-crew/mainsail/releases"
MAINSAIL_PORT="8082"

### set some messages
status_msg(){
  echo; echo -e "${yellow}###### $1${default}"
}

### install dependencies
install_dependencies(){
    status_msg "Installing dependencies..."
    apk add git unzip python2 python2-dev libffi-dev make \
        gcc g++ ncurses-dev avrdude gcc-avr binutils-avr \
        avr-libc python3 py3-virtualenv python3-dev \
        freetype-dev fribidi-dev harfbuzz-dev jpeg-dev \
        lcms2-dev openjpeg-dev tcl-dev tiff-dev tk-dev zlib-dev \
        jq patch curl caddy nginx sudo openrc
}

create_klipper_virtualenv(){
  status_msg "Installing python virtual environment..."
  # Create virtualenv if it doesn't already exist
  [ ! -d "${KLIPPY_ENV}" ] && virtualenv -p python2 "${KLIPPY_ENV}"
  # Install/update dependencies
  "${KLIPPY_ENV}"/bin/pip install -r "${KLIPPER_DIR}"/scripts/klippy-requirements.txt
}

create_klipper_plugin(){    
    CFG_PATH="$klipper_cfg_loc"
    KL_ENV=$KLIPPY_ENV
    KL_DIR=$KLIPPER_DIR
    KL_LOG="${HOME}/klipper_logs/klippy.log"
    KL_UDS="/tmp/klippy_uds"
    P_TMP="/tmp/printer"
    P_CFG="$CFG_PATH/printer.cfg"
    P_CFG_SRC="${SRCDIR}/klipper4a/resources/printer.cfg"

    KL_EXTENSIONS_SRC="${SRCDIR}/klipper4a/resources/extensions/klipper"
    KL_EXTENSIONS_TARGET="/root/extensions/klipper"
    KL_START_TARGET="/root/extensions/klipper/start.sh"

    mkdir -p $KL_EXTENSIONS_TARGET
    cp "$KL_EXTENSIONS_SRC/manifest.json" "$KL_START_TARGET/manifest.json"

    sudo cp "$KL_EXTENSIONS_SRC/start.sh" $KL_START_TARGET
    sudo sed -i "s|%KL_ENV%|$KL_ENV|" $KL_START_TARGET
    sudo sed -i "s|%KL_DIR%|$KL_DIR|" $KL_START_TARGET
    sudo sed -i "s|%KL_LOG%|$KL_LOG|" $KL_START_TARGET
    sudo sed -i "s|%P_CFG%|$P_CFG|" $KL_START_TARGET
    sudo sed -i "s|%P_TMP%|$P_TMP|" $KL_START_TARGET
    sudo sed -i "s|%KL_UDS%|$KL_UDS|" $KL_START_TARGET

    chmod +x $KL_START_TARGET
    chmod 777 $KL_START_TARGET

    cp "$KL_EXTENSIONS_SRC/kill.sh" "$KL_START_TARGET/kill.sh"
    chmod +x "$KL_START_TARGET/kill.sh"
    chmod 777 "$KL_START_TARGET/kill.sh"
}

klipper_setup(){
  ### step 1: clone klipper
  status_msg "Downloading Klipper ..."
  ### force remove existing klipper dir and clone into fresh klipper dir
  [ -d "$KLIPPER_DIR" ] && rm -rf "$KLIPPER_DIR"
  cd "${HOME}" && git clone "$KLIPPER_REPO"
  status_msg "Download complete!"

  ### step 2: install klipper dependencies and create python virtualenv
  create_klipper_virtualenv

  ### step 3: create shared gcode_files and logs folder
  [ ! -d "${HOME}"/gcode_files ] && mkdir -p "${HOME}"/gcode_files
  [ ! -d "${HOME}"/klipper_logs ] && mkdir -p "${HOME}"/klipper_logs

  ### step 4: create klipper plugin
  create_klipper_plugin
}


symlink_webui_nginx_log(){
  LPATH="${HOME}/klipper_logs"
  UI_ACCESS_LOG="/var/log/nginx/$1-access.log"
  UI_ERROR_LOG="/var/log/nginx/$1-error.log"
  [ ! -d "$LPATH" ] && mkdir -p "$LPATH"
  if [ -f "$UI_ACCESS_LOG" ] &&  [ ! -L "$LPATH/$1-access.log" ]; then
    status_msg "Creating symlink for $UI_ACCESS_LOG ..."
    ln -s "$UI_ACCESS_LOG" "$LPATH"
    ok_msg "OK!"
  fi
  if [ -f "$UI_ERROR_LOG" ] &&  [ ! -L "$LPATH/$1-error.log" ]; then
    status_msg "Creating symlink for $UI_ERROR_LOG ..."
    ln -s "$UI_ERROR_LOG" "$LPATH"
    ok_msg "OK!"
  fi
}

mainsail_setup(){
  ### get mainsail download url
  MAINSAIL_DL_URL=$(curl -s $MAINSAIL_REPO_API | grep browser_download_url | cut -d'"' -f4 | head -1)

  ### remove existing and create fresh mainsail folder, then download mainsail
  [ -d "$MAINSAIL_DIR" ] && rm -rf "$MAINSAIL_DIR"
  mkdir "$MAINSAIL_DIR" && cd $MAINSAIL_DIR
  status_msg "Downloading Mainsail $MAINSAIL_VERSION ..."
  wget "$MAINSAIL_DL_URL" && ok_msg "Download complete!"

  ### extract archive
  status_msg "Extracting archive ..."
  unzip -q -o *.zip && ok_msg "Done!"

  ### delete downloaded zip
  status_msg "Remove downloaded archive ..."
  rm -rf *.zip && ok_msg "Done!"
}


fluidd_setup(){
  ### get fluidd download url
  FLUIDD_DL_URL=$(curl -s $FLUIDD_REPO_API | grep browser_download_url | cut -d'"' -f4 | head -1)

  ### remove existing and create fresh fluidd folder, then download fluidd
  [ -d "$FLUIDD_DIR" ] && rm -rf "$FLUIDD_DIR"
  mkdir "$FLUIDD_DIR" && cd $FLUIDD_DIR
  status_msg "Downloading Fluidd $FLUIDD_VERSION ..."
  wget "$FLUIDD_DL_URL" && ok_msg "Download complete!"

  ### extract archive
  status_msg "Extracting archive ..."
  unzip -q -o *.zip && ok_msg "Done!"

  ### delete downloaded zip
  status_msg "Remove downloaded archive ..."
  rm -rf *.zip && ok_msg "Done!"
}


klipper_setup