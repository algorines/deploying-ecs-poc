#!/bin/bash
set -eu

red='\033[0;31m'
green='\033[0;32m'
NC='\033[0m' # No Color

log_info() {
  echo -e "\n${green}$1${NC}"
}

log_error() {
  echo -e "\n${red}$1${NC}"
}

usage() {
  log_info "usage: $0 <microservice_name> <environment> <version>"
  echo "  <microservice_name>: microservice name to update"
  echo "  <environment>: [ prod | stag | pre ]"
  echo "  <environment>: version to deploy"
}

if [ "$#" -ne 3 ]; then
  usage
  exit 1
fi

name_svc=$1

ENV=$2

VERSION=$3

if [ "$ENV" != "prod" ] && [ "$ENV" != "stag" ] && [ "$ENV" != "pre" ]; then
  usage
  log_error "ERROR: '$ENV' must be [ prod | stag | pre ]"
  exit 1
fi

desired_task=1
if [ "$ENV" != "stag" ]; then
  desired_task=2
fi

task_folder='task-definitions-'$ENV''

aux_name_svc=$(ls $task_folder | grep $1)

mkdir -p /tmp/td
cp $task_folder/$aux_name_svc /tmp/td
sed -i'.bk' 's/VERSION/'$VERSION'/g' /tmp/td/$aux_name_svc
sed -i'.bk' 's/DEPLOYMENT_ENV/'$ENV'/g' /tmp/td/$aux_name_svc

#create new task revision
aws --profile aws-project-$ENV ecs register-task-definition --cli-input-json file:///tmp/td/$aux_name_svc

cluster_name=project-$ENV
if [ $name_svc == "b2c-web" ]; then
  cluster_name="b2c-web"
fi
#update-service
aws --profile aws-project-$ENV ecs update-service --cluster $cluster_name --service $name_svc-svc --task-definition $name_svc-td-$ENV
sleep 10
runningCount=$(aws --profile aws-project-$ENV ecs describe-services --services $name_svc-svc --cluster $cluster_name | jq '.services[0].deployments[0].runningCount')
active=$(aws --profile aws-project-$ENV ecs describe-services --services $name_svc-svc --cluster $cluster_name | jq '.services[0].deployments[1].status')
while [ $runningCount != $desired_task ] || [ $active == "ACTIVE" ]
do
  sleep 5
  runningCount=$(aws --profile aws-project-$ENV ecs describe-services --services $name_svc-svc --cluster $cluster_name | jq '.services[0].deployments[0].runningCount')
  active=$(aws --profile aws-project-$ENV ecs describe-services --services $name_svc-svc --cluster $cluster_name | jq '.services[0].deployments[1].status')
  echo $runningCount
done

log_info "Updated $name_svc service"
