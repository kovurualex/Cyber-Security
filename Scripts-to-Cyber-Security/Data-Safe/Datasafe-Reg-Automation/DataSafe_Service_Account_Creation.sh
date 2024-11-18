#!/bin/bash

# Function to process - Sort the CSV by region and generate region-specific sorted CSV files
process_sort_csv() {
    local csv_file=$1
    local sorted_file="sorted_ds_sa_$csv_file"

    if [[ ! -f "$csv_file" ]]; then
        echo "CSV file $csv_file not found!"
        exit 1
    fi

    # Skip header, sort, and save sorted entries in 'sorted_ds_sa_$csv_file'
    tail -n +2 "$csv_file" | sort -t, -k1,1 > "$sorted_file"
    regions=$(cut -d',' -f1 "$sorted_file" | sort -u)

    # Generate region-wise sorted CSV files for each unique region
    for region in $regions; do
        region_csv_file="${region}_sorted_${csv_file}"
        grep "^${region}," "$sorted_file" > "$region_csv_file"
        echo "Generated file: $region_csv_file"
    done

    echo "Region-specific CSV files created:"
    ls -ltr *_sorted_ds_sa_*.csv
}

# Function to process Data Safe user creation on each database
process_ds_user_creation() {
    local dsprivsql=$1

    for region_csv_file in *_sorted_ds_sa_*.csv; do
        region=$(echo "$region_csv_file" | cut -d'_' -f1)

        if [[ "$region" == "$OCI_REGION" ]]; then
            echo "Processing CSV file for the current region: $region_csv_file"
        else
            echo "Switching to region ${region}..."
            export OCI_CONFIG_PROFILE="${region}"
            export PS1="\u@cloudshell:\W (${region})$"
            export OCI_REGION="${region}"
            export OCI_CLI_PROFILE="${region}"
            
        fi

        while IFS=',' read -r region host_ip_address db_name pdb_name sys_user sys_password datasafe_service_account datasafe_service_account_password listener_port service_name; do
            conn_str="$sys_user/$sys_password@$host_ip_address:$listener_port/$service_name as sysdba"
            spool_file="${pdb_name}_info.txt"

            sqlplus -s "$conn_str" <<EOF
                spool $spool_file
                set pagesize 20
                set linesize 300
                SELECT PDB_ID, PDB_NAME, STATUS FROM DBA_PDBS;

                CREATE USER $datasafe_service_account IDENTIFIED BY "$datasafe_service_account_password";
                GRANT CONNECT, RESOURCE TO $datasafe_service_account;
                SELECT username, account_status FROM dba_users WHERE LOWER(username) = LOWER('$datasafe_service_account');

                @$dsprivsql $datasafe_service_account GRANT ALL
                spool off
EOF
            if [[ $? -eq 0 ]]; then
                echo "SQL commands executed successfully for PDB: $pdb_name"
            else
                echo "SQL command execution failed for PDB: $pdb_name"
            fi
        done < "$region_csv_file"
    done 
}

# Main script starts here

echo "Select the type of Data Safe Service Account creation:"
echo "1. Cloud Base Databases"
echo "2. Cloud Exadata Databases"
echo "3. On-premises Databases"
read -rp "Enter your choice (1/2/3): " choice

# Determine CSV file based on choice
case $choice in
    1)
        input_csv="All_Regions_DS_Reg_Base_Databases.csv"
        output_csv="Base_Databases_Connections.csv"
        # Prepare the output CSV file with necessary headers
        echo "region,host_ip_address,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,listener_port,service_name" > "$output_csv"
        while IFS=',' read -r region DB_NAME dbsystem_id PDB_Name serviceName listenerPort compartment_name compartment_id connectivity_option_Name connectivity_option_ID userName Password Data_Safe_Display_Name; do
        if [[ ! -f "$input_csv" ]]; then
            echo "File $input_csv not found!"
            echo "Prepared the $output_csv "
        else
            #echo "File $input_csv found!"
            #echo "generated the $output_csv with available details"
            echo "$region,,${db_name},${pdb_name},,,,,${listener_port},${service_name}" >> "$output_csv"
        fi
        done < "$input_csv"
        echo "sample Base_Databases_Connections.csv : headers - region,host_ip_address,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,listener_port,service_name"
        echo "Prepared $output_csv. Please update all fields as necessary."
        read -rp "Provide the path to the updated CSV file: " outputcsv
        process_sort_csv "$outputcsv"
        ;;
    2)
        input_csv="All_Regions_DS_Reg_EXADATA_Databases.csv"
        output_csv="Exadata_Databases_Connections.csv"
        # Prepare the output CSV file with necessary headers
        echo "region,host_ip_address,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,listener_port,service_name" > "$output_csv"
        while IFS=',' read -r region DB_Name vm_cluster_id PDB_Name serviceName listenerPort compartment_name compartment-id connectivity_option_Name connectivity_option_ID userName Password Data_Safe_Display_Name; do
        if [[ ! -f "$input_csv" ]]; then
            echo "File $input_csv not found!"
            echo "Prepared the $output_csv "
        else
            echo "File $input_csv found!"
            echo "generated the $output_csv with available details"
            echo "$region,,${db_name},${pdb_name},,,,,${listener_port},${service_name}" >> "$output_csv"
        fi
        done < "$input_csv"
        echo "Prepared $output_csv. Please update all fields as necessary."
        read -rp "Provide the path to the updated CSV file: " outputcsv
        process_sort_csv "$outputcsv"
        ;;
    3)
        input_csv="All_Regions_DS_Reg_On-Premises_Databases.csv"
        output_csv="On-Premises_Databases_Connections.csv"
        # Prepare the output CSV file with necessary headers
        echo "region,host_ip_address,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,listener_port,service_name" > "$output_csv"
        while IFS=',' read -r region db_name pdb_name service_name listenerPort DB_HOST_IP compartment_name compartment_id connectivity_option_name connectivity_option_id username password data_safe_display_name; do
        if [[ ! -f "$input_csv" ]]; then
            echo "File $input_csv not found!"
            echo "Prepared the $output_csv "
        else
            echo "File $input_csv found!"
            echo "generated the $output_csv with available details"
            echo "$region,$DB_HOST_IP,${db_name},${pdb_name},,,,,${listener_port},${service_name}" >> "$output_csv"
        fi
        done < "$input_csv"
        echo "Prepared $output_csv. Please update all fields as necessary."
        read -rp "Provide the path to the updated CSV file: " outputcsv
        process_sort_csv "$outputcsv"
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

# Check if datasafe_privileges.sql file is present
ds_priv_sql="datasafe_privileges.sql"
if [[ ! -f "$ds_priv_sql" ]]; then
    echo "File $ds_priv_sql not found!"
    read -rp "Please provide the path to datasafe_privileges.sql: " ds_priv_sql
fi
process_ds_user_creation "$ds_priv_sql"

echo "Script execution completed."
