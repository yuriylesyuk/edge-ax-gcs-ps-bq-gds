#!/bin/bash
set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. $BASEDIR/ctl-lib.sh

check_envvars "PROJECT_ID BUCKET REGION_ID"

ACTION="$1"
if [[ ! ";nukeitout;provision;" =~ ";$ACTION;" ]]; then

    echo " Supported Action:"
    echo "    nukeitout  provision"
    exit 2
fi

export STAGING_LOCATION=${STAGING_LOCATION:-gs://$BUCKET/staging}
export TEMPLATE_LOCATION=${TEMPLATE_LOCATION:-gs://$BUCKET/templates}

export EDGE_AX_GCS_BUCKET=${EDGE_AX_GCS_BUCKET:-$BUCKET}
export EDGE_AX_NOTIFICATIONS_PB_TOPIC=${EDGE_AX_NOTIFICATIONS_PB_TOPIC:-$PROJECT_ID-edge-ax-nots}
export EDGE_AX_FACTS_PB_TOPIC=${EDGE_AX_FACTS_PB_TOPIC:-$PROJECT_ID-edge-ax-facts}
export EDGE_AX_BQ_DATASET=${EDGE_AX_BQ_DATASET:-edge_ax}
export EDGE_AX_BQ_FACTS_TABLE=${EDGE_AX_BQ_FACTS_TABLE:-$EDGE_AX_BQ_DATASET.tlab_prod_fact}


#-----------------------------------------------------------------------
if [ "provision" == "$ACTION" ]; then


#
# setup and configure gcp part of the ax solution
#    gcs
#    pb
#    bq
#    dataflow: gcs-to-pb
#    dataflow: pb-to-bq
#

# management commands
#    gcloud dataflow jobs list
#    gcloud dataflow jobs cancel 2018-09-07_10_13_59-2931274094598596933


#
# create bucket for ax batches
#
### gsutil mb -c regional -l $REGION_ID gs://$EDGE_AX_GCS_BUCKET


#
# setup notifications
#
gcloud pubsub topics create $EDGE_AX_NOTIFICATIONS_PB_TOPIC --project=$PROJECT_ID

gsutil notification create -t $EDGE_AX_NOTIFICATIONS_PB_TOPIC -f json -e OBJECT_FINALIZE gs://$EDGE_AX_GCS_BUCKET

#
# create topic for ax facts
#
gcloud pubsub topics create $EDGE_AX_FACTS_PB_TOPIC --project=$PROJECT_ID

#
# create bq dataset and facts table
#

# TODO: soft-code location 

bq --location=US mk -d --default_table_expiration 31557600 --description "Edge/AX dataset." $EDGE_AX_BQ_DATASET
bq mk --expiration 31557600 --time_partitioning_type=DAY --time_partitioning_expiration 31557600 --project_id=$PROJECT_ID --table $EDGE_AX_BQ_FACTS_TABLE ./pg-edge-fact-table.json


#
# ps-to-bq dataflow
#
# create template
cd ax-dataflows-gcstopb
mvn compile exec:java \
    -Dexec.mainClass=com.exco.ax.dataflows.gcstopb.EdgeAXGcsToPubSub \
    -Dexec.args="--runner=DataflowRunner \
                 --project=$PROJECT_ID \
                 --stagingLocation=$STAGING_LOCATION \
                 --templateLocation=$TEMPLATE_LOCATION/ax-dataflows-gcstopb"
cd ..

## PERMISSION: dataflow.jobs.create
# create job
gcloud dataflow jobs run ax-dataflows-gcstopb \
        --gcs-location $TEMPLATE_LOCATION/ax-dataflows-gcstopb \
        --parameters="inputTopic=projects/$PROJECT_ID/topics/$EDGE_AX_NOTIFICATIONS_PB_TOPIC,outputTopic=projects/$PROJECT_ID/topics/$EDGE_AX_FACTS_PB_TOPIC" 


#
# ps-to-bq dataflow
#
# create template
cd ax-dataflows-pbtobq
mvn compile exec:java \
    -Dexec.mainClass=com.exco.ax.dataflows.pbtobq.EdgeAXPubSubToBigQuery \
    -Dexec.args="--runner=DataflowRunner \
                 --project=$PROJECT_ID \
                 --stagingLocation=$STAGING_LOCATION \
                 --templateLocation=$TEMPLATE_LOCATION/ax-dataflows-pbtobq"
cd ..

# create job
gcloud dataflow jobs run ax-dataflows-pbtobq \
        --gcs-location $TEMPLATE_LOCATION/ax-dataflows-pbtobq \
        --parameters="inputTopic=projects/$PROJECT_ID/topics/$EDGE_AX_FACTS_PB_TOPIC,outputTableSpec=$EDGE_AX_BQ_FACTS_TABLE" 

fi

#-----------------------------------------------------------------------
if [ "nukeitout" == "$ACTION" ]; then

bq rm -f -t  $PROJECT_ID:$EDGE_AX_BQ_FACTS_TABLE
bq rm -f $PROJECT_ID:$EDGE_AX_BQ_DATASET

job_id=`gcloud dataflow jobs list --format=json | jq -r '.[] | select( .name== "ax-dataflows-gcstopb" and .state == "Running") | .id'`
if [ ! -z "$job_id" ]; then
    gcloud dataflow jobs cancel $job_id
fi 

job_id=`gcloud dataflow jobs list --format=json | jq -r '.[] | select( .name== "ax-dataflows-pbtobq" and .state == "Running") | .id'`
if [ ! -z "$job_id" ]; then
    gcloud dataflow jobs cancel $job_id
fi

set +e

gsutil notification delete gs://$EDGE_AX_GCS_BUCKET


###gsutil rm -r gs://$EDGE_AX_GCS_BUCKET

gcloud pubsub topics delete $EDGE_AX_NOTIFICATIONS_PB_TOPIC --project=$PROJECT_ID
gcloud pubsub topics delete $EDGE_AX_FACTS_PB_TOPIC --project=$PROJECT_ID

##
## TODO: remove templates
##
fi
