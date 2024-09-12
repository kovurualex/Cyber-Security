#!/bin/bash

# This script is designed to:
# 1. Prompt the user for the Compartment ID to query Autonomous Databases in Oracle Cloud Infrastructure (OCI).
# 2. Execute an OCI CLI command to list all Autonomous Databases in the specified compartment.
# 3. Generate a CSV file that contains details such as the Display Name, DB Version, Autonomous Database ID, and Data Safe Status.
# 4. For each database that has a Data Safe Status not equal to "REGISTERED", it creates a JSON file containing the database ID and other metadata.
# 5. Generate Oracle Data Safe registration commands for every unregistered Autonomous Database and save them into a file.
# 
# The JSON files are named 'database-details_$AutonomousDatabaseName.json' and stored in the current working directory.
# The CSV file is named 'autonomous_databases.csv' and is also saved in the current directory.
# The Oracle Data Safe registration commands are saved in 'data_safe_registration_commands.sh'.

# Prompt user for Compartment ID
read -p "Enter the Compartment ID: " COMPARTMENT_ID

# Define output file names
CSV_FILE="autonomous_databases.csv"
COMMANDS_FILE="data_safe_registration_commands.sh"

# Fetch the list of Autonomous Databases and generate a CSV file for the output
oci db autonomous-database list --compartment-id $COMPARTMENT_ID \
--query 'data[*].{"Display Name": "display-name", "DB Version": "db-version", "ID": "id", "Data Safe Status": "data-safe-status"}' \
--output json | jq -r '.[] | [.["Display Name"], .["DB Version"], .["ID"], .["Data Safe Status"]] | @csv' > $CSV_FILE

# Notify user that the CSV file has been generated
echo "CSV file $CSV_FILE has been generated with the database details."

# Initialize the Data Safe registration commands file
echo "#!/bin/bash" > $COMMANDS_FILE
echo "# This file contains Oracle Data Safe registration commands for unregistered databases." >> $COMMANDS_FILE

# Loop through the CSV file and process databases where "Data Safe Status" is not "REGISTERED"
cat $CSV_FILE | while IFS=',' read -r db_name db_version db_id data_safe_status
do
    # Remove quotes from variables
    db_name=$(echo $db_name | tr -d '"')
    db_id=$(echo $db_id | tr -d '"')
    data_safe_status=$(echo $data_safe_status | tr -d '"')
    
    # Check if Data Safe Status is not "REGISTERED"
    if [[ "$data_safe_status" != "REGISTERED" ]]; then
        # Create the JSON file for each unregistered database
        json_file_name="database-details_$db_name.json"
        cat <<EOF > $json_file_name
{
    "autonomousDatabaseId": "$db_id",
    "databaseType": "AUTONOMOUS_DATABASE",
    "infrastructureType": "ORACLE_CLOUD"
}
EOF
        echo "Generated $json_file_name for Autonomous Database: $db_name"

        # Append the Data Safe registration command to the commands file
        echo "oci data-safe target-database create --compartment-id $COMPARTMENT_ID --database-details file://$json_file_name --display-name $db_name" >> $COMMANDS_FILE
    fi
done

# Notify user that the Data Safe registration commands have been generated
echo "Data Safe registration commands have been generated in $COMMANDS_FILE."

