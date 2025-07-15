#!/bin/bash

# Input CSV files
AZURE_CSV="azure_ad_users.csv"
OCI_CSV="oci_iam_users.csv"
MERGED_CSV="merged_users.csv"

# Create output file with header
echo 'id,displayName,userPrincipalName,mail,source' > "$MERGED_CSV"

# Process Azure AD users
tail -n +2 "$AZURE_CSV" | awk -F',' 'BEGIN{OFS=","} {print $1,$2,$3,$4,"AzureAD"}' >> "$MERGED_CSV"

# Process OCI IAM users
tail -n +2 "$OCI_CSV" | awk -F',' 'BEGIN{OFS=","} {print $1,$2,"null",$3,"OCI"}' >> "$MERGED_CSV"

echo "Merged CSV created: $MERGED_CSV"

