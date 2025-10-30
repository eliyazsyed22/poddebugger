#!/bin/bash

#############################################
# Pod Degradation Diagnostic Script
# Purpose: Diagnose why pod went into degraded state
# Usage: ./pod-diagnostic.sh <pod-name> [-n|--namespace <namespace>]
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "Usage: $0 <pod-name> [-n|--namespace <namespace>]"
    echo ""
    echo "Options:"
    echo "  -n, --namespace    Specify namespace (optional, uses current context if not provided)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 my-pod                    # Uses current namespace from kubectl context"
    echo "  $0 my-pod -n production      # Uses specified namespace"
    echo "  $0 my-pod --namespace qalw   # Uses specified namespace"
    exit 1
}

# Parse arguments
POD_NAME=""
NAMESPACE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            if [ -z "$POD_NAME" ]; then
                POD_NAME="$1"
            else
                echo -e "${RED}ERROR: Unknown argument: $1${NC}"
                show_usage
            fi
            shift
            ;;
    esac
done

# Check if pod name is provided
if [ -z "$POD_NAME" ]; then
    echo -e "${RED}ERROR: Pod name required${NC}"
    echo ""
    show_usage
fi

# If namespace not provided, get from current context
if [ -z "$NAMESPACE" ]; then
    NAMESPACE=$(kubectl config view --minify --output 'jsonpath={..namespace}')
    
    # If still empty, default to "default"
    if [ -z "$NAMESPACE" ]; then
        NAMESPACE="default"
        echo -e "${YELLOW}No namespace found in context, using 'default'${NC}"
    else
        echo -e "${GREEN}Using namespace from current context: ${NAMESPACE}${NC}"
    fi
fi

echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Pod Diagnostic Report${NC}"
echo -e "${BLUE}================================${NC}"
echo -e "Pod: ${GREEN}${POD_NAME}${NC}"
echo -e "Namespace: ${GREEN}${NAMESPACE}${NC}"
echo -e "Timestamp: $(date)"
echo ""

#############################################
# 1. Check if pod exists
#############################################
echo -e "${YELLOW}[1/9] Checking if pod exists...${NC}"
if ! kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}✗ Pod '$POD_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo ""
    echo "Available pods in namespace '$NAMESPACE':"
    kubectl get pods -n "$NAMESPACE"
    exit 1
fi
echo -e "${GREEN}✓ Pod exists${NC}"
echo ""

#############################################
# 2. Get Current Pod Status
#############################################
echo -e "${YELLOW}[2/9] Current Pod Status:${NC}"
kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o wide
echo ""

#############################################
# 3. Check for OOMKilled
#############################################
echo -e "${YELLOW}[3/9] Checking for OOM (Out of Memory) Kill...${NC}"
LAST_STATE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[*].lastState.terminated}')
CURRENT_STATE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[*].state.terminated}')

OOM_FOUND=0
if echo "$LAST_STATE" | grep -q "OOMKilled"; then
    echo -e "${RED}✗ CRITICAL: Pod was OOMKilled in last state!${NC}"
    echo "$LAST_STATE" | grep -o '"reason":"[^"]*"' | head -1
    OOM_FOUND=1
elif echo "$CURRENT_STATE" | grep -q "OOMKilled"; then
    echo -e "${RED}✗ CRITICAL: Pod is currently OOMKilled!${NC}"
    echo "$CURRENT_STATE" | grep -o '"reason":"[^"]*"' | head -1
    OOM_FOUND=1
else
    echo -e "${GREEN}✓ No OOMKill detected${NC}"
fi

# Check exit code
EXIT_CODE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[*].lastState.terminated.exitCode}')
if [ "$EXIT_CODE" == "137" ]; then
    echo -e "${RED}✗ CRITICAL: Exit code 137 detected (OOMKilled or SIGKILL)${NC}"
    OOM_FOUND=1
fi
echo ""

#############################################
# 4. Check Resource Limits vs Requirements
#############################################
echo -e "${YELLOW}[4/9] Analyzing Resource Limits vs JVM Requirements...${NC}"
MEMORY_LIMIT=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.limits.memory}')
MEMORY_REQUEST=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.memory}')
CPU_LIMIT=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.limits.cpu}')
CPU_REQUEST=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].resources.requests.cpu}')

