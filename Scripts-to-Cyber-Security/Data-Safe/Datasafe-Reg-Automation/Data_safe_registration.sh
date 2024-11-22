#!/bin/bash

# Process the Data safe registration
ds_reg_process() {
  local csv_file=$1
  
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

# Registered Target Database details
Datasafe_targets="Datasafe_TargetDBs.csv"
echo "region,compartment_name,Compartment_ID,Target_DB_Name,TARGET_DB_ID" > "$Datasafe_targets"

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

  # Step 4: Process each CSV file entry based on the database type
  # The fields in CSV will vary based on the database type selected
  case $db_type in
    1)  # Oracle Autonomous Databases
      while IFS=',' read -r region adb_name adb_id compartment_name compartment_id data_safe_display_name; do
        echo "Registering Oracle Autonomous Database: $adb_name"
        
        # Create JSON file for Autonomous Database
        cat > database-details_ADB.json <<- EOM
        {
          "autonomousDatabaseId": "$adb_id",
          "databaseType": "AUTONOMOUS_DATABASE",
          "infrastructureType": "ORACLE_CLOUD"
        }
EOM

        # Print OCI command before executing
        # echo "OCI Command: oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_ADB.json --display-name $data_safe_display_name"

        # Execute Data Safe registration command
        oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_ADB.json --display-name "$data_safe_display_name" > "${region}_DS_ADB_Output.txt"
        TARGET_DB_ID=$(jq -r '.data.id' "${region}_DS_ADB_Output.txt")
        echo "$region,$compartment_name,$compartment_id,$data_safe_display_name,$TARGET_DB_ID" >> "$Datasafe_targets"
      done < "$region_csv_file"
      ;;
    
    2)  # Oracle Exadata Databases
      while IFS=',' read -r region db_name vm_cluster_id pdb_name service_name port compartment_name compartment_id connectivity_option_name connectivity_option_id username password data_safe_display_name; do
        echo "Registering Oracle Exadata Database: $pdb_name"
        
        # Create JSON file for Exadata Database
        cat > database-details_Cloud_EXADB.json <<- EOM
        {
          "databaseType": "DATABASE_CLOUD_SERVICE",
          "dbSystemId": null,
          "infrastructureType": "ORACLE_CLOUD",
          "listenerPort": $port,
          "serviceName": "$service_name",
          "vmClusterId": "$vm_cluster_id"
        }
EOM

        # Create credentials JSON file
        cat > credentials_EXADB.json <<- EOM
        {
          "password": "$password",
          "userName": "$username"
        }
EOM

        # Create connection option JSON file
        cat > connection-option_EXADB.json <<- EOM
        {
          "connectionType": "PRIVATE_ENDPOINT",
          "datasafePrivateEndpointId": "$connectivity_option_id"
        }
EOM

        # Print OCI command before executing
        # echo "OCI Command: oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_Cloud_EXADB.json --connection-option file://connection-option_EXADB.json --credentials file://credentials_EXADB.json --display-name $data_safe_display_name"

        # Execute Data Safe registration command
        oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_Cloud_EXADB.json --connection-option file://connection-option_EXADB.json --credentials file://credentials_EXADB.json --display-name "$data_safe_display_name" > "${region}_DS_Cloud_EXADB_Output.txt"
        TARGET_DB_ID=$(jq -r '.data.id' "${region}_DS_Cloud_EXADB_Output.txt")
        echo "$region,$compartment_name,$compartment_id,$data_safe_display_name,$TARGET_DB_ID" >> "$Datasafe_targets"
      done < "$region_csv_file"
      ;;
    
    3)  # Oracle Base Databases
      while IFS=',' read -r region db_name dbsystem_id pdb_name service_name port compartment_name compartment_id connectivity_option_name connectivity_option_id username password data_safe_display_name; do
        echo "Registering Oracle Base Database: $pdb_name"
        
        # Create JSON file for Base Database
        cat > database-details_Cloud_DB.json <<- EOM
        {
          "databaseType": "DATABASE_CLOUD_SERVICE",
          "dbSystemId": "$dbsystem_id",
          "infrastructureType": "ORACLE_CLOUD",
          "listenerPort": $port,
          "serviceName": "$service_name",
          "vmClusterId": null
        }
EOM

        # Create credentials JSON file
        cat > credentials_DB.json <<- EOM
        {
          "password": "$password",
          "userName": "$username"
        }
EOM

        # Create connection option JSON file
        cat > connection-option_DB.json <<- EOM
        {
          "connectionType": "PRIVATE_ENDPOINT",
          "datasafePrivateEndpointId": "$connectivity_option_id"
        }
EOM

        # Print OCI command before executing
        # echo "OCI Command: oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_Cloud_DB.json --connection-option file://connection-option_DB.json --credentials file://credentials_DB.json --display-name $data_safe_display_name"

        # Execute Data Safe registration command
        oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_Cloud_DB.json --connection-option file://connection-option_DB.json --credentials file://credentials_DB.json --display-name "$data_safe_display_name" > "${region}_DS_Cloud_DB_Output.txt"
        TARGET_DB_ID=$(jq -r '.data.id' "${region}_DS_Cloud_DB_Output.txt")
        echo "$region,$compartment_name,$compartment_id,$data_safe_display_name,$TARGET_DB_ID" >> "$Datasafe_targets"
      done < "$region_csv_file"
      ;;

    4)  # Oracle On-Premises Databases
      while IFS=',' read -r region db_name pdb_name service_name port ip compartment_name compartment_id connectivity_option_name connectivity_option_id username password data_safe_display_name; do
        echo "Registering Oracle On-Premises Database: $pdb_name"
        ip_string=$(echo "$ip" | sed 's/;/","/g; s/^/"/; s/$/"/')
        # Create JSON file for On-Premises Database
        cat > database-details_On-Premises.json <<- EOM
        {
          "databaseType": "INSTALLED_DATABASE",
          "infrastructureType": "ON_PREMISES",
          "instanceId": null,
          "ipAddresses": [$ip_string],
          "listenerPort": $port,
          "serviceName": "$service_name"
        }
