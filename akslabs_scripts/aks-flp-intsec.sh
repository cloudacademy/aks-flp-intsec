#!/bin/bash

# script name: aks-flp-intsec.sh
# Version v0.0.1 20211118
# Set of tools to deploy AKS troubleshooting labs

# "-l|--lab" Lab scenario to deploy
# "-r|--region" region to deploy the resources
# "-u|--user" User alias to add on the lab name
# "-h|--help" help info
# "--version" print version

# read the options
TEMP=`getopt -o g:n:l:r:u:hv --long resource-group:,name:,lab:,region:,user:,help,validate,version -n 'aks-flp-intsec.sh' -- "$@"`
eval set -- "$TEMP"

# set an initial value for the flags
RESOURCE_GROUP=""
CLUSTER_NAME=""
LAB_SCENARIO=""
USER_ALIAS=""
LOCATION="uksouth"
VALIDATE=0
HELP=0
VERSION=0

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -g|--resource-group) case "$2" in
            "") shift 2;;
            *) RESOURCE_GROUP="$2"; shift 2;;
            esac;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) CLUSTER_NAME="$2"; shift 2;;
            esac;;
        -l|--lab) case "$2" in
            "") shift 2;;
            *) LAB_SCENARIO="$2"; shift 2;;
            esac;;
        -r|--region) case "$2" in
            "") shift 2;;
            *) LOCATION="$2"; shift 2;;
            esac;;
        -u|--user) case "$2" in
            "") shift 2;;
            *) USER_ALIAS="$2"; shift 2;;
            esac;;    
        -v|--validate) VALIDATE=1; shift;;
        --version) VERSION=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

# Variable definition
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"
SCRIPT_VERSION="Version v0.0.1 20211118"

# Funtion definition

# az login check
function az_login_check () {
    if $(az account list 2>&1 | grep -q 'az login')
    then
        echo -e "\n--> Warning: You have to login first with the 'az login' command before you can run this lab tool\n"
        az login -o table
    fi
}

# check resource group and cluster
function check_resourcegroup_cluster () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    RG_EXIST=$(az group show -g $RESOURCE_GROUP &>/dev/null; echo $?)
    if [ $RG_EXIST -ne 0 ]
    then
        echo -e "\n--> Creating resource group ${RESOURCE_GROUP}...\n"
        az group create --name $RESOURCE_GROUP --location $LOCATION -o table &>/dev/null
    else
        echo -e "\nResource group $RESOURCE_GROUP already exists...\n"
    fi

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\n--> Cluster $CLUSTER_NAME already exists...\n"
        echo -e "Please remove that one before you can proceed with the lab.\n"
        exit 5
    fi
}

# validate cluster exists
function validate_cluster_exists () {
    RESOURCE_GROUP="$1"
    CLUSTER_NAME="$2"

    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -ne 0 ]
    then
        echo -e "\n--> ERROR: Failed to create cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP ...\n"
        exit 5
    fi
}

# Usage text
function print_usage_text () {
    NAME_EXEC="aks-flp-intsec"
    echo -e "$NAME_EXEC usage: $NAME_EXEC -l <LAB#> -u <USER_ALIAS> [-v|--validate] [-r|--region] [-h|--help] [--version]\n"
    echo -e "\nHere is the list of current labs available:\n
*************************************************************************************
*\t 1. AKS faling to pull image from ACR
*\t 2. AKS MSI issue (not ready yet)
*\t 3. AKS policy issue (not ready yet)
*************************************************************************************\n"
}

