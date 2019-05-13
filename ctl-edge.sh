#-----------------------------------------------------------------------
#
# Check input parameters
#
#-----------------------------------------------------------------------
set -e
function error_report(){
   echo "Error on line $(caller)"
}
trap "error_report" ERR



if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters"
    echo "    rewind.sh <action>"
    echo ""
    echo "where action is in list: nukeout  jumpbox  provision  edge  org"
    echo ""
    exit 5
fi

ACTION=$1

if [[ ! ";nukeitout;ssh;jumpbox;provision;edge;org;" =~ ";$ACTION;" ]]; then 

    echo " Supported Action:"
    echo "    nukeitout  jumpbox  provision (ssh included)  edge  org ssh (standalone)"
    exit 2
fi


# edge cluster prefix:
#     CLUSTER_PREFIX=cc-  # cc -- consul connect
# usage: ${CLUSTER_PREFIX}
CLUSTER_PREFIX="${CLUSTER_PREFIX:-}"

echo ""
echo "Cluster Prefix: ${CLUSTER_PREFIX:-}."
echo ""



#-----------------------------------------------------------------------
#
#
#  Functions
#
#
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
function setup_ssh_ansible(){

echo -e "\nGenerate and setup edge ssh key\n"
#
# generate [once:)]
ssh-keygen -t rsa -f ~/.ssh/edge -C edge -q -N ""

SSH_KEYS=`gcloud compute project-info describe --format=json | jq -r '.commonInstanceMetadata.items[] | select( .key== "ssh-keys") | .value'`

EDGE_SSH_KEY=`cat ~/.ssh/edge.pub | awk '{print "edge:" $1 " " $2  " google-ssh {\"userName\":\"edge\",\"expireOn\":\"2018-12-04T20:12:00+0000\"}"}'`
                                                                                                                                                               
gcloud compute project-info add-metadata  --no-user-output-enabled --metadata-from-file ssh-keys=<( echo -e "$SSH_KEYS\n$EDGE_SSH_KEY" )

#
echo -e "\nSetup ansible configuration"

# apt for debian
sudo yum -y install ansible wget

mkdir ~/ansible

cat <<EOT > ~/.ansible.cfg
[defaults]
inventory = ~/ansible/hosts
fork = 50
EOT


for i in `seq 1 5`
do
    export N${i}_IP=`gcloud compute instances describe ${CLUSTER_PREFIX}n$i --zone=$ZONE_ID --format json | jq -r '.networkInterfaces[] .accessConfigs[] | select( .name == "external-nat" ) .natIP'`

    export N${i}_IP_INT=`gcloud compute instances describe ${CLUSTER_PREFIX}n$i --zone=$ZONE_ID --format json | jq -r '.networkInterfaces[].networkIP'`
done


# print out list of _IPs
env|grep _IP
for i in `seq 1 5`
do
    REF_IP=N${i}_IP_INT
    eval NODE_IP=\$$REF_IP
    cat <<EOT >> ~/.ssh/config
Host n$i
    HostName $NODE_IP
    User edge
    IdentityFile ~/.ssh/edge
EOT
done

sudo chmod 0600 ~/.ssh/config

echo "[edge]" > ~/ansible/hosts
for i in `seq 1 5`
do
    REF_IP=N${i}_IP_INT
    eval NODE_IP=\$$REF_IP
    cat <<EOT >> ~/ansible/hosts
n$i ansible_host=$NODE_IP ansible_user=edge ansible_ssh_private_key_file=~/.ssh/edge
EOT
done

for i in `seq 1 5`
do
    REF_IP=N${i}_IP_INT
    eval NODE_IP=\$$REF_IP
    ssh-keyscan -t rsa $NODE_IP >> ~/.ssh/known_hosts
done

ansible edge -m ping
}
#-----------------------------------------------------------------------




#-----------------------------------------------------------------------
#
#
# Environment
#
#-----------------------------------------------------------------------

#
#
# Check if logged in
#
echo "Checking if logged into a gcp account..."

OUTPUT=`gcloud auth list --format json`
if [ "$OUTPUT" = "[]" ]; then
    echo "Please log into a valid student account using"
    echo "    gcloud auth login"
    echo "command."
    exit 1
