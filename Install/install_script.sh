#!/bin/bash
RTKBASE_USER=rtkbase
RTKBASE_PATH=/usr/local/${RTKBASE_USER}
RTKBASE_GIT=${RTKBASE_PATH}/rtkbase
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
NMEACONF=NmeaConf
CONF_TAIL=RTCM3_OUT.txt
CONF980=UM980_${CONF_TAIL}
CONF982=UM982_${CONF_TAIL}
SERVER_PATCH=server_py.patch
STATUS_PATCH=status_js.patch
SYSCONGIG=RtkbaseSystemConfigure.sh
SYSSERVICE=RtkbaseSystemConfigure.service
SYSPROXY=RtkbaseSystemConfigureProxy.sh
SERVICE_PATH=/etc/systemd/system
PI=pi
BANNER=/etc/ssh/sshd_config.d/rename_user.conf

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

configure_ttyS0(){
  CMDLINE=$1/cmdline.txt
  BOOTCONFIG=$1/config.txt
  #echo \$1=${1} CMDLINE=${CMDLINE} BOOTCONFIG=${BOOTCONFIG}

  if [[ -f ${CMDLINE} ]]
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

  if [[ -f ${BOOTCONFIG} ]]
  then
     HAVE_UART=`grep "^enable_uart=" ${BOOTCONFIG}`
     #echo HAVE_UART=${HAVE_UART}
     ENABLED_UART=`grep "^enable_uart=1" ${BOOTCONFIG}`
     #echo ENABLED_UART=${ENABLED_UART}
     HAVE_BT=`grep "^dtoverlay=disable-bt" ${BOOTCONFIG}`
     #echo HAVE_BT=${HAVE_BT}
     HAVE_UART3=`grep "^dtoverlay=uart3" ${BOOTCONFIG}`
     #echo HAVE_UART3=${HAVE_UART3}

     if [[ ${HAVE_UART} == "" ]] || [[ ${HAVE_BT} == "" ]] || [[ ${HAVE_UART3} == "" ]]
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

     if [[ ${HAVE_BT} == "" ]]
     then
        echo dtoverlay=disable-bt >> ${BOOTCONFIG}
        echo Bluetooth disabled into ${BOOTCONFIG}
     fi

     if [[ ${HAVE_UART3} == "" ]]
     then
        echo dtoverlay=uart3 >> ${BOOTCONFIG}
        echo Uart3 added to ${BOOTCONFIG}
     fi
  fi
}

is_packet_not_installed(){
   instaled=`dpkg-query -W ${1} 2>/dev/null | grep ${1}`
   #echo 1=${1} instaled=${instaled}
   if [[ ${instaled} != "" ]]
   then
      return 1
   fi
}

