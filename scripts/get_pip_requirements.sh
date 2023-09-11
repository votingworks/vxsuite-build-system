#!/usr/bin/env bash

debian_major_version=$(cat /etc/debian_version | cut -d'.' -f1)
system_architecture=$(uname -m)

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

#-- The process to get the latest versions and hashes is a bit convoluted
#-- We start with an existing pip requirements file and strip off everything
#-- except the pip name.
#-- To be sure we aren't reusing existing pips, we create a new virtualenv
#-- in a temporary directory.
#-- Pips are downloaded to that directory, which fetches the latest version
#-- Those are then installed so we can use pip commands to generate a new
#-- requirements file with the version and correct hash.
#-- We reuse pip3 download with --require-hashes since it fetches the 
#-- expected hash from PyPi, and we add that to our new requirements file
function pip_requirements ()
{
  local pip_requirements="${DIR}/pip_deb${debian_major_version}_${system_architecture}_requirements.txt"
  local new_pip_requirements="${tmp_dir}/pip_deb${debian_major_version}_${system_architecture}_requirements.txt"

  mkdir -p $tmp_dir

  if [[ "$debian_major_version" == "12" ]]; then
    mkdir -p ${tmp_dir}/.virtualenv
    cd ${tmp_dir}/.virtualenv && virtualenv ansible
    cd ..
    source ${tmp_dir}/.virtualenv/ansible/bin/activate
  fi
  
  for pip in `cat $pip_requirements | cut -d'=' -f1`
  do
    pip3 download -d $tmp_dir $pip
    pip3 install --no-index --find-links $tmp_dir $pip
  done

  for pip in `pip3 freeze` 
  do
    pip3 download -d $tmp_dir $pip --require-hashes 2>&1 | grep $pip | grep 'hash=' | xargs >> $new_pip_requirements
  done

  # Go ahead and clean up even though /tmp will eventually clear
  # All we care about is the pip requirements file
  rm $tmp_dir/*.whl
  rm -r $tmp_dir/.virtualenv

  echo ""
  echo "You can find the new requirements file at: ${new_pip_requirements}"
  echo ""
  
}

tmp_dir="/tmp/$$"
pip_requirements

exit 0
