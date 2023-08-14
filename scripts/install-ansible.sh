debian_version=$(cat /etc/debian_version | cut -d'.' -f1)

if [[ "$debian_version" == "12" ]]; then
  sudo apt install -y python3 python3-pip python3-virtualenv
  mkdir .virtualenv
  cd .virtualenv && virtualenv ansible
  cd ..
  source .virtualenv/ansible/bin/activate
  python3 -m pip install ansible passlib 

  #-- This should be automatic in the future. Remind for now.
  #-- This is a problem with our legacy use of python.
  #-- If it remains by the time we are on Debian 12, address.
  echo "Please be sure to run: source .virtualenv/ansible/bin/activate"
elif [[ "$debian_version" == "11" ]]; then
  sudo apt install -y python3.9 python3-pip
  sudo python3.9 -m pip install ansible passlib 
else
  echo "Error: unsupported OS."
  exit 1
fi

exit 0
