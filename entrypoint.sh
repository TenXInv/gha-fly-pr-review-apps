#!/bin/sh -l

set -ex

if [ -n "$INPUT_PATH" ]; then
  # Allow user to change directories in which to run Fly commands.
  cd "$INPUT_PATH" || exit
fi

PR_NUMBER=$(jq -r .number /github/workflow/event.json)
if [ -z "$PR_NUMBER" ]; then
  echo "This action only supports pull_request actions."
  exit 1
fi

GITHUB_REPOSITORY_NAME=${GITHUB_REPOSITORY#"$GITHUB_REPOSITORY_OWNER"/}
EVENT_TYPE=$(jq -r .action /github/workflow/event.json)

# Default the Fly app name to pr-{number}-{repo_owner}-{repo_name}
app="${INPUT_NAME:-pr-$PR_NUMBER-$GITHUB_REPOSITORY_OWNER-$GITHUB_REPOSITORY_NAME}"
# Change underscores to hyphens.
app=$(echo "$app" | sed 's/_/-/g')
region="${INPUT_REGION:-${FLY_REGION:-iad}}"
org="${INPUT_ORG:-${FLY_ORG:-personal}}"
config="${INPUT_CONFIG:-fly.toml}"
image_arg=""
build_args=""
build_secrets=""

if ! echo "$app" | grep "$PR_NUMBER"; then
  echo "For safety, this action requires the app's name to contain the PR number."
  exit 1
fi

# PR was closed - remove the Fly app if one exists and exit.
if [ "$EVENT_TYPE" = "closed" ]; then
  flyctl apps destroy "$app" -y || true
  exit 0
fi

if [ -n "$INPUT_BUILD_ARGS" ]; then
  for ARG in $(echo "$INPUT_BUILD_ARGS" | tr " " "\n"); do
    build_args="$build_args --build-arg ${ARG}"
  done
fi

if [ -n "$INPUT_BUILD_SECRETS" ]; then
  for ARG in $(echo "$INPUT_BUILD_SECRETS" | tr " " "\n"); do
    build_secrets="$build_secrets --build-secret ${ARG}"
  done
fi

if [ -n "$INPUT_IMAGE" ]; then
  image_arg="--image $INPUT_IMAGE"
fi

# Deploy the Fly app, creating it first if needed.
if ! flyctl status --app "$app"; then
  # Backup the original config file since 'flyctl launch' messes up the [build.args] section
  cp "$config" "$config.bak"
  set -f
  # shellcheck disable=SC2086 # we want word splitting
  IFS=' ' flyctl launch --no-deploy --config "$config" --copy-config --name "$app" $image_arg --region "$region" --org "$org" ${build_args} ${build_secrets} $INPUT_LAUNCH_OPTIONS
  set +f
  # Restore the original config file
  cp "$config.bak" "$config"
fi

if [ -n "$INPUT_SECRETS" ]; then
  echo "$INPUT_SECRETS" | tr " " "\n" | flyctl secrets import --app "$app"
fi

# Attach postgres cluster to the app if specified.
if [ -n "$INPUT_POSTGRES" ]; then
  flyctl postgres attach "$INPUT_POSTGRES" --app "$app" || true
fi

# Trigger the deploy of the new version.
echo "Contents of config $config file: " && cat "$config"
set -f
if [ -n "$INPUT_VMSIZE" ]; then
  # shellcheck disable=SC2086 # we want word splitting
  IFS=' ' flyctl deploy --config "$config" --app "$app" --regions "$region" $image_arg --strategy immediate --ha="$INPUT_HA" ${build_args} ${build_secrets} --vm-size "$INPUT_VMSIZE"
else
  # shellcheck disable=SC2086 # we want word splitting
  IFS=' ' flyctl deploy --config "$config" --app "$app" --regions "$region" $image_arg --strategy immediate --ha="$INPUT_HA" ${build_args} ${build_secrets} --vm-cpu-kind "$INPUT_CPUKIND" --vm-cpus "$INPUT_CPU" --vm-memory "$INPUT_MEMORY"
fi
set +f

# Make some info available to the GitHub workflow.
flyctl status --app "$app" --json >status.json
hostname=$(jq -r .Hostname status.json)
appid=$(jq -r .ID status.json)
{
  echo "hostname=$hostname"
  echo "url=https://$hostname"
  echo "id=$appid"
  echo "name=$app"
} >>"$GITHUB_OUTPUT"
