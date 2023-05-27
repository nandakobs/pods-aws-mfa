#!/bin/bash

source ~/.bashrc

check_script_setup() {
  if [[ ! -x ${0} ]]; then
    chmod +x "${0}"
  fi

  script_name=$(basename "${0}")
  link_path="/usr/bin/${script_name%.*}"
  script_path=$(readlink -f "${0}")

  if [[ ! -L "${link_path}" ]] || [[ ! -e "${link_path}" ]]; then
    sudo ln -sf "${script_path}" "${link_path}"
  else
    type=$(file -b "${link_path}")

    if [[ "${type}" != "symbolic link to ${script_path}" ]]; then
      sudo ln -sf "${script_path}" "${link_path}"
    fi
  fi

  if ! command -v jq &>/dev/null; then
    echo "Dependency jq is not installed. Installing..."
    apt-get update && apt-get install -y jq
    echo "Dependency jq has been installed."
  fi
}

remove_script_setup() {
  sed -i '/^#Pods aliases$/d' ~/.bash_aliases
  sed -i '/^alias podsprd=.*/d' ~/.bash_aliases
  sed -i '/^alias podsqa=.*/d' ~/.bash_aliases
  sed -i '/^alias podsdev=.*/d' ~/.bash_aliases
  sed -i '/^export aws_arn=.*/d' ~/.bashrc
  sudo apt-get remove --auto-remove jq
  sudo rm /usr/bin/pods_mfa
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
  echo "$(echo -e "\n${alises_title}"; echo "${pods_prd}"; echo "${pods_qa}"; echo "${pods_dev}")" >> ~/.bash_aliases
  source ~/.bash_aliases
}

manage_aliases() {
  has_contexts=$1
  change_aliases=$2
  if [[ "${change_aliases}" = true ]]; then
    sed -i '/^#Pods aliases$/d' ~/.bash_aliases
    sed -i '/^alias podsprd=.*/d' ~/.bash_aliases
    sed -i '/^alias podsqa=.*/d' ~/.bash_aliases
    sed -i '/^alias podsdev=.*/d' ~/.bash_aliases
    write_aliases "${has_contexts}"
  else
    if [[ ! -f ~/.bash_aliases ]]; then
      touch ~/.bash_aliases
      write_aliases "${has_contexts}"
    else
      if ! grep -q "#Pods aliases" ~/.bash_aliases; then
        write_aliases "${has_contexts}"
      fi
    fi
  fi
}

verify_arn() {
  # Extract and saves your aws_arn if it's not already set
  if ! grep -q "export aws_arn=" ~/.bashrc; then
    output=$(aws iam get-role --role-name developer 2>&1)

    if [[ $output == *"An error occurred"* ]]; then
      regex="arn:aws:iam::\d+:(mfa|user)/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"
      ARN=$(echo "${output}" | grep -o -P "${regex}")

      if [[ ${ARN} == *"user"* ]]; then
        ARN=$(echo "${ARN}" | sed 's/user/mfa/')
      fi
    else
      ARN=$(echo "${output}" | jq -r '.Role.Arn')
    fi

    if [[ -n "${ARN}" ]]; then
      echo "export aws_arn=\"${ARN}\"" >>~/.bashrc
      source ~/.bashrc
    fi
  fi
}

get_new_token() {
  read -r -p "Insert your MFA code: " mfa_code

  number_of_tries=0
  while [[ $number_of_tries -lt 2 ]]; do

    json_output=$(aws sts get-session-token --serial-number "${aws_arn}" --token-code "${mfa_code}")

    echo "${json_output}"

    if jq -e '.Credentials | has("SessionToken")' <<<"${json_output}" >/dev/null; then

      access_key=$(echo "$json_output" | jq -r '.Credentials.AccessKeyId')
      secret_key=$(echo "$json_output" | jq -r '.Credentials.SecretAccessKey')
      session_token=$(echo "$json_output" | jq -r '.Credentials.SessionToken')

      aws configure --profile "mfa" set aws_access_key_id "${access_key}"
      aws configure --profile "mfa" set aws_secret_access_key "${secret_key}"
      aws configure --profile "mfa" set aws_session_token "${session_token}"

      break

    fi

    number_of_tries=$((number_of_tries + 1))
    echo "Something went wrong..."
    read -r -p "Insert your MFA code: " mfa_code
  done

}

check_token() {
  output=$(aws --profile "mfa" sts get-caller-identity 2>&1)

  if [[ "$output" == *"An error occurred (ExpiredToken) when calling the GetCallerIdentity operation"* ]]; then
    echo "AWS Session Token has expired."
    get_new_token
  fi
}

if [[ "$1" == "--check" ]]; then
  check_token
elif [[ "$1" == "--update" ]]; then
  get_new_token
elif [[ "$1" == "--change-aliases" ]]; then
  read -r -p "Will the new aliases have different contexts? [yes/no] " user_input
  has_contexts=$(echo "${user_input}" | xargs)
  case "${has_contexts}" in
  [Yy]* | [Yy][Ee][Ss]*)
    has_contexts=true
    ;;
  *)
    has_contexts=false
    ;;
  esac
  manage_aliases "${has_contexts}" true
  echo "Aliases updated!"
elif [[ "$1" == "--install" ]]; then
  check_script_setup
  echo "The script is ready to work! Please run 'pods_mfa --configure' OR 'pods_mfa --configure-with-contexts' so you can start using it."
elif [[ "$1" == "--configure" ]]; then
  manage_aliases false
  verify_arn
  echo "It's all set up! Access your pods by running 'podsdev', 'podsqa' or 'podsprd'."
elif [[ "$1" == "--configure-with-contexts" || "$1" == "-cwc" ]]; then
  manage_aliases true
  verify_arn
  echo "It's all set up! Access your pods by running 'podsdev', 'podsqa' or 'podsprd'."
elif [[ "$1" == "--configure-for-kubectl" || "$1" == "-cfk" ]]; then
  verify_arn
  echo "It's all set up! You can check if your credentials have expired with 'pods_mfa --check' or run 'pods_mfa --update' to update it directly."
elif [[ "$1" == "--uninstall" ]]; then
  remove_script_setup
fi
