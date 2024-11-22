#!/bin/bash

# Function to process a given region and retrieve information about databases
process_region() {
    local REGION_NAME=$1
    
    # Step 1: List compartments in the region and save the results
    echo "Listing compartments in region ${REGION_NAME}..."
    # Define the output file header
    compartments_file="${REGION_NAME}_compartments.csv"
    echo "region,compartment_name,compartment_id" > "${REGION_NAME}_compartments.csv"
    oci iam compartment list --all --compartment-id-in-subtree true --output json --query 'data[*].{Name:"name", ID:"id"}' \
    | jq -r --arg region "$REGION_NAME" '.[] | [$region, .Name, .ID] | @csv' | sed 's/"//g' >> "$compartments_file"


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


    # Step 3: All VCN Details processing along with subnet details
    echo "VCN Details processing along with subnet details"
    # File names based on the region
    temp_vcns_file="temp_vcns.txt"
    vcn_compartments_file="${REGION_NAME}_vcn_unique_compartment_ids.txt"
    temp_subnets_file="temp_subnets.txt"
    final_output_file="${REGION_NAME}_vcns_subnets.csv"

    # Initialize files with headers
    echo "vcn_name,vcn_id,compartment_id" > "$temp_vcns_file"
    echo "compartment_id" > "$vcn_compartments_file"
    echo "subnet_name,subnet_id,vcn_id" > "$temp_subnets_file"
    echo "region,compartment_name,vcn_name,subnet_name,compartment_id,vcn_id,subnet_id" > "$final_output_file"

    # echo "Finding VCN details and saving to $temp_vcns_file"
    oci search resource structured-search --query-text "query vcn resources" --output json \
        | jq -r '.data.items[] | [.["display-name"], .identifier, .["compartment-id"]] | join(",")' \
        >> "$temp_vcns_file"

    # Skip the header and extract unique compartment IDs from line 2 onwards
    # echo "Extracting unique compartment IDs from $temp_vcns_file to $vcn_compartments_file"
    tail -n +2 "$temp_vcns_file" | cut -d',' -f3 | sort -u >> "$vcn_compartments_file"

    # echo "Finding subnet details for each compartment"
    # Loop through compartment IDs, starting from the second line of $vcn_compartments_file
    tail -n +2 "$vcn_compartments_file" | while IFS= read -r compartment_id; do
        # echo "Processing compartment ID: $compartment_id"
        echo "Processing compartment ID: ${compartment_id:0:20}..."
        oci network subnet list --compartment-id "$compartment_id" --all \
            | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"]] | join(",")' \
            >> "$temp_subnets_file"
    done

    # Process Subnet Data and Write to Final Output File
    # echo "Processing subnet data and writing to $final_output_file"

    # Loop through each line in temp_subnets_file, skipping the header
    tail -n +2 "$temp_subnets_file" | while IFS=',' read -r subnet_name subnet_id vcn_id; do
        # Lookup vcn_name and compartment_id from temp_vcns_file based on vcn_id
        vcn_data=$(grep -w "$vcn_id" "$temp_vcns_file" | tail -n 1)  # exact match for vcn_id
        vcn_name=$(echo "$vcn_data" | cut -d',' -f1)
        compartment_id=$(echo "$vcn_data" | cut -d',' -f3 | sed 's/ //g')  # Remove spaces if any

        # Debugging print statements for verification
        # echo "Subnet Name: $subnet_name, Subnet ID: $subnet_id, VCN ID: $vcn_id"
        # echo "VCN Data Found: $vcn_data"
        # echo "VCN Name: $vcn_name, Compartment ID: $compartment_id"

        # Lookup compartment_name from ${REGION_NAME}_compartments.csv based on compartment_id
        compartment_name=$(grep -w "$compartment_id" "${REGION_NAME}_compartments.csv" | cut -d',' -f2 | sed 's/ //g')
        # Set compartment_name to "root" if compartment_id is not found
        if [ -z "$compartment_name" ]; then
        compartment_name="root"
        fi

        # Additional debug prints for compartment name
        # echo "Compartment Name: $compartment_name for Compartment ID: $compartment_id"

        # Prepare the formatted line for final output
        output_line="$REGION_NAME,$compartment_name,$vcn_name,$subnet_name,$compartment_id,$vcn_id,$subnet_id"
        
        # Write the formatted line to the final output file
        echo "$output_line" >> "$final_output_file"

    done

    echo "Completed processing all subnets. Final output is in $final_output_file."


    # Step 4: Datasafe Conectivity options details
    echo "Processing Datasafe Conectivity options details"
    # File names based on the region
        temp_pe_file="temp_Private_Endpoints.txt"
        temp_op_file="temp_OnPrem_Connectors.txt"
        pe_compartments_file="${REGION_NAME}_pe_unique_compartment_ids.txt"
        temp_pe_vcn_subnet_file="temp_pe_vcn_subnets.txt"
        final_pe_output_file="${REGION_NAME}_Private_Endpoints.csv"
        final_op_output_file="${REGION_NAME}_OnPrem_Connectors.csv"
    # Initialize files with headers
        echo "pe_name,pe_id,compartment_id" > "$temp_pe_file"
        echo "op_name,op_id,compartment_id" > "$temp_op_file"
        echo "compartment_id" > "$pe_compartments_file"
        echo "pe_name,pe_id,vcn_id,subnet_id,compartment_id" > "$temp_pe_vcn_subnet_file"
        echo "region,compartment_name,pe_name,vcn_name,subnet_name,compartment_id,pe_id,vcn_id,subnet_id" > "$final_pe_output_file"
        echo "region,compartment_name,op_name,compartment_id,op_id" > "$final_op_output_file"

        echo "Finding Datasafe PrivateEndpoint details "
        oci search resource structured-search --query-text "query DataSafePrivateEndpoint resources" --output json \
            | jq -r '.data.items[] | [.["display-name"], .identifier, .["compartment-id"]] | join(",")' \
            >> "$temp_pe_file"
        
        echo "Finding Datasafe OnpremConnector details"
        oci search resource structured-search --query-text "query DataSafeOnpremConnector resources" --output json \
            | jq -r '.data.items[] | [.["display-name"], .identifier, .["compartment-id"]] | join(",")' \
            >> "$temp_op_file"

    # Skip the header and extract unique compartment IDs from line 2 onwards
        # echo "Extracting unique compartment IDs from $temp_pe_file to $pe_compartments_file"
        tail -n +2 "$temp_pe_file" | cut -d',' -f3 | sort -u >> "$pe_compartments_file"

        echo "Finding vcn,subnet details of Private_endpoints for each compartment"
        # Loop through compartment IDs, starting from the second line of $pe_compartments_file
        tail -n +2 "$pe_compartments_file" | while IFS= read -r compartment_id; do
            # echo "Processing compartment ID: $compartment_id"
            # echo "Processing compartment ID: ${compartment_id:0:20}..."
            oci data-safe private-endpoint list --compartment-id $compartment_id --all \
                | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"], .["subnet-id"], .["compartment-id"]] | @csv' | sed 's/"//g' \
                >> "$temp_pe_vcn_subnet_file"
        done

    # Process connection options and Write to Final Output File
        # echo "Processing Private endpoints vcn  data and writing to $final_pe_output_file"
        # Loop through each line in temp_pe_vcn_subnet_file, skipping the header
        tail -n +2 "$temp_pe_vcn_subnet_file" | while IFS=',' read -r pe_name pe_id vcn_id subnet_id compartment_id; do
            # Lookup vcn_name and compartment_id from temp_vcns_file based on vcn_id
            vcn_data=$(grep -w "$vcn_id" "${REGION_NAME}_vcns_subnets.csv" | tail -n 1)  # exact match for vcn_id
            vcn_name=$(echo "$vcn_data" | cut -d',' -f3)
            subnet_data=$(grep -w "$subnet_id" "${REGION_NAME}_vcns_subnets.csv" | tail -n 1)  # exact match for vcn_id
            subnet_name=$(echo "$subnet_data" | cut -d',' -f4)
            # Lookup compartment_name from ${REGION_NAME}_compartments.csv based on compartment_id
            compartment_name=$(grep -w "$compartment_id" "${REGION_NAME}_compartments.csv" | cut -d',' -f2 | sed 's/ //g')
            # Set compartment_name to "root" if compartment_id is not found
            if [ -z "$compartment_name" ]; then
            compartment_name="root"
            fi
            # Additional debug prints for compartment name
            # echo "VCN NAME: $vcn_name , SUBNET NAME : $subnet_name"
            # Prepare the formatted line for final output
            output_line="$REGION_NAME,$compartment_name,$pe_name,$vcn_name,$subnet_name,$compartment_id,$pe_id,$vcn_id,$subnet_id"
            # Write the formatted line to the final output file
            echo "$output_line" >> "$final_pe_output_file"
        done

        # echo "Processing OnPrem_Connectors and writing to $final_pe_output_file"
        # Loop through temp_op_file each line in , skipping the header
        tail -n +2 "$temp_op_file" | while IFS=',' read -r op_name op_id compartment_id; do
            # Lookup compartment_name from ${REGION_NAME}_compartments.csv based on compartment_id
            compartment_name=$(grep -w "$compartment_id" "${REGION_NAME}_compartments.csv" | cut -d',' -f2 | sed 's/ //g')
            # Set compartment_name to "root" if compartment_id is not found
            if [ -z "$compartment_name" ]; then
            compartment_name="root"
            fi
            # Additional debug prints for compartment name
            # echo "Compartment Name: $compartment_name for Compartment ID: $compartment_id"
            # Prepare the formatted line for final output
            output_line="$REGION_NAME,$compartment_name,$op_name,$compartment_id,$op_id"
            # Write the formatted line to the final output file
            echo "$output_line" >> "$final_op_output_file"
        done

        echo "Completed processing all Data Safe Connection Options. Final output is in $final_pe_output_file and $final_op_output_file "

    # Step 5: Process Data Safe Target Database compartments
    echo "Processing Data Safe Target Databases..."
    # Define headers for both output files
    echo "region,database-type,display-name,autonomous-database-id,infrastructure-type,id,lifecycle-state,connection_type,connection_id" > "${REGION_NAME}_DataSafe_Autonomous_DBs.csv"
    echo "region,database-type,display-name,db-system-id,infrastructure-type,listener-port,service-name,id,vm-cluster-id,lifecycle-state,connection_type,connection_id" > "${REGION_NAME}_DataSafe_Cloud_DBs.csv"
    echo "region,database-type,display-name,db-system-id,infrastructure-type,listener-port,service-name,id,vm-cluster-id,lifecycle-state,connection_type,connection_id" > "${REGION_NAME}_DataSafe_Base_DBs.csv"
    echo "region,database-type,display-name,db-system-id,infrastructure-type,listener-port,service-name,id,vm-cluster-id,lifecycle-state,connection_type,connection_id" > "${REGION_NAME}_DataSafe_Exa_DBs.csv"
    echo "region,database-type,display-name,id,infrastructure-type,listener-port,ip-addresses,service-name,connection_type,connection_id" > "${REGION_NAME}_DataSafe_Installed_DBs.csv"
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

    # Step 6: Process Non Autonomous Database compartments
    CLOUD_DB_OUTPUT_FILE="${REGION_NAME}_Cloud_Databases.csv"
    CLOUD_BaseDB_OUTPUT_FILE="${REGION_NAME}_Cloud_BaseDatabases.csv"
    CLOUD_ExaDB_OUTPUT_FILE="${REGION_NAME}_Cloud_ExaDatabases.csv"
    CLOUD_PDB_CONNECT_FILE="${REGION_NAME}_Cloud_PDB_Connect_Strings.csv"

    echo "Processing Cloud Database compartments..."
    # Define the output file headers
    echo "region,compartment-name,compartment-id,db-name,id,pdb_name,pdbid,db-system-id,vm-cluster-id" > "$CLOUD_DB_OUTPUT_FILE"
    echo "region,compartment-name,compartment-id,db-name,id,pdb_name,pdbid,db-system-id,domain,listener-port,subnet-id,db-version,vcn_name,vcn_id,data_safe_status" > "$CLOUD_BaseDB_OUTPUT_FILE"
    echo "region,compartment-name,compartment-id,db-name,id,pdb_name,pdbid,vm-cluster-id,domain,listener-port,subnet-id,db-version,vcn_name,vcn_id,data_safe_status" > "$CLOUD_ExaDB_OUTPUT_FILE"
    echo "region,compartment-name,compartment-id,pdb_name,pdb_id,container_database_id,connect_string" > "$CLOUD_PDB_CONNECT_FILE"

    while IFS=',' read -r compartment_id; do
        compartment_name=$(grep "$compartment_id" "${REGION_NAME}_compartments.csv" | awk -F',' '{print $2}')
        if [[ -n "$compartment_name" ]]; then            
            # echo "Listing cloud databases in compartment ${compartment_id}..."
            # echo collecting the pdb connection strings
            oci db pluggable-database list --compartment-id "$compartment_id" | jq -r '.data[] | [.["pdb-name"], .id, .["container-database-id"], .["connection-strings"]["pdb-default"]] | @csv'|sed 's/"//g' > pdb_connect.txt
            if [[ ! -s pdb_connect.txt ]]; then
                echo "No pluggable database data found for compartment $compartment_id."
                exit 1
            fi
            while IFS=',' read -r pdb_name pdb_id container_database_id connect_string; do
                echo "$REGION_NAME,$compartment_name,$compartment_id,$pdb_name,$pdb_id,$container_database_id,$connect_string" >> "$CLOUD_PDB_CONNECT_FILE"
            done < "pdb_connect.txt" 
            # Process different database types
            process_cloud_dbs "$compartment_name" "$compartment_id" "$REGION_NAME"
        fi
    done < "${REGION_NAME}_CloudDB_unique_compartment_ids.txt"

    # Step 7: Process Autonomous Database compartments
    # Define output filenames based on the region
    AUTONOMOUS_DB_OUTPUT_FILE="${REGION_NAME}_Cloud_AutonomousDBs.csv"
    # Initialize the output files with headers
    echo "region,compartment_name,adb_name,adb_version,adb_id,data_safe_status,compartment_id" > "$AUTONOMOUS_DB_OUTPUT_FILE"
    echo "Processing Autonomous Database compartments..."
    while IFS=',' read -r compartment_id; do
        compartment_name=$(grep "$compartment_id" "${REGION_NAME}_compartments.csv" | awk -F',' '{print $2}')
        if [[ -n "$compartment_name" ]]; then
            oci db autonomous-database list --compartment-id "$compartment_id" --query 'data[*].{"Display Name": "display-name", "DB Version": "db-version", "ID": "id", "Data Safe Status": "data-safe-status", "Compartment ID": "compartment-id"}' --output json \
            | jq -r '.[] | [.["Display Name"], .["DB Version"], .["ID"], .["Data Safe Status"], .["Compartment ID"]] | @csv' | sed 's/"//g' > autonomous_data_info.txt
            while IFS=',' read -r display_name db_version id data_safe_status compartment_id; do
                echo "$REGION_NAME,$compartment_name,$display_name,$db_version,$id,$data_safe_status,$compartment_id" >> "$AUTONOMOUS_DB_OUTPUT_FILE"
            done < "autonomous_data_info.txt"    
        else
            echo "No matching compartment found for ID ${compartment_id} in region ${REGION_NAME}."
        fi
    done < "${REGION_NAME}_AutonomousDB_unique_compartment_ids.txt"
    
    
    #Step 8: Prepare CSV files for registering non-monitored databases in Data Safe.
    echo "Prepare CSV files for registering non-monitored databases in Data Safe."
    # Input files
    file4="${REGION_NAME}_Cloud_BaseDatabases.csv"
    file5="${REGION_NAME}_Cloud_ExaDatabases.csv"
    file6="${REGION_NAME}_Cloud_AutonomousDBs.csv"
    file11="${REGION_NAME}_Private_Endpoints.csv"
    file12="${REGION_NAME}_OnPrem_Connectors.csv"

    # Output files
    file7="${REGION_NAME}_DS_Reg_Autonomous_Databases.csv"
    file8="${REGION_NAME}_DS_Reg_Base_Databases.csv"
    file9="${REGION_NAME}_DS_Reg_EXADATA_Databases.csv"
    file10="${REGION_NAME}_DS_Reg_On-Premises_Databases.csv"

    # Ensure input files exist
    for input_file in "$file4" "$file5" "$file6" "$file11" "$file12"; do
    if [ ! -f "$input_file" ]; then
        echo "Error: $input_file does not exist."
        exit 1
    fi
    done

    # Helper function to map connectivity options based on vcn_name from file11
    map_connectivity_options() {
    local vcn_name="$1"
    local result=$(awk -F ',' -v vcn="$vcn_name" '$4 == vcn {print $3","$7}' "$file11" | head -1)
    echo "${result:-NULL,NULL}"  # Return NULL,NULL if no match is found
    }

     # Generate file7: Oracle Autonomous Databases (only if data_safe_status is "NOT_REGISTERED")
    echo "region,ADB_Name,ADB_ID,compartment_name,Compartment_ID,Data_Safe_Display_Name" > "$file7"
    while IFS=, read -r region compartment_name display_name db_version id data_safe_status compartment_id; do
    if [ "$data_safe_status" == "NOT_REGISTERED" ]; then
        adb_name="${display_name}"  # Assuming display_name corresponds to ADB_Name
        adb_id="${id}"              # Assuming id corresponds to ADB_ID
        echo "${region:-NULL},${adb_name:-NULL},${adb_id:-NULL},${compartment_name:-NULL},${compartment_id:-NULL},${adb_name:-NULL}" >> "$file7"
    fi
    done < <(tail -n +2 "$file6")

    # Generate file8: Oracle Base Databases (only if data_safe_status is "NOT_REGISTERED")
    echo "region,DB_NAME,dbsystem-id,PDB_Name,serviceName,listenerPort,compartment_name,compartment-id,connectivity_option_Name,connectivity_option_ID,userName,Password,Data_Safe_Display_Name" > "$file8"
    while IFS=, read -r region compartment_name compartment_id db_name id pdb_name pdbid db_system_id domain listener_port subnet_id db_version vcn_name vcn_id data_safe_status; do
    if [ "$data_safe_status" == "NOT_REGISTERED" ]; then
        connectivity_options=$(map_connectivity_options "$vcn_name")
        service_name="${pdb_name}.${domain}"
        echo "${region:-NULL},${db_name:-NULL},${db_system_id:-NULL},${pdb_name:-NULL},${service_name:-NULL},${listener_port:-NULL},${compartment_name:-NULL},${compartment_id:-NULL},${connectivity_options:-NULL,NULL},,,${pdb_name:-NULL}" >> "$file8"
    fi
    done < <(tail -n +2 "$file4")

    # Generate file9: Oracle Exadata Databases (only if data_safe_status is "NOT_REGISTERED")
    echo "region,DB_Name,vm-cluster-id,PDB_Name,serviceName,listenerPort,compartment_name,compartment-id,connectivity_option_Name,connectivity_option_ID,userName,Password,Data_Safe_Display_Name" > "$file9"
    while IFS=, read -r region compartment_name compartment_id db_name id pdb_name pdbid vm_cluster_id domain listener_port subnet_id db_version vcn_name vcn_id data_safe_status; do
    if [ "$data_safe_status" == "NOT_REGISTERED" ]; then
        connectivity_options=$(map_connectivity_options "$vcn_name")
        service_name="${pdb_name}.${domain}"
        echo "${region:-NULL},${db_name:-NULL},${vm_cluster_id:-NULL},${pdb_name:-NULL},${service_name:-NULL},${listener_port:-NULL},${compartment_name:-NULL},${compartment_id:-NULL},${connectivity_options:-NULL,NULL},,,${pdb_name:-NULL}" >> "$file9"
    fi
    done < <(tail -n +2 "$file5")

    # Generate file10: Oracle On-Premises Databases (sample entry)
    echo "region,db_name,pdb_name,service_name,listenerPort,DB_HOST_IP,compartment_name,compartment_id,connectivity_option_name,connectivity_option_id,username,password,data_safe_display_name" > "$file10"
    echo "$REGION_NAME,DBSEC19cLAB,pdb1,pdb1,1521,129.213.28.240;10.0.0.150,AlexKovuru,ocid1.compartment.oc1..aaaaaaaa7ksdb47smsqbyfn7pc2fd7qxmij3n2kisrutq5f3jmebtvjggjua,OC 202407121441,ocid1.datasafeonpremconnector.oc1.iad.amaaaaaas4n35viafiq42owokuttm5i2cy2sfnaqmxjviilbpq26fekvzona,,,pdb1" >> "$file10"

    echo "Output files generated successfully: $file7, $file8, $file9, and $file10"

}