fi

echo "A user is logged in."

#
#
# Configure Project Id
#
if [ "$PROJECT_ID" = "" ]; then
    echo "Please Setup PROJECT_ID variable."
    echo "You can use:"
    echo "    export PROJECT_ID=\$GOOGLE_CLOUD_PROJECT"
    echo "or:"
    echo "    export PROJECT_ID=\`gcloud config get-value project\`"
    echo ""
    exit 1
fi

gcloud config set project $PROJECT_ID

if [ "$ZONE_ID" = "" ]; then
    echo "Please Setup ZONE_ID variable."
    echo ""
    exit 1
fi
gcloud config set compute/zone $ZONE_ID

gcloud config list



#-----------------------------------------------------------------------
if [ "nukeitout" == "$ACTION" ]; then

    set +e
    gcloud -q compute instances delete ${CLUSTER_PREFIX}n1 ${CLUSTER_PREFIX}n2 ${CLUSTER_PREFIX}n3 ${CLUSTER_PREFIX}n4 ${CLUSTER_PREFIX}n5
    gcloud -q deployment-manager deployments delete edge-5n-${CLUSTER_PREFIX}planet
    set -e

    rm -rf ~/ansible

    rm -f ~/.ssh/config 
    rm -f ~/.ssh/edge
    rm -f ~/.ssh/edge.pub 


    echo -e "\nJob done."

    exit 0
fi

#-----------------------------------------------------------------------
#
# Ssh autologin and ansible Setup
#
#-----------------------------------------------------------------------
if [ "ssh" == "$ACTION" ]; then
    setup_ssh_ansible
    exit 0
fi
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
#
# Lab 1 Setup
#
#-----------------------------------------------------------------------
if [ "provision"  == "$ACTION" ]; then

echo -e "\nProvision VMs.\n\n"

#
# Checking repo creds and license file
#

if [ ! -f /opt/apigee-install/credentials.txt ]; then
    echo " Credentials File is not found!"
    exit 2
fi


if [ ! -f /opt/apigee-install/license.txt ]; then
    echo "License File not found!"
    exit 3
fi



