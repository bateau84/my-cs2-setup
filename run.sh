#!/bin/bash

CONFIG_FILE=$(realpath -q ~/.cs2/config)
if [ -f ${CONFIG_FILE} ]; then
    . ${CONFIG_FILE}
else 
    echo "config file not found. Creating..."
    NEW_CONFIG=true
    mkdir -p ${CONFIG_FILE%/*}
    touch ${CONFIG_FILE}
fi

requirements=("dos2unix" "tar" "unzip" "wget" "whoami" "realpath" "id" "wc" "compgen")
for requirement in "${requirements[@]}"; do
    if ! command -v "$requirement" &> /dev/null; then
        echo "command $requirement is required. Aborting..."
        exit 1
    fi
done

if [ ${DEBUG:-"0"} == "1" ]; then
    set -x
fi

if [ "${SRCDS_TOKEN:-""}" == "" ]; then
    echo "SRCDS_TOKEN not set"
    read -p "Enter SRCDS_TOKEN: " SRCDS_TOKEN
    echo "## Steam parameters:" >> ~/.cs2/config
    echo "SRCDS_TOKEN=\"${SRCDS_TOKEN}\"" >> ~/.cs2/config
    echo "STEAMAPPVALIDATE=\"${STEAMAPPVALIDATE:-"0"}\"" >> ~/.cs2/config
    echo "" >> ~/.cs2/config
fi

## Set some defaults
# Can be overwritten in ~/.cs2/config
DEBUG="${DEBUG:-"0"}"
STEAMAPPVALIDATE="${STEAMAPPVALIDATE:-"1"}"
DOCKER_IMAGE="${DOCKER_IMAGE:-"docker.io/joedwards32/cs2:latest"}"
GAME_DIR=$(eval "realpath -q ${GAME_DIR:-"~/CS2-dedicated"}")
METAMOD_URL="${METAMOD_URL:-"https://mms.alliedmods.net/mmsdrop/2.0/mmsource-2.0.0-git1282-linux.tar.gz"}"
CSSHARP_URL="${CSSHARP_URL:-"https://github.com/roflmuffin/CounterStrikeSharp/releases/download/v179/counterstrikesharp-with-runtime-build-179-linux-12485be.zip"}"
CSSHARP_PLUGINS=${CSSHARP_PLUGINS}
LOCAL_OS_USER="${LOCAL_OS_USER:-"$(whoami)"}"
INSTALL_METAMOD="${INSTALL_METAMOD:-"1"}"
INSTALL_CSSHARP="${INSTALL_CSSHARP:-"1"}"
INSTALL_CSSHARP_PLUGINS="${INSTALL_CSSHARP:-"1"}"
CONTAINER_TOOL="${CONTAINER_TOOL:-"podman"}"
CONTAINER_EXTRA_ARGS="${CONTAINER_EXTRA_ARGS:-""}"
USER_ID=$(id -u ${LOCAL_OS_USER})
GROUP_ID=$(id -g ${LOCAL_OS_USER})

if [ ${NEW_CONFIG:-"false"} == "true" ]; then
    echo "config file was empty. Inserting..."
    echo "The following was added to ${CONFIG_FILE}: "
    echo "## Script defaults:" >> ~/.cs2/config
    echo "DEBUG=\"${DEBUG}\"" | tee -a ${CONFIG_FILE}
    echo "DOCKER_IMAGE=\"${DOCKER_IMAGE}\"" | tee -a ${CONFIG_FILE}
    echo "GAME_DIR=\"${GAME_DIR}\"" | tee -a ${CONFIG_FILE}
    echo "METAMOD_URL=\"${METAMOD_URL}\"" | tee -a ${CONFIG_FILE}
    echo "CSSHARP_URL=\"${CSSHARP_URL}\"" | tee -a ${CONFIG_FILE}
    echo "CSSHARP_PLUGINS=()" | tee -a ${CONFIG_FILE}
    echo "INSTALL_METAMOD="${INSTALL_METAMOD:-"1"}"" | tee -a ${CONFIG_FILE}
    echo "INSTALL_CSSHARP="${INSTALL_CSSHARP:-"1"}"" | tee -a ${CONFIG_FILE}
    echo "INSTALL_CSSHARP_PLUGINS="${INSTALL_CSSHARP_PLUGINS:-"1"}"" | tee -a ${CONFIG_FILE}
    echo "LOCAL_OS_USER=\"${LOCAL_OS_USER}\"" | tee -a ${CONFIG_FILE}
    echo "CONTAINER_TOOL=\"${CONTAINER_TOOL}\"" | tee -a ${CONFIG_FILE}
    echo "CONTAINER_EXTRA_ARGS=\"${CONTAINER_EXTRA_ARGS}\"" | tee -a ${CONFIG_FILE}
    echo "" | tee -a ${CONFIG_FILE}
    echo "## Dedicated server defaults:" | tee -a ${CONFIG_FILE}
    echo "CS2_SERVERNAME=\"CHANGE-ME\"" | tee -a ${CONFIG_FILE}
    echo "CS2_PW=\"\"" | tee -a ${CONFIG_FILE}
    echo "CS2_IP=\"0.0.0.0\"" | tee -a ${CONFIG_FILE}
    echo "CS2_PORT=\"27015\"" | tee -a ${CONFIG_FILE}

    echo ""
    echo "Please edit ${CONFIG_FILE} and re-run this script"
    exit 0
fi

if [ ! -d "${GAME_DIR}" ]; then
    FIRST_RUN="true"
    echo "${GAME_DIR} does not exist. Creating..."
    mkdir -p ${GAME_DIR}
    chmod 755 -R ${GAME_DIR}
fi

extractFile() {
    file="$1"
    DESTINATION="$2"
    echo "Extracting ${file}"
    case "${file##*.}" in
        gz)
            tar -xvzf ${file} --directory ${DESTINATION}
            ;;
        zip)
            unzip -o ${file} -d ${DESTINATION}
            #  &> /dev/null
            ;;
        *)
            echo "Unknown file type"
            ;;
    esac
}

initMetamod() {
    if [[ ${INSTALL_METAMOD} == "1" && ${FIRST_RUN} != "true" ]]; then
        echo "metamod is marked for installment. Installing..."
        METAMOD_FILE="${METAMOD_URL##*/}"
        METAMOD_DOWNLOAD_FILE="/tmp/${METAMOD_FILE}"
        
        wget ${METAMOD_URL} -O ${METAMOD_DOWNLOAD_FILE} &> /dev/null
        extractFile ${METAMOD_DOWNLOAD_FILE} ${GAME_DIR}/game/csgo/

        dos2unix ${GAME_DIR}/game/csgo/gameinfo.gi &> /dev/null

        awk -f metamod.awk ${GAME_DIR}/game/csgo/gameinfo.gi > ${GAME_DIR}/game/csgo/gameinfo.gi.tmp && mv ${GAME_DIR}/game/csgo/gameinfo.gi.tmp ${GAME_DIR}/game/csgo/gameinfo.gi
        sed -ri 's/(INSTALL_METAMOD=)"1"/\1"0"/g' ~/.cs2/config
    fi
}

