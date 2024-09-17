#!/bin/bash

# Script Purpose:
# This shell script is designed to interact with Oracle Cloud Infrastructure (OCI) to retrieve
# and process Data Safe target database information based on their types (AUTONOMOUS_DATABASE,
# DATABASE_CLOUD_SERVICE, and INSTALLED_DATABASE). 
# 
# The script performs the following tasks:
# 1. Prompts the user to input a "compartment ID" where the databases reside.
# 2. Lists all the Data Safe target databases in the specified compartment and filters them based on their database type.
# 3. For each type of database, the script retrieves specific details using OCI CLI and processes the data:
#    - AUTONOMOUS_DATABASE: Retrieves details such as display name, autonomous database ID, infrastructure type, etc.
#    - DATABASE_CLOUD_SERVICE: Retrieves details like DB system ID, VM cluster ID (handles null values), listener port, and more.
#    - INSTALLED_DATABASE: Retrieves details like instance ID, IP addresses, service name, etc.
# 4. Generates separate output files for each type of database containing the retrieved details.
# 5. Cleans up temporary files and finalizes the output.


# Step 1: Prompt for compartment-id
read -p "Enter the compartment ID: " compartment_id

# Step 2: List the data-safe target-database and save it to a file
oci data-safe target-database list --compartment-id $compartment_id --lifecycle-state ACTIVE --all | \
jq -r '.data[] | [.["database-type"], .["display-name"], .["id"], .["infrastructure-type"], .["lifecycle-state"]] | @csv' > Datasafe_target_list.txt

# Step 3: Process AUTONOMOUS_DATABASE entries
while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state
do
  if [[ "$db_type" == "\"AUTONOMOUS_DATABASE\"" ]]; then
    oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"') | \
    jq -r '[
      .data["database-details"]."database-type",
      .data["display-name"],
      .data["database-details"]."autonomous-database-id",
      .data["database-details"]."infrastructure-type",
      .data["id"],
      .data["lifecycle-state"]
    ] | @csv' >> output1.txt
  fi
done < Datasafe_target_list.txt

# Step 4: Process DATABASE_CLOUD_SERVICE entries
while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state
do
  if [[ "$db_type" == "\"DATABASE_CLOUD_SERVICE\"" ]]; then
    oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"') | \
    jq -r '.data | [
      .["database-details"]["database-type"],
      .["display-name"],
      (.["database-details"]["db-system-id"] // "null"),
      .["database-details"]["infrastructure-type"],
      .["database-details"]["listener-port"],
      .["database-details"]["service-name"],
      .id,
      (.["database-details"]["vm-cluster-id"] // "null"),
      .["lifecycle-state"]
    ] | @csv' >> output2.txt
  fi
done < Datasafe_target_list.txt

# Step 5: Process INSTALLED_DATABASE entries
while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state
do
  if [[ "$db_type" == "\"INSTALLED_DATABASE\"" ]]; then
    oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"') | \
    jq -r '[
      .data["database-details"]["database-type"], 
      .data["display-name"], 
      .data["database-details"]["instance-id"], 
      .data["database-details"]["infrastructure-type"], 
      .data["database-details"]["listener-port"], 
      (.data["database-details"]["ip-addresses"] | join(", ")), 
      .data["database-details"]["service-name"]
    ] | @csv' >> output3.txt
  fi
done < Datasafe_target_list.txt

# Step 6: Copy and clean up output files
cp output1.txt Data_Safe_Autonomous_DBs_Details.txt
rm output1.txt

cp output2.txt Data_Safe_Cloud_DBs_Details.txt
rm output2.txt

cp output3.txt Data_Safe_Installed_DBs_Details.txt
rm output3.txt

echo "Processing completed. Output files generated."

