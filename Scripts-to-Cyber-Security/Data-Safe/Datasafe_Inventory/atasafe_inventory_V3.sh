#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Script Name   : datasafe_inventory_V3.sh
#
# Purpose       :
#   Generate OCI Data Safe Target Database Inventory reports.
#
#   Supports:
#     1. Single Region Execution
#     2. All Subscribed Regions Execution
#
#   Generates:
#     - <region>_DataSafe_Inventory.csv
#     - All_Regions_DataSafe_Inventory.csv
#
# Created By    : Alex Kovuru
# Creation Date : May 14, 2026
# Email         : alex.kovuru@oracle.com
###############################################################################

usage() {
    echo "Usage:"
    echo "  $0 one <region-name>"
    echo "  $0 all"
    exit 1
}

MODE="${1:-}"
ARG_REGION="${2:-}"
OUT_DIR="${OUT_DIR:-.}"

[[ -n "$MODE" ]] || usage

declare -A COMPARTMENT_NAME_CACHE

###############################################################################
# Logging Function
###############################################################################
log() {
    echo "[INFO] $*" >&2
}

###############################################################################
# Resolve Compartment Name from OCID
###############################################################################
get_compartment_name() {

    local compartment_id="$1"
    local region="$2"

    if [[ -n "${COMPARTMENT_NAME_CACHE[$compartment_id]:-}" ]]; then
        echo "${COMPARTMENT_NAME_CACHE[$compartment_id]}"
        return
    fi

    local compartment_name

    compartment_name="$(
        oci iam compartment get \
            --region "$region" \
            --compartment-id "$compartment_id" \
            --query 'data.name' \
            --raw-output 2>/dev/null || true
    )"

    if [[ -z "$compartment_name" || "$compartment_name" == "null" ]]; then
        compartment_name="null"
    fi

    COMPARTMENT_NAME_CACHE["$compartment_id"]="$compartment_name"

    echo "$compartment_name"
}

###############################################################################
# Build Group Membership Cache
#
# Store:
#   Group ID
#   Group Name
#   Member Target Database OCIDs
###############################################################################
build_group_cache() {

    local region="$1"
    local compartment_id="$2"
    local groups_file="$3"

    : > "$groups_file"

    local groups_json

    groups_json="$(
        oci data-safe target-database-group-summary \
            list-target-database-groups \
            --region "$region" \
            --compartment-id "$compartment_id" \
            --output json 2>/dev/null || \
        echo '{"data":{"items":[]}}'
    )"

    echo "$groups_json" |
    jq -r '.data.items[]? | [.id, .["display-name"]] | @tsv' |
    while IFS=$'\t' read -r group_id group_name
    do

        gjson="$(
            oci data-safe target-database-group get \
                --region "$region" \
                --target-database-group-id "$group_id" \
                --output json 2>/dev/null || true
        )"

        members="$(
            echo "$gjson" |
            jq -r '
                .data."matching-criteria".include["target-database-ids"][]?
            ' |
            paste -sd '|' -
        )"

        printf '%s\t%s\t%s\n' \
            "$group_id" \
            "$group_name" \
            "$members" >> "$groups_file"

    done
}

###############################################################################
# Process One Compartment
###############################################################################
process_compartment() {

    local region="$1"
    local compartment_id="$2"
    local out_file="$3"

    targets_json="$(
        oci data-safe target-database list \
            --region "$region" \
            --compartment-id "$compartment_id" \
            --all \
            --output json 2>/dev/null || \
        echo '{"data":[]}'
    )"

    target_count="$(echo "$targets_json" | jq '.data | length')"

    [[ "$target_count" -gt 0 ]] || return 0

    groups_file="$(mktemp)"

    build_group_cache \
        "$region" \
        "$compartment_id" \
        "$groups_file"

    echo "$targets_json" |
    jq -r '
      .data[] |
      [
        .["display-name"],
        .id,
        .["database-type"],
        .["infrastructure-type"],
        .["lifecycle-state"],
        .["time-created"],
        .["compartment-id"]
      ] | @tsv
    ' |
    while IFS=$'\t' read -r \
        target_name \
        target_id \
        db_type \
        infra_type \
        lifecycle_state \
        time_created \
        target_compartment_id
    do

        compartment_name="$(
            get_compartment_name \
                "$target_compartment_id" \
                "$region"
        )"

        #######################################################################
        # Get Dictionary Version
        #######################################################################
        dict_json="$(
            oci raw-request \
                --region "$region" \
                --http-method GET \
                --target-uri \
