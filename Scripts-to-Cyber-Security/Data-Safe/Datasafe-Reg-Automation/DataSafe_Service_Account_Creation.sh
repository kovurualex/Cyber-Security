
#!/bin/bash

# Function to sort CSV and generate region and VCN-specific files
process_sort_csv() {
    local csv_file="$1"

    if [[ ! -f "$csv_file" ]]; then
        echo "CSV file $csv_file not found!"
        exit 1
    fi

    local sorted_file="sorted_ds_sa_${csv_file}"

    # Extract the header
    local header
    header=$(head -n 1 "$csv_file")

    # Skip header, sort by region and vcn_name
    tail -n +2 "$csv_file" | sort -t, -k1,1 -k9,9 > "$sorted_file"

    # Extract unique regions and process
    while read -r region; do
        local region_csv_file="${region}_sorted_ds_sa_${csv_file}"
        echo "$header" > "$region_csv_file"  # Add header to region-specific file
        grep "^${region}," "$sorted_file" >> "$region_csv_file"
        echo "Generated file: $region_csv_file"

        # Extract unique VCN names for the region
        while read -r vcn_name; do
            vcnnameshort=$(echo "$vcn_name" | sed 's/ //g')
            local vcn_csv_file="${region}_${vcnnameshort}-sorted_ds_sa_${csv_file}"
            echo "$header" > "$vcn_csv_file"  # Add header to VCN-specific file
            grep "^${region},.*${vcn_name}," "$sorted_file" >> "$vcn_csv_file"
            echo "Generated file: $vcn_csv_file"
        done < <(grep "^${region}," "$sorted_file" | cut -d',' -f9 | sort -u)
    done < <(cut -d',' -f1 "$sorted_file" | sort -u)

    echo "Generated all region-specific and VCN-specific files."
    ls -ltr *-sorted_ds_sa_*.csv | awk '{print $9}' > vcn_files_list.txt
}


# Function to create Data Safe Service Account
    cat > Datasafe_SA_Creation.sh <<- 'EOM'
        #!/bin/bash

    if [[ -z "$1" ]]; then
        echo "Usage: $0 <input_file>"
        exit 1
    fi

    input_file="$1"
    dsprivsql="datasafe_privileges.sql"

    if [[ ! -f "$dsprivsql" ]]; then
        echo "File $dsprivsql not found!"
        exit 1
    fi

    if [[ ! -f "$input_file" ]]; then
        echo "Input file $input_file not found!"
        exit 1
    fi

    # Process each line in the input CSV
    tail -n +2 "$input_file" | while IFS=',' read -r region connect_string db_name pdb_name sys_user sys_password datasafe_service_account datasafe_service_account_password vcn_name subnet_name vcn_id subnet_id; do
        echo "Processing: Region=$region, DB=$db_name, PDB=$pdb_name, User=$datasafe_service_account"
        
        conn_str="$sys_user/$sys_password@$connect_string as sysdba"
        spool_file="${pdb_name}_info.txt"

        sqlplus -s "$conn_str" <<-EOF
        spool $spool_file
        set pagesize 20
        set linesize 300
        SELECT PDB_ID, PDB_NAME, STATUS FROM DBA_PDBS;

        CREATE USER "$datasafe_service_account" IDENTIFIED BY "$datasafe_service_account_password";
        GRANT CONNECT, RESOURCE TO "$datasafe_service_account";
        SELECT username, account_status FROM dba_users WHERE LOWER(username) = LOWER('$datasafe_service_account');

        @$dsprivsql "$datasafe_service_account" GRANT ALL
        spool off
EOF
    done
    
EOM

chmod +x Datasafe_SA_Creation.sh    

# Function for handling Method 1: Execute process with single input file
handle_method1() {
    local inputfile1=$1
    echo "Executing process_ds_user_creation for each entry in $inputfile1."
    chmod +x Datasafe_SA_Creation.sh
    echo " Execuet the script ./Datasafe_SA_Creation.sh $inputfile1 "
}

