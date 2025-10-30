# Pod Diagnostic Script

This script helps diagnose why your Kubernetes pod went into a degraded state.

## Usage

```bash
./pod-diagnostic.sh <pod-name> [-n|--namespace <namespace>]
```

The script automatically uses your current kubectl context namespace. You can override it with the `-n` flag if needed.

### Examples

**Using current namespace context (recommended):**
```bash
# Works with your kubectl context/alias setup
./pod-diagnostic.sh us-obsidiantasks-qal-usw2-eks-qbopayroll-iopapp-5767fd98b72j5g4
```

**Override namespace explicitly:**
```bash
# Specify a different namespace
./pod-diagnostic.sh my-pod -n qalw
./pod-diagnostic.sh my-pod --namespace production
```

**Show help:**
```bash
./pod-diagnostic.sh --help
```

## What It Checks

1. **Pod Existence** - Verifies the pod exists in your namespace
2. **Current Status** - Shows pod state, age, and node placement
3. **OOMKilled Detection** - Checks if pod was killed due to out-of-memory
4. **Resource Analysis** - Compares memory limits against JVM requirements
5. **Restart Count** - Identifies crash loops
6. **Probe Configuration** - Validates liveness/readiness probe settings
7. **Recent Events** - Shows Kubernetes events related to the pod
8. **Previous Logs** - Displays logs from previous container instance
9. **Current Logs** - Shows recent logs from current container

## Output

The script provides:
- ✓ Green checkmarks for passed checks
- ⚠ Yellow warnings for potential issues
- ✗ Red errors for critical problems
- Actionable recommendations to fix issues

## Common Issues Detected

### OOMKilled (Exit Code 137)
**Cause:** Container memory limit is lower than application memory usage

**Fix:** Increase memory limits in your deployment:
```yaml
resources:
  requests:
    memory: "14Gi"
    cpu: "2000m"
  limits:
    memory: "16Gi"
    cpu: "4000m"
```

### Probe Failures
**Cause:** Liveness/readiness probes failing before app fully starts

**Fix:** Increase initial delay:
```yaml
livenessProbe:
  initialDelaySeconds: 300  # 5 minutes
  timeoutSeconds: 10
readinessProbe:
  initialDelaySeconds: 180  # 3 minutes
  timeoutSeconds: 10
```

## Requirements

- `kubectl` installed and configured with context/namespace
- Access to the Kubernetes cluster
- Permissions to view pods, events, and logs in your namespace
- Works with existing kubectl aliases and namespace configurations

## Tips

- Run this script when pod is in CrashLoopBackOff or Error state
- Check the "Summary & Recommendations" section at the end for actionable fixes
- Save output for troubleshooting: `./pod-diagnostic.sh <pod> > diagnostic-report.txt`

