#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
blue='\033[0;34m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)


[[ $EUID -ne 0 ]] && echo -e "${red}Fatal error: ${plain} Please run this script with root privilege \n " && exit 1


# Check OS and set release variable
if [[ -f /etc/os-release ]]; then
    source /etc/os-release
    release=$ID
elif [[ -f /usr/lib/os-release ]]; then
    source /usr/lib/os-release
    release=$ID
else
    echo "Failed to check the system OS, please contact the author!" >&2
    exit 1
fi
echo "The OS release is: $release"

arch() {
    case "$(uname -m)" in
    x86_64 | x64 | amd64) echo 'amd64' ;;
    armv8* | armv8 | arm64 | aarch64) echo 'arm64' ;;
    *) echo -e "${green}Unsupported CPU architecture! ${plain}" && rm -f install.sh && exit 1 ;;
    esac
}

echo "arch: $(arch)"

default_ip=$(hostname -I|cut -f1 -d ' ')

# Prompt the user with the default value
read -p "ip khod ra vared konid ya Enter bezanid [$default_ip]: " user_input


# Use the default value if the user input is empty
ipv4="${user_input:-$default_ip}"

# Output the final IP address
echo "The IP address is: $ipv4"



if [[ -e /etc/debian_version ]]; then
		OS="debian"
		source /etc/os-release
		if [[ $ID == "ubuntu" ]]; then
			OS="ubuntu"
			MAJOR_UBUNTU_VERSION=$(echo "$VERSION_ID" | cut -d '.' -f1)
			if [[ $MAJOR_UBUNTU_VERSION -lt 18 ]]; then
				echo "⚠️ Your version of Ubuntu is not supported. Please Install On Ubuntu 20"
				echo ""
				exit
			fi
		else
			echo "⚠️ Your OS not supported. Please Install On Ubuntu 20"
			echo ""
			read -rp "Please enter 'Y' to exit, or press the any key to continue installation ：" back2menuInput
   			 case "$back2menuInput" in
       			 y) exit 1 ;;
   			 esac
		fi
fi

gen_random_string() {
    local length="$1"
    local random_string=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | fold -w "$length" | head -n 1)
    echo "$random_string"
}

install_base() {
    case "${release}" in
    ubuntu | debian | armbian)
        apt-get update && apt-get install -y -q wget curl tar mariadb-server certbot jq openssl
        ;;
    centos | almalinux | rocky | ol)
        yum -y update && yum install -y -q wget curl tar mariadb-server certbot jq openssl
        ;;
    fedora | amzn | virtuozzo)
        dnf -y update && dnf install -y -q wget curl tar mariadb-server certbot jq openssl
        ;;
    arch | manjaro | parch)
        pacman -Syu && pacman -Syu --noconfirm wget curl tar mariadb-server certbot jq openssl
        ;;
    opensuse-tumbleweed)
        zypper refresh && zypper -q install -y wget curl tar mariadb-server certbot jq openssl
        ;;
    *)
        apt-get update && apt install -y -q wget curl tar mariadb-server certbot jq openssl
        ;;
    esac
}

