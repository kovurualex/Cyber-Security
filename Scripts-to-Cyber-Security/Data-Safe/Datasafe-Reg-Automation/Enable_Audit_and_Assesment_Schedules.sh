#!/bin/bash

# Prompt for Data Safe Registered databases details
echo "Datasafe_TargetDBs.csv - Sample CSV Format: region,Compartment_ID,Target_DB_Name, Target_DB_ID"
# Read the CSV file
read -p "Please provide the path to your CSV file: " csv_file

# Step 3: Prompt for Assessments schedule_time and read it
echo "Assessment Schedule Time template in UTC: -<ss> <mm> <hh> <day-of-week> <day-of-month>"
echo "For example 1:  13 55 22 3 * (Schedule: Every Wednesday at 10:55:13 PM UTC)"
echo "For example 2:  00 00 01 7 * (Schedule: Every Sunday at 01:00 AM UTC)"
read -p "Enter the Assessment Schedule Time: " schedule_time

# Format the schedule
formatting_schedule="v1; $schedule_time"
formatted_schedule="\"$formatting_schedule\""


# Step 4: Prompt Audit Trail collection Start Time
read -p "Enter Audit Trail collection Start Time (YYYY-MM-DD): " audit_collection_start_time

# Validate the format (YYYY-MM-DD)
if [[ $audit_collection_start_time =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "Audit Trail collection Start Time accepted."
else
    echo "Audit Trail collection Start Time Format incorrect. Please enter a valid date in YYYY-MM-DD format."
    exit 1
fi

# Step 5: Source the external script for enabling policies
# Define the table content in an associative array with policy category and name
declare -A policies=(
  [1]="BASIC_ACTIVITY, Database schema changes"
  [2]="BASIC_ACTIVITY, Logon events"
  [3]="BASIC_ACTIVITY, Critical database activity"
  [4]="ADMIN_USER_ACTIVITY, Admin user activity"
  [5]="USER_ACTIVITY, User activity"
  [6]="COMPLIANCE_STANDARD, Center for Internet Security (CIS) configuration"
  [7]="ORACLE_PREDEFINED, ORA_ACCOUNT_MGMT"
  [8]="ORACLE_PREDEFINED, ORA_DATABASE_PARAMETER"
  [9]="ORACLE_PREDEFINED, ORA_DV_AUDPOL"
  [10]="ORACLE_PREDEFINED, ORA_DV_AUDPOL2"
  [11]="ORACLE_PREDEFINED, ORA_LOGON_FAILURES"
  [12]="ORACLE_PREDEFINED, ORA_RAS_POLICY_MGMT"
  [13]="ORACLE_PREDEFINED, ORA_RAS_SESSION_MGMT"
  [14]="ORACLE_PREDEFINED, ORA_SECURECONFIG"
)

# Print the table header
echo "S.No    Audit-Policy-Category         Audit-Policy-Name"
echo "----------------------------------------------------------"

# Print the table content
for i in {1..14}; do
  IFS=',' read -ra policy_details <<< "${policies[$i]}"
  echo "$i       ${policy_details[0]}           ${policy_details[1]}"
done

echo "----------------------------------------------------------"

# Prompt user for input
read -p "Enter the S.No of the policies you want to enable (comma separated, e.g., 1,3,5): " input

# Process input
IFS=',' read -ra selected_policies <<< "$input"

# Prepare the JSON structure and write to file
json_file="Provision_Audit_policies.json"
echo "[" > $json_file

for sn in "${selected_policies[@]}"; do
  IFS=',' read -ra policy_details <<< "${policies[$sn]}"

  # Trim leading/trailing spaces from policy name
  policy_name=$(echo "${policy_details[1]}" | xargs)

  # Add JSON object for each selected policy
  echo "  {" >> $json_file
  echo "    \"auditPolicyName\": \"$policy_name\"," >> $json_file
  echo "    \"isEnabled\": true," >> $json_file
  echo "    \"isPrivUsersManagedByDataSafe\": false" >> $json_file
  echo "  }," >> $json_file
done

# Remove the trailing comma from the last item
sed -i '$ s/,$//' $json_file

# Close the JSON array
echo "]" >> $json_file

# Display a message that the file has been created
echo "JSON file 'Provision_Audit_policies.json' has been created with the selected policies."
json_file_Formate="file://Provision_Audit_policies.json"

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
  while IFS=',' read -r region compartment_id target_db_name target_db_id; do
  echo "Processing Target Database: $region, $target_db_name"

  # Step 4a: Get security assessment details for the target DB
  security_assessment=$(oci data-safe security-assessment list --compartment-id "$compartment_id" --target-id "$target_db_id" --sort-by timeCreated --sort-order ASC --all | jq -r '.data[] | "\"\(.["display-name"])\",\"\(.id)\""' | head -1)
  
  # Extract security assessment display name and ID
  security_assessment_name=$(echo $security_assessment | cut -d',' -f1 | tr -d '"')
  security_assessment_id=$(echo $security_assessment | cut -d',' -f2 | tr -d '"')
  
  # Schedule the security assessment
  generated_script="Assessment_schedules.sh"
  log_file="Assessment_schedules.log"
  echo "#!/bin/bash" > $generated_script
  chmod +x $generated_script
  echo "oci data-safe security-assessment update --security-assessment-id $security_assessment_id --schedule $formatted_schedule" >> $generated_script
  #oci data-safe security-assessment update --security-assessment-id $security_assessment_id --schedule $formatted_schedule

  # Step 4b: Get user assessment details for the target DB
  user_assessment=$(oci data-safe user-assessment list --compartment-id "$compartment_id" --target-id "$target_db_id" --sort-by timeCreated --sort-order ASC --all | jq -r '.data[] | "\"\(.["display-name"])\",\"\(.id)\""' | head -1)

  # Extract user assessment display name and ID
  user_assessment_name=$(echo $user_assessment | cut -d',' -f1 | tr -d '"')
  user_assessment_id=$(echo $user_assessment | cut -d',' -f2 | tr -d '"')

  # Schedule the user assessment
  echo "oci data-safe user-assessment update --user-assessment-id $user_assessment_id --schedule $formatted_schedule " >> $generated_script
  #oci data-safe user-assessment update --user-assessment-id "$user_assessment_id" --schedule "$formatted_schedule"

  # Capture the full output and errors to a log file for Assessment Schedules
  echo "Scheduling the Assessments for $region, $target_db_name "
  ./$generated_script > $log_file 2>&1

  # Step 4c: Process audit trails for the target DB
  audit_trail_file="${target_db_name}_audit_Trails.txt"
  oci data-safe audit-trail list --compartment-id "$compartment_id" --target-id "$target_db_id" --all | jq -r '.data.items[] | "\(.["display-name"]),\(.id),\(.status)"' > "$audit_trail_file"
  
  while IFS=',' read -r display_name id status; do
    if [ "$status" = "NOT_STARTED" ]; then
      echo "Start Audit Collection for $region, $target_db_name "
      oci data-safe audit-trail start --audit-collection-start-time "$audit_collection_start_time" --audit-trail-id "$id"
    fi
  done < "$audit_trail_file"

  # Step 4d: Enable audit policies for the target DB
  audit_policy_file="${target_db_name}_audit_policy_ids.csv"
  generated_script2="AuditPolicy_Retrive.sh"
  log_file2="AuditPolicy_Retrive.log"
  echo "#!/bin/bash" > $generated_script2
  chmod +x $generated_script2
  oci data-safe audit-policy-collection list-audit-policies --compartment-id "$compartment_id" --target-id "$target_db_id" --all | jq -r '.data.items[] | [.["display-name"], .id, .["lifecycle-state"]] | join(",")' > "$audit_policy_file"
  
  while IFS=',' read -r display_name id lifecycle_state; do
    if [ "$lifecycle_state" = "ACTIVE" ]; then
      echo "Provisioning the Audit Policies for $region, $target_db_name "
      oci data-safe audit-policy provision --audit-policy-id "$id" --provision-audit-conditions "$json_file_Formate"
      echo "oci data-safe audit-policy retrieve --audit-policy-id $id" >> $generated_script2
      #oci data-safe audit-policy retrieve --audit-policy-id "$id" 
    fi
  done < "$audit_policy_file"
  sleep 2
  ./$generated_script2 > $log_file2 2>&1
done < "$region_csv_file"

done
echo "Script execution completed."


