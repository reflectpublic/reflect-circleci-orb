#!/bin/bash

curlf() {
  OUTPUT_FILE=$(mktemp)
  HTTP_CODE=$(curl --silent --output "$OUTPUT_FILE" --write-out "%{http_code}" "$@")
  if [[ ${HTTP_CODE} -lt 200 || ${HTTP_CODE} -gt 299 ]] ; then
    >&2 cat "$OUTPUT_FILE"
    return 22
  fi
  
  local RESPONSE
  RESPONSE=$(cat "$OUTPUT_FILE")
  rm "$OUTPUT_FILE"
  echo "$RESPONSE"
}

api_execute_suite() {
  curlf -X POST --data "$3" -H "x-api-key: $1" "https://api.reflect.run/v1/suites/$2/executions"
}

api_get_execution_status() {
  curlf -X GET -H "x-api-key: $1" "https://api.reflect.run/v1/suites/$2/executions/$3"
}

print_test_suite_execution_url() {
  echo "Test suite execution located at: https://app.reflect.run/suites/$1/executions/$2"
}

if [ -z "$PARAM_VARIABLES" ]; then
  PARAM_VARIABLES="{}"
fi

if [ -z "$PARAM_OVERRIDES" ]; then
  PARAM_OVERRIDES="{}"
fi

EXECUTE_SUITE_REQUEST_BODY=$( jq -n \
                  --argjson variables "$PARAM_VARIABLES" \
                  --argjson overrides "$PARAM_OVERRIDES" \
                  '{variables: $variables, overrides: $overrides}' )

if [ "$PARAM_WAIT_FOR_TEST_RESULTS" -eq 0 ]; then
  RESPONSE=$(api_execute_suite "$REFLECT_API_KEY" "$PARAM_SUITE_ID" "$EXECUTE_SUITE_REQUEST_BODY")

  if [[ "$?" -eq 22 ]]; then
    printf "\nError: Unable to execute test suite"
    exit 22
  fi

  EXECUTION_ID=$(echo "$RESPONSE" | jq -r '.executionId')

  print_test_suite_execution_url "$PARAM_SUITE_ID" "$EXECUTION_ID"

  echo "Started test suite with execution id: $EXECUTION_ID. Exiting without waiting for test suite to complete."

else
  RESPONSE=$(api_execute_suite "$REFLECT_API_KEY" "$PARAM_SUITE_ID" "$EXECUTE_SUITE_REQUEST_BODY")

  if [[ "$?" -eq 22 ]]; then
    printf "\nError: Unable to execute test suite"
    exit 22
  fi

  EXECUTION_ID=$(echo "$RESPONSE" | jq -r '.executionId')

  print_test_suite_execution_url "$PARAM_SUITE_ID" "$EXECUTION_ID"

  echo "Started test suite with execution id: $EXECUTION_ID. Will wait for test suite to complete before exiting."

  IS_FINISHED=false
  while [ "$IS_FINISHED" = "false" ]; do
      EXECUTION_STATUS=$(api_get_execution_status "$REFLECT_API_KEY" "$PARAM_SUITE_ID" "$EXECUTION_ID")
      
      echo "Checking test status..."
      IS_FINISHED=$(echo "$EXECUTION_STATUS" | jq '.isFinished')
      STATUS=$(echo "$EXECUTION_STATUS" | jq -r '.status')

      if [ "$IS_FINISHED" = "false" ]; then
        echo "Not finished yet. Sleeping for 10 seconds."
        sleep 10
      fi
  done

  if [ "$STATUS" != "passed" ]; then
    echo "Test suite failed with status: $STATUS"
    exit 1
  else
    echo "Test suite completed successfully with 0 failing tests!"
  fi
fi
