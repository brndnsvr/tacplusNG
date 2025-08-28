# Executive Summary: Socket EOF Handling Bug Fix

## Problem Discovery
Production monitoring systems (VMware vROps) were triggering persistent high CPU utilization alarms. Server terminals showed load averages exceeding 30 on 16-core systems. Initial investigation revealed:
- Multiple tac_plus-ng processes consuming 40-60% CPU each
- System load average of 30+ on 16-core servers
- Connections stuck in CLOSE-WAIT state for hours
- Authentication services experiencing significant delays

## Troubleshooting Process

### 1. Initial Observations
- **Monitoring Alerts**: VMware vROps reported sustained high CPU usage across multiple TACACS+ servers
- **System Check**: `top` and `htop` showed tac_plus-ng processes pinned at 40-60% CPU utilization each
- **Load Average**: Systems reporting load averages of 30+ on 16-core machines (normal: <2)

### 2. Network Analysis
Using `netstat -an | grep CLOSE_WAIT` revealed:
```
tcp  0  0  10.0.1.5:49  10.0.2.10:54321  CLOSE_WAIT
tcp  0  0  10.0.1.5:49  10.0.2.11:43210  CLOSE_WAIT
tcp  0  0  10.0.1.5:49  10.0.2.12:12345  CLOSE_WAIT
```
Numerous connections stuck in CLOSE_WAIT state, indicating the application wasn't properly closing connections after the remote peer disconnected.

### 3. System Call Tracing
Running `strace -p <PID>` on affected processes revealed the smoking gun:
```
recvfrom(7, "", 4096, 0, NULL, NULL) = 0
recvfrom(7, "", 4096, 0, NULL, NULL) = 0
recvfrom(7, "", 4096, 0, NULL, NULL) = 0
[infinite loop]
```
The `recv()` calls were continuously returning 0 (EOF indicator) without the process handling the closed connection.

### 4. Code Analysis
Traced the issue to the `recv_inject()` function in `tac_plus-ng/main.c` where EOF was being mishandled.

## Root Cause Analysis

The bug was in the `recv_inject()` function's handling of socket EOF conditions. When remote peers close connections, `recv()` returns 0 to indicate EOF. The original code incorrectly converted this EOF (0) to an error (-1) with the line:
```c
return (!res && len) ? -1 : res;
```

This transformation had a cascading effect:
1. EOF (0) was converted to -1 (error)
2. Since `errno` wasn't set for EOF, it retained `EAGAIN` from previous operations
3. The calling code interpreted -1 with `errno=EAGAIN` as "try again later"
4. Event handler skipped cleanup and retried indefinitely
5. Result: infinite busy loops with `recvfrom()` continuously returning 0

## Impact

### System Performance
- **CPU Usage**: 40-60% per stuck process
- **Load Average**: 30+ on 16-core systems  
- **Memory**: Gradual increase due to unclosed connections
- **File Descriptors**: Exhaustion risk from accumulated CLOSE_WAIT sockets

### Service Impact
- **Authentication Delays**: TACACS+ authentication requests experiencing timeouts
- **Connection Limits**: New connections rejected when limits reached
- **Cascading Failures**: Network devices falling back to local authentication
- **Operational Impact**: Critical infrastructure authentication compromised

## Fix Implementation

The current codebase has been refactored with improved error handling. Instead of the simple EOF-to-error conversion that was originally patched, the code now uses a more sophisticated `enum io_status` mechanism:

### 1. Enhanced recv_inject() Function (main.c)
`recv_inject()` now accepts an `io_status` pointer parameter and properly sets status values:
- `io_status_close` for EOF conditions
- `io_status_error` for actual errors
- `io_status_retry` for EAGAIN/EWOULDBLOCK
- `io_status_ok` for successful reads

### 2. Systematic Status Checking (packet.c)
All `recv_inject()` calls now use `check_status()` which:
- Properly handles EOF by calling `cleanup()` when `io_status_close` is detected
- Ensures consistent error handling across all read operations
- Prevents the EAGAIN misinterpretation that caused the infinite loops

This refactored approach is more robust than the original fix documented in CHANGES-CC.md, providing systematic EOF handling throughout the codebase rather than individual EOF checks at each call site.

## Verification

### Test Methodology
1. **Controlled Disconnect Test**: Initiated connections and forcefully closed them from client side
2. **Load Testing**: Simulated high connection churn with automated connect/disconnect cycles
3. **Monitoring**: Tracked CPU, memory, and socket states during testing

### Results After Fix
- **CPU Usage**: Returns to normal (<1% when idle)
- **Load Average**: Drops to expected levels (<2 on 16-core systems)
- **Socket States**: No CLOSE_WAIT accumulation; proper cleanup observed
- **strace Verification**: Shows proper connection cleanup:
  ```
  recvfrom(7, "", 4096, 0, NULL, NULL) = 0
  close(7) = 0
  ```
- **Connection Handling**: Graceful handling of 1000+ connections/minute in testing

## Additional Patches

Ubuntu compatibility patches are applied separately via `apply_ubuntu_patches.sh` to address:
1. **OpenSSL Version Warning**: Comments out version check warning for OpenSSL < 3.0
2. **LDAP TLS 1.3 Compatibility**: Disables TLS 1.3 options that may not be available in Ubuntu's LDAP libraries

These patches enable compilation on Ubuntu systems with standard package versions without affecting the core EOF bug fix.

## Recommendations

1. **Immediate**: Apply this fix to all production TACACS+ servers
2. **Monitoring**: Set up alerts for CLOSE_WAIT socket accumulation
3. **Testing**: Implement connection stress testing in QA environments
4. **Long-term**: Consider implementing connection timeout mechanisms as additional safeguard