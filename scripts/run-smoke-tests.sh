#!/bin/bash

echo "Running Smoke Tests..."

# Use the public DNS or IP of your load balancer
PUBLIC_IP_OR_DOMAIN="a4ea12fe303ca488b83d20010df66751-112387697.ap-south-1.elb.amazonaws.com"
APP_PORT=8081

# Number of retries
maxRetries=10
waitTime=10

for i in $(seq 1 $maxRetries); do
    echo "Attempt $i/$maxRetries: Checking application health status..."

    # Get response code and response body for debugging purposes
    response=$(curl -s -o /tmp/smoke_test_response.txt -w "%{http_code}" http://${PUBLIC_IP_OR_DOMAIN}:${APP_PORT}/actuator/health)

    # Log the response code
    echo "Response code: $response"

    # If response code is 200, the application is healthy
    if [ "$response" -eq 200 ]; then
        echo "Smoke Test Passed: Application is healthy."
        exit 0
    else
        # Log the response body for debugging
        echo "Response body:"
        cat /tmp/smoke_test_response.txt

        echo "Application is not healthy yet, retrying in $waitTime seconds..."
        sleep $waitTime
    fi
done

# If max retries are reached, the smoke test has failed
echo "Smoke Test Failed: Application is not healthy after $maxRetries attempts."
exit 1
