{\rtf1\ansi\ansicpg1252\cocoartf2822
\cocoatextscaling0\cocoaplatform0{\fonttbl\f0\fnil\fcharset0 HelveticaNeue;}
{\colortbl;\red255\green255\blue255;}
{\*\expandedcolortbl;;}
\paperw11900\paperh16840\margl1440\margr1440\vieww11520\viewh8400\viewkind0
\deftab560
\pard\pardeftab560\slleading20\partightenfactor0

\f0\fs26 \cf0 #!/bin/bash\
\
# Output file\
OUTPUT_FILE="oci_iam_users.csv"\
\
# Run the OCI CLI command and extract data using jq\
echo "id,name,email" > "$OUTPUT_FILE"  # CSV Header\
\
oci iam user list --all | jq -r '.data[] | [.id, .name, .email] | @csv' >> "$OUTPUT_FILE"\
\
echo "CSV file generated: $OUTPUT_FILE"\
}