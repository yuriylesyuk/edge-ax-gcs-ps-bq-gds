"""
The airflow to process micro-batches arriving to gcs and push them to pubsub

"""
from airflow import models

from datetime import datetime, timedelta

from airflow.contrib.operators.dataflow_operator import DataflowTemplateOperator
# from gcs_to_gcs import GoogleCloudStorageToGoogleCloudStorageOperator

default_args = {
    'owner': 'yuriyl',
    'start_date': datetime(2018, 5, 21),
    'email': ['yuriyl@google.com'],
    'email_on_failure': True,
    'email_on_retry': False,
    'retries': 5,
    'retry_delay': timedelta(minutes=5),
    'dataflow_default_options': {
        'project': 'ops-enablement-yl',
        'zone': 'us-central1-f',
        'tempLocation': 'gs://ops-enablement-yl-ax-repo/tmp'
    }
}

with models.DAG(
  'edge_ax_gs_to_pubsub_v2', 
  default_args=default_args, 
  schedule_interval= "0 0 1 * *"
) as dag:


    df_gs_to_ps = DataflowTemplateOperator(
        task_id='ingest_files',
        template="gs://dataflow-templates/latest/GCS_Text_to_Cloud_PubSub",
        parameters={
            #"inputFilePattern": "gs://ops-enablement-yl-repo/edge/api/*.txt.gz",
            "inputFilePattern": "gs://ops-enablement-yl-ax-repo/*.txt.gz",
            "outputTopic": "projects/ops-enablement-yl/topics/edge-ax"
        },
        #gcp_conn_id='gcp_project',
        dag=dag
    )

    # gs_file_to_coldline = GoogleCloudStorageToGoogleCloudStorageOperator(
    #     task_id='move_files',
    #     source_bucket='gs://ops-enablement-yl-ax-repo',
    #     source_object='*.txt.gz',
    #     destination_bucket='ops-enablement-yl-ax-repo-cl',
    #     move_object=True,
    #     google_cloud_storage_conn_id='google_cloud_storage_default'
    # )

    # df_gs_to_ps >> gs_file_to_coldline
    df_gs_to_ps