# Lab scenario 1
function lab_scenario_1 () {
    CLUSTER_NAME=aks-intsec-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-intsec-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME
    ACR_NAME=acr${USER_ALIAS}${RANDOM}

    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"

    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 2 \
    --tag aks-intsec-lab=${LAB_SCENARIO} \
    --generate-ssh-keys \
    --yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
    az acr create -n $ACR_NAME -g $RESOURCE_GROUP --sku basic -o table
    az acr import  -n $ACR_NAME --source docker.io/library/nginx:latest --image nginx:v1 -o table

kubectl create ns workload &>/dev/null
cat <<EOF | kubectl -n workload apply -f &>/dev/null -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx0-deployment
  labels:
    app: nginx0-deployment
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx0
  template:
    metadata:
      labels:
        app: nginx0
    spec:
      containers:
      - name: nginx
        image: ${ACR_NAME}.azurecr.io/nginx:v1
        ports:
        - containerPort: 80
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    echo -e "\n\n************************************************************************\n"
    echo -e "\n--> Issue description: \n AKS cluster with pods in failed status on workload namespace\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_1_validation () {
    CLUSTER_NAME=aks-intsec-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-intsec-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags -o yaml 2>/dev/null | grep aks-intsec-lab | cut -d ' ' -f2 | tr -d "'")"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null
        NUMBER_OF_PODS="$(kubectl get po -n workload --field-selector=status.phase=Running | grep ^nginx0-deployment | wc -l)"
        if [ $NUMBER_OF_PODS -ge 2 ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nThe pods in $CLUSTER_NAME look good now\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

# Lab scenario 2
function lab_scenario_2 () {
    CLUSTER_NAME=aks-intsec-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-intsec-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --generate-ssh-keys \
    --tag aks-intsec-lab=${LAB_SCENARIO} \
	--yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME
    
    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    MC_RESOURCE_GROUP=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query nodeResourceGroup -o tsv)
    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    VNET_NAME="$(az network vnet list -g $MC_RESOURCE_GROUP --query "[0].name" --output tsv)"
    SUBNET_URI="$(az network vnet subnet list -g $MC_RESOURCE_GROUP --vnet-name $VNET_NAME --query "[0].id" --output tsv)"
    az network nic create --name test-nic -g $RESOURCE_GROUP --subnet $SUBNET_URI -o none
    az aks delete -g $RESOURCE_GROUP -n $CLUSTER_NAME --yes --no-wait

    echo -e "\n\n********************************************************"
    echo -e "\n--> Issue description: \n AKS cluster stuck in deleting status, need help to delete the cluster\n"
    echo -e "Cluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_2_validation () {
    CLUSTER_NAME=aks-intsec-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-intsec-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    CLUSTER_EXIST=$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME &>/dev/null; echo $?)
    if [ $CLUSTER_EXIST -eq 0 ]
    then
        echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
    else
        echo -e "\nScenario $LAB_SCENARIO looks good, cluster $CLUSTER_NAME has been removed\n"
    fi
}

# Lab scenario 3
function lab_scenario_3 () {
    CLUSTER_NAME=aks-intsec-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-intsec-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    check_resourcegroup_cluster $RESOURCE_GROUP $CLUSTER_NAME
    
    echo -e "\n--> Deploying cluster for lab${LAB_SCENARIO}...\n"
    az aks create \
    --resource-group $RESOURCE_GROUP \
    --name $CLUSTER_NAME \
    --location $LOCATION \
    --node-count 1 \
    --generate-ssh-keys \
    --tag aks-intsec-lab=${LAB_SCENARIO} \
	--yes \
    -o table

    validate_cluster_exists $RESOURCE_GROUP $CLUSTER_NAME

    echo -e "\n\n--> Please wait while we are preparing the environment for you to troubleshoot...\n"
    az aks get-credentials -g $RESOURCE_GROUP -n $CLUSTER_NAME --overwrite-existing &>/dev/null

cat <<EOF | kubectl apply -f &>/dev/null -
kind: Deployment
apiVersion: apps/v1
metadata:
  name: mypod
spec:
  replicas: 2
  selector:
    matchLabels:
      app: mypod
  template:
    metadata:
      labels:
        app: mypod
    spec:
      containers:
      - name: mypod
        image: nginx:latest
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 250m
            memory: 256Mi
---
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: mypod-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: mypod
EOF

    CLUSTER_URI="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query id -o tsv)"
    UPGRADE_VERSION="$(az aks get-upgrades -g $RESOURCE_GROUP -n $CLUSTER_NAME --output table | grep $RESOURCE_GROUP | awk '{print $4}' | tr -d ',')"
    while true; do for s in / - \\ \|; do printf "\r$s"; sleep 1; done; done &
    az aks upgrade -g $RESOURCE_GROUP -n $CLUSTER_NAME --kubernetes-version $UPGRADE_VERSION --yes &>/dev/null
    kill $!; trap 'kill $!' SIGTERM
    echo -e "\n\n********************************************************"
    echo -e "\n--> Issue description: \nCluster upgrade failed\n"
    echo -e "\nCluster uri == ${CLUSTER_URI}\n"
}

