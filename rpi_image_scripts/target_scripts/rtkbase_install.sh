#!/bin/sh

echo "Installing RTKBase..."

mkdir -p /usr/local/rtkbase/

cp /tmp/install.sh /usr/local/rtkbase/
chown root:root /usr/local/rtkbase/install.sh
chmod 755 /usr/local/rtkbase/install.sh

cat <<"EOF" > /etc/systemd/system/rtkbase_setup.service
[Unit]
Description=RTKBase setup second stage
After=local-fs.target
After=network.target

[Service]
ExecStart=/usr/local/rtkbase/setup_2nd_stage.sh
RemainAfterExit=true
Type=oneshot

[Install]
WantedBy=multi-user.target
EOF

cat <<"EOF" > /usr/local/rtkbase/setup_2nd_stage.sh
#!/bin/sh

if test -x /usr/local/rtkbase/install.sh
then
  HOME=/usr/local/rtkbase
  export HOME
  /usr/local/rtkbase/install.sh -2 >> /usr/local/rtkbase/install.log 2>&1
fi
EOF

chmod +x /usr/local/rtkbase/setup_2nd_stage.sh

hostname raspberrypi
/usr/local/rtkbase/install.sh -1 2>&1

systemctl enable rtkbase_setup.service
