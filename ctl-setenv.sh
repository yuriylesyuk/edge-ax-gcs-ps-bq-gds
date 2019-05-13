#
# Usage:
#   clone the file
#   edit/configure variables as appropriate
#   source ctl-setenv.sh
#

export PROJECT_ID=<gcp-project-id>
export REGION_ID=<gcp-region-id>
export ZONE_ID=<gcp-zone-id>
export BUCKET=<bucket>


gcloud config set project $PROJECT_ID
gcloud config set compute/zone $ZONE_ID


# to activate:
#   gcloud auth activate-service-account --key-file=$GOOGLE_APPLICATION_CREDENTIALS
export GOOGLE_SERVICE_ACCOUNT=${GOOGLE_SERVICE_ACCOUNT:-uap-service}
export GOOGLE_SERVICE_CREDENTIALS=${GOOGLE_SERVICE_CREDENTIALS:-/opt/apigee-edge-ax/sakey/$GOOGLE_SERVICE_ACCOUNT-privatekey.json}