# Function for handling Method 2: execute process for each vcn catagoraised inputfiles
handle_method2() {
    local inputfile1=$1
    local inputfile2=$(tail -n 1 "$1")

    chmod +x Datasafe_SA_Creation.sh
    echo " **** Instructions ***"
    echo " Configure Cloud Shell for VCN and subnet access via Ephemeral Private Network Setup in the OCI console."
    echo " For each VCN, ensure the network is configured appropriately based on the corresponding input files."
    echo " Ensure that only VCNs, subnets, and Network Security Groups (NSGs) within your home region are configured."
    echo " If access to subnets in regions outside your home region is required, configure peering to enable connectivity from the private network."
    echo " Run for each VCN from $inputfile1: ./ Datasafe_SA_Creation.sh $inputfile2 "

}


# Main script starts here
echo "Select the type of Database to create Data Safe Service Account:"
echo "1. Cloud Base Databases"
echo "2. Cloud Exadata Databases"
echo "3. On-premises Databases"
read -rp "Enter your choice (1/2/3): " choice
read -rp "Enter sys password: " syspass
read -rp "Enter the desired Datasafe service account password: " dssapass


# Determine CSV file based on choice
case $choice in
    1)
        # CSV processing logic for choice 1...
        # Input and output CSV files
        input_csv="All_Regions_DS_Reg_Base_Databases.csv"
        input_csv2="All_Regions_Cloud_PDB_Connect_Strings.csv"
        input_csv3="All_Regions_Cloud_BaseDatabases.csv"
        input_csv4="All_Regions_VCNs_Subnets.csv"
        output_csv="Base_Databases_Connections.csv"
        sysuser="sys"
        dssauser="DATASAFEADMIN"
        

        # Input files details (log for documentation)
        #echo "All_Regions_DS_Reg_Base_Databases.csv - Headers: region,DB_NAME,dbsystem-id,PDB_Name,serviceName,listenerPort,compartment_name,compartment-id,connectivity_option_Name,connectivity_option_ID,userName,Password,Data_Safe_Display_Name"
        #echo "All_Regions_Cloud_BaseDatabases.csv - Headers: region,compartment-name,compartment-id,db-name,id,pdb_name,pdbid,db-system-id,domain,listener-port,subnet-id,db-version,vcn_name,vcn_id,data_safe_status"
        #echo "All_Regions_Cloud_PDB_Connect_Strings.csv - Headers: region,compartment-name,compartment-id,pdb_name,pdb_id,container_database_id,connect_string"
        #echo "All_Regions_VCNs_Subnets.csv - Headers: region,compartment_name,pe_name,vcn_name,subnet_name,compartment_id,pe_id,vcn_id,subnet_id"

        # Prepare the output CSV file with necessary headers
        echo "region,connect_string,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,vcn_name,subnet_name,vcn_id,subnet_id" > "$output_csv"

        # Check if input file exists
        if [[ ! -f "$input_csv" ]]; then
            echo "Error: Input file $input_csv not found!"
            exit 1
        fi

        # Process the input CSV
        while IFS=',' read -r region DB_NAME dbsystem_id PDB_Name serviceName listenerPort compartment_name compartment_id connectivity_option_Name connectivity_option_ID userName Password Data_Safe_Display_Name; do
            # Skip header row
            if [[ "$region" == "region" ]]; then
                continue
            fi

            # Fetch PDB data
            pdb_data=$(grep -w "$dbsystem_id" "$input_csv3" | grep -w "$PDB_Name" | tail -n 1)
            if [[ -z "$pdb_data" ]]; then
                echo "Warning: No matching PDB data found for dbsystem-id=$dbsystem_id, PDB_Name=$PDB_Name"
                continue
            fi
            pdbid=$(echo "$pdb_data" | cut -d',' -f7)
            subnetid=$(echo "$pdb_data" | cut -d',' -f11)

            # Fetch network data
            network_data=$(grep -w "$subnetid" "$input_csv4" | tail -n 1)
            if [[ -z "$network_data" ]]; then
                echo "Warning: No matching network data found for subnet-id=$subnetid"
                continue
            fi
            vcnname=$(echo "$network_data" | cut -d',' -f3)
            vcnid=$(echo "$network_data" | cut -d',' -f6)
            subnetname=$(echo "$network_data" | cut -d',' -f4)

            # Fetch PDB connection string
            pdb_connect_data=$(grep -w "$pdbid" "$input_csv2" | tail -n 1)
            if [[ -z "$pdb_connect_data" ]]; then
                echo "Warning: No matching connection string found for pdb-id=$pdbid"
                continue
            fi
            pdb_conn_string=$(echo "$pdb_connect_data" | cut -d',' -f7)

            # Append to output CSV
            echo "$region,$pdb_conn_string,$DB_NAME,$PDB_Name,$sysuser,$syspass,$dssauser,$dssapass,$vcnname,$subnetname,$vcnid,$subnetid" >> "$output_csv"

        done < "$input_csv"

        echo "sample Base_Databases_Connections.csv : headers - region,connect_string,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,vcn_name,subnet_name,vcn_id,subnet_id"
        echo "Prepared $output_csv Please cross-verify and update any fields as necessary."
        read -rp "Provide the path to the updated CSV file: " outputcsv
        ;;
    2)

        # CSV processing logic for choice 2...
        # Input and output CSV files
        input_csv="All_Regions_DS_Reg_EXADATA_Databases.csv"
        input_csv2="All_Regions_Cloud_PDB_Connect_Strings.csv"
        input_csv3="All_Regions_Cloud_ExaDatabases.csv"
        input_csv4="All_Regions_VCNs_Subnets.csv"
        output_csv="Exadata_Databases_Connections.csv"
        sysuser="sys"
        dssauser="DATASAFEADMIN"

        # Input files details (log for documentation)
        #echo "All_Regions_DS_Reg_EXADATA_Databases.csv - Headers: region,DB_Name,vm-cluster-id,PDB_Name,serviceName,listenerPort,compartment_name,compartment-id,connectivity_option_Name,connectivity_option_ID,userName,Password,Data_Safe_Display_Name"
        #echo "All_Regions_Cloud_ExaDatabases.csv - Headers: region,compartment-name,compartment-id,db-name,id,pdb_name,pdbid,vm-cluster-id,domain,listener-port,subnet-id,db-version,vcn_name,vcn_id,data_safe_status"
        #echo "All_Regions_Cloud_PDB_Connect_Strings.csv - Headers: region,compartment-name,compartment-id,pdb_name,pdb_id,container_database_id,connect_string"
        #echo "All_Regions_VCNs_Subnets.csv - Headers: region,compartment_name,pe_name,vcn_name,subnet_name,compartment_id,pe_id,vcn_id,subnet_id"

        # Prepare the output CSV file with necessary headers
        echo "region,connect_string,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,vcn_name,subnet_name,vcn_id,subnet_id" > "$output_csv"

        # Check if input file exists
        if [[ ! -f "$input_csv" ]]; then
            echo "Error: Input file $input_csv not found!"
            exit 1
        fi

        # Process the input CSV
        while IFS=',' read -r region DB_Name vm_cluster_id PDB_Name serviceName listenerPort compartment_name compartment_id connectivity_option_Name connectivity_option_ID userName Password Data_Safe_Display_Name; do
            # Skip header row
            if [[ "$region" == "region" ]]; then
                continue
            fi

            # Fetch PDB data
            pdb_data=$(grep -w "$vm_cluster_id" "$input_csv3" | grep -w "$PDB_Name" | tail -n 1)
            if [[ -z "$pdb_data" ]]; then
                echo "Warning: No matching PDB data found for dbsystem-id=$vm_cluster_id, PDB_Name=$PDB_Name"
                continue
            fi
            pdbid=$(echo "$pdb_data" | cut -d',' -f7)
            subnetid=$(echo "$pdb_data" | cut -d',' -f11)

            # Fetch network data
            network_data=$(grep -w "$subnetid" "$input_csv4" | tail -n 1)
            if [[ -z "$network_data" ]]; then
                echo "Warning: No matching network data found for subnet-id=$subnetid"
                continue
            fi
            vcnname=$(echo "$network_data" | cut -d',' -f3)
            vcnid=$(echo "$network_data" | cut -d',' -f6)
            subnetname=$(echo "$network_data" | cut -d',' -f4)

            # Fetch PDB connection string
            pdb_connect_data=$(grep -w "$pdbid" "$input_csv2" | tail -n 1)
            if [[ -z "$pdb_connect_data" ]]; then
                echo "Warning: No matching connection string found for pdb-id=$pdbid"
                continue
            fi
            pdb_conn_string=$(echo "$pdb_connect_data" | cut -d',' -f7)

            # Append to output CSV
            echo "$region,$pdb_conn_string,$DB_NAME,$PDB_Name,$sysuser,$syspass,$dssauser,$dssapass,$vcnname,$subnetname,$vcnid,$subnetid" >> "$output_csv"

        done < "$input_csv"
        echo "Prepared $output_csv Please cross-verify and update any fields as necessary."
        read -rp "Provide the path to the updated CSV file: " outputcsv
        ;;
    3)
        # CSV processing logic for choice 3...
        input_csv="All_Regions_DS_Reg_On-Premises_Databases.csv"
        output_csv="On-Premises_Databases_Connections.csv"
        sysuser="sys"
        dssauser="DATASAFEADMIN"
        # Prepare the output CSV file with necessary headers
        echo "region,connect_string,db_name,pdb_name,sys_user,sys_password,datasafe_service_account,datasafe_service_account_password,vcn_name,subnet_name,vcn_id,subnet_id" > "$output_csv"
        while IFS=',' read -r region db_name pdb_name service_name listenerPort DB_HOST_IP compartment_name compartment_id connectivity_option_name connectivity_option_id username password data_safe_display_name; do
        if [[ ! -f "$input_csv" ]]; then
            echo "File $input_csv not found!"
        else
            echo "File $input_csv found!"
            echo "generated the $output_csv with available details"
            conn_string=$DB_HOST_IP:listenerPort/$service_name
            echo "$region,$conn_string,${db_name},${pdb_name},$sysuser,$syspass,$dssauser,$dssapass,,,, " >> "$output_csv"
        fi
        done < "$input_csv"
        echo "Prepared $output_csv Please cross-verify and update any fields as necessary."
        read -rp "Provide the path to the updated CSV file: " outputcsv
        ;;
    *)
        echo "Invalid choice."
        exit 1
        ;;
esac

if [[ ! -f "$input_csv" ]]; then
    echo "Input file $input_csv not found!"
    exit 1
fi

# Prompt user for their method
echo "Which method would you like to use to create the Data Safe service account?"
echo "  Method 1: Existing setup - Bastion Server"
echo "  Method 2: Cloud Shell"
read -rp "Please enter your choice (1 or 2): " choicemethod

# Validate the choice and invoke process_sort_csv if choicemethod is "2"
case $choicemethod in
    1)
        echo "You selected Method 1: Bastion Host or Jump Server."
        # Add commands for Method 1 here
        handle_method1 $outputcsv
        ;;
    2)
        echo "You selected Method 2: Cloud Shell or OCI CLI - configured VM instance."
        process_sort_csv "$outputcsv"
        # Add commands for Method 2 here
        handle_method2 "vcn_files_list.txt"
        ;;
    *)
        echo "Invalid choice. Please enter 1 or 2."
        ;;
esac


