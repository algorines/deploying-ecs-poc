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
  log_info "usage: $0 <task_definitions_path> <environment> <version>"
  echo "  <task_definition_path>: /path/to/task/definitions"
  echo "  <environment>: [ prod | stag | pre ]"
  echo "  <version>: [ latest | stable ]"
}

copy_json_to_tmp() {
  #Copy json to temp directory
  mkdir -p /tmp/td
  for task in $tasks_list
  do
    cp $task_folder/$task /tmp/td
  done
}

set_td_env() {
  # Set environment on task definitions
  for task in $tasks_list
  do
    sed -i'.bk' 's/DEPLOYMENT_ENV/'$ENV'/g' /tmp/td/$task
  done
}

set_version_dockerhub() {
  for task in $tasks_list
  do
    sed -i'.bk' 's/VERSION/'$VERSION'/g' /tmp/td/$task
  done
}

if [ "$#" -ne 3 ]; then
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

VERSION=$3

if [ "$VERSION" != "latest" ] && [ "$VERSION" != "stable" ]; then
  usage
  log_error "ERROR: '$VERSION' must be [ latest | stable ]"
  exit 1
fi

tasks_list=$(ls $task_folder)

copy_json_to_tmp
set_td_env
set_version_dockerhub

#Create-task-definitions
for task in $tasks_list
do
  aws --profile aws-project-$ENV ecs register-task-definition --cli-input-json file:///tmp/td/$task
  log_info "Create $task"
done
