#!/bin/bash
NEW_VERSION=104

RTKBASE_USER=rtkbase
RTKBASE_PATH=/usr/local/${RTKBASE_USER}
RTKBASE_GIT=${RTKBASE_PATH}/rtkbase
RTKBASE_UPDATE=${RTKBASE_PATH}/update
RTKBASE_TOOLS=${RTKBASE_GIT}/tools
RTKBASE_WEB=${RTKBASE_GIT}/web_app
RTKBASE_RECV=${RTKBASE_GIT}/receiver_cfg
BASEDIR=`realpath $(dirname $(readlink -f "$0"))`
BASENAME=`basename $(readlink -f "$0")`
ORIGDIR=`pwd`
#echo BASEDIR=${BASEDIR} BASENAME=${BASENAME}
RECVPORT=/dev/serial0
RTKBASE_INSTALL=rtkbase_install.sh
RUN_CAST=run_cast.sh
SET_BASE_POS=UnicoreSetBasePos.sh
UNICORE_SETTIGNS=UnicoreSettings.sh
UNICORE_CONFIGURE=UnicoreConfigure.sh
SETTINGS_NOW=${RTKBASE_GIT}/settings.conf
SETTINGS_SAVE=${RTKBASE_GIT}/settings.save
NMEACONF=NmeaConf
CONF_TAIL=RTCM3_OUT.txt
CONF980=UM980_${CONF_TAIL}
CONF982=UM982_${CONF_TAIL}
SERVER_PATCH=server_py.patch
STATUS_PATCH=status_js.patch
BASE_PATCH=base_html.patch
SETTING_PATCH=settings_js.patch
SYSCONGIG=RtkbaseSystemConfigure.sh
SYSSERVICE=RtkbaseSystemConfigure.service
SYSPROXY=RtkbaseSystemConfigureProxy.sh
TUNE_POWER=tune_power.sh
CONFIG=config.txt
RTKLIB=rtklib
SERVICE_PATH=/etc/systemd/system
PI=pi
BANNER=/etc/ssh/sshd_config.d/rename_user.conf
VERSION=version.txt

lastcode=N
exitcode=0

ExitCodeCheck(){
  lastcode=$1
  if [[ $lastcode > $exitcode ]]
  then
     exitcode=${lastcode}
     #echo exitcode=${exitcode}
  fi
}

configure_cmdline(){
  CMDLINE=$1/cmdline.txt
  #echo \$1=${1} CMDLINE=${CMDLINE}

  if [[ -f ${CMDLINE} ]]
  then
     DONT_EDIT=`grep "^DO NOT EDIT THIS FILE" ${CMDLINE}`
     #echo DONT_EDIT_${CMDLINE}=${DONT_EDIT}
     if [[ "${DONT_EDIT}" == "" ]]
     then
        HAVE_CONSOLE_LOGIN=`grep "console=serial0" ${CMDLINE}`
        #echo HAVE_CONSOLE_LOGIN=${HAVE_CONSOLE_LOGIN}

        if [[ ${HAVE_CONSOLE_LOGIN} != "" ]]
        then
           sed -i s/console=serial[0-9],[0-9]*\ //  "${CMDLINE}"
           ExitCodeCheck $?
           #cat ${CMDLINE}
           #echo
           echo Cnahged ${CMDLINE}
           NEEDREBOOT=Y
        fi
     fi
  fi
}

