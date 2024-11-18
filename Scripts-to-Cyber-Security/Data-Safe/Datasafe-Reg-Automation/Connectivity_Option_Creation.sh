#!/bin/bash

# Function to process and sort CSV by region, generating region-specific sorted files
process_sort_csv() {
    local csv_file=$1
    local sorted_file="sorted_ds_co_$csv_file"

    if [[ ! -f "$csv_file" ]]; then
        echo "CSV file $csv_file not found!"
        exit 1
    fi

    tail -n +2 "$csv_file" | sort -t, -k1,1 > "$sorted_file"
    local regions=$(cut -d',' -f1 "$sorted_file" | sort -u)

    for region in $regions; do
        local region_csv_file="${region}_sorted_${csv_file}"
        grep "^${region}," "$sorted_file" > "$region_csv_file"
        echo "Generated file: $region_csv_file"
    done

    echo "Region-specific CSV files created:"
    ls -ltr *_sorted_ds_co_*.csv
}

# Step 1: Prompt for connectivity option
echo "Select the connectivity option to create:"
echo "1. Private Endpoints"
echo "2. On-premises Connectors"
read -p "Enter choice (1 or 2): " choice

# Step 2: Process based on the user's choice
if [[ "$choice" -eq 1 ]]; then
    # Private Endpoints
    if [[ -f "All_Regions_Private_Endpoints.csv" ]]; then
        if [[ -f "All_Regions_Cloud_BaseDatabases.csv" || -f "All_Regions_Cloud_ExaDatabases.csv" ]]; then
            echo "Preparing All_region_Create_PE.csv for creating Private Endpoints..."
            output_file="All_region_Create_PE.csv"
            echo "region,compartment_name,pe_name,vcn_name,subnet_name,compartment_id,vcn_id,subnet_id" > "$output_file"

            # Process Cloud Base Databases
            if [[ -f "All_Regions_Cloud_BaseDatabases.csv" ]]; then
                while IFS=',' read -r region compartment_name compartment_id db_name db_id pdb_name pdbid db_system_id domain listener_port subnet_id db_version vcn_name vcn_id data_safe_status; do
                    if ! grep -q ",$subnet_id$" All_Regions_Private_Endpoints.csv; then
                        pe_display_name="PE_$vcn_name"
                        echo "$region,$compartment_name,$pe_display_name,$vcn_name,,${compartment_id},${vcn_id},${subnet_id}" >> "$output_file"
                    fi
                done < <(tail -n +2 All_Regions_Cloud_BaseDatabases.csv)
            fi

            # Process Cloud Exadata Databases
            if [[ -f "All_Regions_Cloud_ExaDatabases.csv" ]]; then
                while IFS=',' read -r region compartment_name compartment_id db_name db_id pdb_name pdbid vm_cluster_id domain listener_port subnet_id db_version vcn_name vcn_id data_safe_status; do
                    if ! grep -q ",$subnet_id$" All_Regions_Private_Endpoints.csv; then
                        pe_display_name="PE_$vcn_name"
                        echo "$region,$compartment_name,$pe_display_name,$vcn_name,,${compartment_id},${vcn_id},${subnet_id}" >> "$output_file"
                    fi
                done < <(tail -n +2 All_Regions_Cloud_ExaDatabases.csv)
            fi

            echo "All_region_Create_PE.csv file has been created."
        else
            echo "Required file (All_Regions_Cloud_BaseDatabases.csv or All_Regions_Cloud_ExaDatabases.csv) not found. Exiting."
            exit 1
        fi
    else
        echo "File All_Regions_Private_Endpoints.csv not found. Exiting."
        exit 1
    fi
    echo "sample file All_Regions_Private_Endpoints.csv : headers - region,compartment_name,pe_name,vcn_name,subnet_name,compartment_id,vcn_id,subnet_id"
    read -p "Enter the file path for All_Regions_Private_Endpoints.csv - Please update all fields as necessary: " private_endpoints_file
    process_sort_csv "$private_endpoints_file"

elif [[ "$choice" -eq 2 ]]; then
    # On-premises Connectors chosen
    echo "sample file All_region_Create_ON_Prem_C.csv : header - region,compartment_name,compartment_id"
    echo "region,compartment_name,compartment_id" > All_region_Create_ON_Prem_C.csv
    read -p "Enter the file path for All_region_Create_ON_Prem_C.csv - Please update all fields as necessary: " on_prem_file
    process_sort_csv "$on_prem_file"
else
    echo "Invalid choice."
    exit 1
fi

# Get the current OCI region
echo "Current OCI region: $OCI_REGION"
current_region=$OCI_REGION

# Process to create connectivity option
for region_csv_file in *_sorted_ds_co_*.csv; do
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

    if [[ "$choice" -eq 1 ]]; then
        while IFS=',' read -r region compartment_name pe_name vcn_name subnet_name compartment_id vcn_id subnet_id; do
            oci data-safe private-endpoint create --compartment-id "$compartment_id" --display-name "$pe_name" --subnet-id "$subnet_id" --vcn-id "$vcn_id"
        done < "$region_csv_file"
    elif [[ "$choice" -eq 2 ]]; then
        echo "Creating On-premises Connectors for current region..."
        while IFS=',' read -r region compartment_name compartment_id; do
            if [[ "$region" == "$current_region" ]]; then
                oci data-safe on-prem-connector create --compartment-id "$compartment_id"
            fi
        done < "$region_csv_file"
    fi
done

echo "Script execution completed."