echo "Prerequisites: Fetching Oracle JDK..."
export ORACLE_JDK8_URL=${ORACLE_JDK8_URL:-"https://download.oracle.com/otn-pub/java/jdk/8u191-b12/2787e4a523244c269598db4e85c51e0c/jdk-8u191-linux-x64.rpm"}
export ORACLE_JDK8_FILE=${ORACLE_JDK8_URL##*/}
set +e
wget --no-cookies --no-check-certificate --directory-prefix=/opt/apigee-install --header "Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com%2F; oraclelicense=accept-securebackup-cookie" "$ORACLE_JDK8_URL" 2>&1

if [ $? -ne 0 ]; then
    echo "JDK url is not valid: $ORACLE_JDK8_URL"
    echo ""
    echo "Until we update this script, please visit Oracle Java SE Development Kit 8 Downloads page, accept license "
    echo " and right-click and Copy Link Address for latest jdk-8u<release>-linux-x64.rpm"
    echo "Override it by setting"
    echo "    export ORACLE_JDK8_URL=<full-url-to-rpm-file>"
    echo ""
    exit 1
fi
set -e

#
# VM provisioning
#

function provision_vm(){

VM=$1


read -r -d '' SPEC << EOT  || true
- name: $VM
  type: compute.v1.instance
  properties:


    zone: $ZONE_ID
    machineType: zones/$ZONE_ID/machineTypes/n1-standard-2
    disks:
    - deviceName: boot
      type: PERSISTENT
      boot: true
      autoDelete: true
      initializeParams:
        sourceImage: projects/centos-cloud/global/images/family/centos-7
    networkInterfaces:
    - network: global/networks/default
      accessConfigs:
      - name: external-nat
        type: ONE_TO_ONE_NAT
EOT

echo -e "$SPEC"

}

echo -e "#\n# 5 nodes for Edge planet\n#\nresources:" > "/opt/apigee-install/edge-5n-${CLUSTER_PREFIX}spec.yaml"

for i in `seq 1 5`
do
    vm_name=${CLUSTER_PREFIX}n$i
    echo "provisioning vm: $vm_name"
    provision_vm $vm_name >> "/opt/apigee-install/edge-5n-${CLUSTER_PREFIX}spec.yaml"
    echo "" >> "/opt/apigee-install/edge-5n-${CLUSTER_PREFIX}spec.yaml"
done

gcloud deployment-manager deployments create edge-5n-${CLUSTER_PREFIX}planet --config /opt/apigee-install/edge-5n-${CLUSTER_PREFIX}spec.yaml

# clean up if things went wrong:
#   gcloud compute instances delete n1 n2 n3 n4 n5
#   gcloud deployment-manager deployments delete edge-5n-planet

#
#


# The ssh/ansible setup makes sense after nodes are provisioned.
setup_ssh_ansible


#
## Configure response files
# gen response on local machine
cat <<EOT > /opt/apigee-install/edge-response.cfg
IP1="$N1_IP_INT"
IP2="$N2_IP_INT"
IP3="$N3_IP_INT"
IP4="$N4_IP_INT"
IP5="$N5_IP_INT"

IP1_PUBLIC="$N1_IP"
IP2_PUBLIC="$N2_IP"
IP3_PUBLIC="$N3_IP"
IP4_PUBLIC="$N4_IP"
IP5_PUBLIC="$N5_IP"

HOSTIP="\$(hostname -i)"
MSIP="\$IP1"
ADMIN_EMAIL="admin@exco.com"
APIGEE_ADMINPW="Apigee123!"
LICENSE_FILE="/opt/apigee-install/license.txt"
USE_LDAP_REMOTE_HOST="n"
LDAP_TYPE="1"
APIGEE_LDAPPW="Apigee123!"
MP_POD="gateway"
REGION="dc-1"
ZK_HOSTS="\$IP1 \$IP2 \$IP3"
ZK_CLIENT_HOSTS="\$IP1 \$IP2 \$IP3"
CASS_HOSTS="\$IP1:1,1 \$IP2:1,1 \$IP3:1,1"
#CASS_USERNAME="cassandra"
#CASS_PASSWORD="cassandra"
CASS_CLUSTERNAME="Apigee"
PG_MASTER="\$IP4"
PG_STANDBY="\$IP5"
SKIP_SMTP="y"
SMTPHOST="smtp.example.com"
SMTPPORT="25"
SMTPUSER="smtp@example.com"
SMTPMAILFROM="admin@exco.com"
SMTPPASSWORD="smtppwd"
SMTPSSL="n"
BIND_ON_ALL_INTERFACES="y"
EOT

cat <<EOT > /opt/apigee-install/edge-response-setup-org.cfg
IP1="$N1_IP_INT"

MSIP=\$IP1
ADMIN_EMAIL=admin@exco.com
APIGEE_ADMINPW="Apigee123!"
NEW_USER="y"
USER_NAME=orgadmin@exco.com
FIRST_NAME=OrgAdminName
LAST_NAME=OrgAdminLastName
USER_PWD=Apigee123!
ORG_NAME=org
ORG_ADMIN=\$USER_NAME
ENV_NAME=prod
VHOST_PORT=9001
VHOST_NAME=default
VHOST_ALIAS=org-prod.apigee.net
USE_ALL_MPS=y
EOT


ansible edge -b -a "yum clean all"
ansible edge -b -a "sudo yum update -y"



ansible edge -b -m yum -a "name=mc state=present"
ansible edge -b -m yum -a "name=wget state=present"

ansible edge -ba "mkdir -p /opt/apigee-install"
ansible edge -ba "chown edge:edge /opt/apigee-install"


#
# prerequisites
#


ansible edge -b -m copy -a "src=/opt/apigee-install/credentials.txt dest=/opt/apigee-install/"

ansible edge -b -m copy -a "src=/opt/apigee-install/edge-response.cfg dest=/opt/apigee-install/"

ansible edge -b -m copy -a "src=/opt/apigee-install/edge-response-setup-org.cfg dest=/opt/apigee-install/"

ansible edge -b -m copy -a "src=/opt/apigee-install/license.txt dest=/opt/apigee-install/"


ansible edge -m copy -a "src=/opt/apigee-install/${ORACLE_JDK8_FILE} dest=/opt/apigee-install"

ansible edge -bm yum -a "name=/opt/apigee-install/${ORACLE_JDK8_FILE} state=present"

ansible edge -a "java -version"

fi
#-----------------------------------------------------------------------

#----------------------------------------------------------------------
#
# Edge setup
#
#-----------------------------------------------------------------------
if [ "edge" == "$ACTION" ]; then

echo -e "\nInstall Edge.\n\n"



#
# Define environment variables
#
export REPO_CLIENT_ID=`awk '/User:/{print $2}' /opt/apigee-install/credentials.txt`
export REPO_PASSWORD=`awk '/Password:/{print $2}' /opt/apigee-install/credentials.txt`

ansible edge -a "wget https://software.apigee.com/bootstrap_4.18.05.sh -O /opt/apigee-install/bootstrap_4.18.05.sh"

ansible edge -ba "setenforce 0"

ansible edge -ba "bash /opt/apigee-install/bootstrap_4.18.05.sh apigeeuser=$REPO_CLIENT_ID apigeepassword=$REPO_PASSWORD"


ansible edge -a "/opt/apigee/apigee-service/bin/apigee-service apigee-setup install"
#
# Lab 1: Install Edge
#
ansible n1,n2,n3 -f1 -m shell -a "/opt/apigee/apigee-setup/bin/setup.sh -f /opt/apigee-install/edge-response.cfg -p ds | tee /opt/apigee-install/edge-apigee-ds-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"
ansible n1 -m shell -a "/opt/apigee/apigee-setup/bin/setup.sh -f /opt/apigee-install/edge-response.cfg -p ms | tee /opt/apigee-install/edge-apigee-ms-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"
ansible n2,n3 -f1 -m shell -a "/opt/apigee/apigee-setup/bin/setup.sh -f /opt/apigee-install/edge-response.cfg -p rmp | tee /opt/apigee-install/edge-apigee-rmp-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"
ansible n4,n5 -f1 -m shell -a "/opt/apigee/apigee-setup/bin/setup.sh -f /opt/apigee-install/edge-response.cfg -p sax | tee /opt/apigee-install/edge-apigee-sax-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"
ansible n1 -m shell -a "/opt/apigee/apigee-service/bin/apigee-service apigee-validate install | tee /opt/apigee-install/edge-apigee-validate-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"
ansible n1 -m shell -a "/opt/apigee/apigee-service/bin/apigee-service apigee-validate setup -f /opt/apigee-install/edge-response.cfg | tee /opt/apigee-install/edge-apigee-validate-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"


# TODO: No point for internal project; no harm, but will be deleted

#
# Firewall rules to expose the planet
#
gcloud compute firewall-rules create edge-ms --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:8080 --source-ranges=0.0.0.0/0
gcloud compute firewall-rules create edge-ui --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:9000 --source-ranges=0.0.0.0/0
fi
#-----------------------------------------------------------------------
#-----------------------------------------------------------------------
#
# Lab 2 Setup
#
#-----------------------------------------------------------------------
if [ "org" == "$ACTION" ]; then
echo -e "\nProvision org/edge.\n\n"

#
# Lab 2: Provision org and env
#
ansible n1 -f1 -m shell -a "/opt/apigee/apigee-service/bin/apigee-service apigee-provision setup-org -f /opt/apigee-install/edge-response-setup-org.cfg | tee /opt/apigee-install/edge-apigee-setup-org-install-`date -u +\"%Y-%m-%dT%H:%M:%SZ\"`.log"


# TODO: No point for internal project; no harm, but will be deleted

# Firewall rule for default vhost 9001
gcloud compute firewall-rules create vhost --direction=INGRESS --priority=1000 --network=default --action=ALLOW --rules=tcp:9001 --source-ranges=0.0.0.0/0


fi
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
#
# Lab 2 Setup
#
#-----------------------------------------------------------------------
if [ "proxy" == "$ACTION" ]; then
echo -e "\nSetting up Proxy and generating targer 3.\n\n"

fi
#-----------------------------------------------------------------------

gcloud compute instances list


