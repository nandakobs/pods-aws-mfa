#!/bin/bash

source "$HOME/.bashrc"

#######################################
###      PODS_MFA UTILS [START]     ###

readonly GC="\033[1;38;5;83m" # Green Color
readonly OC="\033[1;38;5;208m" # Orange Color
readonly RC="\033[1;91m" # Red Color
readonly YC="\033[1;38;5;220m" # Yellow Color
readonly CE="\033[0m" # Color End
readonly ARROW="${OC}>${CE}"

check_dependency() {
  local dependency="$1"
  if ! command -v "${dependency}" &> /dev/null; then
      echo -ne "${YC}WARNING:${CE} ${dependency} is not installed on this machine. "
      echo "Please consider installing it to continue."
      exit 1
  fi
}

check_sudo() {
  local command="$1"

  if [[ $(id -u) -ne 0 ]]; then
    echo "This command requires sudo permission."
    echo "Please run 'sudo pods_mfa ${command}'"
    exit 1
  fi
}

echo_progress() {
  local message="$1"
  local time="$2"
  echo -n "${message} "

  for i in 208 202 166 58 64 70 82; do
      echo -ne "\033[1;38;5;${i}m>${CE}"
      sleep "${time}"
  done

  echo -ne "${GC}OK${CE}\n"
}

err() {
  echo -e "\n${RC}ERROR:${CE}$*" >&2
}

is_input_positive() {
  local input
  input="$(echo "$1" | xargs)"

  case "${input}" in
    [Yy]* | [Yy][Ee][Ss]*) echo true ;;
    [Nn]* | [Nn][Oo]*) echo false ;;
    *) echo "idk" ;;
  esac
}

remove_aliases() {
  sed -i '/^#Pods aliases$/d' "$HOME/.bash_aliases"
  sed -i '/^alias podsprd=.*/d' "$HOME/.bash_aliases"
  sed -i '/^alias podsqa=.*/d' "$HOME/.bash_aliases"
  sed -i '/^alias podsdev=.*/d' "$HOME/.bash_aliases"
  source "$HOME/.bash_aliases"
}

###      PODS_MFA UTILS [END]       ###
#######################################

#######################################
# check_script_setup:
#   Checks and sets up the necessary requirements for the script to work correctly.
#   Side effects:
#     Changes the script's permissions to executable.
#     Creates or updates a symbolic link to the script.
#######################################
check_script_setup() {
  local script_name
  local script_path
  local type

  if [[ ! -x "${0}" ]]; then
    echo_progress  "Making this script executable" 0.2
    chmod +x "${0}"
  fi

  script_name="$(basename "${0}")"
  local link_path="/usr/bin/${script_name%.*}"
  script_path="$(readlink -f "${0}")"

  if [[ ! -L "${link_path}" ]] || [[ ! -e "${link_path}" ]]; then
    echo_progress  "Linking important stuff" 0.2
    sudo ln -sf "${script_path}" "${link_path}"
  else
    type="$(file -b "${link_path}")"

    if [[ "${type}" != "symbolic link to ${script_path}" ]]; then
      echo_progress  "Adjusting some symbolic links" 0.2
      sudo ln -sf "${script_path}" "${link_path}"
    fi

  fi

  echo_progress  "Checking for dependencies" 0.2
  check_dependency "aws"
}

remove_script_setup() {
  remove_aliases
  sed -i "/^export AWS_ARN=.*/d" "$HOME/.bashrc"
  source "$HOME/.bashrc"
  sudo rm /usr/bin/pods_mfa
  echo_progress  "Removing pods_mfa" 0.5
}

write_aliases() {
  has_contexts=$1
  if [[ "${has_contexts}" = true ]]; then
    read -r -p "Enter context for production: " prd_input
    read -r -p "Enter context for qa: " qa_input
    read -r -p "Enter context for development: " dev_input

    prd=$(echo "${prd_input}" | xargs)
    qa=$(echo "${qa_input}" | xargs)
    dev=$(echo "${dev_input}" | xargs)

    prd_context="kubectl config use-context ${prd} >/dev/null 2>&1 &&"
    qa_context="kubectl config use-context ${qa} >/dev/null 2>&1 &&"
    dev_context="kubectl config use-context ${dev} >/dev/null 2>&1 &&"
  else
    prd_context=""
    qa_context=""
    dev_context=""
  fi

  alises_title="#Pods aliases"
  pods_prd="alias podsprd='pods_mfa --check && ${prd_context} k9s -n production'"
  pods_qa="alias podsqa='pods_mfa --check && ${qa_context} k9s -n qa'"
  pods_dev="alias podsdev='pods_mfa --check && ${dev_context} k9s -n development'"
  echo "$(echo -e "\n${alises_title}"; echo "${pods_prd}"; echo "${pods_qa}"; echo "${pods_dev}")" >> "$HOME/.bash_aliases"
  source "$HOME/.bash_aliases"
}

