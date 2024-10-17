#!/bin/bash

echo "Running Performance Tests..."

# Run JMeter performance test plan
/path/to/jmeter/bin/jmeter -n -t src/test/jmeter/petclinic_test_plan.jmx -l jmeter-results.jtl

if grep -q "FAILED" jmeter-results.jtl; then
    echo "Performance Tests Failed."
    exit 1
else
    echo "Performance Tests Passed."
    exit 0
fi
