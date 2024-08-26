#!/bin/bash

help () {
    cat << EOF
Client script to trigger HUP via action server API
hup-device [options]

Options:
    -h, --help
        Display this help and exit.

    -a, --auth API_TOKEN
        balena API token for authentication.

    -d, --debug
        Run HUP in debug mode on device.

    -e, --endpoint ACTIONS_ENDPOINT
        Actions host endpoint; defaults to "actions.balena-devices.com/v1".
        Use "actions.devices.<cloud-uuid>.bob.local/v1" for a local balena-cloud.

    -f, --follow
        Follow HUP progress to completion.

    -r, --response
        Show HTTP response output.

    -u, --uuid UUID
        UUID for device to HUP; must use long UUID.

    -v, --version OS_VERSION
        Target OS_VERSION for HUP.
EOF
}

# Parse arguments
while [ "$#" -gt "0" ]; do
    key=$1
    case $key in
        -h|--help)
            help
            exit 0
            ;;
        -a|--auth)
            API_TOKEN=$2
            shift
            ;;
        -d|--debug)
            DEBUG=1
            ;;
        -e|--endpoint)
            ACTIONS_ENDPOINT=$2
            shift
            ;;
        -f|--follow)
            FOLLOW=1
            ;;
        -r|--response)
            RESPONSE=1
            ;;
        -v|--version)
            OS_VERSION=$2
            shift
            ;;
        -u|--uuid)
            UUID=$2
            shift
            ;;
        *)
            echo "[WARN] $0 : Argument '$1' unknown. Ignoring."
            ;;
    esac
    shift
done

# Fail if missing arguments
if [ -z "${ACTIONS_ENDPOINT}" ]; then
    ACTIONS_ENDPOINT="actions.balena-devices.com/v1"
fi

if [ -z "${API_TOKEN}" ]; then
    echo "[ERROR] hup-device-v2 : API token not provided"
    exit 1
fi

if [ -z "${OS_VERSION}" ]; then
    echo "[ERROR] hup-device-v2 : target OS version not provided"
    exit 1
fi

if [ -z "${UUID}" ]; then
    echo "[ERROR] hup-device-v2 : UUID not provided"
    exit 1
fi

# Execute HUP request
outfile=$(mktemp)
errfile=$(mktemp)
if [ -n "${DEBUG}" ]; then
    debug_param=", \"debug\": true"
else
    debug_param=""
fi

status_code=$(\
    curl -s -X POST "https://${ACTIONS_ENDPOINT}/${UUID}/resinhup" \
        --show-error \
        -w "%{http_code}" \
        -L \
        -o "${outfile}" \
        --retry 3 \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "{ \"parameters\": { \"target_version\": \"${OS_VERSION}\" ${debug_param} } }" \
        2> "${errfile}"
    )

# Print status code and output text
res=1
if [ -n "${status_code}" ]; then
    if [ "${status_code:0:1}" == "2" ]; then
        echo "[INFO] code: ${status_code}"
        res=0
    else
        echo "[WARN] code: ${status_code}"
    fi
else
    echo "[WARN] no code"
fi

if [ -s "${errfile}" ]; then
    echo "[WARN] stderr: $(cat "${errfile}")"
fi
rm -f "${errfile}"

if [ -n "${RESPONSE}" ] && [ -s "${outfile}" ]; then
    echo "[INFO] response: $(cat "${outfile}")"
fi
rm -f "${outfile}"

# Only concerned with following HUP progress below.
if [ -z "${FOLLOW}" ] || [ "${res}" != 0 ]; then
    exit $res
fi

# Print device status, provisioning_progress, and provisioning_state updates until
# progress reaches 100%.
progress=""
last_status=""
last_progress=""
last_prov_state=""
printf "%8s  %12s  %3s  %16s\n" "  Time  " "   Status   " "Pct" "     Detail             "
echo "--------  ------------  ---  ------------------------"

while [ true ]
do
    device=$(curl "https://api.d90c5192ae585eaed21f1f48258c954c.bob.local/v6/device(uuid='${UUID}')" \
        --no-progress-meter \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Content-Type: application/json")

    status=$(echo "${device}" | jq -r '.d[0] | .status')
    progress=$(echo "${device}" | jq -r '.d[0] | .provisioning_progress')
    prov_state=$(echo "${device}" | jq -r '.d[0] | .provisioning_state')
    # to keep output clean
    if [ "${progress}" = "null" ]; then
        progress=""
    fi
    # Only print if changed
    if [ "${status}" != "${last_status}" ] || [ "${progress}" != "${last_progress}" ] || [ "${prov_state}" != "${last_prov_state}" ]; then
        tstamp=$(date +"%H:%M:%S")
        printf "%8s  %-12.12s  %3.3s  %-24.24s\n" "${tstamp}" "${status}" "${progress}" "${prov_state}"

        last_status="${status}"
        last_progress="${progress}"
        last_prov_state="${prov_state}"
    fi
    sleep 3
done
