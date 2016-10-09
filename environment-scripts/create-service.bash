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
  log_info "usage: $0 <task_definitions_path> <environment>"
  echo "  <task_definition_path>: /path/to/task/definitions"
  echo "  <environment>: [ prod | stag | pre ]"
}

if [ "$#" -ne 2 ]; then
  usage
  exit 1
fi

task_folder=$1

if [ ! -d "$task_folder" ]; then
  usage
  log_error "ERROR: '$task_folder' does not exist or is not a directory"
  exit 1
fi

if [[ ! $task_folder = /* ]]; then
  usage
  log_error "ERROR: '$task_folder' must be an absolute path"
  exit 1
fi

ENV=$2

if [ "$ENV" != "prod" ] && [ "$ENV" != "stag" ] && [ "$ENV" != "pre" ]; then
  usage
  log_error "ERROR: '$ENV' must be [ prod | stag | pre ]"
  exit 1
fi

#set deployment options
maxPercent=200
minPercent=100
desired_count=2
if [ "$ENV" == "stag" ]; then
  desired_count=1
  maxPercent=100
  minPercent=0
  tasks_list=$(ls $task_folder | grep -v front-proxy)
  for task in $tasks_list
  do
    aux_name_svc=$(echo ${task:3})
    name_svc=$(echo ${aux_name_svc%-td.*})
    aws --profile aws-project-$ENV ecs create-service --cluster project-$ENV \
    --service-name $name_svc-svc --task-definition $name_svc-td-$ENV --desired-count $desired_count \
    --deployment-configuration maximumPercent=$maxPercent,minimumHealthyPercent=$minPercent
    log_info "Create $name_svc service"
  done

  #Create front-proxy service and associate to loadBalancer
  aws --profile aws-project-$ENV ecs create-service --cluster project-$ENV \
  --service-name front-proxy-svc --task-definition front-proxy-td-$ENV \
  --desired-count $desired_count --load-balancers \
  loadBalancerName=front-proxy-$ENV,containerName=front-proxy,containerPort=80 --role ecsServiceRole \
  --deployment-configuration maximumPercent=$maxPercent,minimumHealthyPercent=$minPercent
  log_info "Create front-proxy service"
else
  if [ "$ENV" == "pre" ]; then
    maxPercent=150
    minPercent=50
  fi
  #Create-task-definitions
  port=8080
  tasks_list=$(ls $task_folder | grep -v front-proxy)
  for task in $tasks_list
  do
    aux_name_svc=$(echo ${task:3})
    name_svc=$(echo ${aux_name_svc%-td.*})
    tg_arn=$(aws --profile aws-project-$ENV elbv2 describe-target-groups --names tg-$name_svc-svc | jq '.TargetGroups[0].TargetGroupArn')
    aws --profile aws-project-$ENV ecs create-service --cluster project-$ENV \
    --service-name $name_svc-svc --task-definition $name_svc-td-$ENV --desired-count $desired_count \
    --load-balancers \
    targetGroupArn=$tg_arn,containerName=$name_svc,containerPort=$port --role ecsServiceRole \
    --deployment-configuration maximumPercent=$maxPercent,minimumHealthyPercent=$minPercent
    log_info "Create $name_svc service"
  done

  #Create front-proxy service and associate to loadBalancer
  aws --profile aws-project-$ENV ecs create-service --cluster project-$ENV \
  --service-name front-proxy-svc --task-definition front-proxy-td-$ENV \
  --desired-count $desired_count --load-balancers \
  loadBalancerName=front-proxy-$ENV,containerName=front-proxy,containerPort=80 --role ecsServiceRole \
  --deployment-configuration maximumPercent=$maxPercent,minimumHealthyPercent=$minPercent
  log_info "Create front-proxy service"
fi
