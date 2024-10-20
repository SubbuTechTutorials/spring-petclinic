#!/bin/bash

echo "Running Smoke Tests..."

# Check if the application is running on the correct port (8081 in this case)
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/actuator/health)

if [ "$response" -eq 200 ]; then
    echo "Smoke Test Passed: Application is healthy."
    exit 0
else
    echo "Smoke Test Failed: Application is not healthy."
    exit 1
fi
