#!/bin/bash

function verify-Arguments ()
{
  printf "\n"
  if [ $1 -gt 0 ]; then
    printf "$1 arguments passed\n"
  else
    printf "No Arguments have been passed\n"
    exit
  fi
}

function verify-LocalUserAccount ()
{
  for arg in $@; do
    if getent passwd $arg > /dev/null; then
      printf "$arg local user found\n"
    else
      printf "$arg local user not found, exiting...\n"
      exit
    fi
  done
}

function display-Arguments ()
{
  # display user names sent to script
  printf "\n"
  for x in "$@"
    do
      printf "$x\n"
    done
}

function verify-Package ()
{
  printf "\n"
  package=$1
  echo "Checking for TigerVNC install..."
  if yum list installed $package &> /dev/null ; then
    printf "$package is installed\n"
  else
    printf "$pacakge not found, exiting...\n"
  exit
  fi
}

function verify-PortInUse ()
{
  port=$1
  if lsof -Pi :${port} &> /dev/null ; then
    printf "\nPort $port taken"
    return 0
  else
    return 1
  fi
}

function setup-VNCpassword ()
{
  pw="remote"
  user=$1
  vncpath="/home/$user/.vnc"

  mkdir "$vncpath"
  echo $pw | vncpasswd -f > "$vncpath/passwd"
  chown -R $user:$user "$vncpath"
  chmod 600 "$vncpath/passwd"
}

#### START MAIN

verify-Arguments $#
verify-LocalUserAccount $@
verify-Package tigervnc-server


# determine first open port after 5900
# $#+1 allows port discovery when single user is passed as argument
printf "\nCheck for available ports\n"
for ((x=1; x<=$(($#+1)); x++)); do
  port=590${x}
  if verify-PortInUse $port; then
    continue
  else
    startport=$port
    endport=$((($port + $#) - 1))

    for ((y=$startport; y<=$endport; y++)); do
      if verify-PortInUse $y; then 
        printf "\nDynamic port check failed, $y can't be used, exiting..."
		exit
      else
		printf "\nDynamic port check passed, $y is free to use"
      fi
    done

  break
  fi
done

printf "\n\n"
printf "Start port\t$startport\n"
printf "End port\t$endport\n"


argPosition=1
vncPort=$(echo -n $startport | tail -c 1)

for arg in $@; do
  printf "\nSetting up $arg\n"
  
  path="/etc/systemd/system/vncserver@:${vncPort}.service"
  cp /lib/systemd/system/vncserver@.service $path

  # configure user and resolution
  printf "\n$path\n"
  sed -i "s/<USER>/$arg/g" $path
  sed -i 's/vncserver %i/vncserver %i -geometry 1680x1050/' $path
 
  setup-VNCpassword $arg
  
  # skip GNOME inital setup prompt
  mkdir /home/$arg/.config
  echo "yes" > /home/$arg/.config/gnome-initial-setup-done
  chown -R $arg:$arg /home/$arg/.config 

  ((vncPort++))
done


systemctl daemon-reload
for ((x=$startport; x<=$endport; x++)); do
  vncPort=$(echo -n $x | tail -c 1)
  service=vncserver@:${vncPort}.service
  
  printf "\nEnabling $service\n"
  systemctl enable $service
  
  printf "\nStarting $service\n"
  systemctl start $service

  printf "\nStaus of $service\n"
  systemctl status $service
done


printf "\nConfigure Firewall\n"
firewall-cmd --permanent --zone=public --add-service=vnc-server
printf "\nReload firewall\n"
firewall-cmd --reload

printf "\nKill network proxy prompt\n"
if cat /etc/xdg/autostart/gnome-software-service.desktop | grep X-GNOME-Autostart-enabled=falses; then 
  printf "\nGNOME network proxy prompt is already disabled, no change made\n"
else 
  echo "X-GNOME-Autostart-enabled=false" >> /etc/xdg/autostart/gnome-software-service.desktop
fi

printf "\nSet GUI as default target\n"
if [ $(systemctl get-default) = "graphical.target" ]; then 
  printf "\nGUI target is set but reboot to avoid GNOME network proxy prompt\n"; 
else
  systemctl set-default graphical.target
  printf "\nReboot to enable GUI\n"
fi