configure_config(){
  BOOTCONFIG=$1/config.txt
  #echo \$1=${1} BOOTCONFIG=${BOOTCONFIG}
  if [[ -f ${BOOTCONFIG} ]]
  then
     DONT_EDIT=`grep "^DO NOT EDIT THIS FILE" ${BOOTCONFIG}`
     #echo DONT_EDIT_${BOOTCONFIG}=${DONT_EDIT}
     if [[ "${DONT_EDIT}" == "" ]]
     then
        HAVE_UART=`grep "^enable_uart=" ${BOOTCONFIG}`
        #echo HAVE_UART=${HAVE_UART}
        ENABLED_UART=`grep "^enable_uart=1" ${BOOTCONFIG}`
        #echo ENABLED_UART=${ENABLED_UART}
        HAVE_MINI_BT=`grep "^dtoverlay=miniuart-bt" ${BOOTCONFIG}`
        #echo HAVE_MINI_BT=${HAVE_MINI_BT}
        HAVE_CORE_FREQ=`grep "^core_freq=250" ${BOOTCONFIG}`
        #echo HAVE_CORE_FREQ=${HAVE_CORE_FREQ}

        if [[ ${HAVE_UART} == "" ]] || [[ ${HAVE_MINI_BT} == "" ]] || [[ ${HAVE_CORE_FREQ} == "" ]]
        then
           echo [all] >> ${BOOTCONFIG}
           echo >> ${BOOTCONFIG}
           NEEDREBOOT=Y
        fi

        if [[ ${HAVE_UART} == "" ]]
        then
           echo enable_uart=1 >> ${BOOTCONFIG}
           echo Uart0 added to ${BOOTCONFIG}
        elif [[ ${ENABLED_UART} == "" ]]
        then
           sed -i s/^enable_uart=.*/enable_uart=1/  "${BOOTCONFIG}"
           ExitCodeCheck $?
           echo Uart0 enabled at ${BOOTCONFIG}
           NEEDREBOOT=Y
        fi

        if [[ ${HAVE_MINI_BT} == "" ]]
        then
           echo dtoverlay=miniuart-bt >> ${BOOTCONFIG}
           echo Bluetooth change to miniUART into ${BOOTCONFIG}
        fi

        if [[ ${HAVE_CORE_FREQ} == "" ]]
        then
           echo core_freq=250 >> ${BOOTCONFIG}
           echo Core freq added to ${BOOTCONFIG}
        fi
     fi
  fi
}

replace_config(){
  BOOTCONFIG=$1/${CONFIG}
  NEWCONFIG=${BASEDIR}/${CONFIG}
  #echo \$1=${1} BOOTCONFIG=${BOOTCONFIG} NEWCONFIG=${NEWCONFIG}
  if [[ -f ${BOOTCONFIG} ]]
  then
     DONT_EDIT=`grep "^DO NOT EDIT THIS FILE" ${BOOTCONFIG}`
     #echo DONT_EDIT_${BOOTCONFIG}=${DONT_EDIT}
     if [[ "${DONT_EDIT}" == "" ]]
     then
        #echo diff -q ${NEWCONFIG} ${BOOTCONFIG}
        IS_DIFF=`diff -q ${NEWCONFIG} ${BOOTCONFIG}`
        #echo IS_DIFF=${IS_DIFF}
        if [[ "${IS_DIFF}" != "" ]]
        then
           #echo cp ${BOOTCONFIG} ${BOOTCONFIG}.old
           cp ${BOOTCONFIG} ${BOOTCONFIG}.old
           ExitCodeCheck $?
           #echo mv ${NEWCONFIG} ${BOOTCONFIG}
           mv ${NEWCONFIG} ${BOOTCONFIG}
           ExitCodeCheck $?
           NEEDREBOOT=Y
           echo ${BOOTCONFIG} replaced. Old version in the ${BOOTCONFIG}.old
        fi
     fi
  fi
}

check_version(){
  if [ -f ${BASEDIR}/${VERSION} ]
  then
     NEW_VERSION=`cat ${BASEDIR}/${VERSION}`
     ExitCodeCheck $?
  fi
  #echo BASEDIR=${BASEDIR} RTKBASE_PATH=${RTKBASE_PATH}
  if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]] && [ -f ${RTKBASE_PATH}/${VERSION} ]
  then
     echo '################################'
     echo 'CHECK VERSION'
     echo '################################'
     UPDATE=Y
     OLD_VERSION=`cat ${RTKBASE_PATH}/${VERSION}`
     ExitCodeCheck $?
     #echo NEW_VERSION=${NEW_VERSION} OLD_VERSION=${OLD_VERSION}
     if [ "${NEW_VERSION}" -lt "${OLD_VERSION}" ]
     then
        echo Already installed version'('${OLD_VERSION}')' is newer, than install.sh version'('${NEW_VERSION}')'. Exiting
        #echo rm -f ${FILES_EXTRACT}
        rm -f ${FILES_EXTRACT}
        exit
     else
        echo Update from version ${OLD_VERSION} to version ${NEW_VERSION}
        if [ -f ${SETTINGS_NOW} ]
        then
           #echo cp ${SETTINGS_NOW} ${SETTINGS_SAVE}
           cp ${SETTINGS_NOW} ${SETTINGS_SAVE}
           ExitCodeCheck $?
        fi
     fi
  else
     OLD_VERSION=${NEW_VERSION}
     UPDATE=N
  fi
}

