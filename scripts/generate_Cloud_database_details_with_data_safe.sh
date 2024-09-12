#!/bin/bash
# Script Name: generate_dbaas_datasafe_integration.sh
# Purpose: Automate listing of DBaaS databases, subnet extraction, and Data Safe target DB registration.

# Step 1: Prompt for the compartment-id
read -p "Enter the Compartment ID: " compartment_id

# Step 2: List DBaaS databases and store details in Output1.txt (Removed '--all')
oci db database list --compartment-id $compartment_id | jq -r '.data[] | [(.["db-name"] // "null"), (.["db-system-id"] // "null"), (.["sid-prefix"] // "null"), (.["id"] // "null"), (.["pdb-name"] // "null"), (.["vm-cluster-id"] // "null")] | @csv' > Output1.txt

# Step 3: Process entries with 'vm-cluster-id' as null and append 'subnet-id'
touch Output_with_subnet.txt  # Create temporary output file

while IFS=',' read -r db_name db_system_id sid_prefix db_id pdb_name vm_cluster_id
do
  db_system_id=$(echo $db_system_id | tr -d '"' | xargs)  # Remove extra quotes and spaces from DB system ID
  vm_cluster_id=$(echo $vm_cluster_id | tr -d '"' | xargs)  # Remove extra quotes and spaces from VM cluster ID
  db_name=$(echo $db_name | tr -d '"' | xargs)  # Clean $db_name
  sid_prefix=$(echo $sid_prefix | tr -d '"' | xargs)  # Clean $sid_prefix
  db_id=$(echo $db_id | tr -d '"' | xargs)  # Clean $db_id
  pdb_name=$(echo $pdb_name | tr -d '"' | xargs)  # Clean $pdb_name
  
  if [[ "$vm_cluster_id" == "null" ]] && [[ "$db_system_id" != "null" ]]; then
    subnet_id=$(oci db system get --db-system-id "$db_system_id" | jq -r '.data["subnet-id"]')
    if [ -z "$subnet_id" ]; then
      subnet_id="null"
    fi
    echo "${db_name},${db_system_id},${sid_prefix},${db_id},${pdb_name},${vm_cluster_id},${subnet_id}" >> Output_with_subnet.txt
  else
    echo "${db_name},${db_system_id},${sid_prefix},${db_id},${pdb_name},${vm_cluster_id},null" >> Output_with_subnet.txt
  fi
done < Output1.txt

# Step 4: Process entries with 'db-system-id' as null and append 'subnet-id'
while IFS=',' read -r db_name db_system_id sid_prefix db_id pdb_name vm_cluster_id
do
  db_system_id=$(echo $db_system_id | tr -d '"' | xargs)
  vm_cluster_id=$(echo $vm_cluster_id | tr -d '"' | xargs)
  db_name=$(echo $db_name | tr -d '"' | xargs)
  sid_prefix=$(echo $sid_prefix | tr -d '"' | xargs)
  db_id=$(echo $db_id | tr -d '"' | xargs)
  pdb_name=$(echo $pdb_name | tr -d '"' | xargs)
  
  if [[ "$db_system_id" == "null" ]] && [[ "$vm_cluster_id" != "null" ]]; then
    subnet_id=$(oci db cloud-vm-cluster get --cloud-vm-cluster-id "$vm_cluster_id" | jq -r '.data["subnet-id"]')
    if [ -z "$subnet_id" ]; then
      subnet_id="null"
    fi
    echo "${db_name},${db_system_id},${sid_prefix},${db_id},${pdb_name},${vm_cluster_id},${subnet_id}" >> Output_with_subnet.txt
  fi
done < Output1.txt

# Step 5: Save final list of DBaaS databases with subnet IDs to CSV file
mv Output_with_subnet.txt Oracle_Cloud_Databases_Details.csv

