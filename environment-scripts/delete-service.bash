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

#Create-task-definitions
tasks_list=$(ls $task_folder)
for task in $tasks_list
do

  aux_name_svc=$(echo ${task:3})
  name_svc=$(echo ${aux_name_svc%-td.*})
  aws --profile aws-project-$ENV ecs update-service --cluster project-$ENV --service $name_svc-svc --desired-count 0
  aws --profile aws-project-$ENV ecs delete-service --cluster project-$ENV --service $name_svc-svc
  log_info "Delete $name_svc service"
done