check_boot_configiration(){
   echo '################################'
   if have_full
   then
      echo 'CHECK BOOT CONFIGURATION'
   else
      echo 'REPLACE BOOT CONFIGURATION'
   fi
   echo '################################'

   configure_cmdline /boot
   configure_cmdline /boot/firmware

   if have_full
   then
      configure_config /boot
      configure_config /boot/firmware
   else
      replace_config /boot
      replace_config /boot/firmware
   fi
   #hciuart_enabled=$(systemctl is-enabled hciuart.service)
   #[[ "${hciuart_enabled}" != "disabled" ]] && [[ "${hciuart_enabled}" != "masked" ]] && systemctl disable hciuart
}

is_packet_not_installed(){
   instaled=`dpkg-query -W ${1} 2>/dev/null | grep ${1}`
   #echo 1=${1} instaled=${instaled}
   if [[ ${instaled} != "" ]]
   then
      return 1
   fi
}

NEED_INSTALL=
install_packet_if_not_installed(){
   is_packet_not_installed ${1} && NEED_INSTALL="${NEED_INSTALL} ${1}"
   #echo NEED_INSTALL=${NEED_INSTALL} \$\1=${1}
}

restart_as_root(){
   WHOAMI=`whoami`
   if [[ ${WHOAMI} != "root" ]]
   then
      #echo sudo ${0} ${1}
      sudo ${0} ${1}
      #echo exit after sudo
      exit $?
   fi
   #echo i am ${WHOAMI}$
}

do_reboot(){
   #echo NEEDREBOOT=${NEEDREBOOT}
   if [[ ${NEEDREBOOT} == "Y" ]]
   then
      echo Please try again ${0} after reboot
      #echo rm -f ${FILES_EXTRACT}
      rm -f ${FILES_EXTRACT}
      reboot now
      exit
   fi

}

info_reboot(){
   #echo NEEDREBOOT=${NEEDREBOOT}
   if [[ ${NEEDREBOOT} == "Y" ]]
   then
      echo Please REBOOT, because start configuration changed!
   fi
}

check_port(){
   if [[ ! -c "${RECVPORT}" ]]
   then
      echo port ${RECVPORT} not found. Setup port and try again
      #echo rm -f ${FILES_EXTRACT}
      rm -f ${FILES_EXTRACT}
      exit
   fi
}

install_additional_utilies(){
   echo '################################'
   echo 'INSTALL ADDITIONAL UTILITIES'
   echo '################################'

   NEED_INSTALL=
   install_packet_if_not_installed avahi-utils
   install_packet_if_not_installed avahi-daemon
   install_packet_if_not_installed uuid
   install_packet_if_not_installed cpufrequtils
   install_packet_if_not_installed uhubctl
   install_packet_if_not_installed ntpdate

   #echo NEED_INSTALL=${NEED_INSTALL}
   if [[ "${NEED_INSTALL}" != "" ]]
   then
      apt-get install -y ${NEED_INSTALL}
      ExitCodeCheck $?
      NEED_INSTALL=
   fi
}

delete_pi_user(){
   FOUND=`sed 's/:.*//' /etc/passwd | grep "${PI}"`
   if [[ -n "${FOUND}" ]]
   then
      echo '################################'
      echo 'DELETE PI USER'
      echo '################################'
      userdel -r "${PI}"
      ExitCodeCheck $?
   fi
   if [[ -f "${BANNER}" ]]
   then
      rm -r "${BANNER}"
      if ! ischroot
      then
         systemctl restart sshd
      fi
   fi
}

