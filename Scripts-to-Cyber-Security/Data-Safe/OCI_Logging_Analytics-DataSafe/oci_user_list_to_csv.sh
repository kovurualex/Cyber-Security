#!/bin/bash

# Output file
OUTPUT_FILE="oci_iam_users.csv"

# Run the OCI CLI command and extract data using jq
echo "id,name,email" > "$OUTPUT_FILE"  # CSV Header

oci iam user list --all | jq -r '.data[] | [.id, .name, .email] | @csv' >> "$OUTPUT_FILE"

echo "CSV file generated: $OUTPUT_FILE"

