#!/bin/bash

echo "Running Smoke Tests..."

# Example: Use cURL to check the health endpoint
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health)

if [ "$response" -eq 200 ]; then
    echo "Smoke Test Passed: Application is healthy."
    exit 0
else
    echo "Smoke Test Failed: Application is not healthy."
    exit 1
fi