change_hostname(){
   echo '################################'
   echo 'CHANGE HOSTNAME IF STANDART'
   echo '################################'
   STANDART_HOST=raspberrypi
   #STANDART_HOST=rtkbase
   RTKBASE_HOST=${RTKBASE_USER}
   #RTKBASE_HOST=raspberrypi
   CHANGE_HOST_RTKBASE=Y
   CHANGE_HOST_NOW=N

   NOW_HOST=`hostname`
   #echo NOW_HOST=$NOW_HOST
   if [[ $NOW_HOST != $STANDART_HOST ]]
   then
      CHANGE_HOST_RTKBASE=N
   fi

   HOSTNAME=/etc/hostname
   NOW_HOSTNAME=`cat $HOSTNAME`
   #echo NOW_HOSTNAME=$NOW_HOSTNAME
   if [[ $NOW_HOSTNAME != $STANDART_HOST ]]
   then
      CHANGE_HOST_RTKBASE=N
   fi
   if [[ $NOW_HOSTNAME != $NOW_HOST ]]
   then
       CHANGE_HOST_NOW=Y
   fi

   HOSTS=/etc/hosts
   NOW_HOSTS=`grep "127.0.1.1" $HOSTS | awk -F ' ' '{print $2}'`
   #echo NOW_HOSTS=$NOW_HOSTS
   if [[ $NOW_HOSTS != $STANDART_HOST ]]
   then
      CHANGE_HOST_RTKBASE=N
   fi
   if [[ $NOW_HOSTS != $NOW_HOST ]]
   then
       CHANGE_HOST_NOW=Y
   fi

   #echo 1=${1}
   RESTART_AVAHI=N
   if [[ $CHANGE_HOST_RTKBASE = Y ]]
   then
      echo Set \"$RTKBASE_HOST\" as host
      hostname $RTKBASE_HOST
      echo $RTKBASE_HOST >$HOSTNAME
      sed -i s/127\.0\.1\.1.*/127\.0\.1\.1\ $RTKBASE_HOST/ "$HOSTS"
      ExitCodeCheck $?
      RESTART_AVAHI=Y
   elif [[ $CHANGE_HOST_NOW = Y ]]
   then
      if [[ "${1}" != "0" ]]
      then
         echo Set \"$NOW_HOST\" as host
         echo $NOW_HOST >$HOSTNAME
         sed -i s/127\.0\.1\.1.*/127\.0\.1\.1\ $NOW_HOST/ "$HOSTS"
         ExitCodeCheck $?
         RESTART_AVAHI=Y
      else
         echo WARNING!!! hostname=$NOW_HOST /etc/hostname=$NOW_HOSTNAME /etc/hosts resolve $NOW_HOSTS
      fi
   fi
   if ! ischroot
   then
      if [[ $RESTART_AVAHI = Y ]]
      then
         systemctl is-active --quiet avahi-daemon && sudo systemctl restart avahi-daemon
      fi
   fi
}

unpack_files(){
   if [[ "${FILES_EXTRACT}" != "" ]]
   then
      echo '################################'
      echo 'UNPACK FILES'
      echo '################################'

      # Find __ARCHIVE__ marker, read archive content and decompress it
      ARCHIVE=$(awk '/^__ARCHIVE__/ {print NR + 1; exit 0; }' "${0}")
      # Check if there is some content after __ARCHIVE__ marker (more than 100 lines)
      [[ $(sed -n '/__ARCHIVE__/,$p' "${0}" | wc -l) -lt 100 ]] && echo "UM980_RPI_Hat_RtkBase isn't bundled inside install.sh" && exit 1  
      tail -n+${ARCHIVE} "${0}" | tar xpJv --no-same-owner --no-same-permissions  --wildcards -C ${BASEDIR} ${FILES_EXTRACT}
      ExitCodeCheck $?
   fi
}

stop_rtkbase_services(){
  if ! ischroot
  then
     echo '################################'
     echo 'STOP RTKBASE SERVICES'
     echo '################################'
      #store service status before upgrade
      rtkbase_web_active=$(systemctl is-active rtkbase_web.service)
      str2str_active=$(systemctl is-active str2str_tcp)
      str2str_ntrip_A_active=$(systemctl is-active str2str_ntrip_A)
      str2str_ntrip_B_active=$(systemctl is-active str2str_ntrip_B)
      str2str_local_caster=$(systemctl is-active str2str_local_ntrip_caster)
      str2str_rtcm=$(systemctl is-active str2str_rtcm_svr)
      str2str_serial=$(systemctl is-active str2str_rtcm_serial)
      str2str_file=$(systemctl is-active str2str_file)

      # stop previously running services
      [ "${str2str_ntrip_A_active}" = "active" ] && systemctl stop str2str_ntrip_A
      [ "${str2str_ntrip_B_active}" = "active" ] && systemctl stop str2str_ntrip_B
      [ "${str2str_local_caster}" = "active" ] && systemctl stop str2str_local_ntrip_caster
      [ "${str2str_rtcm}" = "'active" ] && systemctl stop str2str_rtcm_svr
      [ "${str2str_serial}" = "active" ] && systemctl stop str2str_rtcm_serial
      [ "${str2str_file}" = "active" ] && systemctl stop str2str_file
      if [ "${str2str_active}" = "active" ] || [ "${str2str_active}" = "activating" ]
      then
         #echo systemctl stop str2str_tcp \&\& sleep 2
         systemctl stop str2str_tcp && sleep 2
      fi
      [ "${rtkbase_web_active}" = "active" ] && systemctl stop rtkbase_web.service
   fi
}

