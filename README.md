# Pods AWS MFA

Are you tired of the constant struggle of accessing your pods? Fed up with expired AWS credentials or the hassle of 
switching contexts every single time? This script gotcha!

The Pods AWS MFA script simplifies pod access in Kubernetes, eliminating the need to check out your AWS Session Token
and streamlining interactions. Ideal for k9s users and anyone using kubectl with AWS MFA fatigue.

## Prerequisites

To use this script, you need to have the following prerequisites installed and configured:

- AWS Credentials: The script requires AWS credentials to authenticate with the AWS API. Make sure you have already 
configured your AWS credentials by running the following command and providing your AWS Access Key ID, Secret Access Key,
default region, and output format:

  ```shell
  aws configure
  ```
  
- MFA Device: The script assumes that you have an MFA (Multi-Factor Authentication) device associated with your AWS account.
This is required to generate the temporary session tokens for AWS API access. Ensure that you have set up an MFA device 
for your AWS account before using the script.

- `kubectl`: The Kubernetes command-line tool. You can install it by following the instructions in the official Kubernetes
documentation for your operating system.

- `k9s`: A terminal-based UI for Kubernetes. You can install it by following the instructions provided in the official 
k9s documentation for your operating system.

## How to Use

- Download the `pods_mfa.sh` script from the repository.

- Open the terminal in the path the script is and run the following command:
   ```shell
   sudo bash ./pods_mfa.sh --install
   ```
  
Then run `pods_mfa --configure` to configure your info and then it's all set up! 

If you're a `k9s` user now you can access your pods by running `podsdev`, `podsqa` or `podsprd` without worrying about 
your AWS credential's expiration or having to change the contexts before accessing them.

If you only use `kubectl` you can check if your credentials have expired with `pods_mfa --check`, and if so, update it. 
Or run `pods_mfa --update` to update it directly.

## How it Works

When you run the first command `sudo bash ./pods_mfa.sh --install` the option `--install` will make the script 
executable and callable from anywhere.

The configuration will get such information as your personal ARN and your contexts ARN, so it can configure the aliases properly.

When you access your pods via the `podsdev`, `podsqa` or `podsprd` aliases it verifies the status of the aws credentials
by executing a simple command. 

If the credentials have expired, the script prompts the user to refresh them. Once authenticated, the script uses the 
`aws configure --profile` command to save the new temporary session token and stores the token expiration date and its 
timezone in a temporary file for the next check-up.

After that, a kubectl command will be used to change to the select context (if you've configured with contexts), and the
`k9s` UI will be displayed.

Besides the aliases, you can call the script using options to update your credentials directly or change the aliases'
configuration. See the section below for more details. 

## Options

The script supports the following options:

- `--help`: Show this script options.

- `--check`: Checks if the credentials have expired, if so, the script prompts the user to refresh them.

- `--update`: Update the credentials, even if the current Session Token is still valid.

- `--version`: Show script version.

- `--set-arn`: Manually set your ARN.

- `--show-aliases`: Show the configured aliases.

- `--change-aliases`: Change the value of the configured aliases.

- `--configure`: Extracts your ARN, checks external dependencies, and configures aliases if needed.

- `--install`: Makes the script executable and callable from anywhere. Requires sudo permission.

- `--uninstall`: Remove any change the script did in your machine. Requires sudo permission.

To use these options, simply include them when running the script. Here is an example:

  ```shell
  pods_mfa --change-aliases
  ```

## Compatibility

The Pods AWS MFA script is primarily developed and tested on Ubuntu. If you are using a different operating system, 
such as macOS or another Linux distribution, please note that you may need to make adjustments to the script to ensure 
compatibility. Feel free to modify the script according to your specific environment or contribute improvements to 
enhance compatibility with other platforms.

## Contributions

Contributions are welcome!

If you find any issues, have suggestions for improvements, or want to add new features, feel free to submit a pull request.

## License

The Pods AWS MFA script is licensed under the [MIT License](https://github.com/nandakobs/pods-aws-mfa/blob/main/LICENSE).
