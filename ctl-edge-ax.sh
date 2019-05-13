set -e

BASEDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

. $BASEDIR/ctl-lib.sh

check_envvars "PROJECT_ID BUCKET ZONE_ID GOOGLE_SERVICE_CREDENTIALS"


for i in `seq 1 5`
do
    export N${i}_IP=`gcloud compute instances describe ${CLUSTER_PREFIX}n$i --zone=$ZONE_ID --format json | jq -r '.networkInterfaces[] .accessConfigs[] | select( .name == "external-nat" ) .natIP'`

    export N${i}_IP_INT=`gcloud compute instances describe ${CLUSTER_PREFIX}n$i --zone=$ZONE_ID --format json | jq -r '.networkInterfaces[].networkIP'`
done

ansible n1 -b -m file -a "path=$( dirname $GOOGLE_SERVICE_CREDENTIALS ) state=directory owner=apigee group=apigee"
ansible n1 -b -m copy -a "src=$GOOGLE_SERVICE_CREDENTIALS dest=$GOOGLE_SERVICE_CREDENTIALS owner=apigee group=apigee"

ansible n1 -b -m yum -a "name=git state=latest"
ansible n1 -b -m yum -a "name=nodejs state=latest"

ansible n1 -b -m copy -a "src=~/edge-ax-gcs-ps-bq-gds/gcp-ax-collection dest=/opt/gcp-ax-collection owner=apigee group=apigee"

# create bucket here; skip its creation exists in cxtl-gcspsbq.sh
gsutil mb -c regional -l us-central1 gs://$BUCKET

cat <<EOT > gcp-ax-collection.ini
privatekey=$GOOGLE_SERVICE_CREDENTIALS
bucket=$BUCKET
EOT
ansible n1 -b -m copy -a "src=gcp-ax-collection.ini dest=/opt/gcp-ax-collection/gcp-ax-collection owner=apigee group=apigee"

ansible n1 -b --become-user=apigee -m shell -a "cd /opt/gcp-ax-collection/gcp-ax-collection; npm install"
ansible n1 -b --become-user=apigee -m shell -a "cd /opt/gcp-ax-collection/gcp-ax-collection; nohup node app.js </dev/null >cd /opt/gcp-ax-collection/gcp-ax-collection 2>&1 &"

ansible n1 -b --become-user=apigee -m shell -a "cd /opt/gcp-ax-collection/gcp-ax-collection; nohup node app.js </dev/null >/opt/gcp-ax-collection/gcp-ax-collection/nohup.log 2>&1 &"


ansible n1 -b -a "npm install pm2 -g"
ansible n1 -b -m shell -a "cd /opt/gcp-ax-collection/gcp-ax-collection; pm2 start app.js"
# curl "http://n1:3000/v1/upload/location?repo=edge&relative_file_path=abc.tgz"



cat <<EOT > message-processor.properties                                                                                                                                                                                                                                                      
conf_datalake-ingestion_datastore.tsBucketInterval=120000
conf_datalake-ingestion_datalake.ingestion.turnedOn=true

conf_datalake-ingestion_uap.collectionService=http://n1:3000/v1/upload/location
conf_datalake-ingestion_uap.repository=edge
conf_datalake-ingestion_uap.dataset=api
EOT

ansible n2,n3 -b -m copy -a "src=message-processor.properties dest=/opt/apigee/customer/application/message-processor.properties owner=apigee group=apigee"
ansible n2,n3 -f1 -a "apigee-service edge-message-processor restart" 


# export MS_IP=`ansible n1 -a "hostname -i" |grep 10\.`
export MS_IP=$N1_IP
export R1_IP=$N2_IP
export R2_IP=$N3_IP

export MS_IP_INT=$N1_IP_INT
export R1_IP_INT=$N2_IP_INT
export R2_IP_INT=$N3_IP_INT

echo "MS_IP_INT=$MS_IP_INT"
echo "R1_IP_INT=$R1_IP_INT"
echo "R2_IP_INT=$R2_IP_INT"

export application=echo
export bundle=echo_v1.zip
export org=org
export env=prod
export rev=1
export url=http://$MS_IP_INT:8080

echo "machine $MS_IP_INT login admin@exco.com password " 'Apigee123!' > ~/.netrc

curl -n "$url/v1/organizations/$org/apis?action=import&name=$application" -T $bundle -H "Content-Type: application/octet-stream" -X POST
curl -n "$url/v1/organizations/$org/apis/$application/revisions/$rev/deployments?action=deploy&env=$env" -X POST -H "Content-Type: application/octet-stream"



# curl -v -H "Host: org-prod.apigee.net" http://$R1_IP_INT:9001/echo
# ab -n 10 -c 1 -H "Host: org-prod.apigee.net" http://$R1_IP_INT:9001/echo
# ab -n 1000000 -c 1 -H "Host: org-prod.apigee.net" http://$R1_IP_INT:9001/echo
