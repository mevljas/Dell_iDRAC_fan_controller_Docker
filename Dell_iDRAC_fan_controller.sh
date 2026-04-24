#!/bin/bash

# Enable strict bash mode to stop the script if an uninitialized variable is used, if a command fails, or if a command with a pipe fails
# Not working in some setups : https://github.com/tigerblue77/Dell_iDRAC_fan_controller/issues/48
# set -euo pipefail

source functions.sh
source constants.sh

# Trap the signals for container exit and run graceful_exit function
trap 'graceful_exit' SIGINT SIGQUIT SIGTERM

# Prepare, format and define initial variables

# readonly DELL_FRESH_AIR_COMPLIANCE=45

# Check if FAN_SPEED variable is in hexadecimal format. If not, convert it to hexadecimal
if [[ "$FAN_SPEED" == 0x* ]]; then
  readonly DECIMAL_FAN_SPEED=$(convert_hexadecimal_value_to_decimal "$FAN_SPEED")
  readonly HEXADECIMAL_FAN_SPEED="$FAN_SPEED"
else
  readonly DECIMAL_FAN_SPEED="$FAN_SPEED"
  readonly HEXADECIMAL_FAN_SPEED=$(convert_decimal_value_to_hexadecimal "$FAN_SPEED")
fi

if ! is_integer "$DECIMAL_FAN_SPEED" || [ "$DECIMAL_FAN_SPEED" -lt 0 ] || [ "$DECIMAL_FAN_SPEED" -gt 100 ]; then
  print_error_and_exit "FAN_SPEED must be an integer from 0 to 100"
fi
if ! is_integer "$CPU_TEMPERATURE_THRESHOLD" || [ "$CPU_TEMPERATURE_THRESHOLD" -le 0 ]; then
  print_error_and_exit "CPU_TEMPERATURE_THRESHOLD must be a positive integer"
fi
if ! is_integer "$CHECK_INTERVAL" || [ "$CHECK_INTERVAL" -le 0 ]; then
  print_error_and_exit "CHECK_INTERVAL must be a positive integer"
fi
if ! is_integer "$FAN_CURVE_RAMP_WINDOW" || [ "$FAN_CURVE_RAMP_WINDOW" -le 0 ]; then
  print_error_and_exit "FAN_CURVE_RAMP_WINDOW must be a positive integer"
fi

FAN_CURVE_START_TEMPERATURE=$((CPU_TEMPERATURE_THRESHOLD - FAN_CURVE_RAMP_WINDOW))
if [ "$FAN_CURVE_START_TEMPERATURE" -lt 1 ]; then
  FAN_CURVE_START_TEMPERATURE=1
fi
readonly FAN_CURVE_START_TEMPERATURE

set_iDRAC_login_string "$IDRAC_HOST" "$IDRAC_USERNAME" "$IDRAC_PASSWORD"

get_Dell_server_model

readonly DELL_POWEREDGE_GEN_14_OR_NEWER=false
readonly CPU1_TEMPERATURE_INDEX=1
readonly CPU2_TEMPERATURE_INDEX=2

# Log main informations
echo "Server model: $SERVER_MANUFACTURER $SERVER_MODEL"
echo "iDRAC/IPMI host: $IDRAC_HOST"

# Log the fan speed objective, CPU temperature threshold and check interval
echo "Fan speed floor: $DECIMAL_FAN_SPEED% (temperature curve enabled)"
echo "Fan curve ramp starts at: ${FAN_CURVE_START_TEMPERATURE}°C"
echo "CPU temperature threshold: "$CPU_TEMPERATURE_THRESHOLD"°C"
echo "Check interval: ${CHECK_INTERVAL}s"
echo ""

TABLE_HEADER_PRINT_COUNTER=$TABLE_HEADER_PRINT_INTERVAL
# Set the flag used to check if the active fan control profile has changed
IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED=true

# Check present sensors
IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=true
IS_CPU2_TEMPERATURE_SENSOR_PRESENT=true
retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT
if [ -z "$EXHAUST_TEMPERATURE" ]; then
  echo "No exhaust temperature sensor detected."
  IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT=false
fi
if [ -z "$CPU2_TEMPERATURE" ]; then
  echo "No CPU2 temperature sensor detected."
  IS_CPU2_TEMPERATURE_SENSOR_PRESENT=false
