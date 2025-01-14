#!/bin/bash
#
# This is a convenience script meant to identify broken links in a
# Trusted Build release COTS report. The identified links currently 
# require a manual fix.

if [[ -z "$1" ]]; then
  echo "Usage: $0 /path/to/cots_report.csv"
  exit 1
fi

cots_report=$1

if [[ ! -f ${cots_report} ]]; then
  echo "Error: ${cots_report} could not be found. Please verify the path."
  exit 2
fi

tmp_cots_get="/tmp/cots_get.log"

if [[ -f ${tmp_cots_get} ]]; then
  rm -f ${tmp_cots_get}
fi

echo "Validating current links in ${cots_report}..."
for url in `cut -d',' -f1 ${cots_report}`
do
  echo -n "$url = " >> ${tmp_cots_get}
  curl -s -L -I -o /dev/null -w "%{http_code}" "${url}" >> ${tmp_cots_get}
  echo "" >> ${tmp_cots_get}
done

grep 404 ${tmp_cots_get}
if [[ $? == "0" ]];
then
  echo ""
  echo "You will need to manually fix these links in ${cots_report}"
else
  echo ""
  echo "No broken links were found. ${cots_report} can be included in the SLI spreadsheet."
fi

exit 0;