# Step 6: List Data Safe private endpoints and save to Datasafe_Private-Endpoint_List.txt
oci data-safe private-endpoint list --compartment-id $compartment_id --all | jq -r '.data[] | [.["display-name"], .id, .["vcn-id"], .["subnet-id"]] | @csv' > Datasafe_Private-Endpoint_List.txt

# Step 7: Generate JSON file for each DBaaS 'pdb-name'
while IFS=',' read -r db_name db_system_id sid_prefix db_id pdb_name vm_cluster_id subnet_id
do
  # Clean up input values
  db_system_id=$(echo $db_system_id | tr -d '"' | xargs)
  vm_cluster_id=$(echo $vm_cluster_id | tr -d '"' | xargs)
  db_name=$(echo $db_name | tr -d '"' | xargs)
  sid_prefix=$(echo $sid_prefix | tr -d '"' | xargs)
  db_id=$(echo $db_id | tr -d '"' | xargs)
  pdb_name=$(echo $pdb_name | tr -d '"' | xargs)
  subnet_id=$(echo $subnet_id | tr -d '"' | xargs)

  # Handle null values correctly
  if [ "$vm_cluster_id" == "null" ]; then
    vm_cluster_id="null"
  else
    vm_cluster_id="\"$vm_cluster_id\""
  fi

  if [ "$subnet_id" == "null" ]; then
    subnet_id="null"
  else
    subnet_id="\"$subnet_id\""
  fi

  # Generate JSON file
  cat <<EOF > "database-details_${pdb_name}.json"
{
  "databaseType": "DATABASE_CLOUD_SERVICE",
  "dbSystemId": "$db_system_id",
  "infrastructureType": "ORACLE_CLOUD",
  "listenerPort": 1521,
  "serviceName": "${pdb_name}.sub10121249210.dbsecvcn.oraclevcn.com",
  "vmClusterId": $vm_cluster_id
}
EOF

done < Oracle_Cloud_Databases_Details.csv

# Step 8: Generate Data Safe target DB registration command and append to the script file 'Datasafe_CloudDB_Registration_Commands.sh'
output_script="Datasafe_CloudDB_Registration_Commands.sh"

# Create the script file and add a shebang at the beginning
echo "#!/bin/bash" > $output_script

while IFS=',' read -r pe_display_name pe_id vcn_id pe_subnet_id
do
  # Clean up input values
  pe_display_name=$(echo $pe_display_name | tr -d '"' | xargs)
  pe_subnet_id=$(echo $pe_subnet_id | tr -d '"' | xargs)

  while IFS=',' read -r db_name db_system_id sid_prefix db_id pdb_name vm_cluster_id subnet_id
  do
    # Clean up input values
    db_name=$(echo $db_name | tr -d '"' | xargs)
    db_system_id=$(echo $db_system_id | tr -d '"' | xargs)
    sid_prefix=$(echo $sid_prefix | tr -d '"' | xargs)
    db_id=$(echo $db_id | tr -d '"' | xargs)
    pdb_name=$(echo $pdb_name | tr -d '"' | xargs)
    vm_cluster_id=$(echo $vm_cluster_id | tr -d '"' | xargs)
    subnet_id=$(echo $subnet_id | tr -d '"' | xargs)

    if [ "$subnet_id" == "$pe_subnet_id" ] && [ "$pdb_name" != "null" ]; then
      # Prepare the Data Safe target DB registration command
      command="oci data-safe target-database create --compartment-id $compartment_id \
      --database-details file://database-details_${pdb_name}.json \
      --connection-option file://connection-option_${pe_display_name}.json \
      --credentials file://Credentials_Target_DBaaS.json \
      --display-name $pdb_name"

      # Remove extra spaces before appending
      command=$(echo "$command" | awk '{$1=$1};1')

      # Append the command to the script file
      echo "$command" >> $output_script
    fi
  done < Oracle_Cloud_Databases_Details.csv

done < Datasafe_Private-Endpoint_List.txt

# Make the script executable
chmod +x $output_script

echo "Process Completed! All commands saved to $output_script"