fi
# Output new line to beautify output if one of the previous conditions have echoed
if ! $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT || ! $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
  echo ""
fi

#readonly NUMBER_OF_DETECTED_CPUS=(${CPUS_TEMPERATURES//;/ })
# TODO : write "X CPU sensors detected." and remove previous ifs
readonly HEADER=$(build_header $NUMBER_OF_DETECTED_CPUS)

# Start monitoring
while true; do
  # Sleep for the specified interval before taking another reading
  sleep "$CHECK_INTERVAL" &
  SLEEP_PROCESS_PID=$!

  # Initialize a variable to store the comments displayed when the fan control profile changed
  COMMENT=" -"
  if ! retrieve_temperatures $IS_EXHAUST_TEMPERATURE_SENSOR_PRESENT $IS_CPU2_TEMPERATURE_SENSOR_PRESENT; then
    apply_Dell_default_fan_control_profile
    if ! $IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED; then
      IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED=true
      COMMENT="Temperature retrieval failed, Dell default dynamic fan control profile applied for safety"
    fi
  else
    MAX_CPU_TEMPERATURE=$(get_max_cpu_temperature)
    if [ -z "$MAX_CPU_TEMPERATURE" ]; then
      apply_Dell_default_fan_control_profile
      if ! $IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED; then
        IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED=true
        COMMENT="CPU temperature parsing failed, Dell default dynamic fan control profile applied for safety"
      fi
    elif [ "$MAX_CPU_TEMPERATURE" -gt "$CPU_TEMPERATURE_THRESHOLD" ]; then
      apply_Dell_default_fan_control_profile
      if ! $IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED; then
        IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED=true
        COMMENT="CPU temperature is too high (${MAX_CPU_TEMPERATURE}°C), Dell default dynamic fan control profile applied for safety"
      fi
    else
      TARGET_FAN_SPEED=$(calculate_curve_fan_speed "$MAX_CPU_TEMPERATURE" "$DECIMAL_FAN_SPEED" "$CPU_TEMPERATURE_THRESHOLD" "$FAN_CURVE_RAMP_WINDOW")

      if [ -z "$TARGET_FAN_SPEED" ] || ! apply_user_fan_control_profile_with_speed "$TARGET_FAN_SPEED"; then
        apply_Dell_default_fan_control_profile
        if ! $IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED; then
          IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED=true
          COMMENT="Fan curve evaluation failed, Dell default dynamic fan control profile applied for safety"
        fi
      elif $IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED; then
        IS_DELL_DEFAULT_FAN_CONTROL_PROFILE_APPLIED=false
        COMMENT="CPU temperature is now OK (<= $CPU_TEMPERATURE_THRESHOLD°C), fan curve control resumed."
      fi
    fi
  fi

  # If server model is not Gen 14 (*40) or newer
  if ! $DELL_POWEREDGE_GEN_14_OR_NEWER; then
    # Enable or disable, depending on the user's choice, third-party PCIe card Dell default cooling response
    # No comment will be displayed on the change of this parameter since it is not related to the temperature of any device (CPU, GPU, etc...) but only to the settings made by the user when launching this Docker container
    if "$DISABLE_THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE"; then
      disable_third_party_PCIe_card_Dell_default_cooling_response
      THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Disabled"
    else
      enable_third_party_PCIe_card_Dell_default_cooling_response
      THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS="Enabled"
    fi
  fi

  # Print temperatures, active fan control profile and comment if any change happened during last time interval
  if [ $TABLE_HEADER_PRINT_COUNTER -eq $TABLE_HEADER_PRINT_INTERVAL ]; then
    printf "%s\n" "$HEADER"
    TABLE_HEADER_PRINT_COUNTER=0
  fi
  print_temperature_array_line "$INLET_TEMPERATURE" "$CPUS_TEMPERATURES" "$EXHAUST_TEMPERATURE" "$CURRENT_FAN_CONTROL_PROFILE" "$THIRD_PARTY_PCIE_CARD_DELL_DEFAULT_COOLING_RESPONSE_STATUS" "$COMMENT"
  ((TABLE_HEADER_PRINT_COUNTER++))
  wait $SLEEP_PROCESS_PID
done
