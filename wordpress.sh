#!/bin/bash

####################################################
#
# DEPLOYING WORDREPSS ON GKE WITH PVC AND CLOUD SQL
#
####################################################

    # SET ENV
    gcloud config set compute/zone us-central1-a
    export PROJECT_ID=airy-totality-151318
    CLUSTER_NAME=wordpress-cluster
    INSTANCE_NAME=wordpress-db-001
    SA_NAME=cloudsql-proxy
    SA_EMAIL=$(gcloud iam service-accounts list --filter=displayName:$SA_NAME --format='value(email)')

build () {

    # CLONE REPO
    git clone https://github.com/GoogleCloudPlatform/kubernetes-engine-samples
    cd kubernetes-engine-samples/wordpress-persistent-disks/
    WORKING_DIR=$(pwd)

    # CREATE GKE CLUSTER
    gcloud container clusters create $CLUSTER_NAME --num-nodes=3 --enable-autoupgrade --no-enable-basic-auth --no-issue-client-certificate --enable-ip-alias --metadata disable-legacy-endpoints=true

    # CREATE PERSISTENT VOLUME
    kubectl apply -f $WORKING_DIR/wordpress-volumeclaim.yaml
    # kubectl get persistentvolumeclaim

    # CREATE SQL INSTANCE
    gcloud sql instances create $INSTANCE_NAME
    export INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe $INSTANCE_NAME --format='value(connectionName)')
    gcloud sql databases create wordpress --instance $INSTANCE_NAME
    CLOUD_SQL_PASSWORD=$(openssl rand -base64 18)
    gcloud sql users create wordpress --host=% --instance $INSTANCE_NAME --password $CLOUD_SQL_PASSWORD

    # DEPLOY WORDPRESS
    gcloud iam service-accounts create $SA_NAME --display-name $SA_NAME
    sleep 10
    SA_EMAIL=$(gcloud iam service-accounts list --filter=displayName:$SA_NAME --format='value(email)')

    gcloud projects add-iam-policy-binding $PROJECT_ID --role roles/cloudsql.client --member serviceAccount:$SA_EMAIL
    gcloud iam service-accounts keys create $WORKING_DIR/key.json --iam-account $SA_EMAIL
    
    kubectl create secret generic cloudsql-db-credentials --from-literal username=wordpress --from-literal password=$CLOUD_SQL_PASSWORD
    kubectl create secret generic cloudsql-instance-credentials --from-file $WORKING_DIR/key.json

    # INSTALL WORDPRESS
    cat $WORKING_DIR/wordpress_cloudsql.yaml.template | envsubst > $WORKING_DIR/wordpress_cloudsql.yaml
    kubectl create -f $WORKING_DIR/wordpress_cloudsql.yaml
    # kubectl get pod -l app=wordpress --watch

    # EXPOSE WORDPRESS SERVICE
    kubectl create -f $WORKING_DIR/wordpress-service.yaml
    # kubectl get svc -l app=wordpress --watch

    # VISIT SITE
    # Via browser, visit http://external-ip-address

}


terminate () {
    kubectl delete service wordpress
    # watch gcloud compute forwarding-rules list
    kubectl delete deployment wordpress
    kubectl delete pvc wordpress-volumeclaim
    gcloud container clusters delete $CLUSTER_NAME --quiet
    sleep 10
    gcloud sql instances delete $INSTANCE_NAME --quiet
    gcloud projects remove-iam-policy-binding $PROJECT_ID --role roles/cloudsql.client --member serviceAccount:$SA_EMAIL
    gcloud iam service-accounts delete $SA_EMAIL    
}


#build
terminate
