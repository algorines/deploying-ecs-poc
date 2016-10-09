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
  log_info "usage: $0 <task_definitions_path> <environment> <version> <ecs_path> <create_tasks?> <create_serivces?>"
  echo "  <task_definition_path>: /path/to/task/definitions"
  echo "  <environment>: [ prod | stag | pre ]"
  echo "  <version>: [ latest | stable ]"
  echo "  <ecs_path>: /path/to/ecs/config"
  echo "  <create_tasks?>: write true/false"
  echo "  <create_services?>: write true/false to create"
}

STARTTIME=$(date +%s)

if [ "$#" -ne 6 ]; then
  usage
  log_error "ERROR Arguments number"
  exit 1
fi

task_folder=$1

if [ ! -d "$task_folder" ]; then
  usage
  log_error "ERROR: '$task_folder' does falset exist or is falset a directory"
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

VERSION=$3

if [ "$VERSION" != "latest" ] && [ "$VERSION" != "stable" ]; then
  usage
  log_error "ERROR: '$VERSION' must be [ latest | stable ]"
  exit 1
fi

ecs_path=$4

if [ ! -d "$ecs_path" ]; then
  usage
  log_error "ERROR: '$ecs_path' does falset exist or is falset a directory"
  exit 1
fi

if [[ ! $ecs_path = /* ]]; then
  usage
  log_error "ERROR: '$ecs_path' must be an absolute path"
  exit 1
fi

create_tasks=$5

if [ "$create_tasks" != "true" ] && [ "$create_tasks" != "false" ]; then
  usage
  log_error "ERROR: '$ENV' must be [ true | false ]"
  exit 1
fi

create_services=$6

if [ "$create_services" != "true" ] && [ "$create_services" != "false" ]; then
  usage
  log_error "ERROR: '$ENV' must be [ true | false ]"
  exit 1
fi

if [ $ENV == "stag" ]; then
  deploy_template="deploy-compose.json"
elif [ $ENV == "pre" ]; then
  deploy_template="deploy-ecs-pre.json"
else
  deploy_template="deploy-ecs.json"
fi

#copy files to tmp
cp $ecs_path/ecs.config /tmp/
cp $ecs_path/config.json /tmp/
cp $ecs_path/parameters-$ENV.json /tmp/
cp $ecs_path/$deploy_template /tmp/

#Set envrinment on ecs.config
sed -i'.bk' 's/DEPLOYMENT_ENV/'$ENV'/' /tmp/ecs.config
sed -i'.bk' 's/DEPLOYMENT_ENV/'$ENV'/' /tmp/parameters-$ENV.json
sed -i'.bk' 's/DEPLOYMENT_ENV/'$ENV'/' /tmp/$deploy_template

#Upload to S3
aws --profile aws-project-$ENV s3 cp /tmp/ecs.config s3://project-docker-conf-$ENV/ecs.config
aws --profile aws-project-$ENV s3 cp /tmp/config.json s3://project-docker-conf-$ENV/config.json
aws --profile aws-project-$ENV s3 cp /tmp/$deploy_template s3://project-cf-templates-$ENV/$deploy_template

#waiting for upload files
sleep 5

#Create-stack
aws --profile aws-project-$ENV cloudformation create-stack \
--stack-name ecs-project-$ENV --template-url https://s3-eu-west-1.amazonaws.com/project-cf-templates-$ENV/$deploy_template \
--parameters file:///tmp/parameters-$ENV.json --capabilities CAPABILITY_IAM

#status
status=$(aws --profile aws-project-$ENV cloudformation describe-stacks --stack-name ecs-project-$ENV | jq '.Stacks[0].StackStatus' | sed -e 's/^"//' -e 's/"$//')

echo -ne "Wating for environment up"
while [ $status == "CREATE_IN_PROGRESS" ]
do
  sleep 5
  echo -ne "."
  status=$(aws --profile aws-project-$ENV cloudformation describe-stacks --stack-name ecs-project-$ENV | jq '.Stacks[0].StackStatus' | sed -e 's/^"//' -e 's/"$//')
done
if [ $status == "CREATE_COMPLETE" ]; then
  if [ $ENV != "stag" ]; then
    #Create Load Balancers
    cd $task_folder/..
    bash create-ALBs.bash $task_folder $ENV
    #Create services
    #Creating tasks and services
    if [ $create_tasks == "true" ]; then
      cd $task_folder/..
      bash create-task-definitions.bash $task_folder $ENV $VERSION
    fi

    if [ $create_services == "true" ]; then
      cd $task_folder/..
      bash create-service.bash $task_folder $ENV
    fi
  fi
  log_info "Creation completed"
  ENDTIME=$(date +%s)
  echo "It takes $[$ENDTIME - $STARTTIME] seconds to complete this task..."

else
  log_error "Created Failed"
fi
