#!/bin/bash

DIRNAME="sqdeveloper"
SQDEV_PATH="${HOME}/.niveus/${DIRNAME}"
SONAR_SCANNER_PATH="${SQDEV_PATH}/scanner"
SQDEV_CONFIG_PATH="${SQDEV_PATH}/config"
SQDEV_TOKEN_FILE="${SQDEV_CONFIG_PATH}/TOKEN"
APPNAME="SonarCube Developers"
DEPENDENCIES="docker docker-compose"

# Colors
NOCOLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
YELLOW='\033[1;33m'


# Check if docker and docker-compose is installed.
for i in $DEPENDENCIES; do
    command -v $i >/dev/null && continue || { echo "$i not found."; exit 1; }
done


# Check for args/kwargs.
if [ $# -eq 0 ]
then
    echo -e "${YELLOW} Please enter a valid argument. ${NOCOLOR}"
    exit 1
fi


ARG1=$1

case "$ARG1" in
    install)
        echo "Installing ${APPNAME}."
        echo "Enter password."
        sudo echo ""
        # Installation dir
        mkdir -p $SQDEV_PATH
        echo -e "created installation folder at ${ORANGE} ${SQDEV_PATH} ${NOCOLOR}"
        cd $SQDEV_PATH
        echo "Cloning the latest $APPNAME repository."
        git clone -b automation git@gitlab.niveussolutions.com:utility/utility/sonarqube-developers.git .
        # config dir
        mkdir -p $SQDEV_CONFIG_PATH
        echo -e "created config folder at ${ORANGE} ${SQDEV_PATH} ${NOCOLOR}"

        echo "Making sqdev executable."
        chmod +x ./sqdev.sh
        
        # Adding symlink to /usr/bin
        echo "Creating sqdev symlink."
        sudo ln -s "${SQDEV_PATH}/sqdev.sh" /usr/bin/sqdev

        ;;
    start)
        if [ -d $SQDEV_PATH ]
        then
            echo "Running $APPNAME."
            cd $SQDEV_PATH
            docker-compose -f dc-sonar-qube.yaml up -d

            # Check if the containers are up and running.
            if [ "$(docker ps -q -f name=sonarqube)" ] && [ "$(docker ps -q -f name=sonar_database)" ]
            then
                echo -e "$APPNAME running on ${GREEN}http://localhost:5678/ ${NOCOLOR}"
            else
                echo -e "${RED} $APPNAME failed to run. Please check Docker and docker-compose installation. ${NOCOLOR}"
            fi

        else
            echo "$APPNAME not installed."
        fi

        ;;
    stop)
        # Check if the containers are running.
        if [ "$(docker ps -q -f name=sonarqube)" ] || [ "$(docker ps -q -f name=sonar_database)" ]
        then
            # Containers are running
            echo "Stopping $APPNAME"
            cd $SQDEV_PATH
            docker-compose -f dc-sonar-qube.yaml down
        else
            echo -e "${RED} $APPNAME is not currently running."
        fi

        ;;
    update)
        echo "Enter password."
        sudo echo ""
        echo "$APPNAME will be stopped before updating. Contunue? y/n."
        read user_confirmaton
        # Exit if containers should not be stopped.
        if ! [[ "$user_confirmaton" =~ [yY]  ]]
        then
            echo "Aborting operation."
            exit 1
        fi

        # Check if the containers are running.
        if [ "$(docker ps -q -f name=sonarqube)" ] || [ "$(docker ps -q -f name=sonar_database)" ]
        then
            echo "Stopping the containers"
            cd $SQDEV_PATH
            docker-compose -f dc-sonar-qube.yaml down
        
        # Checking for exited containers
        elif [ "$(docker ps -aq -f status=exited -f name=sonarqube)" ] || [ "$(docker ps -aq -f status=exited -f name=sonar_database)" ]
        then
            docker rm sonarqube sonar_database
        fi

        # Unlink sqdev
        sudo unlink /usr/bin/sqdev

        cd $SQDEV_PATH
        # Removing any changes that might interefere with git pull.
        git checkout -- .

        # Pull the latest repo.
        git pull origin master

        echo "Making sqdev executable."
        chmod +x ./sqdev.sh
        
        # Adding symlink to /usr/bin
        echo "Creating sqdev symlink."
        sudo ln -s "${SQDEV_PATH}/sqdev.sh" /usr/bin/sqdev

        # Update docker images.
        echo "Pulling latest SonarQube docker images."
        docker pull sonarqube:latest
        docker pull sonarsource/sonar-scanner-cli:latest

        ;;
    uninstall)
        echo "Enter password."
        sudo echo ""

        # Check if the containers are running.
        if [ "$(docker ps -q -f name=sonarqube)" ] || [ "$(docker ps -q -f name=sonar_database)" ]
        then
            echo "Stopping the containers"
            cd $SQDEV_PATH
            docker-compose -f dc-sonar-qube.yaml down
        
        # Checking for exited containers
        elif [ "$(docker ps -aq -f status=exited -f name=sonarqube)" ] || [ "$(docker ps -aq -f status=exited -f name=sonar_database)" ]
        then
            docker rm sonarqube sonar_database
        fi

        echo -e "${ORANGE}Removing $APPNAME images. ${NOCOLOR}"
        docker rmi sonarqube:latest postgres:latest
        # Should we remove postrges? Or let Docker remove it if it is not used for other containers?

        # Removing the repo and symlink
        echo -e "${RED}Removing symlink.${NOCOLOR}"
        sudo unlink /usr/bin/sqdev
        echo -e "${RED}Removing ${APPNAME} files.${NOCOLOR}"
        rm -rf $SQDEV_PATH

        # Removing docker volumes if specified.
        if [[ $# -gt 1 ]] && [[ $2 == "all" ]]
        then
            echo "Removing Volumes."

            docker volume rm "${DIRNAME}_sonarqube_conf ${DIRNAME}_sonarqube_data ${DIRNAME}_sonarqube_logs \
            ${DIRNAME}_sonarqube_extensions ${DIRNAME}_sonarqube_bundled-plugins \
            ${DIRNAME}_postgresql ${DIRNAME}_postgresql_data"
        else
            echo "Docker volumes not removed."
        fi

        ;;
    scanner)
        # TODO: Needs rework on this section.

        # Check for args/kwargs.
        if [ ! -n "$2" ]
        then
            echo -e "${YELLOW} Please enter a valid argument for Sonar Scanner. ${NOCOLOR}"
            exit 1
        fi

        # For removing every stopped sonar scanner containers.
        if [ "$2" == "clean" ]
        then
            if [ "$(docker container ls -aq --filter name=sonar_scanner)" ]
            then    
                echo "Removing unused Sonar Scanner containers."
                docker rm $(docker container ls -aq --filter name=sonar_scanner)
                exit 1
            else
                echo "No containers found."
                exit 1
            fi
        fi

        if [ "$(docker ps -q -f name=sonarqube)" ] && [ "$(docker ps -q -f name=sonar_database)" ]
        then
            # Convert args to array.
            args=("$@")

            for index in "${!args[@]}"; do
                current_arg="${args[$index]}"
                next_index=$(($index + 1))

                if [ $current_arg == "-d" ] || [ $current_arg == "--dir" ]
                    then
                        TEMP_DIR="${args[$next_index]}"

                        if [[ "$TEMP_DIR" = /* ]]
                        then
                            PROJECT_DIRECTORY=TEMP_DIR
                        elif [[ "${TEMP_DIR:0:1}" == "." ]]
                        then
                            tmp=${TEMP_DIR#?}
                            PROJECT_DIRECTORY="${PWD}${tmp}"
                        else
                            echo "Please enter relative or absolute path. $TEMP_DIR"
                            exit 1
                        fi
                        
                        # Check if directory exists.
                        if [ ! -d "$PROJECT_DIRECTORY" ]
                        then
                            echo "Directory $PROJECT_DIRECTORY does not exist."
                            exit 1
                        fi

                elif [ $current_arg == "-k" ] || [ $current_arg == "--key" ]
                then
                    PROJECT_KEY="${args[$next_index]}"
                elif [ $current_arg == "-t" ] || [ $current_arg == "--token" ]
                then
                    PROJECT_TOKEN="${args[$next_index]}"
                fi
            done

            # Getting sqdev token from env variable if not provided in scanner command.
            if [ -f "$SQDEV_TOKEN_FILE" ] && [ ! "$PROJECT_TOKEN" ]
            then
                SQDEV_TOKEN=$(cat "$SQDEV_TOKEN_FILE")
                PROJECT_TOKEN=$SQDEV_TOKEN

                echo -e "${GREEN}Loading default SonarQube token from config file.${NOCOLOR}"
            elif [ ! -f "$SQDEV_TOKEN_FILE" ] && [ ! "$PROJECT_TOKEN" ]
            then
                echo -e "${RED}SonarQube token not found in config file. ${NOCOLOR}\
                \n\nKindly include the token with the command or add the token to sqdev using ${YELLOW} sqdev token <new token> ${NOCOLOR}"

                exit 1
            fi


            # Validate Sonar Scanner args.
            if [ "$PROJECT_DIRECTORY" ] && [ "$PROJECT_KEY" ] && [ "$PROJECT_TOKEN" ]
            then
                cd $SONAR_SCANNER_PATH

                # Creating .env file
                echo "PROJECT_DIRECTORY=$PROJECT_DIRECTORY" > .env
                echo "PROJECT_KEY=$PROJECT_KEY" >> .env
                echo "PROJECT_TOKEN=$PROJECT_TOKEN" >> .env

                docker-compose -f ./dc-sonar-scanner.yaml up  # Container will exit after scan is completed.

                # Remove the container after scanning.
                docker-compose -f ./dc-sonar-scanner.yaml down
            else
                echo -e "${RED}All args for scanner not found. Kindly try again.${NOCOLOR}"
                exit 1
            fi
        
        else
            echo "${APPNAME} is not running. Please start ${APPNAME}"
        fi

        ;;
    token)
        # Check if token exists.
        if [ ! -n "$2" ]
        then
            echo -e "${YELLOW} Please enter a token. ${NOCOLOR}"
            exit 1
        fi

        SQDEV_TOKEN="$2"

        echo -e "Adding token to file ${GREEN} ${SQDEV_TOKEN_FILE} ${NOCOLOR}"
        echo "$2" > "$SQDEV_TOKEN_FILE"

        ;;
    *)
        echo "Invalid argument. $ARG1 is not supported."
        ;;
esac