function lab_scenario_3_validation () {
    CLUSTER_NAME=aks-intsec-ex${LAB_SCENARIO}-${USER_ALIAS}
    RESOURCE_GROUP=aks-intsec-ex${LAB_SCENARIO}-rg-${USER_ALIAS}
    
    LAB_TAG="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query tags -o yaml 2>/dev/null | grep aks-intsec-lab | cut -d ' ' -f2 | tr -d "'")"
    echo -e "\n+++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo -e "--> Running validation for Lab scenario $LAB_SCENARIO\n"
    if [ -z $LAB_TAG ]
    then
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    elif [ $LAB_TAG -eq $LAB_SCENARIO ]
    then
        CLUSTER_STATUS="$(az aks show -g $RESOURCE_GROUP -n $CLUSTER_NAME --query provisioningState -o tsv)"
        if [ "$CLUSTER_STATUS" == 'Succeeded' ]
        then
            echo -e "\n\n========================================================"
            echo -e "\nThe Cluster $CLUSTER_NAME looks good now\n"
        else
            echo -e "\nScenario $LAB_SCENARIO is still FAILED\n"
        fi
    else
        echo -e "\n--> Error: Cluster $CLUSTER_NAME in resource group $RESOURCE_GROUP was not created with this tool for lab $LAB_SCENARIO and cannot be validated...\n"
        exit 6
    fi
}

#if -h | --help option is selected usage will be displayed
if [ $HELP -eq 1 ]
then
	print_usage_text
    echo -e '"-l|--lab" Lab scenario to deploy (3 possible options)
"-r|--region" region to create the resources
"--version" print version of aks-flp-intsec
"-h|--help" help info\n'
	exit 0
fi

if [ $VERSION -eq 1 ]
then
	echo -e "$SCRIPT_VERSION\n"
	exit 0
fi

if [ -z $LAB_SCENARIO ]; then
	echo -e "\n--> Error: Lab scenario value must be provided. \n"
	print_usage_text
	exit 9
fi

if [ -z $USER_ALIAS ]; then
	echo -e "Error: User alias value must be provided. \n"
	print_usage_text
	exit 10
fi

# lab scenario has a valid option
if [[ ! $LAB_SCENARIO =~ ^[1-3]+$ ]];
then
    echo -e "\n--> Error: invalid value for lab scenario '-l $LAB_SCENARIO'\nIt must be value from 1 to 3\n"
    exit 11
fi

# main
echo -e "\n--> AKS Troubleshooting sessions
********************************************

This tool will use your default subscription to deploy the lab environments.
Verifing if you are authenticated already...\n"

# Verify az cli has been authenticated
az_login_check

if [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_1

elif [ $LAB_SCENARIO -eq 1 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_1_validation

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_2

elif [ $LAB_SCENARIO -eq 2 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_2_validation

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 0 ]
then
    check_resourcegroup_cluster
    lab_scenario_3

elif [ $LAB_SCENARIO -eq 3 ] && [ $VALIDATE -eq 1 ]
then
    lab_scenario_3_validation
else
    echo -e "\n--> Error: no valid option provided\n"
    exit 12
fi

exit 0