add_rtkbase_user(){
   echo '################################'
   echo 'ADD RTKBASE USER'
   echo '################################'

   if [[ ! -d "${RTKBASE_PATH}" ]]
   then
      #echo mkdir ${RTKBASE_PATH}
      mkdir ${RTKBASE_PATH}
      ExitCodeCheck $?
   fi

   if [[ ! -d "${RTKBASE_UPDATE}" ]]
   then
      #echo mkdir ${RTKBASE_UPDATE}
      mkdir ${RTKBASE_UPDATE}
      ExitCodeCheck $?
   fi

   HAVEUSER=`cat /etc/passwd | grep ${RTKBASE_USER}`
   #echo HAVEUSER=${HAVEUSER}
   if [[ ${HAVEUSER} == "" ]]
   then
      #echo adduser --comment "RTKBase user" --disabled-password --home ${RTKBASE_PATH} ${RTKBASE_USER}
      adduser --comment "RTKBase user" --disabled-password --home ${RTKBASE_PATH} ${RTKBASE_USER}
      ExitCodeCheck $?
   fi

   usermod -a -G plugdev,dialout ${RTKBASE_USER}
   ExitCodeCheck $?

   RTKBASE_SUDOER=/etc/sudoers.d/${RTKBASE_USER}
   #echo RTKBASE_SUDOER=${RTKBASE_SUDOER}
   if [[ ! -f "${RTKBASE_SUDOER}" ]]
   then
      #echo echo "rtkbase ALL=NOPASSWD: ALL" \> ${RTKBASE_SUDOER}
      echo "rtkbase ALL=NOPASSWD: ALL" > ${RTKBASE_SUDOER}
   fi
}

