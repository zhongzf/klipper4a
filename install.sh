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

klipper_setup(){
  ### step 1: clone klipper
  status_msg "Downloading Klipper ..."
  ### clone into fresh klipper dir
  cd "${HOME}" && git clone "$KLIPPER_REPO"
  status_msg "Download complete!"

  ### step 2: create python virtualenv
  create_klipper_virtualenv

  ### step 3: create shared gcode_files and logs folder
  [ ! -d "${HOME}"/gcode_files ] && mkdir -p "${HOME}"/gcode_files
  [ ! -d "${HOME}"/klipper_logs ] && mkdir -p "${HOME}"/klipper_logs

  ### step 4: create klipper plugin
  create_klipper_plugin
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

  mkdir -p $KL_EXTENSIONS_TARGET
  cp "$KL_EXTENSIONS_SRC/manifest.json" "$KL_EXTENSIONS_TARGET/manifest.json"

  KL_START_TARGET="/root/extensions/klipper/start.sh"
  sudo cp "$KL_EXTENSIONS_SRC/start.sh" $KL_START_TARGET
  sudo sed -i "s|%KL_ENV%|$KL_ENV|" $KL_START_TARGET
  sudo sed -i "s|%KL_DIR%|$KL_DIR|" $KL_START_TARGET
  sudo sed -i "s|%KL_LOG%|$KL_LOG|" $KL_START_TARGET
  sudo sed -i "s|%P_CFG%|$P_CFG|" $KL_START_TARGET
  sudo sed -i "s|%P_TMP%|$P_TMP|" $KL_START_TARGET
  sudo sed -i "s|%KL_UDS%|$KL_UDS|" $KL_START_TARGET
  chmod +x $KL_START_TARGET
  chmod 777 $KL_START_TARGET

  cp "$KL_EXTENSIONS_SRC/kill.sh" "$KL_EXTENSIONS_TARGET/kill.sh"
  chmod +x "$KL_EXTENSIONS_TARGET/kill.sh"
  chmod 777 "$KL_EXTENSIONS_TARGET/kill.sh"
}

moonraker_setup(){
  ### step 1: clone moonraker
  status_msg "Downloading Moonraker ..."
  ### clone into fresh moonraker dir
  cd "${HOME}" && git clone $MOONRAKER_REPO
  ok_msg "Download complete!"

  ### step 2: create python virtualenv
  create_moonraker_virtualenv

  ### step 3: create moonraker.conf folder and moonraker.confs
  create_moonraker_conf

  ### step 4: create moonraker plugin
  create_moonraker_plugin
}

create_moonraker_virtualenv(){
  status_msg "Installing python virtual environment..."
  # Create virtualenv if it doesn't already exist
  if [ ! -d "$MOONRAKER_ENV" ]; then
    virtualenv -p /usr/bin/python3 "$MOONRAKER_ENV"
  fi

  ### Install/update dependencies
  "$MOONRAKER_ENV"/bin/pip install -r "$MOONRAKER_DIR"/scripts/moonraker-requirements.txt
}

create_moonraker_conf(){
  PORT=7125
  CFG_PATH="$klipper_cfg_loc"
  LOG_PATH="${HOME}/klipper_logs"
  MR_CONF="$CFG_PATH/moonraker.conf"
  MR_DB="${HOME}/.moonraker_database"
  KLIPPY_UDS="/tmp/klippy_uds"
  MR_CONF_SRC="${SRCDIR}/klipper4a/resources/moonraker.conf"
  mr_ip_list=()
  IP=$(hostname -I | cut -d" " -f1)
  LAN="$(hostname -I | cut -d" " -f1 | cut -d"." -f1-2).0.0/16"

  write_mr_conf(){
    [ ! -d "$CFG_PATH" ] && mkdir -p "$CFG_PATH"
    if [ ! -f "$MR_CONF" ]; then
      status_msg "Creating moonraker.conf in $CFG_PATH ..."
        cp "$MR_CONF_SRC" "$MR_CONF"
        sed -i "s|%PORT%|$PORT|" "$MR_CONF"
        sed -i "s|%CFG%|$CFG_PATH|" "$MR_CONF"
        sed -i "s|%LOG%|$LOG_PATH|" "$MR_CONF"
        sed -i "s|%MR_DB%|$MR_DB|" "$MR_CONF"
        sed -i "s|%UDS%|$KLIPPY_UDS|" "$MR_CONF"
        # if host ip is not in the default ip ranges, replace placeholder
        # otherwise remove placeholder from config
        if ! grep -q "$LAN" "$MR_CONF"; then
          sed -i "s|%LAN%|$LAN|" "$MR_CONF"
        else
          sed -i "/%LAN%/d" "$MR_CONF"
        fi
        sed -i "s|%USER%|${USER}|g" "$MR_CONF"
      ok_msg "moonraker.conf created!"
    else
      warn_msg "There is already a file called 'moonraker.conf'!"
      warn_msg "Skipping..."
    fi
  }

  ### write single instance config
  write_mr_conf
  mr_ip_list+=("$IP:$PORT")
}

create_moonraker_plugin(){    
  CFG_PATH="$klipper_cfg_loc"
  MR_ENV=$MOONRAKER_ENV
  MR_DIR=$MOONRAKER_DIR
  MR_LOG="${HOME}/klipper_logs/moonraker.log"
  MR_CONF="$CFG_PATH/moonraker.conf"

  MR_EXTENSIONS_SRC="${SRCDIR}/klipper4a/resources/extensions/moonraker"
  MR_EXTENSIONS_TARGET="/root/extensions/moonraker"

  mkdir -p $MR_EXTENSIONS_TARGET
  cp "$MR_EXTENSIONS_SRC/manifest.json" "$MR_EXTENSIONS_TARGET/manifest.json"

  MR_START_TARGET="/root/extensions/moonraker/start.sh"
  sudo cp "$MR_EXTENSIONS_SRC/start.sh" $MR_START_TARGET
  sudo sed -i "s|%MR_ENV%|$MR_ENV|" $MR_START_TARGET
  sudo sed -i "s|%MR_DIR%|$MR_DIR|" $MR_START_TARGET
  sudo sed -i "s|%MR_LOG%|$MR_LOG|" $MR_START_TARGET
  sudo sed -i "s|%MR_CONF%|$MR_CONF|" $MR_START_TARGET
  chmod +x $MR_START_TARGET
  chmod 777 $MR_START_TARGET

  cp "$MR_EXTENSIONS_SRC/kill.sh" "$MR_EXTENSIONS_TARGET/kill.sh"
  chmod +x "$MR_EXTENSIONS_TARGET/kill.sh"
  chmod 777 "$MR_EXTENSIONS_TARGET/kill.sh"
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

install_dependencies
klipper_setup
moonraker_setup
fluidd_setup
mainsail_setup