#!/bin/bash

# Function to process a given region and retrieve information about databases
process_region() {
    local REGION_NAME=$1

    # Step 1: List compartments in the region and save the results
    echo "Listing compartments in region ${REGION_NAME}..."
    oci iam compartment list --all --compartment-id-in-subtree true --output json \
    --query 'data[*].{Name:"name", ID:"id"}' | jq -r --arg region "$REGION_NAME" \
    '.[] | "\($region),\(.Name),\(.ID)"' > "${REGION_NAME}_compartments.csv"
    
    # Step 2: Generate unique compartment IDs for different database types
    echo "Generating unique compartment IDs for databases..."
    
    # Cloud Databases
    echo "Listing unique compartments for Cloud Databases..."
    oci search resource structured-search --query-text "query database resources" --output json \
    | jq -r '.data.items[] | select(.["lifecycle-state"] == "AVAILABLE") | .["compartment-id"]' | sort -u \
    > "${REGION_NAME}_CloudDB_unique_compartment_ids.txt"

    # Autonomous Databases
    echo "Listing unique compartments for Autonomous Databases..."
    oci search resource structured-search --query-text "query AutonomousDatabase resources" --output json \
    | jq -r '.data.items[] | select(.["lifecycle-state"] == "AVAILABLE") | .["compartment-id"]' | sort -u \
    > "${REGION_NAME}_AutonomousDB_unique_compartment_ids.txt"

    # Data Safe Target Databases
    echo "Listing unique compartments for Data Safe Target Databases..."
    oci search resource structured-search --query-text "query DataSafeTargetDatabase resources" --output json \
    | jq -r '.data.items[] | select(.["lifecycle-state"] == "ACTIVE") | .["compartment-id"]' | sort -u \
    > "${REGION_NAME}_DataSafeDB_unique_compartment_ids.txt"

    # Step 3: Define output filenames based on the region
    CLOUD_DB_OUTPUT_FILE="${REGION_NAME}_Cloud_Databases.csv"
    AUTONOMOUS_DB_OUTPUT_FILE="${REGION_NAME}_Autonomous_Databases.csv"

    # Initialize the output files with headers
    echo "compartment-name,db-name,db-system-id,sid-prefix,id,pdb-name,vm-cluster-id,compartment-id,display-name,db-version" \
    > "$CLOUD_DB_OUTPUT_FILE"
    echo "Compartment Name,Display Name,DB Version,ID,Data Safe Status,Compartment ID" \
    > "$AUTONOMOUS_DB_OUTPUT_FILE"

    # Step 4: Process Cloud Database compartments
    echo "Processing Cloud Database compartments..."
    while IFS=',' read -r compartment_id; do
        compartment_name=$(grep "$compartment_id" "${REGION_NAME}_compartments.csv" | awk -F',' '{print $2}')
        if [[ -n "$compartment_name" ]]; then            
            echo "Listing cloud databases in compartment ${compartment_id}..."
            oci db database list --compartment-id "$compartment_id" | jq -r \
            '.data[] | [.["db-name"] // "null", .["db-system-id"] // "null", .["sid-prefix"] // "null", .["id"] // "null", .["pdb-name"] // "null", .["vm-cluster-id"] // "null"] | @tsv' | sed 's/\t/,/g' \
            > "${REGION_NAME}_CloudDB_Output1.txt"

            oci db db-home list --compartment-id "$compartment_id" | jq -r \
            '.data[] | "\(.["compartment-id"]),\(.["display-name"]),\(.["vm-cluster-id"]),\(.["db-system-id"]),\(.["db-version"]) " | gsub(" *, *"; ",")' \
            > "${REGION_NAME}_CloudDB_Output2.txt"

            if [[ -s ${REGION_NAME}_CloudDB_Output1.txt ]]; then
                echo "Combining Cloud Database information for region ${REGION_NAME}..."
                while IFS=',' read -r db_name db_system_id sid_prefix id pdb_name vm_cluster_id; do
                    matching_line=$(grep -E ",${db_system_id}," "${REGION_NAME}_CloudDB_Output2.txt" || grep -E ",${vm_cluster_id}," "${REGION_NAME}_CloudDB_Output2.txt")
                    if [[ -n "$matching_line" ]]; then
                        compartment_id=$(echo "$matching_line" | awk -F ',' '{print $1}')
                        display_name=$(echo "$matching_line" | awk -F ',' '{print $2}')
                        db_version=$(echo "$matching_line" | awk -F ',' '{print $5}')
                        echo "$compartment_name,$db_name,$db_system_id,$sid_prefix,$id,$pdb_name,$vm_cluster_id,$compartment_id,$display_name,$db_version" \
                        >> "$CLOUD_DB_OUTPUT_FILE"
                    else
                        echo "$compartment_name,$db_name,$db_system_id,$sid_prefix,$id,$pdb_name,$vm_cluster_id,$compartment_id,null,null" \
                        >> "$CLOUD_DB_OUTPUT_FILE"
                    fi
                done < "${REGION_NAME}_CloudDB_Output1.txt"
            else
                echo "No Cloud Databases found for compartment ${compartment_id}."
            fi
        fi
    done < "${REGION_NAME}_CloudDB_unique_compartment_ids.txt"

    # Step 5: Process Autonomous Database compartments
    echo "Processing Autonomous Database compartments..."
    while IFS=',' read -r compartment_id; do
        compartment_name=$(grep "$compartment_id" "${REGION_NAME}_compartments.csv" | awk -F',' '{print $2}')
        if [[ -n "$compartment_name" ]]; then
            oci db autonomous-database list --compartment-id "$compartment_id" --query 'data[*].{"Display Name": "display-name", "DB Version": "db-version", "ID": "id", "Data Safe Status": "data-safe-status", "Compartment ID": "compartment-id"}' --output json \
            | jq -r --arg compartment_name "$compartment_name" '.[] | [$compartment_name, .["Display Name"], .["DB Version"], .["ID"], .["Data Safe Status"], .["Compartment ID"]] | @csv' \
            >> "$AUTONOMOUS_DB_OUTPUT_FILE"
        else
            echo "No matching compartment found for ID ${compartment_id} in region ${REGION_NAME}."
        fi
    done < "${REGION_NAME}_AutonomousDB_unique_compartment_ids.txt"
    
    # Step 6: Process Data Safe Target Database compartments
    echo "Processing Data Safe Target Databases..."
    while IFS=',' read -r compartment_id; do
        compartment_name=$(grep "$compartment_id" "${REGION_NAME}_compartments.csv" | awk -F',' '{print $2}')
        if [[ -n "$compartment_name" ]]; then
            oci data-safe target-database list --compartment-id "$compartment_id" --lifecycle-state ACTIVE --all | \
            jq -r '.data[] | [.["database-type"], .["display-name"], .["id"], .["infrastructure-type"], .["lifecycle-state"]] | @csv' \
            > "${REGION_NAME}_DataSafe_Target_List.txt"

            # Process different database types
            process_data_safe_dbs "$compartment_name" "$REGION_NAME"
        else
            echo "No matching compartment found for ID ${compartment_id} in region ${REGION_NAME}."
        fi
    done < "${REGION_NAME}_DataSafeDB_unique_compartment_ids.txt"
}