# Function to process Data Safe databases
process_data_safe_dbs() {
    local compartment_name=$1
    local region_name=$2

    # Process Autonomous Databases
    while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state; do
        if [[ "$db_type" == "\"AUTONOMOUS_DATABASE\"" ]]; then
            # Fetch database details
            database_details=$(oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"'))
            # Extract main fields
                csv_line=$(echo "$database_details" | jq -r '[
      .data["database-details"]."database-type",
      .data["display-name"],
      .data["database-details"]."autonomous-database-id",
      .data["database-details"]."infrastructure-type",
      .data["id"],
      .data["lifecycle-state"]
    ] | @csv')
            # Extract connection-type and add respective ID field
                connection_type=$(echo "$database_details" | jq -r '.data["connection-option"]["connection-type"]')
                
                if [[ "$connection_type" == "ONPREM_CONNECTOR" ]]; then
                    on_prem_connector_id=$(echo "$database_details" | jq -r '.data["connection-option"]["on-prem-connector-id"]')
                    echo "$region_name,$csv_line,$connection_type,$on_prem_connector_id" | sed 's/"//g' >> "${region_name}_DataSafe_Autonomous_DBs.csv"
                elif [[ "$connection_type" == "PRIVATE_ENDPOINT" ]]; then
                    datasafe_private_endpoint_id=$(echo "$database_details" | jq -r '.data["connection-option"]["datasafe-private-endpoint-id"]')
                    echo "$region_name,$csv_line,$connection_type,$datasafe_private_endpoint_id" | sed 's/"//g' >> "${region_name}_DataSafe_Autonomous_DBs.csv"
                else
                    # In case there’s no specific ID associated with the connection type
                    echo "$region_name,$csv_line,$connection_type," | sed 's/"//g' >> "${region_name}_DataSafe_Autonomous_DBs.csv"
                fi
        fi
    done < "${REGION_NAME}_DataSafe_Target_List.txt"

    # Process Non Autonomous Databases Service 
    while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state; do
        if [[ "$db_type" == "\"DATABASE_CLOUD_SERVICE\"" ]]; then
            # Fetch database details
            database_details=$(oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"'))
            
            # Extract main fields
            csv_line=$(echo "$database_details" | jq -r '.data | [
                .["database-details"]["database-type"],
                .["display-name"],
                (.["database-details"]["db-system-id"] // "null"),
                .["database-details"]["infrastructure-type"],
                .["database-details"]["listener-port"],
                .["database-details"]["service-name"],
                .id,
                (.["database-details"]["vm-cluster-id"] // "null"),
                .["lifecycle-state"]
            ] | @csv')
            
            # Extract connection-type and add respective ID field
            connection_type=$(echo "$database_details" | jq -r '.data["connection-option"]["connection-type"]')
            if [[ "$connection_type" == "ONPREM_CONNECTOR" ]]; then
                connection_id=$(echo "$database_details" | jq -r '.data["connection-option"]["on-prem-connector-id"]')
            elif [[ "$connection_type" == "PRIVATE_ENDPOINT" ]]; then
                connection_id=$(echo "$database_details" | jq -r '.data["connection-option"]["datasafe-private-endpoint-id"]')
            else
                connection_id=""
            fi

            # Append the full line including connection info
            full_line="$region_name,$csv_line,$connection_type,$connection_id"
            echo "$full_line" | sed 's/"//g' >> "${region_name}_DataSafe_Cloud_DBs.csv"
            
            # Check if vm-cluster-id is null and route to appropriate file
            vm_cluster_id=$(echo "$database_details" | jq -r '.data["database-details"]["vm-cluster-id"]')
            if [[ "$vm_cluster_id" == "null" ]]; then
                echo "$full_line" | sed 's/"//g' >> "${region_name}_DataSafe_Base_DBs.csv"
            else
                echo "$full_line" | sed 's/"//g' >> "${region_name}_DataSafe_Exa_DBs.csv"
            fi
        fi
    done < "${region_name}_DataSafe_Target_List.txt"


    # Process Installed Databases
    while IFS=, read -r db_type display_name target_database_id infra_type lifecycle_state; do
        if [[ "$db_type" == "\"INSTALLED_DATABASE\"" ]]; then
            # Fetch database details
            database_details=$(oci data-safe target-database get --target-database-id $(echo $target_database_id | tr -d '"'))
            # Extract main fields
                csv_line=$(echo "$database_details" | jq -r '[
            .data["database-details"]["database-type"],
            .data["display-name"],
            .data["id"],
            .data["database-details"]["infrastructure-type"],
            .data["database-details"]["listener-port"],
            (.data["database-details"]["ip-addresses"] | join(";")),
            .data["database-details"]["service-name"]
            ] | @csv')
            # Extract connection-type and add respective ID field
                connection_type=$(echo "$database_details" | jq -r '.data["connection-option"]["connection-type"]')
                
                if [[ "$connection_type" == "ONPREM_CONNECTOR" ]]; then
                    on_prem_connector_id=$(echo "$database_details" | jq -r '.data["connection-option"]["on-prem-connector-id"]')
                    echo "$region_name,$csv_line,$connection_type,$on_prem_connector_id" | sed 's/"//g' >> "${region_name}_DataSafe_Installed_DBs.csv"
                elif [[ "$connection_type" == "PRIVATE_ENDPOINT" ]]; then
                    datasafe_private_endpoint_id=$(echo "$database_details" | jq -r '.data["connection-option"]["datasafe-private-endpoint-id"]')
                    echo "$region_name,$csv_line,$connection_type,$datasafe_private_endpoint_id" | sed 's/"//g' >> "${region_name}_DataSafe_Installed_DBs.csv"
                else
                    # In case there’s no specific ID associated with the connection type
                    echo "$region_name,$csv_line,$connection_type," | sed 's/"//g' >> "${region_name}_DataSafe_Installed_DBs.csv"
                fi
        fi
    done < "${region_name}_DataSafe_Target_List.txt"
}

# Function to process the different types of DB's
process_cloud_dbs() {
    local compartmentname=$1
    local compartmentid=$2
    local region_name=$3

    # Default status
    data_safe_status="NOT_REGISTERED"
    vcn_name="null"
    vcn_id="null"

    #New logic for pluggable DBs
                # echo "New code started "
                # echo "Compaftment_name: $compartmentname , Compartment_ID: $compartmentid "
            # Get database and pluggable DBs list output relevant fields
                # Define input and output files
                file1="${region_name}_TEST_CloudDB_PluggableDBs_Output1.txt"
                file2="${region_name}_TEST_CloudDBs_List.txt"
                file3="${region_name}_CloudDB_Output1.txt"

                echo "cdb_id,pdb_id,pdb_name" > "$file1"
                echo "db_name,db_system_id,db_id,pdbname,vm_cluster_id" > "$file2"
                # echo "db_name,db_system_id,pdb_id,db_id,pdb_name,vm_cluster_id" > "$file3"
                # Clear or create the output file
                        > "$file3"

                # Get pluggable DBs list
                oci db pluggable-database list --compartment-id "$compartmentid" | jq -r '.data[] | [.["container-database-id"], .id, .["pdb-name"]] | @csv' | sed 's/"//g' >> "$file1"
                        # echo "get pluggable dbs list"
                        # echo "Compaftment_name: $compartmentname , Compartment_ID: $compartmentid "
                        # Get database list
                oci db database list --compartment-id "$compartmentid" | jq -r '.data[] | [.["db-name"] // "null", .["db-system-id"] // "null", .["id"] // "null", .["pdb-name"] // "null", .["vm-cluster-id"] // "null"] | @csv' | sed 's/"//g' >> "$file2"
                    # echo "get database list "
                    # echo "Compaftment_name: $compartmentname , Compartment_ID: $compartmentid "
                        # Processing for consolidated DBs list
                while IFS=, read -r cdb_id pdb_id pdb_name; do
                # Skip if the line does not have enough columns
                if [ -z "$cdb_id" ] || [ -z "$pdb_id" ] || [ -z "$pdb_name" ]; then
                continue
                fi
                # Find matching lines in File_2.txt based on the 3rd value (db_id)
                while IFS=, read -r db_name db_system_id db_id pdbname vm_cluster_id; do
                if [ "$db_id" == "$cdb_id" ]; then
                # Combine values from File_1.txt and File_2.txt
                echo "$db_name,$db_system_id,$pdb_id,$db_id,$pdb_name,$vm_cluster_id" >> "$file3"
                break # Stop after finding the first match in File_2.txt
                fi
                done < "$file2"
                done < "$file1"
                # echo "Compaftment_name: $compartmentname , Compartment_ID: $compartmentid "
                # echo "newcode completed"


            # Check if the output file is populated
            if [[ -s ${region_name}_CloudDB_Output1.txt ]]; then
                echo "Processing Cloud Database information for region ${region_name}..."
                # echo "Compaftment_name: $compartmentname , Compartment_ID: $compartmentid "
                while IFS=',' read -r db_name db_system_id pdbid id pdb_name vm_cluster_id; do
                    if [[ "$db_system_id" == "null" && "$vm_cluster_id" != "null" ]]; then
                        # For ExaDB entries where db-system-id is null
                        cloud_vm_cluster_data=$(oci db cloud-vm-cluster get --cloud-vm-cluster-id "$vm_cluster_id" | jq -r '.data | [.domain, .["listener-port"], .["subnet-id"], .version] | @csv' | sed 's/"//g')
                        # grab the matching vcn details from ${REGION_NAME}_vcns_subnets.csv
                        db_system_subnet_id=$(echo "$cloud_vm_cluster_data" | cut -d',' -f3)
                        db_system_vcn=$(grep -w "$db_system_subnet_id" "${region_name}_vcns_subnets.csv" | tail -n 1)  # exact match for vcn_id
                        vcn_name=$(echo "$db_system_vcn" | cut -d',' -f3)
                        vcn_id=$(echo "$db_system_vcn" | cut -d',' -f6)
                        # grab the Data Safe Status from ${region_name}_DataSafe_Exa_DBs.csv
                        match=$(grep -E "$vm_cluster_id" "${region_name}_DataSafe_Exa_DBs.csv" | grep -E "$pdb_name")
                        if [ -n "$match" ]; then
                        # Extract service-name and trim it before the first dot '.'
                        service_name=$(echo "$match" | awk -F, '{print $7}' | awk -F. '{print $1}')
                        # Check if trimmed service-name matches pdb-name
                            if [ "$service_name" == "$pdb_name" ]; then
                                data_safe_status="REGISTERED"
                            fi
                        fi
                        echo "$region_name,$compartmentname,$compartmentid,$db_name,$id,$pdb_name,$pdbid,$vm_cluster_id,$cloud_vm_cluster_data,$vcn_name,$vcn_id,$data_safe_status" >> "$CLOUD_ExaDB_OUTPUT_FILE"
                    else
                        # For BaseDB entries where db-system-id is not null
                        db_system_data=$(oci db system get --db-system-id "$db_system_id" | jq -r '.data | [.domain, .["listener-port"], .["subnet-id"], .version] | @csv' | sed 's/"//g')
                        # grab the matching vcn details from ${REGION_NAME}_vcns_subnets.csv
                        db_system_subnet_id=$(echo "$db_system_data" | cut -d',' -f3)
                        db_system_vcn=$(grep -w "$db_system_subnet_id" "${region_name}_vcns_subnets.csv" | tail -n 1)  # exact match for vcn_id
                        vcn_name=$(echo "$db_system_vcn" | cut -d',' -f3)
                        vcn_id=$(echo "$db_system_vcn" | cut -d',' -f6)
                        # grab the Data Safe Status from ${region_name}_DataSafe_Base_DBs.csv
                        match=$(grep -E "$db_system_id" "${region_name}_DataSafe_Base_DBs.csv" | grep -E "$pdb_name")
                        if [ -n "$match" ]; then
                        # Extract service-name and trim it before the first dot '.'
                        service_name=$(echo "$match" | awk -F, '{print $7}' | awk -F. '{print $1}')
                        # Check if trimmed service-name matches pdb-name
                            if [ "$service_name" == "$pdb_name" ]; then
                                data_safe_status="REGISTERED"
                            fi
                        fi
                                    # echo "Compaftment_name: $compartmentname , Compartment_ID: $compartmentid "
                        echo "$region_name,$compartmentname,$compartmentid,$db_name,$id,$pdb_name,$pdbid,$db_system_id,$db_system_data,$vcn_name,$vcn_id,$data_safe_status" >> "$CLOUD_BaseDB_OUTPUT_FILE"
                    fi
                done < "${region_name}_CloudDB_Output1.txt"
            else
                echo "No Cloud Databases found for compartment ${compartmentid}."
            fi
}
# Main script logic
# Display the current region value
echo "Current region: $OCI_REGION"

# Prompt user to choose between the current region (OCI_REGION) or all regions (ALL)
echo "Do you want to process the current region only or all regions? (Enter '${OCI_REGION}' for current region or 'ALL' for all regions):"
read REGION_CHOICE

if [[ "$REGION_CHOICE" == "ALL" ]]; then
    echo "Processing all regions..."

    # Step 1: List all regions and save to All_regions_subscription.csv
    echo "Listing all regions..."
    echo "is-home-region,region-key,region-name,status" > All_regions_subscription.csv
    oci iam region-subscription list --output json | jq -r '.data[] | "\(.["is-home-region"]),\(.["region-key"]),\(.["region-name"]),\(.status)"' >> All_regions_subscription.csv

    # Process each region from All_regions_subscription.csv
    while IFS=',' read -r is_home_region region_key region_name status; do
        echo "Switching to region ${region_name}..."
        export OCI_CONFIG_PROFILE="${region_name}"
        export PS1="\u@cloudshell:\W (${region_name})$"
        export OCI_REGION="${region_name}"
        export OCI_CLI_PROFILE="${region_name}"

        # Proceed to list compartments and databases for this region
        process_region "${region_name}"

    # done < All_regions_subscription.csv  
    done < <(tail -n +2 All_regions_subscription.csv)

elif [[ "$REGION_CHOICE" == "$OCI_REGION" ]]; then
    # Process current region without changing environment variables
    echo "Processing the current region ${OCI_REGION}..."
    process_region "${OCI_REGION}"

else
    echo "Invalid choice. Please enter '${OCI_REGION}' or 'ALL'."
    exit 1
fi

# Function to append CSV files with cumulative rows and remove double quotes
# Function to append CSV files with cumulative rows and remove double quotes
append_csv_files() {
    local file_pattern=$1
    local output_file=$2

    # Get the list of matching CSV files, excluding the output file if it matches the pattern
    csv_files=($(ls $file_pattern 2>/dev/null | grep -v "$output_file"))

    # Check if no files are found
    if [ ${#csv_files[@]} -eq 0 ]; then
        echo "No files matching $file_pattern found."
        return
    fi

    # If only one file is found, copy it directly to the output without processing
    if [ ${#csv_files[@]} -eq 1 ]; then
        # cp "${csv_files[0]}" "$output_file"
        #echo "Skip the files to appened due to csv files related to only one region."
        sleep 1
        return
    fi

    # Clear the output file if it exists
    > "$output_file"

    # Write the header from the first file to the output file
    header_file="${csv_files[0]}"
    header=$(head -n 1 "$header_file")
    if [ -n "$header" ]; then
        echo "$header" | sed 's/"//g' >> "$output_file"
    else
        echo "Error: Header is empty or could not be read from $header_file"
        return
    fi

    # Append data from all files, excluding headers after the first file
    for csv_file in "${csv_files[@]}"; do
        tail -n +2 "$csv_file" | sed 's/"//g' >> "$output_file"
    done

    # echo "Files matching $file_pattern have been combined into $output_file with headers and double quotes handled."
    echo "Appended all CSV files with cumulative rows across all regions."
}

# Append files for each category
append_csv_files "*_compartments.csv" "All_Regions_compartments.csv"
append_csv_files "*_vcns_subnets.csv" "All_Regions_VCNs_Subnets.csv"
append_csv_files "*_Private_Endpoints.csv" "All_Regions_Private_Endpoints.csv"
append_csv_files "*_OnPrem_Connectors.csv" "All_Regions_OnPrem_Connectors.csv"
append_csv_files "*_DataSafe_Cloud_DBs.csv" "All_Regions_DataSafe_Cloud_DBs.csv"
append_csv_files "*_DataSafe_Base_DBs.csv" "All_Regions_DataSafe_Base_DBs.csv"
append_csv_files "*_DataSafe_Exa_DBs.csv" "All_Regions_DataSafe_Exa_DBs.csv"
append_csv_files "*_DataSafe_Autonomous_DBs.csv" "All_Regions_DataSafe_Autonomous_DBs.csv"
append_csv_files "*_DataSafe_Installed_DBs.csv" "All_Regions_DataSafe_Installed_DBs.csv"
append_csv_files "*_DS_Reg_Autonomous_Databases.csv" "All_Regions_DS_Reg_Autonomous_Databases.csv"
append_csv_files "*_DS_Reg_Base_Databases.csv" "All_Regions_DS_Reg_Base_Databases.csv"
append_csv_files "*_DS_Reg_EXADATA_Databases.csv" "All_Regions_DS_Reg_EXADATA_Databases.csv"
append_csv_files "*_DS_Reg_On-Premises_Databases.csv" "All_Regions_DS_Reg_On-Premises_Databases.csv"
append_csv_files "*_Cloud_PDB_Connect_Strings.csv" "All_Regions_Cloud_PDB_Connect_Strings.csv"
append_csv_files "*_Cloud_BaseDatabases.csv" "All_Regions_Cloud_BaseDatabases.csv"
append_csv_files "*_Cloud_ExaDatabases.csv" "All_Regions_Cloud_ExaDatabases.csv"
append_csv_files "*_Cloud_AutonomousDBs.csv" "All_Regions_Cloud_AutonomousDBs.csv"



echo "Script execution Completed"