manage_aliases() {
  has_contexts=$1
  change_aliases=$2
  if [[ "${change_aliases}" = true ]]; then
    sed -i '/^#Pods aliases$/d' "$HOME/.bash_aliases"
    sed -i '/^alias podsprd=.*/d' "$HOME/.bash_aliases"
    sed -i '/^alias podsqa=.*/d' "$HOME/.bash_aliases"
    sed -i '/^alias podsdev=.*/d' "$HOME/.bash_aliases"
    write_aliases "${has_contexts}"
  else
    if [[ ! -f "$HOME/.bash_aliases" ]]; then
      touch "$HOME/.bash_aliases"
      write_aliases "${has_contexts}"
    else
      if ! grep -q "#Pods aliases" "$HOME/.bash_aliases"; then
        write_aliases "${has_contexts}"
      fi
    fi
  fi
}

#######################################
# verify_arn:
#   Verifies if the AWS_ARN is exported in "$HOME/.bashrc". If not, extracts the value and exports it.
#   Side effects:
#     Modifies the "$HOME/.bashrc" file to include the AWS_ARN export if it's not already present.
#   Related doc:
#     https://awscli.amazonaws.com/v2/documentation/api/latest/reference/iam/get-user.html
#     Note that the text output pattern is: "USER    PATH   ARN  USER_ID   CREATE_DATE"
#######################################
verify_arn() {
  local output
  local arn

  if ! grep -q "export AWS_ARN=" "$HOME/.bashrc"; then
    output="$(aws iam get-user --output text 2>&1)"
    arn="$(echo "${output}" | grep -o -P 'arn:aws:iam::[^[:space:]]*')"

    if [[ -z "${arn}" ]]; then

      if [[ "${arn}" == *":user/"* ]]; then
        arn="${arn/user/mfa}"
      fi

      echo "export AWS_ARN=\"${arn}\"" >> "$HOME/.bashrc"
      source "$HOME/.bashrc"
    else
      err "USER_ARN_NOT_FOUND\n"
      check_dependency "aws"
      echo "Please check your configuration in the aws-cli."
      exit 1
    fi

  fi
}

refresh_temp_file_expiration() {
  local actual_temp_file
  local new_temp_file
  local expiration_timestamp
  local timezone

  actual_temp_file="$(find /tmp -type f -name "pods_mfa.*" -print -quit 2>/dev/null)"

  if [[ -n "${actual_temp_file}" ]]; then
    rm -f /tmp/pods_mfa.*
  fi

  new_temp_file="$(mktemp pods_mfa.XXXXXX >/dev/null)"
  local expiration_datetime="$1"
  expiration_timestamp="$(date +%s -d "${expiration_datetime}")"
  timezone="$(date -d "${expiration_datetime}" +%:::z)"
  echo "$(echo "${expiration_timestamp}"; echo "${timezone}")" >> "${new_temp_file}"
}