echo "Memory Request: ${MEMORY_REQUEST:-"Not Set"}"
echo "Memory Limit:   ${MEMORY_LIMIT:-"Not Set"}"
echo "CPU Request:    ${CPU_REQUEST:-"Not Set"}"
echo "CPU Limit:      ${CPU_LIMIT:-"Not Set"}"
echo ""

# Convert memory limit to MB for comparison
if [ -n "$MEMORY_LIMIT" ]; then
    # Extract numeric value and unit
    MEMORY_VALUE=$(echo "$MEMORY_LIMIT" | grep -oE '[0-9]+')
    MEMORY_UNIT=$(echo "$MEMORY_LIMIT" | grep -oE '[A-Za-z]+')
    
    case "$MEMORY_UNIT" in
        Gi)
            MEMORY_MB=$((MEMORY_VALUE * 1024))
            ;;
        G)
            MEMORY_MB=$((MEMORY_VALUE * 1000))
            ;;
        Mi)
            MEMORY_MB=$MEMORY_VALUE
            ;;
        M)
            MEMORY_MB=$((MEMORY_VALUE * 1000 / 1024))
            ;;
        *)
            MEMORY_MB=0
            ;;
    esac
    
    # JVM requirements from logs: 6144M heap + 768M metaspace + 4639M direct = ~11.5GB + overhead
    REQUIRED_MB=14336  # 14GB minimum
    
    echo "JVM Requirements from your logs:"
    echo "  - Heap:        6144 MB (-Xms6144m -Xmx6144m)"
    echo "  - Metaspace:   768 MB (-XX:MaxMetaspaceSize=768m)"
    echo "  - Direct Mem:  4639 MB (-XX:MaxDirectMemorySize=4639m)"
    echo "  - Subtotal:    11551 MB"
    echo "  - Native/OS:   ~2048 MB (overhead)"
    echo "  -------------------------"
    echo "  - TOTAL:       ~14 GB minimum required"
    echo ""
    
    if [ "$MEMORY_MB" -lt "$REQUIRED_MB" ]; then
        echo -e "${RED}✗ CRITICAL: Memory limit ($MEMORY_LIMIT = ${MEMORY_MB}MB) is INSUFFICIENT!${NC}"
        echo -e "${RED}   Required: At least 14Gi (14336 MB)${NC}"
        echo -e "${RED}   This is likely causing OOMKills${NC}"
    else
        echo -e "${GREEN}✓ Memory limit ($MEMORY_LIMIT = ${MEMORY_MB}MB) is adequate${NC}"
    fi
else
    echo -e "${YELLOW}⚠ WARNING: No memory limit set - pod can be killed by node OOM${NC}"
fi
echo ""

#############################################
# 5. Check Restart Count
#############################################
echo -e "${YELLOW}[5/9] Checking Restart Count...${NC}"
RESTART_COUNT=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].restartCount}')
echo "Restart Count: $RESTART_COUNT"
if [ "$RESTART_COUNT" -gt 3 ]; then
    echo -e "${RED}✗ High restart count detected - pod is crashlooping${NC}"
elif [ "$RESTART_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}⚠ Pod has restarted $RESTART_COUNT time(s)${NC}"
else
    echo -e "${GREEN}✓ No restarts${NC}"
fi
echo ""

#############################################
# 6. Check Probe Configurations
#############################################
echo -e "${YELLOW}[6/9] Checking Probe Configurations...${NC}"
LIVENESS_INITIAL=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].livenessProbe.initialDelaySeconds}')
LIVENESS_TIMEOUT=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].livenessProbe.timeoutSeconds}')
READINESS_INITIAL=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe.initialDelaySeconds}')
READINESS_TIMEOUT=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].readinessProbe.timeoutSeconds}')

echo "Liveness Probe:"
if [ -n "$LIVENESS_INITIAL" ]; then
    echo "  - Initial Delay: ${LIVENESS_INITIAL}s"
    echo "  - Timeout: ${LIVENESS_TIMEOUT}s"
    
    if [ "$LIVENESS_INITIAL" -lt 180 ]; then
        echo -e "${YELLOW}  ⚠ WARNING: Initial delay might be too short for this app (recommend 300s)${NC}"
    fi
else
    echo "  - Not configured"
fi

