#!/bin/bash

# This script is designed to:
# 1. Prompt the user for a Compartment ID and list Data Safe active target databases.
# 2. Retrieve security and user assessments for each target database.
# 3. Generate a CSV file containing the target database details and their associated assessments.
# 4. Generate schedule update scripts for security and user assessments.
# 5. Copy the CSV file and remove double quotes from the copied version.

# Step 1: Read the “compartment-id” by prompting it
read -p "Enter the Compartment ID: " compartment_id

# Step 2: Data Safe active target DB Lists
oci data-safe target-database list --compartment-id $compartment_id --lifecycle-state ACTIVE --all | \
jq -r '.data[] | [.["database-type"], .["display-name"], .["id"], .["infrastructure-type"], .["lifecycle-state"]] | @csv' > Datasafe_Active_TargetDB_list.txt

# Step 3: Process each target DB from the list
echo "database-type,display-name,id,infrastructure-type,lifecycle-state,security-assessment-name,security-assessment-id,user-assessment-name,user-assessment-id" > Datasafe_Active_TargetDBs.txt

while IFS=',' read -r database_type display_name target_id infrastructure_type lifecycle_state
do
  # Remove any quotes from target_id
  target_id=$(echo $target_id | tr -d '"')

  # Validate if target_id follows correct format (simple check for 'ocid1.')
  if [[ $target_id == ocid1.* ]]; then
    # a) Get the security assessment details
    security_assessment=$(oci data-safe security-assessment list --compartment-id $compartment_id --target-id $target_id --sort-by timeCreated --sort-order ASC --all | \
      jq -r '.data[] | "\"\(.["display-name"])\",\"\(.id)\""' | head -1)

    # Extract security assessment values
    security_assessment_name=$(echo $security_assessment | cut -d',' -f1 | tr -d '"')
    security_assessment_id=$(echo $security_assessment | cut -d',' -f2 | tr -d '"')

    # b) Get the user assessment details
    user_assessment=$(oci data-safe user-assessment list --compartment-id $compartment_id --target-id $target_id --sort-by timeCreated --sort-order ASC --all | \
      jq -r '.data[] | "\"\(.["display-name"])\",\"\(.id)\""' | head -1)

    # Extract user assessment values
    user_assessment_name=$(echo $user_assessment | cut -d',' -f1 | tr -d '"')
    user_assessment_id=$(echo $user_assessment | cut -d',' -f2 | tr -d '"')

    # Append details to CSV
    echo "$database_type,$display_name,$target_id,$infrastructure_type,$lifecycle_state,$security_assessment_name,$security_assessment_id,$user_assessment_name,$user_assessment_id" >> Datasafe_Active_TargetDBs.txt
  fi
done < Datasafe_Active_TargetDB_list.txt

# Step 4: Generate the schedule scripts
# a) Generate security assessment schedule update script
echo "#!/bin/bash" > schedule_security_assessments.sh
tail -n +2 Datasafe_Active_TargetDBs.txt | while IFS=',' read -r database_type display_name target_id infrastructure_type lifecycle_state security_assessment_name security_assessment_id user_assessment_name user_assessment_id
do
  if [ -n "$security_assessment_id" ]; then
    echo "oci data-safe security-assessment update --security-assessment-id $security_assessment_id --schedule \"v1; 00 00 03 1 *\"" >> schedule_security_assessments.sh
  fi
done
chmod +x schedule_security_assessments.sh

# b) Generate user assessment schedule update script
echo "#!/bin/bash" > schedule_user_assessments.sh
tail -n +2 Datasafe_Active_TargetDBs.txt | while IFS=',' read -r database_type display_name target_id infrastructure_type lifecycle_state security_assessment_name security_assessment_id user_assessment_name user_assessment_id
do
  if [ -n "$user_assessment_id" ]; then
    echo "oci data-safe user-assessment update --user-assessment-id $user_assessment_id --schedule \"v1; 00 00 03 1 *\"" >> schedule_user_assessments.sh
  fi
done
chmod +x schedule_user_assessments.sh

# Step 5: Copy Datasafe_Active_TargetDBs.txt to Datasafe_Active_TargetDBs_Assessments.txt and remove double quotes
cp Datasafe_Active_TargetDBs.txt Datasafe_Active_TargetDBs_Assessments.txt
sed -i 's/"//g' Datasafe_Active_TargetDBs_Assessments.txt

echo "Scripts generated successfully: schedule_security_assessments.sh, schedule_user_assessments.sh, and Datasafe_Active_TargetDBs_Assessments.txt"