initCSSharp() {
    if [[ ${INSTALL_CSSHARP} == "1" && ${FIRST_RUN} != "true" ]]; then
        echo "CounterStrikeSharp is marked for installment. Installing..."
        CSSHARP_FILE="${CSSHARP_URL##*/}"
        CSSHARP_DOWNLOAD_FILE="/tmp/${CSSHARP_FILE}"

        wget ${CSSHARP_URL} -O ${CSSHARP_DOWNLOAD_FILE} &> /dev/null
        extractFile ${CSSHARP_DOWNLOAD_FILE} ${GAME_DIR}/game/csgo/

        sed -ri 's/(INSTALL_CSSHARP=)"1"/\1"0"/g' ~/.cs2/config
    fi

    if [[ ${INSTALL_CSSHARP_PLUGINS} == "1" && ${FIRST_RUN} != "true" ]]; then
        for CSSPLUGIN in "${CSSHARP_PLUGINS[@]}"; do
            PLUGIN_NAME="$(echo ${CSSPLUGIN} | awk -F/ '{print $(NF-4)}')"
            FILE_NAME="$(echo ${CSSPLUGIN} | awk -F/ '{print $(NF-0)}')"
            echo "Installing ${PLUGIN_NAME} from URL:${CSSPLUGIN}"

            wget ${CSSPLUGIN} -O /tmp/${FILE_NAME} &> /dev/null
            extractFile /tmp/${FILE_NAME} /tmp/${PLUGIN_NAME}/

            if [ -d /tmp/${PLUGIN_NAME}/addons ]; then
                echo "Installing plugins from addons folder"
                cp -r /tmp/${PLUGIN_NAME}/addons/* ${GAME_DIR}/game/csgo/addons/
            elif [ -d /tmp/${PLUGIN_NAME}/*/addons ]; then
                echo "One or more addons were found in the plugin. Copying..."
                cp -r /tmp/${PLUGIN_NAME}/*/addons/* ${GAME_DIR}/game/csgo/addons/
            fi
        done
        sed -ri 's/(INSTALL_CSSHARP_PLUGINS=)"1"/\1"0"/g' ~/.cs2/config
    fi
}

initContainer() {
    if [ $(${CONTAINER_TOOL} images -a | grep "${DOCKER_IMAGE%:*}" | wc -l) -eq 0 ]; then
        echo "container image not pressent. Pulling..."
        ${CONTAINER_TOOL} pull ${DOCKER_IMAGE} &> /dev/null
    fi

    if [ $(${CONTAINER_TOOL} ps -a | grep cs2 | wc -l) -gt 0 ]; then
        echo "old container pressent. Removing..."
        ${CONTAINER_TOOL} rm -f cs2 &> /dev/null
    fi
}

construct_command() {
    local cmd=("${CONTAINER_TOOL}" run -d --name=cs2 --userns=keep-id --user ${USER_ID}:${GROUP_ID} ${CONTAINER_EXTRA_ARGS} \
        -v ${GAME_DIR}:/home/steam/cs2-dedicated/ \
        -v /etc/localtime:/etc/localtime:ro \
        -e \"SRCDS_TOKEN=${SRCDS_TOKEN}\" \
        -e \"STEAMAPPVALIDATE=${STEAMAPPVALIDATE}\")

    for var in $(compgen -A variable | grep -E '^(CS2|TV)_')
    do
        value="${!var}"
        cmd+=(-e "$var=$value")
    done

    cmd+=(--net host ${DOCKER_IMAGE})
    printf '%s ' "${cmd[@]}"
}

runContainer() {
    command=$(construct_command)
    echo "Starting new container \"cs2\"..."

    eval "${command}" &> /dev/null
    if [ "${FIRST_RUN:-"false"}" == "true" ]; then
        echo ""
        echo "############################################"
        echo "This is your first run. MetaMod and SourceMod is marked for installment."
        echo "You need to run this script again to install them."
        echo "Please wait until gamefiles are downloaded"
        echo "See status by running \`${CONTAINER_TOOL} logs -f cs2\` or \`du -csh ${GAME_DIR} \`"
        echo "Don\`t run the script again untill the download is complete"
        echo "It should end on around ~34G to ~35G"
        echo "Depending on your download speed, it should take around 10 to 15 minutes"
        echo "############################################"
    fi
}

initMetamod
initCSSharp
initContainer
runContainer