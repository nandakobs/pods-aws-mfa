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

verify_aliases() {
  if [[ ! -f "$HOME/.bash_aliases" ]]; then
    touch "$HOME/.bash_aliases"
  fi

  if grep -q "#Pods aliases" "$HOME/.bash_aliases"; then
     remove_aliases
  fi
}

#######################################
# write_aliases:
#   Writes specific aliases to the ~/.bash_aliases file.
#   Inputs:
#     has_contexts - If true, asks for user input on context for production, QA, and development.
#   Side effects:
#     Modifies the ~/.bash_aliases file.
#######################################
write_aliases() {
  local has_contexts="$1"

  if [[ "${has_contexts}" == true ]]; then

    while true; do
      local continue
      local input
      local correct
      local contexts=()

      for env_context in production qa development; do
        local context
        read -rp "Enter context for ${env_context}: " input
        context="$(echo "${input}" | xargs)"
        contexts+=("${context}")
      done

      echo -e "\nInformed Contexts\n   PRD: ${contexts[0]}\n   QA: ${contexts[1]}\n   DEV: ${contexts[2]}"
      echo -ne "${ARROW} "
      read -rp "Please confirm, are the contexts correct? [yes/no] " correct
      continue="$(is_input_positive "${correct}")"

      if [[ "${continue}" == true ]]; then
        break
      fi

      echo " "
    done

    local prd_context="kubectl config use-context ${contexts[0]} >/dev/null 2>&1 &&"
    local qa_context="kubectl config use-context ${contexts[1]} >/dev/null 2>&1 &&"
    local dev_context="kubectl config use-context ${contexts[2]} >/dev/null 2>&1 &&"
  else
    local prd_context=""; local qa_context=""; local dev_context="";
  fi

  local alises_title="#Pods aliases"
  local pods_prd="alias podsprd='pods_mfa -ck && ${prd_context} k9s -n production'"
  local pods_qa="alias podsqa='pods_mfa -ck && ${qa_context} k9s -n qa'"
  local pods_dev="alias podsdev='pods_mfa -ck && ${dev_context} k9s -n development'"
  echo "$(echo -e "\n${alises_title}"; echo "${pods_prd}"; echo "${pods_qa}"; echo "${pods_dev}")" >> "$HOME/.bash_aliases"
  source "$HOME/.bash_aliases"
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
      echo "Is everything okay? Set your USER_ARN manually with 'pods_mfa --set-arn'"
      exit 1
    fi

  fi
}

set_arn() {
  local user_arn

  read -rp "Inform your user ARN: " user_arn

  while ! [[ "${user_arn}" =~ arn:aws:iam::[^[:space:]]* ]]; do
    err "INVALID_USER_ARN\n"
    read -rp "Insert a valid user ARN: " user_arn
  done

  echo "export AWS_ARN=\"${user_arn}\"" >> "$HOME/.bashrc"
  source "$HOME/.bashrc"
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
  local response_expected="$1"

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

      if [[ "${response_expected}" == true ]]; then
        echo -e "AWS Session Token ${GC}updated successfully${CE}."
      fi

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
  else
    local response_expected="$1"

    if [[ "${response_expected}" == true ]]; then
      echo -e "\nAWS Session Token is ${GC}currently active${CE}."
    fi

  fi
}

show_user_info() {
  local arn_line
  local user_arn

  echo -e "\npods_aws_mfa/${OC}user_arn${CE}\n"

  if grep -q "export AWS_ARN" "$HOME/.bashrc"; then
    arn_line="$(awk "/^export AWS_ARN/" "$HOME/.bashrc")"
    user_arn="$(echo "${arn_line}" | grep -o '"[^"]*"')"
    echo "    ${user_arn//\"/}"
  else
    echo -e "${YC}WARNING:${CE} User ARN is not set."
    echo -e "Please configure it by running 'pods_mfa --configure' OR 'pods_mfa --set-arn' to do it manually."
  fi

  echo -e "\npods_aws_mfa/${OC}aliases${CE}/\n"

  if grep -q "#Pods aliases" "$HOME/.bash_aliases"; then
    local aliases_values=()

    for alias in podsprd podsqa podsdev; do
       local alias_line
       local alias_value

       alias_line="$(awk "/^alias ${alias}/" "$HOME/.bash_aliases")"
       alias_value="$(echo "${alias_line}" | grep -o "'[^']*'")"
       local alias_without_quotes="${alias_value//\'/}"
       aliases_values+=("${alias_without_quotes}")
    done

    local array_item=0

    for alias in podsprd podsqa podsdev; do
      echo -e "   ${OC}${alias}${CE}: ${aliases_values[${array_item}]}\n\n"
      ((array_item++))
    done

    echo -e "   ${ARROW} If you wish to change/remove the contexts run 'pods_mfa --change-aliases',"
    echo "      or edit the aliases manually in the ~/.bash_aliases file."
  else
    echo -e "Pods aliases were not found.\n${ARROW} If you wish to use it run 'pods_mfa --configure'"
  fi
}

case "$1" in
  -ck) check_token ;;
  --check) check_token true ;;
  --update) get_new_token true ;;
  --set-arn) set_arn ;;
  --show) show_user_info ;;
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
