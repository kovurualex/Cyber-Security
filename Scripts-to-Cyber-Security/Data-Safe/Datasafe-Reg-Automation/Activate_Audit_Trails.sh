#!/bin/bash

# Prompt for Data Safe Registered databases details
echo "Datasafe_TargetDBs.csv - Sample CSV Format: region,compartment_name,Compartment_ID,Target_DB_Name, Target_DB_ID"
# Read the CSV file
read -p "Please provide the path to your CSV file: " csv_file


# Step 4: Prompt Audit Trail collection Start Time
read -p "Enter Audit Trail collection Start Time (YYYY-MM-DD): " audit_collection_start_time

# Validate the format (YYYY-MM-DD)
if [[ $audit_collection_start_time =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Audit Trail collection Start Time accepted."
else
    echo "Audit Trail collection Start Time Format incorrect. Please enter a valid date in YYYY-MM-DD format."
    exit 1
fi

# Step 2: Sort the CSV by region and generate region-specific sorted CSV files
# Skip header, sort, and save sorted entries in 'sorted_$csv_file'
tail -n +2 $csv_file | sort -t, -k1,1 > sorted_$csv_file

# Extract unique region values from the sorted CSV
regions=$(cut -d',' -f1 sorted_$csv_file | sort | uniq)

# Generate region-wise sorted CSV files for each unique region
for region in $regions; do
  region_csv_file="${region}_sorted_${csv_file}"
  
  # Append the region-specific rows from the sorted CSV
  grep "^${region}," sorted_$csv_file > $region_csv_file
  
  echo "Generated file: $region_csv_file"
done

# List all generated region-specific CSV files
echo "Region-specific CSV files:"
ls -ltr *_sorted_$csv_file

# Check current region
echo "Current OCI region: $OCI_REGION"

#Generate Assessment and Audit Status details
Audit_Trails_Status="All_Regions_Target_DBs_Audit_Trails_Status.csv"
echo "region,compartment_name,compartment_id,target_db_name,target_db_id,AuditTrail_name,AuditTrail_id,audit-collection-start-time,lifecycle-state,status" > $Audit_Trails_Status

# Step 3: Process each region CSV file and match with the current region
for region_csv_file in *_sorted_$csv_file; do
  region=$(echo $region_csv_file | cut -d'_' -f1)

  if [[ "$region" == "$OCI_REGION" ]]; then
    echo "Processing CSV file for the current region: $region_csv_file"
  else
    echo "Switching to region ${region}..."
    export OCI_CONFIG_PROFILE="${region}"
    export PS1="\u@cloudshell:\W (${region})$"
    export OCI_REGION="${region}"
    export OCI_CLI_PROFILE="${region}"
    echo "Processing CSV file for region: $region_csv_file"
  fi

  # Step 4: Process each CSV file entry 
  while IFS=',' read -r region compartment_name compartment_id target_db_name target_db_id; do
        echo "Processing Target Database: $region, $target_db_name"

        # Step 4c: Process audit trails for the target DB
        audit_trail_file="${target_db_name}_audit_Trails.txt"
        oci data-safe audit-trail list --compartment-id "$compartment_id" --target-id "$target_db_id" --all | jq -r '.data.items[] | "\(.["display-name"]),\(.id),\(.status)"' > "$audit_trail_file"
        
        while IFS=',' read -r display_name id status; do
        if [ "$status" = "NOT_STARTED" ]; then
            echo "Start Audit Collection for $region, $target_db_name "
            oci data-safe audit-trail start --audit-collection-start-time "$audit_collection_start_time" --audit-trail-id "$id"
        fi
        done < "$audit_trail_file"

        # Step 4f: Retrive the Audit_Trails Status details in csv file
            while IFS=',' read -r display_name id status; do
                Audit_Trail_Details=$(oci data-safe audit-trail get --audit-trail-id "$id" | jq -r '[.data."display-name", .data.id, .data."audit-collection-start-time", .data."lifecycle-state", .data.status] | @csv' | sed 's/"//g')
                echo "$region,$compartment_name,$compartment_id,$target_db_name,$target_db_id,$Audit_Trail_Details" >> $Audit_Trails_Status
            done < "$audit_trail_file"
            echo "Generated Audit trail status csv files successfully"

    done < "$region_csv_file"

done
echo "Script execution completed and generated the below status details file"
echo "All_Regions_Target_DBs_Audit_Trails_Status.csv"

