#!/bin/bash

# Oracle Data Safe Report Processing Script
# This script downloads a report, converts it to CSV, cleans it, and extracts specific columns

# Set compartment OCID
COMPARTMENT_ID="ocid1.compartment.oc1..aaxxxxxxxxxxxxxxxxxxxxxxxxxxxxy4ydqa"

# Get Report ID
# Extract the latest report ID where display-name starts with RS_Sample_ExternalUsers_CustomReport
REPORT_ID=$(oci data-safe report-summary list-reports --compartment-id "$COMPARTMENT_ID" --all | \
  jq -r '.data.items
    | map(select(.["display-name"] | startswith("DS_AZ_OCI_Custom_External_User_Report")))
    | sort_by(.["time-generated"])
    | reverse
    | .[0].id')

# Set variables
OUTPUT_DIR="."
XLS_FILE="DS_AZ_OCI_Custom_External_User_Report_$(date +'%Y%m%d%H%M').xls"
CSV_FILE="${XLS_FILE%.xls}.csv"
CLEANED_FILE="cleaned_audit_records_externalUsers.csv"
FINAL_FILE="cleaned_audit_records_final.csv"

# Suppress the API key warning
export SUPPRESS_LABEL_WARNING=True

# Step 1: Download the report from OCI Data Safe
echo "Downloading report from OCI Data Safe..."
oci data-safe report get-report-content --file "$XLS_FILE" --report-id "$REPORT_ID"

# Check if download was successful
if [ ! -f "$XLS_FILE" ]; then
    echo "Error: Failed to download the report."
    exit 1
fi

# Step 2: Convert XLS to CSV using LibreOffice
echo "Converting XLS to CSV..."
libreoffice --headless --convert-to csv "$XLS_FILE" --outdir "$OUTPUT_DIR"

# Check if conversion was successful
if [ ! -f "$CSV_FILE" ]; then
    echo "Error: Failed to convert XLS to CSV."
    exit 1
fi

# Step 3: Clean the CSV file by removing first 11 lines
echo "Cleaning the CSV file..."
tail -n +12 "$CSV_FILE" > "$CLEANED_FILE"

# Check if cleaning was successful
if [ ! -f "$CLEANED_FILE" ]; then
    echo "Error: Failed to clean the CSV file."
    exit 1
fi

# Step 4: Extract specific columns
echo "Extracting specific columns..."
awk -F',' '{print $1","$2","$3","$4","$5","$6","$7","$9","$12}' "$CLEANED_FILE" > "$FINAL_FILE"

# Check if extraction was successful
if [ ! -f "$FINAL_FILE" ]; then
    echo "Error: Failed to extract columns."
    exit 1
fi

#echo "Processing completed successfully!"
#echo "Final output file: $FINAL_FILE"

# Display the first few lines of the final output
# echo -e "\nSample of the final output:"
# head "$FINAL_FILE"

# Step 5: Final Cleanup and Format Standardization

echo "Post-processing the final CSV..."

# Backup original before processing
cp "$FINAL_FILE" "${FINAL_FILE}.bak"

awk -F',' '
BEGIN { OFS="," }
NR==1 { print; next }                          # Always print header
/^,+$/ { next }                                # Skip lines with only commas
/^ *,+$/ { next }                              # Skip lines with spaces then commas
/^Target :/ { next }                           # Skip DB section headers
$1=="Target" && $2=="DB user" { next }         # Skip repeated headers
NF < 9 { next }                                # Skip incomplete lines (less than 9 fields)
{
    # Append Z to Operation time (8th column) only if not already present
    if ($8 !~ /Z$/) $8 = $8 "Z";
    print
}
' "${FINAL_FILE}.bak" > "$FINAL_FILE"

echo "Final post-processing complete."