# Function to process Data Safe databases
process_data_safe_dbs() {
    local compartment_name=$1
    local region_name=$2

    # Process Autonomous Databases
    while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state; do
        if [[ "$db_type" == "\"AUTONOMOUS_DATABASE\"" ]]; then
            oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"') | \
    jq -r '[
      .data["database-details"]."database-type",
      .data["display-name"],
      .data["database-details"]."autonomous-database-id",
      .data["database-details"]."infrastructure-type",
      .data["id"],
      .data["lifecycle-state"]
    ] | @csv'  >> "${region_name}_DataSafe_Autonomous_DBs.csv"
        fi
    done < "${region_name}_DataSafe_Target_List.txt"

    # Process Cloud Databases Service 
    while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state; do
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
    ] | @csv' >> "${region_name}_DataSafe_Cloud_DBs.csv"
        fi
    done < "${region_name}_DataSafe_Target_List.txt"

    # Process Installed Databases
    while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state; do
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
    ] | @csv' >> "${region_name}_DataSafe_Installed_DBs.csv"
        fi
    done < "${region_name}_DataSafe_Target_List.txt"
}

# Main script logic
# Display the current region value
echo "Current region: $OCI_REGION"

# Prompt user to choose between the current region (OCI_REGION) or all regions (ALL)
echo "Do you want to process the current region only or all regions? (Enter '${OCI_REGION}' for current region or 'ALL' for all regions):"
read REGION_CHOICE

