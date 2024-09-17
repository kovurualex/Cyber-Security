#!/bin/bash

# Script Name: generate_datasafe_private_endpoints.sh
# Description:
# This script automates the process of listing VCNs, Subnets, and Data Safe Private Endpoints within a specified OCI compartment.
# It then generates a CSV file with the details of each private endpoint, including the corresponding VCN and subnet names.
# Finally, it creates a JSON file for each private endpoint, used for defining connection options in Data Safe.

# Steps:
# 1. Prompt the user for the Compartment ID.
# 2. List all VCNs in the compartment and save them to a file (vcn_list.txt).
# 3. List all subnets in the compartment and save them to a file (subnet_list.txt).
# 4. List all Data Safe private endpoints and save them to a file (PE_list.txt).
# 5. Generate a CSV file (list_All_private_endpoints_details.csv) with details of each private endpoint, 
#    including VCN Name, Subnet Name, Private Endpoint Name, and their corresponding IDs.
# 6. Create a JSON file for each private endpoint for use in Data Safe connection options.

# Step 1: Ask for compartment ID and list all VCNs in the compartment
read -p "Enter Compartment ID: " compartment_id

echo "Listing all VCNs in the compartment..."
oci network vcn list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id] | @csv' > vcn_list.txt
echo "VCN list saved to vcn_list.txt"

# Step 2: List all subnets in the compartment and save to a file
echo "Listing all subnets in the compartment..."
oci network subnet list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"]] | @csv' > subnet_list.txt
echo "Subnet list saved to subnet_list.txt"

# Step 3: List existing private endpoints and save to a file
echo "Listing all Data Safe private endpoints..."
oci data-safe private-endpoint list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"], .["subnet-id"]] | @csv' > PE_list.txt
echo "Private endpoint list saved to PE_list.txt"

# Step 4: Append VCN Name and Subnet Name to PE_list.txt by generating list_All_private_endpoints_details.csv
echo "Generating list_All_private_endpoints_details.csv..."

echo '"Private-endpoint-Name, Private-endpoint-ID, VCN Name, VCN ID, Subnet Name, Subnet ID"' > list_All_private_endpoints_details.csv

# Create mappings for VCN IDs to VCN Names and Subnet IDs to Subnet Names
declare -A vcn_map
declare -A subnet_map

# Populate VCN mapping (VCN ID -> VCN Name)
while IFS=, read -r vcn_name vcn_id; do
  vcn_map["$vcn_id"]="$vcn_name"
done < vcn_list.txt

# Populate Subnet mapping (Subnet ID -> Subnet Name)
while IFS=, read -r subnet_name subnet_id vcn_id; do
  subnet_map["$subnet_id"]="$subnet_name"
done < subnet_list.txt

# Read through PE_list.txt and append corresponding VCN and Subnet names
while IFS=, read -r pe_name pe_id vcn_id subnet_id; do
  vcn_name="${vcn_map[$vcn_id]}"  # Get VCN name from the associative array
  subnet_name="${subnet_map[$subnet_id]}"  # Get Subnet name from the associative array
  echo "$pe_name, $pe_id, $vcn_name, $vcn_id, $subnet_name, $subnet_id" >> list_All_private_endpoints_details.csv
done < PE_list.txt

echo "CSV file generated: list_All_private_endpoints_details.csv"

# Step 5: Generate a JSON file for each Private Endpoint, skipping the header and cleaning up PE name and PE ID
echo "Generating JSON files for each private endpoint..."

# Skip the first line (header) by using `tail -n +2` to start reading from the second line
tail -n +2 list_All_private_endpoints_details.csv | while IFS=, read -r pe_name pe_id vcn_name vcn_id subnet_name subnet_id; do
  # Remove double quotes and spaces from the private endpoint name
  pe_name=$(echo "$pe_name" | tr -d '"' | tr ' ' '_')
  
  # Remove double quotes and trim leading/trailing spaces from the private endpoint ID
  pe_id=$(echo "$pe_id" | tr -d '"' | xargs)

  json_file="connection-option_${pe_name}.json"
  echo "{
    \"connectionType\": \"PRIVATE_ENDPOINT\",
    \"datasafePrivateEndpointId\": \"$pe_id\"
  }" > "$json_file"
  echo "Generated: $json_file"
done

echo "JSON file generation completed."

