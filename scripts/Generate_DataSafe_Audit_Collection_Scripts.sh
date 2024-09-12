#!/bin/bash

# Script Name: Generate_DataSafe_Audit_Collection_Scripts.sh
# Description:
# This script prompts the user for a Compartment ID and an Audit Collection Start Time.
# It fetches audit trail data from Oracle Cloud Infrastructure (OCI) Data Safe for the specified compartment,
# extracts relevant fields (such as target ID, trail location, status, ID, and description), and writes them to a CSV file.
# It generates a single shell script that will initiate the audit trail collection for all the target databases using the provided start time.

# Step 1: Prompt for Compartment ID
read -p "Enter the Compartment ID: " COMPARTMENT_ID

# Step 2: Prompt for Audit Trail collection Start Time
while true; do
    read -p "Audit Trail collection Start Time Format: YYYY-MM-DD (This date will be taken as midnight UTC of that day): " audit_collection_start_time
    # Validate the format (YYYY-MM-DD)
    if [[ $audit_collection_start_time =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        echo "Audit Trail collection Start Time accepted."
        break
    else
        echo "Audit Trail collection Start Time Format incorrect. Please enter a valid date in YYYY-MM-DD format."
    fi
done

# Step 3: Run the OCI command and capture the JSON output using the entered Compartment ID
echo "Fetching audit trail data from OCI for Compartment ID: $COMPARTMENT_ID..."
oci data-safe audit-trail list --compartment-id $COMPARTMENT_ID --status NOT_STARTED --all > audit_trail_output.json

# Step 4: Check if the JSON file has any data
if [ ! -s audit_trail_output.json ]; then
    echo "No data found or unable to fetch audit trails."
    exit 1
fi

# Step 5: Extract necessary fields and write them to a CSV file
echo "Extracting audit trail details to CSV..."
jq -r '.data.items[] | [.["target-id"], .["trail-location"], .["status"], .["id"], .["description"]] | @csv' audit_trail_output.json > audit_trails.csv
echo "CSV file created: audit_trails.csv"

# Step 6: Generate a single shell script for all audit-trail-ids
script_name="Data_safe_Target_DB_Audit_Collection_Start.sh"
echo "Generating single shell script for all audit trail entries..."

{
    echo "#!/bin/bash"
    
    # Loop through CSV and generate one command per entry
    while IFS=, read -r target_id trail_location status audit_trail_id description
    do
        # Skip the header if present
        if [[ $audit_trail_id == "id" ]]; then
            continue
        fi

        # Remove quotes around audit_trail_id
        audit_trail_id_clean=$(echo $audit_trail_id | tr -d '"')

        # Append the OCI command for this audit trail entry
        echo "oci data-safe audit-trail start --audit-collection-start-time $audit_collection_start_time --audit-trail-id $audit_trail_id_clean"

    done < audit_trails.csv
} > $script_name

chmod +x $script_name
echo "Generated single script: $script_name"

echo "Script generation complete."

