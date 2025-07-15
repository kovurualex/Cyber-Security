#!/bin/bash

awk -F',' '
# Process merged_users.csv (the first file passed to awk)
FNR == NR {
    if (FNR == 1) {
        # Skip header line of merged_users.csv
        next
    }
    # Remove double quotes from each field
    gsub(/"/, "", $1)  # id
    gsub(/"/, "", $2)  # displayName
    gsub(/"/, "", $4)  # mail
    gsub(/"/, "", $5)  # source

    # Store displayName, mail, and source in an associative array, indexed by id
    users[$1]["displayName"] = $2
    users[$1]["mail"] = $4
    users[$1]["source"] = $5
    next
}

# Process cleaned_audit_records_final.csv (the second file)
{
    if (FNR == 1) {
        # Print original header with additional columns
        print $0",displayName,mail,source"
    } else {
        # Extract external user ID from field 9
        external_user_id = $9

        # Lookup in users map
        display_name = users[external_user_id]["displayName"]
        email = users[external_user_id]["mail"]
        source = users[external_user_id]["source"]

        # Print line with new appended values
        print $0","display_name","email","source
    }
}' merged_users.csv cleaned_audit_records_final.csv > DataSafe_External_Users_Audit_Dashboard.csv