install_rtklib() {
    echo '################################'
    echo 'INSTALLING RTKLIB'
    echo '################################'
    #echo chmod 711 ${BASEDIR}/${RTKLIB}/*
    chmod 711 ${BASEDIR}/${RTKLIB}/*
    ExitCodeCheck $?
    #echo mv ${BASEDIR}/${RTKLIB}/* /usr/local/bin/
    mv ${BASEDIR}/${RTKLIB}/* /usr/local/bin/
    ExitCodeCheck $?
    #ls -la /usr/local/bin/
    #echo rm -rf ${BASEDIR}/${RTKLIB}
    rm -rf ${BASEDIR}/${RTKLIB}
    ExitCodeCheck $?
}

copy_rtkbase_install_file(){
  echo '################################'
  echo 'COPY RTKBASE INSTALL FILE'
  echo '################################'

  CACHE_PIP=${RTKBASE_PATH}/.cache/pip
  #echo CACHE_PIP=${CACHE_PIP}
  if [[ ! -d ${CACHE_PIP} ]]
  then
     #echo mkdir -p ${CACHE_PIP}
     mkdir -p ${CACHE_PIP}
     ExitCodeCheck $?
  fi
  #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${CACHE_PIP}
  chown ${RTKBASE_USER}:${RTKBASE_USER} ${CACHE_PIP}
  ExitCodeCheck $?

  #echo BASEDIR=${BASEDIR} RTKBASE_PATH=${RTKBASE_PATH}
  if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]]
  then
     #echo mv ${BASEDIR}/${RTKBASE_INSTALL} ${RTKBASE_PATH}/
     mv ${BASEDIR}/${RTKBASE_INSTALL} ${RTKBASE_PATH}/
     ExitCodeCheck $?
  fi
  #echo chmod +x ${RTKBASE_PATH}/${RTKBASE_INSTALL}
  chmod +x ${RTKBASE_PATH}/${RTKBASE_INSTALL}
  ExitCodeCheck $?

  if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]]
  then
     #echo mv ${BASEDIR}/${VERSION} ${RTKBASE_PATH}/
     mv ${BASEDIR}/${VERSION} ${RTKBASE_PATH}/
     ExitCodeCheck $?
  fi
}

install_rtkbase_system_configure(){
  echo '################################'
  echo 'INSTALL RTKBASE SYSTEM CONFIGURE'
  echo '################################'

  #echo BASEDIR=${BASEDIR} RTKBASE_PATH=${RTKBASE_PATH}
  if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]]
  then
     #echo mv ${BASEDIR}/${SYSCONGIG} ${RTKBASE_PATH}/
     mv ${BASEDIR}/${SYSCONGIG} ${RTKBASE_PATH}/
     ExitCodeCheck $?
  fi
  #echo chmod +x ${RTKBASE_PATH}/${SYSCONGIG}
  chmod +x ${RTKBASE_PATH}/${SYSCONGIG}
  ExitCodeCheck $?

  if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]]
  then
     #echo mv ${BASEDIR}/${SYSPROXY} ${RTKBASE_PATH}/
     mv ${BASEDIR}/${SYSPROXY} ${RTKBASE_PATH}/
     ExitCodeCheck $?
  fi
  #echo chmod +x ${RTKBASE_PATH}/${SYSPROXY}
  chmod +x ${RTKBASE_PATH}/${SYSPROXY}
  ExitCodeCheck $?

  #echo mv ${BASEDIR}/${SYSSERVICE} ${SERVICE_PATH}/
  mv ${BASEDIR}/${SYSSERVICE} ${SERVICE_PATH}/
  ExitCodeCheck $?

  if ! ischroot
  then
     #echo systemctl daemon-reload
     systemctl daemon-reload
  fi
  #echo systemctl enable ${SYSSERVICE}
  systemctl enable ${SYSSERVICE}
  ExitCodeCheck $?
}

install_tune_power(){
  echo '################################'
  echo 'INSTALL POWER TUNE'
  echo '################################'

  #echo BASEDIR=${BASEDIR} RTKBASE_PATH=${RTKBASE_PATH}
  if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]]
  then
     #echo mv ${BASEDIR}/${TUNE_POWER} ${RTKBASE_PATH}/
     mv ${BASEDIR}/${TUNE_POWER} ${RTKBASE_PATH}/
     ExitCodeCheck $?
  fi
  #echo chmod +x ${RTKBASE_PATH}/${TUNE_POWER}
  chmod +x ${RTKBASE_PATH}/${TUNE_POWER}
  ExitCodeCheck $?
}

rtkbase_install(){
   #echo ${RTKBASE_PATH}/${RTKBASE_INSTALL} -u ${RTKBASE_USER} -j -d -r -t -g
   ${RTKBASE_PATH}/${RTKBASE_INSTALL} -u ${RTKBASE_USER} -j -d -t -g
   ExitCodeCheck $?
   #echo rm -f ${RTKBASE_PATH}/${RTKBASE_INSTALL}
   rm -f ${RTKBASE_PATH}/${RTKBASE_INSTALL}
   #echo chown -R ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}
   chown -R ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}
   ExitCodeCheck $?
}

configure_for_unicore(){
   echo '################################'
   echo 'CONFIGURE FOR UNICORE'
   echo '################################'

   #echo cp ${BASEDIR}/${RUN_CAST} ${RTKBASE_GIT}/
   mv ${BASEDIR}/${RUN_CAST} ${RTKBASE_GIT}/
   ExitCodeCheck $?
   #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}/${RUN_CAST}
   chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}/${RUN_CAST}
   ExitCodeCheck $?

   #echo mv ${BASEDIR}/${SET_BASE_POS} ${RTKBASE_GIT}/
   mv ${BASEDIR}/${SET_BASE_POS} ${RTKBASE_GIT}/
   ExitCodeCheck $?
   #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}/${SET_BASE_POS}
   chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}/${SET_BASE_POS}
   ExitCodeCheck $?
   #echo chmod +x ${RTKBASE_GIT}/${SET_BASE_POS}
   chmod +x ${RTKBASE_GIT}/${SET_BASE_POS}
   ExitCodeCheck $?

   #echo mv ${BASEDIR}/${NMEACONF} ${RTKBASE_GIT}/
   mv ${BASEDIR}/${NMEACONF} ${RTKBASE_GIT}/
   ExitCodeCheck $?
   #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}/${NMEACONF}
   chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_GIT}/${NMEACONF}
   ExitCodeCheck $?
   #echo chmod +x ${RTKBASE_GIT}/${NMEACONF}
   chmod +x ${RTKBASE_GIT}/${NMEACONF}
   ExitCodeCheck $?

   #echo mv ${BASEDIR}/${UNICORE_CONFIGURE} ${RTKBASE_TOOLS}/
   mv ${BASEDIR}/${UNICORE_CONFIGURE} ${RTKBASE_TOOLS}/
   ExitCodeCheck $?
   #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE}
   chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE}
   ExitCodeCheck $?
   #echo chmod +x ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE}
   chmod +x ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE}
   ExitCodeCheck $?

   #echo mv ${BASEDIR}/${CONF980} ${RTKBASE_RECV}/
   mv ${BASEDIR}/${CONF980} ${RTKBASE_RECV}/
   ExitCodeCheck $?
   #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_RECV}/${CONF980}
   chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_RECV}/${CONF980}
   ExitCodeCheck $?

   #echo mv ${BASEDIR}/${CONF982} ${RTKBASE_RECV}/
   mv ${BASEDIR}/${CONF982} ${RTKBASE_RECV}/
   ExitCodeCheck $?
   #echo chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_RECV}/${CONF982}
   chown ${RTKBASE_USER}:${RTKBASE_USER} ${RTKBASE_RECV}/${CONF982}
   ExitCodeCheck $?

   SERVER_PY=${RTKBASE_WEB}/server.py
   #echo SERVER_PY=${SERVER_PY}
   patch -f ${SERVER_PY} ${BASEDIR}/${SERVER_PATCH}
   ExitCodeCheck $?
   chmod 644 ${SERVER_PY}
   ExitCodeCheck $?

   STATUS_JS=${RTKBASE_WEB}/static/status.js
   #echo STATUS_JS=${STATUS_JS}
   patch -f ${STATUS_JS} ${BASEDIR}/${STATUS_PATCH}
   ExitCodeCheck $?
   chmod 644 ${STATUS_JS}
   ExitCodeCheck $?

   SETTING_JS=${RTKBASE_WEB}/static/settings.js
   #echo SETTING_JS=${SETTING_JS}
   patch -f ${SETTING_JS} ${BASEDIR}/${SETTING_PATCH}
   ExitCodeCheck $?
   chmod 644 ${SETTING_JS}
   ExitCodeCheck $?

   BASE_HTML=${RTKBASE_WEB}/templates/base.html
   #echo BASE_HTML=${BASE_HTML}
   patch -f ${BASE_HTML} ${BASEDIR}/${BASE_PATCH}
   ExitCodeCheck $?
   chmod 644 ${BASE_HTML}
   ExitCodeCheck $?

   SETTINGS_HTML=${RTKBASE_WEB}/templates/settings.html
   #echo SETTINGS_HTML=${SETTINGS_HTML}
   sudo -u ${RTKBASE_USER} sed -i s/\>File\ rotation.*\:\ \</\>File\ rotation\ time\ \(in\ hour\)\:\ \</ ${SETTINGS_HTML}
   ExitCodeCheck $?
   sudo -u ${RTKBASE_USER} sed -i s/\>File\ overlap.*\:\ \</\>File\ overlap\ time\ \(in\ seconds\)\:\ \</ ${SETTINGS_HTML}
   ExitCodeCheck $?
   sudo -u ${RTKBASE_USER} sed -i s/\>Archive\ dur.*\:\ \</\>Archive\ duration\ \(in\ days\)\:\ \</ ${SETTINGS_HTML}
   ExitCodeCheck $?

   if ! ischroot
   then
      systemctl is-active --quiet rtkbase_web.service && sudo systemctl restart rtkbase_web.service
   fi
}

configure_settings(){
   if [ -f ${SETTINGS_SAVE} ]
   then
      echo '################################'
      echo 'RESTORE SETTINGS'
      echo '################################'

      #echo cp ${SETTINGS_SAVE} ${SETTINGS_NOW}
      mv ${SETTINGS_SAVE} ${SETTINGS_NOW}
      ExitCodeCheck $?

      #echo rm -f ${BASEDIR}/${UNICORE_SETTIGNS}
      rm -f ${BASEDIR}/${UNICORE_SETTIGNS}
   else
      echo '################################'
      echo 'CONFIGURE SETTINGS'
      echo '################################'

      #echo BASEDIR=${BASEDIR} RTKBASE_PATH=${RTKBASE_PATH}
      if [[ "${BASEDIR}" != "${RTKBASE_PATH}" ]]
      then
         #echo mv ${BASEDIR}/${UNICORE_SETTIGNS} ${RTKBASE_PATH}/
         mv ${BASEDIR}/${UNICORE_SETTIGNS} ${RTKBASE_PATH}/
         ExitCodeCheck $?
      fi
      #echo chmod +x ${RTKBASE_PATH}/${UNICORE_SETTIGNS}
      chmod +x ${RTKBASE_PATH}/${UNICORE_SETTIGNS}
      ExitCodeCheck $?
      #echo ${RTKBASE_PATH}/${UNICORE_SETTIGNS} ${RECVNAME}
      ${RTKBASE_PATH}/${UNICORE_SETTIGNS}
      ExitCodeCheck $?

      #echo rm -f ${RTKBASE_PATH}/${UNICORE_SETTIGNS}
      rm -f ${RTKBASE_PATH}/${UNICORE_SETTIGNS}
   fi
}

configure_gnss(){
   if [[ "${UPDATE}" != "Y" ]] || ! have_full
   then
      #echo ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE} -u ${RTKBASE_USER} -c
      ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE} -u ${RTKBASE_USER} -e
      ExitCodeCheck $?

      #echo ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE} -u ${RTKBASE_USER} -c
      ${RTKBASE_TOOLS}/${UNICORE_CONFIGURE} -u ${RTKBASE_USER} -c
      ExitCodeCheck $?

      if ! ischroot
      then
         systemctl is-active --quiet rtkbase_web.service && sudo systemctl restart rtkbase_web.service
      fi
   fi
}

start_rtkbase_services(){
  #echo ${RTKBASE_TOOLS}/insall.sh -u ${RTKBASE_USER} -s
  ${RTKBASE_TOOLS}/install.sh -u ${RTKBASE_USER} -s
  ExitCodeCheck $?
}

delete_garbage(){
   if [[ "${FILES_DELETE}" != "" ]]
   then
      echo '################################'
      echo 'DELETE GARBAGE'
      echo '################################'

      #echo rm -f ${FILES_DELETE}
      rm -f ${FILES_DELETE}
      #echo \[ $exitcode = 0 \] \&\& have_receiver \&\& echo rm -f ${BASENAME}
      [ $exitcode = 0 ] && have_receiver && rm -f ${BASENAME}
   fi
}

info_open(){
   NOW_HOST=`hostname`
   if [ $exitcode = 0 ]
   then
      echo You can open your browser to http://${NOW_HOST}.local into local network
   else
      echo exitcode = $exitcode Check bugs in this output
   fi
}

HAVE_RECEIVER=0
HAVE_PHASE1=0
HAVE_FULL=0

have_receiver(){
   return ${HAVE_RECEIVER}
}
have_phase1(){
   return ${HAVE_PHASE1}
}
have_full(){
   return ${HAVE_FULL}
}

BASE_EXTRACT="${NMEACONF} ${CONF980} ${CONF982} ${UNICORE_CONFIGURE} \
              ${RUN_CAST} ${SET_BASE_POS} ${UNICORE_SETTIGNS} \
              ${RTKBASE_INSTALL} ${SYSCONGIG} ${SYSSERVICE} ${SYSPROXY} \
              ${SERVER_PATCH} ${STATUS_PATCH} ${TUNE_POWER} ${CONFIG} \
              ${RTKLIB}/* ${VERSION} ${SETTING_PATCH} ${BASE_PATCH}"
FILES_EXTRACT="${BASE_EXTRACT} uninstall.sh"
FILES_DELETE="${SERVER_PATCH} ${STATUS_PATCH} ${SETTING_PATCH} ${BASE_PATCH} ${CONFIG}"

check_phases(){
   if [[ ${1} == "-1" ]]
   then
      HAVE_RECEIVER=1
      HAVE_PHASE1=0
      HAVE_FULL=1
      FILES_EXTRACT="${BASE_EXTRACT}"
   elif [[ ${1} == "-2" ]]
   then
      HAVE_RECEIVER=0
      HAVE_PHASE1=1
      HAVE_FULL=1
      FILES_EXTRACT=
   elif [[ ${1} == "-u" ]]
   then
      FILES_EXTRACT="${BASE_EXTRACT}"
   elif [[ ${1} != "" ]]
   then
      echo Invalid argument \"${1}\"
      exit 1
   fi

   #echo HAVE_RECEIVER=${HAVE_RECEIVER} HAVE_PHASE1=${HAVE_PHASE1} HAVE_FULL=${HAVE_FULL}
   #echo FILES_EXTRACT=${FILES_EXTRACT}
   #echo FILES_DELETE=${FILES_DELETE}
}

restart_as_root ${1}
check_phases ${1}
have_phase1 && export LANG=C
unpack_files
have_phase1 && check_version
have_phase1 && check_boot_configiration
have_full && do_reboot
have_receiver && check_port
have_phase1 && install_additional_utilies
have_full || delete_pi_user
have_receiver && change_hostname ${HAVE_FULL}
stop_rtkbase_services
have_phase1 && add_rtkbase_user
have_phase1 && install_rtkbase_system_configure
have_phase1 && install_tune_power
have_phase1 && install_rtklib
#echo cd ${RTKBASE_PATH}
cd ${RTKBASE_PATH}
have_phase1 && copy_rtkbase_install_file
have_phase1 && rtkbase_install
have_phase1 && configure_for_unicore
have_phase1 && configure_settings
have_receiver && configure_gnss
have_receiver && start_rtkbase_services
#echo cd ${BASEDIR}
cd ${BASEDIR}
have_receiver && delete_garbage
cd ${ORIGDIR}
have_full || info_reboot
have_receiver && info_open
#echo exit $exitcode
exit $exitcode

__ARCHIVE__