echo "Readiness Probe:"
if [ -n "$READINESS_INITIAL" ]; then
    echo "  - Initial Delay: ${READINESS_INITIAL}s"
    echo "  - Timeout: ${READINESS_TIMEOUT}s"
    
    if [ "$READINESS_INITIAL" -lt 120 ]; then
        echo -e "${YELLOW}  ⚠ WARNING: Initial delay might be too short for this app (recommend 180s)${NC}"
    fi
else
    echo "  - Not configured"
fi
echo ""

#############################################
# 7. Get Recent Events
#############################################
echo -e "${YELLOW}[7/9] Recent Events for this Pod:${NC}"
kubectl get events -n "$NAMESPACE" --field-selector involvedObject.name="$POD_NAME" --sort-by='.lastTimestamp' | tail -20
echo ""

#############################################
# 8. Get Previous Container Logs (if available)
#############################################
echo -e "${YELLOW}[8/9] Previous Container Logs (last 50 lines):${NC}"
if kubectl logs "$POD_NAME" -n "$NAMESPACE" --previous --tail=50 &>/dev/null; then
    kubectl logs "$POD_NAME" -n "$NAMESPACE" --previous --tail=50
else
    echo -e "${YELLOW}No previous logs available (pod may not have restarted yet)${NC}"
fi
echo ""

#############################################
# 9. Get Current Container Logs (last 50 lines)
#############################################
echo -e "${YELLOW}[9/9] Current Container Logs (last 50 lines):${NC}"
kubectl logs "$POD_NAME" -n "$NAMESPACE" --tail=50 2>/dev/null || echo "No current logs available"
echo ""

#############################################
# Summary and Recommendations
#############################################
echo -e "${BLUE}================================${NC}"
echo -e "${BLUE}Summary & Recommendations${NC}"
echo -e "${BLUE}================================${NC}"
echo ""

ISSUES_FOUND=0

if [ "$OOM_FOUND" -eq 1 ]; then
    echo -e "${RED}[CRITICAL] Pod was killed due to Out Of Memory${NC}"
    echo "   → Increase memory limit to at least 16Gi"
    echo ""
    ISSUES_FOUND=1
fi

if [ -n "$MEMORY_LIMIT" ] && [ "$MEMORY_MB" -lt "$REQUIRED_MB" ]; then
    echo -e "${RED}[CRITICAL] Insufficient Memory Configuration${NC}"
    echo "   → Current: $MEMORY_LIMIT (${MEMORY_MB}MB)"
    echo "   → Required: At least 14Gi (16Gi recommended for buffer)"
    echo ""
    echo "   Fix: Update your deployment with:"
    echo "   resources:"
    echo "     requests:"
    echo "       memory: \"14Gi\""
    echo "       cpu: \"2000m\""
    echo "     limits:"
    echo "       memory: \"16Gi\""
    echo "       cpu: \"4000m\""
    echo ""
    ISSUES_FOUND=1
fi

if [ -n "$LIVENESS_INITIAL" ] && [ "$LIVENESS_INITIAL" -lt 180 ]; then
    echo -e "${YELLOW}[WARNING] Liveness Probe Initial Delay Too Short${NC}"
    echo "   → Current: ${LIVENESS_INITIAL}s"
    echo "   → Recommended: 300s (5 minutes) for slow-starting Java apps"
    echo ""
    ISSUES_FOUND=1
fi

if [ -n "$READINESS_INITIAL" ] && [ "$READINESS_INITIAL" -lt 120 ]; then
    echo -e "${YELLOW}[WARNING] Readiness Probe Initial Delay Too Short${NC}"
    echo "   → Current: ${READINESS_INITIAL}s"
    echo "   → Recommended: 180s (3 minutes) minimum"
    echo ""
    ISSUES_FOUND=1
fi

if [ "$RESTART_COUNT" -gt 3 ]; then
    echo -e "${YELLOW}[WARNING] High Restart Count Detected${NC}"
    echo "   → Pod is in a crash loop"
    echo "   → Review the issues above to identify root cause"
    echo ""
    ISSUES_FOUND=1
fi

if [ "$ISSUES_FOUND" -eq 0 ]; then
    echo -e "${GREEN}✓ No critical issues detected in configuration${NC}"
    echo ""
    echo "If pod is still failing, check:"
    echo "  1. Application logs for errors"
    echo "  2. Database connectivity"
    echo "  3. External service dependencies"
    echo "  4. ConfigMaps and Secrets"
fi

echo -e "${BLUE}================================${NC}"
echo "Diagnostic complete!"
echo ""

