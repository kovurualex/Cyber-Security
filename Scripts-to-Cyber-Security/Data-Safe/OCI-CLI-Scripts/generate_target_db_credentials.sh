#!/bin/bash

# This script prompts the user for a username and password and creates a JSON file
# named Credentials_Target_DBaaS.json with the provided credentials.
# The JSON file will be used for storing the target database's username and password credentials.

# Prompt the user for username and password
read -p "Enter Username: " username
read -s -p "Enter Password: " password
echo

# Create the JSON file with the credentials
cat > Credentials_Target_DBaaS.json <<EOF
{
  "password": "$password",
  "userName": "$username"
}
EOF

echo "Credentials saved to Credentials_Target_DBaaS.json"