if [[ "$REGION_CHOICE" == "ALL" ]]; then
    echo "Processing all regions..."

    # Step 1: List all regions and save to region_subscriptions.csv
    echo "Listing all regions..."
    oci iam region-subscription list --output json | jq -r '.data[] | "\(.["is-home-region"]),\(.["region-key"]),\(.["region-name"]),\(.status)"' > region_subscriptions.csv

    # Process each region from region_subscriptions.csv
    while IFS=',' read -r is_home_region region_key region_name status; do
        echo "Switching to region ${region_name}..."
        export OCI_CONFIG_PROFILE="${region_name}"
        export PS1="\u@cloudshell:\W (${region_name})$"
        export OCI_REGION="${region_name}"
        export OCI_CLI_PROFILE="${region_name}"

        # Proceed to list compartments and databases for this region
        process_region "${region_name}"

    done < region_subscriptions.csv

elif [[ "$REGION_CHOICE" == "$OCI_REGION" ]]; then
    # Process current region without changing environment variables
    echo "Processing the current region ${OCI_REGION}..."
    process_region "${OCI_REGION}"

else
    echo "Invalid choice. Please enter '${OCI_REGION}' or 'ALL'."
    exit 1
fi

# Add headers to the required files at the beginning if they don't already exist
# Append headers only if the file is empty or doesn't already have the correct header

# region_subscriptions.csv
if ! grep -q "^is-home-region,region-key,region-name,status" region_subscriptions.csv; then
  sed -i '1i is-home-region,region-key,region-name,status' region_subscriptions.csv
fi

# *_compartments.csv
for file in *_compartments.csv; do
  if ! grep -q "^Region,Name,ID" "$file"; then
    sed -i '1i Region,Name,ID' "$file"
  fi
done

# *_DataSafe_Autonomous_DBs.csv
for file in *_DataSafe_Autonomous_DBs.csv; do
  if ! grep -q "^database-type,display-name,autonomous-database-id,infrastructure-type,id,lifecycle-state" "$file"; then
    sed -i '1i database-type,display-name,autonomous-database-id,infrastructure-type,id,lifecycle-state' "$file"
  fi
done

# *_DataSafe_Cloud_DBs.csv
for file in *_DataSafe_Cloud_DBs.csv; do
  if ! grep -q "^database-type,display-name,db-system-id,infrastructure-type,listener-port,service-name,id,vm-cluster-id,lifecycle-state" "$file"; then
    sed -i '1i database-type,display-name,db-system-id,infrastructure-type,listener-port,service-name,id,vm-cluster-id,lifecycle-state' "$file"
  fi
done

# *_DataSafe_Installed_DBs.csv
for file in *_DataSafe_Installed_DBs.csv; do
  if ! grep -q "^database-type,display-name,instance-id,infrastructure-type,listener-port,ip-addresses,service-name" "$file"; then
    sed -i '1i database-type,display-name,instance-id,infrastructure-type,listener-port,ip-addresses,service-name' "$file"
  fi
done

# Define all file patterns to process
file_patterns=(
    "*_Cloud_Databases.csv"
    "*_Autonomous_Databases.csv"
    "*_DataSafe_Autonomous_DBs.csv"
    "*_DataSafe_Cloud_DBs.csv"
    "*_DataSafe_Installed_DBs.csv"
)

# Loop through each file pattern
for pattern in "${file_patterns[@]}"; do
    # List all CSV files matching the current pattern
    for file in $pattern; do
        # Skip if no files match the pattern
        [ -e "$file" ] || continue

        # Extract region from the filename (everything before the first '_')
        region=$(echo "$file" | cut -d'_' -f1)
        
        # Create a temporary file to hold the modified content
        tmpfile=$(mktemp)

        # Variable to track if it's the first line
        first_line=true

        # Read the file line by line
        while IFS= read -r line; do
            if $first_line; then
                # Write the header with "region"
                echo "region,$line" > "$tmpfile"
                first_line=false
            else
                # Write the region with each subsequent line
                echo "$region,$line" >> "$tmpfile"
            fi
        done < "$file"

        # Move the temporary file to replace the original CSV file
        mv "$tmpfile" "$file"

        echo "Processed $file"
    done