#######################################
# get_new_token:
#   Asks for the MFA code and tries to get a new session token using it.
#   If successful, updates the AWS credentials with the new session token.
#   Inputs:
#     response_expected - if true, feedback will be provided to the user.
#   Side effects:
#     Modifies the AWS credentials with the new session token.
#     Stores the token expiration date and its timezone in a temporary file.
#   Related doc:
#     https://awscli.amazonaws.com/v2/documentation/api/latest/reference/sts/get-session-token.html
#     Note that the text output pattern is: "CREDENTIALS ACCESS_KEY  EXPIRATION  SECRET_KEY  SESSION_TOKEN"
#######################################
get_new_token() {

  while true; do
    local mfa_code
    local output
    local title
    local try_again
    local continue

    read -rp "Insert your MFA code: " mfa_code

    while ! [[ "${mfa_code}" =~ ^[0-9]{6}$ ]]; do
        err "INVALID_CODE\n"
        read -rp "Insert a valid MFA code: " mfa_code
    done

    output="$(aws sts get-session-token --serial-number "${AWS_ARN}" --token-code "${mfa_code}" --output text)"
    title="$(echo "${output}" | awk '{print $1}')"

    if [[ "${title}" == "CREDENTIALS"  ]]; then
      local access_key
      local secret_key
      local session_token
      local expiration_datetime

      access_key="$(echo "${output}" | awk '{print $2}')"
      secret_key="$(echo "${output}" | awk '{print $4}')"
      session_token="$(echo "${output}" | awk '{print $5}')"

      aws configure --profile "mfa" set aws_access_key_id "${access_key}"
      aws configure --profile "mfa" set aws_secret_access_key "${secret_key}"
      aws configure --profile "mfa" set aws_session_token "${session_token}"

      expiration_datetime="$(echo "${output}" | awk '{print $3}')"
      refresh_temp_file_expiration expiration_datetime

      break
    fi

    err "${output}"

    read -rp $'\e[1mDo you want to try again?\e[0m [yes/no] ' try_again
    continue="$(is_input_positive "${try_again}")"

    if [[ "${continue}" == false ]]; then
      break
    fi

  done
}

#######################################
# check_token:
#   Verify the expiration status of the current AWS session token by comparing the previously recorded
#   expiration time with the current timestamp, or alternatively, utilize an aws-cli command to perform the check.
#   Side effects:
#     If the AWS session token has expired, gets a new one.
#   Related doc:
#     https://awscli.amazonaws.com/v2/documentation/api/latest/reference/sts/get-caller-identity.html
#######################################
check_token() {
  local temp_file
  local expired_token

  temp_file="$(find /tmp -type f -name "pods_mfa.*" -print -quit 2>/dev/null)"

  if [[ -n "${temp_file}" ]]; then
    local expiration_time
    local timezone
    local current_time

    expiration_time="$(echo "${temp_file}" | awk '{print $1}')"
    timezone="$(echo "${temp_file}" | awk '{print $2}')"
    current_time="$(TZ="${timezone}" date +%s)"

    if (( current_time >= expiration_time )); then
      expired_token=true
    fi

  else
    local output

    output="$(aws --profile "mfa" sts get-caller-identity 2>&1)"

    if [[ "${output}" == *"(ExpiredToken)"* ]]; then
      expired_token=true
    fi

  fi

  if [[ "${expired_token}" == true ]]; then
    echo -e "AWS Session Token ${RC}has expired${CE}."
    get_new_token
  fi
}

case "$1" in
  --check) check_token ;;
  --update) get_new_token ;;
  --change-aliases)
    verify_aliases
    read -rp "Will the new aliases have different contexts? [yes/no] " user_input
    has_contexts="$(is_input_positive "${user_input}")"
    write_aliases "${has_contexts}"
    echo "${ARROW} Aliases updated!"
    ;;
  --install)
    check_sudo "--install" && check_script_setup
    echo -e "The script is ready to work!\nPlease run the command below so you can start using it."
    echo -e " ${ARROW} 'pods_mfa --configure'"
    ;;
  --configure)
    verify_arn
    read -rp "Do you use k9s? [yes/no] " user_input
    is_k9s_user="$(is_input_positive "${user_input}")"

    if [[ "${is_k9s_user}" == true ]]; then
      read -rp "Do you need to access different contexts to see your pods? [yes/no] " different
      has_contexts="$(is_input_positive "${different}")"
      verify_aliases && write_aliases "${has_contexts}"
      echo "It's all set up! Access your pods by running 'podsdev', 'podsqa' or 'podsprd'."
      check_dependency "k9s"
    else
      echo -n "It's all set up! You can check if your credentials have expired with 'pods_mfa --check'"
      echo "or run 'pods_mfa --update' to update it directly."
    fi

    check_dependency "kubectl"
    ;;
  --uninstall) check_sudo "--uninstall" && remove_script_setup ;;
  *)
    err "INVALID_ARGUMENT"
    ;;
esac