install_panel() {
	# curl backend
	local server_ip=$(curl -s https://api.ipify.org)

	read -p "Lotfan port manager ra vared konid: " manager_port
	mkdir -p /usr/local/TsManager

	cd /usr/local/TsManager

	

	if ([[ -e /usr/local/TsManager/tsmanager-${manager_port} ]]); then
		cd tsmanager-${manager_port}

		if [[ -f .env ]]; then
			echo "Reading configuration from .env file..."
			# Use the robust loading method
			set -a
			source .env
			set +a
			
			backend_port="$PORT"
			mysql_username="$MYSQL_USERNAME"
			mysql_password="$MYSQL_PASSWORD"
			mysql_database="$MYSQL_DATABASE"
			api_token="$STATIC_TOKEN"
			mysql_host="$MYSQL_HOST"
		else
			echo "Error: .env file not found!"
			exit 1
		fi
    
		cd ..
		rm -rf mtxpanel-linux-x64
	else
		read -p "lotfan user mysql ra vared konid: " mysql_username
		read -p "lotfan password mysql ra vared konid: " mysql_password
		mysql_database="tsmanager_$manager_port"
		api_token=$(openssl rand -base64 32)

	fi


	mysql -e "drop USER '${mysql_username}'@'localhost'" &
	wait
	mysql -e "CREATE USER '${mysql_username}'@'localhost' IDENTIFIED BY '${mysql_password}';" &
	wait
	mysql -e "GRANT ALL ON *.* TO '${mysql_username}'@'localhost';" &


	read -p "Lotfan Token Github ra vared konid: " github_token

	# Verify token by making an authenticated API request
	response=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer ${github_token}" \
	"https://api.github.com/repos/rezvanniazi/ts-manager-bot-websocket/releases/latest")

	if [ "$response" -eq 200 ]; then
		echo "✅ Token is valid. Proceeding..."
		
		# Get asset ID (original logic)
		asset_id=$(curl -Ls -H "Authorization: Bearer ${github_token}" \
		"https://api.github.com/repos/rezvanniazi/ts-manager-bot-websocket/releases/latest" | \
		jq -r '.assets[] | select(.name == "tsmanager-linux-x64.tar.gz") | .id')

		if [ -n "$asset_id" ]; then
			echo "🔹 Asset ID: $asset_id"
			
		else
			echo "❌ Error: Asset 'tsmanager-linux-x64.tar.gz' not found!"
			exit 1
		fi

	elif [ "$response" -eq 401 ]; then
		echo "❌ Error: Invalid token! (Unauthorized)"
		exit 1
	else
		echo "❌ Error: GitHub API request failed (HTTP $response)"
		exit 1
	fi

	curl -L -H "Authorization: Bearer ${github_token}"   -H "Accept: application/octet-stream"   https://api.github.com/repos/rezvanniazi/ts-manager-bot-websocket/releases/assets/${asset_id} --output tsmanager-linux-x64.tar.gz


	if [[ $? -ne 0 ]]; then
            echo -e "${red}Downloading panel failed, please be sure that your server can access GitHub ${plain}"
            exit 1
    fi
	
	mkdir -p tsmanager-${manager_port}

	tar -xvzf tsmanager-linux-x64.tar.gz -C tsmanager-${manager_port}
	wait
	rm tsmanager-linux-x64.tar.gz


	cd tsmanager-${manager_port}

	mkdir -p certs

	
	if ([[ "${ipv4}" == "localhost" || "${ipv4}" == "127.0.0.1" ]]); then
		node_env="development"

	else
		node_env="production"
		read -p "damane khod ra vared konid: " domain_name

		mkdir certs

		certbot certonly --standalone --non-interactive --agree-tos --email rezvanniazi@proton.me -d $domain_name
		ln -s /etc/letsencrypt/live/$domain_name/fullchain.pem certs/
		ln -s /etc/letsencrypt/live/$domain_name/privkey.pem certs/
	fi



cat > /usr/local/TsManager/tsmanager-$manager_port/.env << EOF
NODE_ENV=$node_env

PORT=$manager_port

MYSQL_HOST="localhost"
MYSQL_USERNAME="$mysql_username"
MYSQL_PASSWORD="$mysql_password"
MYSQL_DATABASE="$mysql_database"
STATIC_TOKEN=$api_token

WEATHER_LIST_CHECK="*/10 * * * *"
PRICE_LIST_CHECK="*/10 * * * *"

EOF



	echo "[Unit]
	Description=Manager ${manager_port} Service
	After=network.target
	Wants=network.target

[Service]
	Type=simple
	WorkingDirectory=/usr/local/TsManager/tsmanager-${manager_port}/
	ExecStart=/usr/local/TsManager/tsmanager-${manager_port}/TsManager
	Restart=on-failure
	RestartSec=5s

[Install]
	WantedBy=multi-user.target" > /etc/systemd/system/tsmanager-${manager_port}.service


	systemctl enable tsmanager-${manager_port}.service
	systemctl start tsmanager-${manager_port}.service

	


	if ([[ ${usingHttps} == 1 ]]); then
		echo -e "${green}Ip manager shoma: https://$domain_name:$manager_port${plain}"
	else
		echo -e "${green}Ip manager shoma: http://$ipv4:$manager_port${plain}"

	fi

	echo -e "${green} Token Api Shoma: ${api_token}${plain}"

	exit 0
}


echo -e "${green}Running...${plain}"

install_base
install_panel