done

# Function to append CSV files and remove double quotes
append_csv_files() {
    local file_pattern=$1
    local output_file=$2

    # Get the list of matching CSV files
    csv_files=($(ls $file_pattern 2>/dev/null))

    # Check if no CSV files are found
    if [ ${#csv_files[@]} -eq 0 ]; then
        echo "No CSV files found for pattern $file_pattern."
        return
    fi

    # Extract the header from the first file and write it to the output file
    head -n 1 "${csv_files[0]}" > "$output_file"

    # Append the data from all CSV files (excluding the header) to the output file
    for csv_file in "${csv_files[@]}"; do
        # Remove double quotes and append the data (excluding the header)
        tail -n +2 "$csv_file" | sed 's/"//g' >> "$output_file"
    done

    echo "All files matching $file_pattern have been appended into $output_file with double quotes removed."
}

# Append *_Cloud_Databases.csv files
append_csv_files "*_Cloud_Databases.csv" "All_Regions_Cloud_Databases.csv"

# Append *_DataSafe_Cloud_DBs.csv files
append_csv_files "*_DataSafe_Cloud_DBs.csv" "All_Regions_DataSafe_Cloud_DBs.csv"

# Append *_compartments.csv files
append_csv_files "*_compartments.csv" "All_Regions_compartments.csv"

# Append *_Autonomous_Databases.csv files
append_csv_files "*_Autonomous_Databases.csv" "All_Regions_Autonomous_Databases.csv"

# Append *_DataSafe_Autonomous_DBs.csv files
append_csv_files "*_DataSafe_Autonomous_DBs.csv" "All_Regions_DataSafe_Autonomous_DBs.csv"

# Append *_DataSafe_Installed_DBs.csv files
append_csv_files "*_DataSafe_Installed_DBs.csv" "All_Regions_DataSafe_Installed_DBs.csv"


# New task: Process All_Regions_Cloud_Databases.csv to check for Data Safe status
process_data_safe_status() {
    local cloud_db_file="All_Regions_Cloud_Databases.csv"
    local data_safe_file="All_Regions_DataSafe_Cloud_DBs.csv"
    local output_file="All_Regions_Cloud_Databases_with_Data_Safe_Status.csv"

    # Add header with new column 'Data Safe Status'
    head -n 1 "$cloud_db_file" | awk -F, '{print $0",Data Safe Status"}' > "$output_file"

    # Loop through each entry in All_Regions_Cloud_Databases.csv (skipping the header)
    tail -n +2 "$cloud_db_file" | while IFS=',' read -r region compartment_name db_name db_system_id sid_prefix id pdb_name vm_cluster_id compartment_id display_name db_version; do
        # Default status
        data_safe_status="NOT_REGISTERED"

        # Match in All_Regions_DataSafe_Cloud_DBs.csv based on db-system-id or vm-cluster-id
        match=$(grep -E "$db_system_id|$vm_cluster_id" "$data_safe_file")

        if [ -n "$match" ]; then
            # Extract service-name and trim it before the first dot '.'
            service_name=$(echo "$match" | awk -F, '{print $7}' | awk -F. '{print $1}')

            # Check if trimmed service-name matches pdb-name
            if [ "$service_name" == "$pdb_name" ]; then
                data_safe_status="REGISTERED"
            fi
        fi

        # Write the line to the new output file with the Data Safe Status
        echo "$region,$compartment_name,$db_name,$db_system_id,$sid_prefix,$id,$pdb_name,$vm_cluster_id,$compartment_id,$display_name,$db_version,$data_safe_status" >> "$output_file"
    done

    echo "Data Safe Status processing completed for Cloud Databases. Output saved to $output_file "
}

# Call the function to process Data Safe status
process_data_safe_status

cp All_Regions_Autonomous_Databases.csv All_Regions_Autonomous_Databases_with_Data_Safe_Status.csv
echo "Data Safe Status processing completed for Autonomous Databases. Output saved to All_Regions_Autonomous_Databases_with_Data_Safe_Status.csv "

echo "Script execution completed."
