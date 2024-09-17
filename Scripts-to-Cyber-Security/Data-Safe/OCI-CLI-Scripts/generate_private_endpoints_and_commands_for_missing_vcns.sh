#!/bin/bash

#Script Name: generate_private_endpoints_and_commands_for_missing_vcns.sh 
# 
# Description: 
# This script identifies VCNs in a specified OCI compartment that do not have Data Safe private endpoints. 
# It generates: 
# 1. A CSV file ("list_vcns_without_private_endpoints.csv") listing missing VCNs and their subnets. 
# 2. A shell script ("create_private_endpoints_commands.sh") with OCI CLI commands to create private endpoints. 
# 
# Steps: 
# 1. Prompts for a compartment OCID. 
# 2. Lists existing private endpoints and identifies VCNs without them. 
# 3. Lists all VCNs and subnets. 
# 4. Outputs missing VCNs to CSV and generates corresponding CLI commands. 
#
# Output: 
# - CSV: VCNs without private endpoints. 
# - Shell script: CLI commands to create Data Safe private endpoints. 
#
# Usage:
# Run the script in a bash shell. Ensure OCI CLI is configured and you have appropriate permissions.
#
# Prompt user for the compartment ID
read -p "Enter the Compartment OCID: " compartment_id

# Step 1: List existing private endpoints and save them to a file
oci data-safe private-endpoint list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"], .["subnet-id"]] | @csv' > Datasafe_Private-Endpoint_List.txt

# Corrected step to extract unique VCN IDs from the private endpoints list
awk -F ',' '{print $3}' Datasafe_Private-Endpoint_List.txt | tr -d '"' | sort | uniq > vcn_ids_with_pe.txt

# Step 2: List all VCNs in the compartment and save them to a file
oci network vcn list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id] | @csv' > vcn_list.txt

# Step 3: List all subnets in the compartment and save them to a file
oci network subnet list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"]] | @csv' > subnet_list.txt

# Initialize the output files
echo "VCN Name, VCN ID, Subnet Name, Subnet ID" > list_vcns_without_private_endpoints.csv
echo "# OCI CLI Commands to Create Data Safe Private Endpoints" > create_private_endpoints_commands.sh

# Loop through each VCN and check if it has a private endpoint
while IFS=, read -r vcn_name vcn_id; do
    # Remove double quotes from VCN name and ID
    vcn_name=$(echo $vcn_name | tr -d '"')
    vcn_id=$(echo $vcn_id | tr -d '"')

    # Check if this VCN ID is in the list of VCNs with private endpoints
    if ! grep -q $vcn_id vcn_ids_with_pe.txt; then
        # No private endpoint found for this VCN, list its subnets
        while IFS=, read -r subnet_name subnet_id subnet_vcn_id; do
            # Remove double quotes from subnet details
            subnet_name=$(echo $subnet_name | tr -d '"')
            subnet_id=$(echo $subnet_id | tr -d '"')
            subnet_vcn_id=$(echo $subnet_vcn_id | tr -d '"')

            if [[ "$subnet_vcn_id" == "$vcn_id" ]]; then
                # Write VCN and subnet details to the output file
                echo "\"$vcn_name\", \"$vcn_id\", \"$subnet_name\", \"$subnet_id\"" >> list_vcns_without_private_endpoints.csv
                
                # Prepare the private endpoint display name as PE_$VCN_NAME
                pe_display_name="PE_$vcn_name"
                
                # Create the OCI CLI command for the private endpoint and append it to the commands file
                echo "oci data-safe private-endpoint create --compartment-id $compartment_id --display-name $pe_display_name --subnet-id $subnet_id --vcn-id $vcn_id" >> create_private_endpoints_commands.sh
            fi
        done < subnet_list.txt
    fi
done < vcn_list.txt

# Clean up temporary files
rm vcn_ids_with_pe.txt
rm vcn_list.txt
rm subnet_list.txt

echo "Script completed. Output files:"
echo "  - VCNs without private endpoints: list_vcns_without_private_endpoints.csv"
echo "  - OCI CLI commands: create_private_endpoints_commands.sh"