EOM

        # Create credentials JSON file
        cat > credentials_On-Premises.json <<- EOM
        {
          "password": "$password",
          "userName": "$username"
        }
EOM

        # Create connection option JSON file
        cat > connection-option_On-Premises.json <<- EOM
        {
          "connectionType": "ONPREM_CONNECTOR",
          "onPremConnectorId": "$connectivity_option_id"
        }
EOM

        # Print OCI command before executing
        # echo "OCI Command: oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_On-Premises.json --connection-option file://connection-option_On-Premises.json --credentials file://credentials_On-Premises.json --display-name $data_safe_display_name"

        # Execute Data Safe registration command
        oci data-safe target-database create --compartment-id $compartment_id --database-details file://database-details_On-Premises.json --connection-option file://connection-option_On-Premises.json --credentials file://credentials_On-Premises.json --display-name "$data_safe_display_name" > "${region}_DS_On-Premises_DB_Output.txt"
        TARGET_DB_ID=$(jq -r '.data.id' "${region}_DS_On-Premises_DB_Output.txt")
        echo "$region,$compartment_name,$compartment_id,$data_safe_display_name,$TARGET_DB_ID" >> "$Datasafe_targets"
      done < "$region_csv_file"
      ;;
    
  esac
done
echo "Details of Registered Target Databases in Data Safe : $Datasafe_targets "
echo "Script execution completed."
}


# Prompt for database type selection
echo "What type of Databases do you want to register in Data Safe?"
echo "Choose from the following types:"
echo "  - 1. Oracle Autonomous Databases"
echo "  - 2. Oracle Exadata Databases"
echo "  - 3. Oracle Base Databases"
echo "  - 4. Oracle On-Premises Databases"
read -p "Enter the number corresponding to the database type: " db_type

# Prompt for the CSV file input based on the database type
case $db_type in
  1)
    echo "You selected Oracle Autonomous Databases."
    echo "All_Regions_DS_Reg_Autonomous_Databases.csv - Sample CSV Format: region,ADB_Name,ADB_ID,compartment_name,Compartment_ID,Data_Safe_Display_Name"
    ;;
  2)
    echo "You selected Oracle Exadata Databases."
    echo "All_Regions_DS_Reg_EXADATA_Databases.csv - Sample CSV Format: region,DB_Name,vm-cluster-id,PDB_Name,serviceName,listenerPort,compartment_name,compartment-id,connectivity_option_Name,connectivity_option_ID,userName,Password,Data_Safe_Display_Name"
    echo "Note * - As part of the prerequisites, please update the CSV files to include connectivity options and Data Safe service account details for each database."
    echo "Note * - Private Endpoint details will be auto-filled in an earlier phase if any database VCNs match existing private endpoints."
    ;;
  3)
    echo "You selected Oracle Base Databases."
    echo "All_Regions_DS_Reg_Base_Databases.csv - Sample CSV Format: region,DB_NAME,dbsystem-id,PDB_Name,serviceName,listenerPort,compartment_name,compartment-id,connectivity_option_Name,connectivity_option_ID,userName,Password,Data_Safe_Display_Name"
    echo "Note * - As part of the prerequisites, please update the CSV files to include connectivity options and Data Safe service account details for each database."
    echo "Note * - Private Endpoint details will be auto-filled in an earlier phase if any database VCNs match existing private endpoints."
    ;;
  4)
    echo "You selected Oracle On-Premises Databases."
    echo "All_Regions_DS_Reg_On-Premises_Databases.csv - Sample CSV Format: region,db_name,pdb_name,service_name,listenerPort,DB_HOST_IP,compartment_name,compartment_id,connectivity_option_name,connectivity_option_id,username,password,data_safe_display_name"
    echo "Note * - As part of the prerequisites, please update the CSV files to include connectivity options and Data Safe service account details for each database."
    echo "Note * - Provide the compartment details where these databases should be tagged in OCI."
    ;;
  *)
    echo "Invalid selection!"
    exit 1
    ;;
esac

# Read the CSV file
read -p "Please provide the path to your CSV file: " csvfile

# Validate the file existence
if [[ ! -f "$csvfile" ]]; then
    echo "Error: File does not exist. Please provide a valid file path."
    exit 1
fi

# Check for empty columns in the CSV file
if awk -F',' '{for(i=1;i<=NF;i++) if($i=="") exit 1}' "$csvfile"; then
    echo "CSV file validation passed. Proceeding with the script..."
    ds_reg_process "$csvfile"
else
    echo "Required fields are missing in the CSV file."
    echo "Please update the prerequisites:"
    echo "1. Set connectivity options (private endpoint or on-premises connector)."
    echo "2. Ensure Data Safe Service account details are complete."
    echo "Refer to 'Datasafe-Reg-Automation_Instructions.pdf' for more information."
    exit 1
fi

