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
        Actions host endpoint; defaults to "actions.balena-devices.com/v2".

    -f, --follow
        Follow HUP progress to completion.

    --follow-host
        API host to follow progress; defaults to "api.balena-cloud.com".

    -u, --uuid uuid
        UUID for device to HUP; must use long UUID.

    -v, --version os_version
        Target os_version for HUP.
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
            debug=1
            ;;
        -e|--endpoint)
            ACTIONS_ENDPOINT=$2
            shift
            ;;
        -f|--follow)
            follow=1
            ;;
        --follow-host)
            follow_host=$2
            shift
            ;;
        -v|--version)
            os_version=$2
            shift
            ;;
        -u|--uuid)
            uuid=$2
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
    ACTIONS_ENDPOINT="actions.balena-devices.com/v2"
fi

if [ -z "${API_TOKEN}" ]; then
    echo "[ERROR] hup-device-v2 : API token not provided"
    exit 1
fi

if [ -z "${follow_host}" ]; then
    follow_host="api.balena-cloud.com"
fi

if [ -z "${os_version}" ]; then
    echo "[ERROR] hup-device-v2 : target OS version not provided"
    exit 1
fi

if [ -z "${uuid}" ]; then
    echo "[ERROR] hup-device-v2 : UUID not provided"
    exit 1
fi

# Execute HUP request
outfile=$(mktemp)
errfile=$(mktemp)
if [ -n "${debug}" ]; then
    debug_param=", \"debug\": true"
else
    debug_param=""
fi

status_code=$(\
    curl -s -X POST "https://${ACTIONS_ENDPOINT}/${uuid}/resinhup" \
        --show-error \
        -w "%{http_code}" \
        -L \
        -o "${outfile}" \
        --retry 3 \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Content-Type: application/json" \
        --data "{ \"parameters\": { \"target_version\": \"${os_version}\" ${debug_param} } }" \
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

if [ -s "${outfile}" ]; then
    echo "[INFO] response: $(cat "${outfile}")"
    rm -f "${outfile}"
fi

# Only concerned with following HUP progress below.
if [ -z "${follow}" ] || [ "${res}" != 0 ]; then
    exit $res
fi

# Print device status, provisioning_progress, and provisioning_state updates as
# they change.
progress=""
last_status=""
last_progress=""
last_prov_state=""
printf "%8s  %12s  %3s  %16s\n" "  Time  " "   Status   " "Pct" "     Detail             "
echo "--------  ------------  ---  ------------------------"

# ensure we cleanup
outfile=$(mktemp)
trap 'rm -f ${outfile};exit' ERR INT TERM

while [ 0 ]
do
    status_code=$(curl "https://${follow_host}/v6/device(uuid='${uuid}')" \
        -w "%{http_code}" \
        -o "${outfile}" \
        --no-progress-meter \
        --header "Authorization: Bearer ${API_TOKEN}" \
        --header "Content-Type: application/json")

    if [ "${status_code:0:1}" != "2" ]; then
        echo "[ERROR] code: ${status_code}"
    else
        status=$(cat "${outfile}" | jq -r '.d[0] | .status')
        progress=$(cat "${outfile}" | jq -r '.d[0] | .provisioning_progress')
        prov_state=$(cat "${outfile}" | jq -r '.d[0] | .provisioning_state')
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
    fi
    sleep 3
done