"https://datasafe.${region}.oci.oraclecloud.com/20181201/targetDatabases/${target_id}/dictionary" \
                --output json 2>/dev/null || true
        )"

        version="$(
            echo "$dict_json" |
            jq -r '.data[0].version // ""' 2>/dev/null || echo ""
        )"

        updated="$(
            echo "$dict_json" |
            jq -r '.data[0].timeUpdated // ""' 2>/dev/null || echo ""
        )"

        #######################################################################
        # Match Group Membership
        #######################################################################
        group_name=""
        group_id=""

        while IFS=$'\t' read -r gid gname members
        do

            if [[ -n "${members:-}" ]] &&
               [[ "|${members}|" == *"|${target_id}|"* ]]
            then
                group_name="$gname"
                group_id="$gid"
                break
            fi

        done < "$groups_file"

        #######################################################################
        # Output CSV Row
        #######################################################################
        printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$region" \
            "$target_name" \
            "$version" \
            "$group_name" \
            "$db_type" \
            "$infra_type" \
            "$target_id" \
            "$lifecycle_state" \
            "$time_created" \
            "$compartment_name" \
            "$target_compartment_id" \
            "$group_id" \
            "$updated" \
            >> "$out_file"

    done

    rm -f "$groups_file"
}

###############################################################################
# Process One Region
###############################################################################
process_region() {

    local region="$1"

    local out_file="${OUT_DIR}/${region}_DataSafe_Inventory.csv"

    log "Processing region: $region"

    echo \
'region,target_db_name,version,group_name,database_type,infrastructure_type,target_database_ocid,lifecycle_state,time_created,compartment_name,compartment_ocid,group_id,dictionary_updated' \
> "$out_file"

    compartments_file="$(mktemp)"

    oci search resource structured-search \
        --region "$region" \
        --query-text "query DataSafeTargetDatabase resources" \
        --output json 2>/dev/null |
    jq -r '.data.items[]? | .["compartment-id"]' |
    sort -u > "$compartments_file"

    while IFS= read -r compartment_id
    do
        [[ -n "$compartment_id" ]] || continue

        process_compartment \
            "$region" \
            "$compartment_id" \
            "$out_file"

    done < "$compartments_file"

    rm -f "$compartments_file"
}

###############################################################################
# Merge Regional CSV Files
###############################################################################
merge_outputs() {

    local merged_file="$1"
    shift

    : > "$merged_file"

    header_written=false

    for file in "$@"
    do

        [[ -f "$file" ]] || continue

        if [[ "$header_written" == false ]]; then
            head -n 1 "$file" > "$merged_file"
            header_written=true
        fi

        tail -n +2 "$file" >> "$merged_file"

    done
}

###############################################################################
# Main Logic
###############################################################################
case "$MODE" in

    one)

        [[ -n "$ARG_REGION" ]] || usage

        process_region "$ARG_REGION"
        ;;

    all)

        mapfile -t REGIONS < <(
            oci iam region-subscription list \
                --output json |
            jq -r '.data[] | ."region-name"'
        )

        region_files=()

        for region in "${REGIONS[@]}"
        do

            process_region "$region"

            region_files+=(
                "${OUT_DIR}/${region}_DataSafe_Inventory.csv"
            )

        done

        merge_outputs \
            "${OUT_DIR}/All_Regions_DataSafe_Inventory.csv" \
            "${region_files[@]}"

        log "Merged file written to: ${OUT_DIR}/All_Regions_DataSafe_Inventory.csv"
        ;;

    *)
        usage
        ;;
esac

