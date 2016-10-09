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
  echo "usage: $0 <task_definitions_path> <environment>"
  echo "  <task_definition_path>: /path/to/task/definitions"
  echo "  <environment>: [ prod | stag | pre ]"
}

if [ "$#" -ne 2 ]; then
  usage
  log_error "ERROR Arguments number"
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
if [ "$ENV" != "stag" ]; then
  #Delete Load Balancers
  cd $task_folder/..
  bash delete-ALBs.bash $task_folder $ENV
  #Delete ECS Services
  bash delete-service-v2.bash $task_folder $ENV
fi

#Delete-stack
aws --profile aws-project-$ENV cloudformation delete-stack --stack-name ecs-project-$ENV
sleep 5
status=$(aws --profile aws-project-$ENV cloudformation describe-stacks --stack-name ecs-project-$ENV | jq '.Stacks[0].StackStatus' | sed -e 's/^"//' -e 's/"$//')

echo -ne "Wating for environment down"
while [[ $status == "DELETE_IN_PROGRESS" ]]
  do
    sleep 5
    echo -ne "."
    status=$(aws --profile aws-project-$ENV cloudformation describe-stacks --stack-name ecs-project-$ENV | jq '.Stacks[0].StackStatus' | sed -e 's/^"//' -e 's/"$//')
  done
if [[ -z $status ]]; then
  log_info "Delete_completed"
else
  log_error "Delete Failed $status"
fi
