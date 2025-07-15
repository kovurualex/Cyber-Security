#!/bin/bash

# Configurations
TENANT_ID="ef2bxxxxxxxxxxxxxx3e915e37c6f"
CLIENT_ID="a8601axxxxxxxxxxxxxxxxxxx78c924162"
CLIENT_SECRET="Bxxxxxxxxxxxxxab."
SCOPE="https://graph.microsoft.com/.default"
TOKEN_URL="https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token"
GRAPH_URL="https://graph.microsoft.com/v1.0/users"
CSV_FILE="azure_ad_users.csv"

# Step 1: Get Access Token
echo "Fetching Access Token..."
ACCESS_TOKEN=$(curl -s -X POST $TOKEN_URL \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=$CLIENT_ID" \
  -d "scope=$SCOPE" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "grant_type=client_credentials" | jq -r '.access_token')

if [[ "$ACCESS_TOKEN" == "null" || -z "$ACCESS_TOKEN" ]]; then
  echo "Failed to retrieve access token."
  exit 1
fi

# Step 2: Call Graph API to get users
echo "Calling Graph API for users list..."
RESPONSE=$(curl -s -X GET "$GRAPH_URL" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json")

# Step 3: Extract users
echo "Parsing users and converting to CSV..."
echo '"id","displayName","userPrincipalName","mail"' > "$CSV_FILE"
echo "$RESPONSE" | jq -r '.value[] | [.id, .displayName, .userPrincipalName, .mail] | @csv' >> "$CSV_FILE"

echo "Users list saved to: $CSV_FILE"

