# Kubectl Context & Namespace Setup

This document explains how the diagnostic script works with your existing kubectl configuration.

## How It Works

The script automatically detects the namespace from your current kubectl context. This means it respects:
- Your current context namespace
- Kubectl context switches
- Any kubectl aliases or wrappers you have set up

## Check Your Current Namespace

```bash
# View current context and namespace
kubectl config view --minify | grep namespace

# Or check your full context
kubectl config current-context
kubectl config get-contexts
```

## Setting Your Namespace Context

### Option 1: Switch Context Namespace (Temporary)
```bash
# Set namespace for current context
kubectl config set-context --current --namespace=qalw

# Verify
kubectl config view --minify | grep namespace
```

### Option 2: Use a Different Context
```bash
# List all contexts
kubectl config get-contexts

# Switch to a context that has your namespace
kubectl config use-context my-qalw-context
```

### Option 3: Create a New Context with Namespace
```bash
# Create a new context with specific namespace
kubectl config set-context qalw-context \
  --cluster=my-cluster \
  --user=my-user \
  --namespace=qalw

# Use it
kubectl config use-context qalw-context
```

## Working with Your Bash Profile Alias

If you have an alias like `alias qalw='kubectl config set-context --current --namespace=qalw'` in your bash profile:

### Setup
```bash
# Add to ~/.bash_profile or ~/.bashrc
alias qalw='kubectl config set-context --current --namespace=qalw'
alias prod='kubectl config set-context --current --namespace=production'

# Reload
source ~/.bash_profile
```

### Usage
```bash
# Switch to qalw namespace
qalw

# Now run the diagnostic script - it will use qalw namespace
./pod-diagnostic.sh my-pod-name
```

## Override Namespace (Optional)

Even with a context namespace set, you can override it:

```bash
# Uses context namespace (e.g., qalw)
./pod-diagnostic.sh my-pod

# Overrides to use different namespace
./pod-diagnostic.sh my-pod -n production
```

## Verify Namespace Detection

When you run the script, it will show which namespace it's using:

```
✓ Using namespace from current context: qalw
================================
Pod Diagnostic Report
================================
Pod: my-pod
Namespace: qalw
...
```

## Troubleshooting

### Script says "No namespace found in context"
Your context doesn't have a default namespace set. The script will fall back to `default` namespace.

**Fix:**
```bash
kubectl config set-context --current --namespace=qalw
```

### Script can't find my pod
Make sure you're in the right namespace:
```bash
# Check current namespace
kubectl config view --minify | grep namespace

# List pods in that namespace
kubectl get pods

# Or explicitly check your target namespace
kubectl get pods -n qalw
```

### Wrong namespace being used
The script uses your **current** context namespace. Switch it:
```bash
kubectl config set-context --current --namespace=correct-namespace
# or
./pod-diagnostic.sh my-pod -n correct-namespace
```

## Quick Reference

```bash
# Check current namespace
kubectl config view --minify | grep namespace

# Set namespace for current session
kubectl config set-context --current --namespace=qalw

# Run diagnostic with auto-detected namespace
./pod-diagnostic.sh my-pod

# Run diagnostic with explicit namespace
./pod-diagnostic.sh my-pod -n qalw

# Show help
./pod-diagnostic.sh --help
```