install_packet_if_not_installed(){
   is_packet_not_installed ${1} && apt-get install -y ${1}
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

check_boot_configiration(){
   echo '################################'
   echo 'CHECK BOOT CONFIGURATION'
   echo '################################'

   configure_ttyS0 /boot
   configure_ttyS0 /boot/firmware

   hciuart_enabled=$(systemctl is-enabled hciuart.service)
   [[ "${hciuart_enabled}" != "disabled" ]] && [[ "${hciuart_enabled}" != "masked" ]] && systemctl disable hciuart
}

do_reboot(){
   #echo NEEDREBOOT=${NEEDREBOOT}
   if [[ ${NEEDREBOOT} == "Y" ]]
   then
      echo Please try again ${0} after reboot
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
      exit
   fi
}

install_additional_utilies(){
   echo '################################'
   echo 'INSTALL ADDITIONAL UTILITIES'
   echo '################################'

   install_packet_if_not_installed avahi-utils
   install_packet_if_not_installed avahi-daemon
   install_packet_if_not_installed uuid
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
      tail -n+${ARCHIVE} "${0}" | tar xpJv --no-same-owner --no-same-permissions -C ${BASEDIR} ${FILES_EXTRACT}
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
      [ "${rtkbase_web_active}" = "active" ] && systemctl stop rtkbase_web.service
      [ "${str2str_active}" = "active" ] && systemctl stop str2str_tcp
      [ "${str2str_ntrip_A_active}" = "active" ] && systemctl stop str2str_ntrip_A
      [ "${str2str_ntrip_B_active}" = "active" ] && systemctl stop str2str_ntrip_B
      [ "${str2str_local_caster}" = "active" ] && systemctl stop str2str_local_ntrip_caster
      [ "${str2str_rtcm}" = "'active" ] && systemctl stop str2str_rtcm_svr
      [ "${str2str_serial}" = "active" ] && systemctl stop str2str_rtcm_serial
      [ "${str2str_file}" = "active" ] && systemctl stop str2str_file
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

   HAVEUSER=`cat /etc/passwd | grep ${RTKBASE_USER}`
   #echo HAVEUSER=${HAVEUSER}
   if [[ ${HAVEUSER} == "" ]]
   then
      #echo adduser --comment "RTKBase user" --disabled-password --home ${RTKBASE_PATH} ${RTKBASE_USER}
      adduser --comment "RTKBase user" --disabled-password --home ${RTKBASE_PATH} ${RTKBASE_USER}
      ExitCodeCheck $?
   fi

   RTKBASE_SUDOER=/etc/sudoers.d/${RTKBASE_USER}
   #echo RTKBASE_SUDOER=${RTKBASE_SUDOER}
   if [[ ! -f "${RTKBASE_SUDOER}" ]]
   then
      #echo echo "rtkbase ALL=NOPASSWD: ALL" \> ${RTKBASE_SUDOER}
      echo "rtkbase ALL=NOPASSWD: ALL" > ${RTKBASE_SUDOER}
   fi
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

rtkbase_install(){
   #echo ${RTKBASE_PATH}/${RTKBASE_INSTALL} -u ${RTKBASE_USER} -j -d -r -t -g
   ${RTKBASE_PATH}/${RTKBASE_INSTALL} -u ${RTKBASE_USER} -j -d -r -t -g
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
}

configure_gnss(){
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
      #have_full || [ $exitcode = 0 ] && have_receiver && echo rm -f ${BASENAME}
      have_full || [ $exitcode = 0 ] && have_receiver && rm -f ${BASENAME}
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
              ${SERVER_PATCH} ${STATUS_PATCH}"
FILES_EXTRACT="${BASE_EXTRACT} uninstall.sh"
FILES_DELETE="${SERVER_PATCH} ${STATUS_PATCH}"

check_phases(){
   if [[ ${1} == "-1" ]]
   then
      HAVE_RECEIVER=1
      HAVE_PHASE1=0
      HAVE_FULL=1
      FILES_EXTRACT="${BASE_EXTRACT}"
   else
      if [[ ${1} == "-2" ]]
      then
         HAVE_RECEIVER=0
         HAVE_PHASE1=1
         HAVE_FULL=1
         FILES_EXTRACT=
      else
        if [[ ${1} != "" ]]
        then
           echo Invalid argument \"${1}\"
           exit 1
        fi
      fi
   fi

   #echo HAVE_RECEIVER=${HAVE_RECEIVER} HAVE_PHASE1=${HAVE_PHASE1} HAVE_FULL=${HAVE_FULL}
   #echo FILES_EXTRACT=${FILES_EXTRACT}
   #echo FILES_DELETE=${FILES_DELETE}
}

restart_as_root ${1}
check_phases ${1}
have_phase1 && export LANG=C
have_phase1 && check_boot_configiration
have_full && do_reboot
have_receiver && check_port
have_phase1 && install_additional_utilies
have_full || delete_pi_user
have_receiver && change_hostname ${HAVE_FULL}
unpack_files
stop_rtkbase_services
have_phase1 && add_rtkbase_user
#echo ${RTKBASE_PATH}
have_phase1 && install_rtkbase_system_configure
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
