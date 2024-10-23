#!/bin/bash

echo "Running Smoke Tests..."

# Use the public DNS or IP of your load balancer
PUBLIC_IP_OR_DOMAIN="abeef2b5efecf47f48fd7141e3079c27-359075947.ap-south-1.elb.amazonaws.com"
APP_PORT=8081

# Number of retries
maxRetries=10
waitTime=10

for i in $(seq 1 $maxRetries); do
    response=$(curl -s -o /dev/null -w "%{http_code}" http://${PUBLIC_IP_OR_DOMAIN}:${APP_PORT}/actuator/health)
    echo "Attempt $i/$maxRetries: Response code: $response"

    if [ "$response" -eq 200 ]; then
        echo "Smoke Test Passed: Application is healthy."
        exit 0
    else
        echo "Application is not healthy yet, retrying in $waitTime seconds..."
        sleep $waitTime
    fi
done

echo "Smoke Test Failed: Application is not healthy after $maxRetries attempts."
exit 1
