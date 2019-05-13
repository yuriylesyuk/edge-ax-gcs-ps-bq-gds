#!/bin/bash
set -e

gcloud services enable cloudresourcemanager.googleapis.com
gcloud services enable dataflow.googleapis.com

export JUMPBOX=jumpbox

#
## requires projec.admin permissions
#
gcloud compute instances create --image-family=centos-7 --image-project=centos-cloud ${CLUSTER_PREFIX}${JUMPBOX}

gcloud iam service-accounts create $GOOGLE_SERVICE_ACCOUNT --display-name "Egde AX Service Account"

gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/compute.admin
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/deploymentmanager.editor
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/iam.serviceAccountUser


gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/storage.admin
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/dataflow.admin
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/pubsub.admin
gcloud projects add-iam-policy-binding $PROJECT_ID --member serviceAccount:$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com --role roles/bigquery.user

gcloud compute instances stop ${JUMPBOX}
gcloud beta compute instances set-scopes ${JUMPBOX} --zone=$ZONE_ID --scopes=cloud-platform --service-account=$GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com
gcloud compute instances start ${JUMPBOX}

gcloud iam service-accounts keys create ~/$( basename $GOOGLE_SERVICE_CREDENTIALS ) --iam-account $GOOGLE_SERVICE_ACCOUNT@$PROJECT_ID.iam.gserviceaccount.com

## gcloud compute --project $PROJECT_ID scp --zone $ZONE_ID  ~/$( basename $GOOGLE_SERVICE_CREDENTIALS ) "${JUMPBOX}:/~"
