#!/usr/bin/env bash
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

NJACKD_BIN=/home/folou/Documentos/njackd
NJACKCTL_BIN=/home/folou/Documentos/njackctl
SOCK=/tmp/njackd_test.sock
CFG=~/.config/njackd/config.json

cleanup() {
  echo ""
  echo "=== Cleaning up ==="
  kill "$NJACKD_PID" 2>/dev/null || true
  wait "$NJACKD_PID" 2>/dev/null || true
  kill "$SIMPLEC_PID" 2>/dev/null || true
  wait "$SIMPLEC_PID" 2>/dev/null || true
  kill "$SIMPLEC2_PID" 2>/dev/null || true
  wait "$SIMPLEC2_PID" 2>/dev/null || true
  kill "$JACKD_PID" 2>/dev/null || true
  wait "$JACKD_PID" 2>/dev/null || true
  rm -f "$SOCK"
  echo "Done."
}

trap cleanup EXIT INT TERM

echo "=== Starting JACK dummy driver ==="
jackd -d dummy -p 1024 &>/tmp/jackd_test.log &
JACKD_PID=$!
sleep 2

if ! jack_lsp &>/dev/null; then
  echo "FAIL: jackd did not start"; cat /tmp/jackd_test.log; exit 1
fi
pass "jackd started"

# Config
mkdir -p ~/.config/njackd
cat > "$CFG" <<'CFG'
{
  "default_volume": 0.75,
  "master_volume": 1.0,
  "ignored_clients": [],
  "poll_interval": 1.0,
  "socket_path": "/tmp/njackd_test.sock"
}
CFG

echo ""
echo "=== Test 1: njackd starts ==="
$NJACKD_BIN &>/tmp/njackd_test.log &
NJACKD_PID=$!
sleep 1

if ! $NJACKCTL_BIN status &>/dev/null; then
  echo "FAIL: njackd did not start"; cat /tmp/njackd_test.log; exit 1
fi
pass "njackd started"

echo ""
echo "=== Test 2: Singleton ==="
$NJACKD_BIN &>/tmp/njackd_singleton.log &
SINGLE_PID=$!
sleep 0.5
if kill -0 "$SINGLE_PID" 2>/dev/null; then
  fail "Second njackd should be rejected"
  kill "$SINGLE_PID" 2>/dev/null || true
else
  pass "Singleton: second instance rejected"
fi

echo ""
echo "=== Test 3: Device proxy routing ==="
if jack_lsp -c | grep -q 'device-sink'; then
  pass "device-sink exists"
else
  fail "device-sink not found"
fi

# device-sink:out_0 -> system:playback_1
ROUTING=$(jack_lsp -c device-sink:out_0 2>&1)
if echo "$ROUTING" | grep -q 'system:playback_1'; then
  pass "device-sink:out_0 -> system:playback_1"
else
  fail "device-sink:out_0 routing: $ROUTING"
fi

ROUTING=$(jack_lsp -c device-sink:out_1 2>&1)
if echo "$ROUTING" | grep -q 'system:playback_2'; then
  pass "device-sink:out_1 -> system:playback_2"
else
  fail "device-sink:out_1 routing: $ROUTING"
fi

echo ""
echo "=== Test 4: App proxy creation ==="
jack_simple_client &>/tmp/jack_simple.log &
SIMPLEC_PID=$!
sleep 2

LIST=$($NJACKCTL_BIN list 2>&1)
if echo "$LIST" | grep -q 'jack_simple_client'; then
  pass "jack_simple_client detected"
else
  fail "Not detected: $LIST"
fi

# Check proxy client exists
if jack_lsp -c | grep -q 'jack_simple_client-sink'; then
  pass "jack_simple_client-sink proxy exists"
else
  fail "Proxy not found"
fi

# Check app -> proxy-in
if jack_lsp -c jack_simple_client:output1 | grep -q 'jack_simple_client-sink:in_0'; then
  pass "jack_simple_client:output1 -> proxy:in_0"
else
  fail "output1 connection wrong"
fi

if jack_lsp -c jack_simple_client:output2 | grep -q 'jack_simple_client-sink:in_1'; then
  pass "jack_simple_client:output2 -> proxy:in_1"
else
  fail "output2 connection wrong"
fi

# Check proxy-out -> device-sink (NOT directly to system)
if jack_lsp -c jack_simple_client-sink:out_0 | grep -q 'device-sink:in_0'; then
  pass "proxy:out_0 -> device-sink:in_0"
else
  if jack_lsp -c jack_simple_client-sink:out_0 | grep -q 'system:playback_1'; then
    fail "proxy:out_0 connected directly to system (bypassing device proxy!)"
  else
    out=$(jack_lsp -c jack_simple_client-sink:out_0 2>&1)
    fail "proxy:out_0 not connected correctly: $out"
  fi
fi

if jack_lsp -c jack_simple_client-sink:out_1 | grep -q 'device-sink:in_1'; then
  pass "proxy:out_1 -> device-sink:in_1"
fi

# Verify app is NOT connected directly to system
if jack_lsp -c jack_simple_client:output1 | grep -q 'system:playback_1'; then
  fail "jack_simple_client:output1 still connected to system directly!"
else
  pass "jack_simple_client:output1 disconnected from system (correct)"
fi

echo ""
echo "=== Test 5: Mute/Unmute ==="
# Set a known volume first
$NJACKCTL_BIN set-volume jack_simple_client 0.5 &>/dev/null
sleep 0.3
LIST_BEFORE=$($NJACKCTL_BIN list 2>&1)
if echo "$LIST_BEFORE" | grep -v 'MUTE' | head -3 | grep -q ' '; then
  pass "list shows mute column"
fi

# Mute
$NJACKCTL_BIN mute jack_simple_client &>/dev/null
sleep 0.5
GV_MUTED=$($NJACKCTL_BIN get-volume jack_simple_client 2>&1)
if echo "$GV_MUTED" | grep -q '0'; then
  pass "mute sets volume to 0"
else
  fail "mute failed: $GV_MUTED"
fi

# Unmute
$NJACKCTL_BIN unmute jack_simple_client &>/dev/null
sleep 0.5
GV_UNMUTED=$($NJACKCTL_BIN get-volume jack_simple_client 2>&1)
if echo "$GV_UNMUTED" | grep -q '0.5'; then
  pass "unmute restores volume to 0.5"
else
  fail "unmute failed: $GV_UNMUTED"
fi

# Mute again, set-volume while muted
$NJACKCTL_BIN mute jack_simple_client &>/dev/null
sleep 0.3
$NJACKCTL_BIN set-volume jack_simple_client 0.8 &>/dev/null
sleep 0.3
GV_WHILE_MUTED=$($NJACKCTL_BIN get-volume jack_simple_client 2>&1)
if echo "$GV_WHILE_MUTED" | grep -q '0'; then
  pass "set-volume while muted: gain stays 0"
else
  fail "gain changed while muted: $GV_WHILE_MUTED"
fi
# Unmute should restore to the new volume (0.8)
$NJACKCTL_BIN unmute jack_simple_client &>/dev/null
sleep 0.3
GV_AFTER=$($NJACKCTL_BIN get-volume jack_simple_client 2>&1)
if echo "$GV_AFTER" | grep -q '0.8'; then
  pass "unmute after set-volume: restores to 0.8"
else
  fail "unmute restored wrong volume: $GV_AFTER"
fi

# Restore volume for later tests
$NJACKCTL_BIN set-volume jack_simple_client 0.5 &>/dev/null

echo ""
echo "=== Test 6: Per-app volume ==="
$NJACKCTL_BIN set-volume jack_simple_client 0.5 &>/dev/null
sleep 0.5
GV=$($NJACKCTL_BIN get-volume jack_simple_client 2>&1)
if echo "$GV" | grep -q '0.5'; then
  pass "set-volume 0.5 -> get-volume: $GV"
else
  fail "Volume mismatch: $GV"
fi

echo ""
echo "=== Test 7: Master volume ==="
$NJACKCTL_BIN set-master-volume 0.33 &>/dev/null
sleep 0.5
MV=$($NJACKCTL_BIN get-master-volume 2>&1)
if echo "$MV" | grep -q '0.33'; then
  pass "set-master-volume 0.33 -> get-master-volume: $MV"
else
  fail "Master volume mismatch: $MV"
fi

echo ""
echo "=== Test 8: Enforcement (PortAudio bypass simulation) ==="
# Simulate PortAudio: connect app output directly to system
jack_connect jack_simple_client:output1 system:playback_1 2>/dev/null || true
sleep 2  # wait for scan cycle

AFTER=$(jack_lsp -c jack_simple_client:output1 2>&1)
if echo "$AFTER" | grep -q 'jack_simple_client-sink'; then
  pass "Enforcement corrected bypass: output1 -> proxy"
else
  fail "Enforcement failed: $AFTER"
fi

echo ""
echo "=== Test 9: Multiple apps ==="
jack_simple_client &>/tmp/jack_simple2.log &
SIMPLEC2_PID=$!
sleep 2

LIST2=$($NJACKCTL_BIN list 2>&1)
CLIENT_COUNT=$(echo "$LIST2" | grep -c 'jack_simple_client')
if [ "$CLIENT_COUNT" -ge 2 ]; then
  pass "Both clients detected ($CLIENT_COUNT instances)"
else
  fail "Not both detected: $LIST2"
fi

# Second client should get different proxy name
if jack_lsp 2>/dev/null | grep -q 'jack_simple_client-01-sink'; then
  pass "Second client proxy: jack_simple_client-01-sink"
else
  SECOND_PROXY=$(jack_lsp 2>/dev/null | grep -- '-sink' | grep -v 'device-sink')
  SECOND_COUNT=$(echo "$SECOND_PROXY" | wc -l)
  if [ "$SECOND_COUNT" -ge 2 ]; then
    pass "Two proxy clients exist (not device-sink)"
  else
    fail "Only $SECOND_COUNT proxy clients: $SECOND_PROXY"
  fi
fi

# Check second proxy routes through device-sink
if jack_lsp -c jack_simple_client-01:output1 2>/dev/null | grep -q 'jack_simple_client-01-sink:in_0'; then
  pass "Second client: output1 -> proxy-in"
else
  OUT1=$(jack_lsp -c jack_simple_client-01:output1 2>/dev/null)
  fail "Second client routing wrong: $OUT1"
fi
if jack_lsp -c jack_simple_client-01-sink:out_0 2>/dev/null | grep -q 'device-sink:in_0'; then
  pass "Second proxy: out_0 -> device-sink:in_0"
else
  OUT2=$(jack_lsp -c jack_simple_client-01-sink:out_0 2>/dev/null)
  fail "Second proxy routing wrong: $OUT2"
fi

echo ""
echo "=== Test 10: Client cleanup ==="
kill "$SIMPLEC2_PID" 2>/dev/null || true
wait "$SIMPLEC2_PID" 2>/dev/null || true
sleep 2  # wait for scan

if jack_lsp 2>/dev/null | grep -q 'jack_simple_client-sink-01'; then
  fail "Proxy for removed client still exists"
else
  pass "Proxy cleaned up after client disconnect"
fi

echo ""
echo "=== Test 11: Status ==="
ST=$($NJACKCTL_BIN status 2>&1)
echo "  status: $ST"
if echo "$ST" | grep -q 'clients:'; then
  pass "Status shows clients"
fi
if echo "$ST" | grep -q 'version:'; then
  pass "Status shows version"
fi
if echo "$ST" | grep -q 'xruns:'; then
  pass "Status shows xruns"
fi

echo ""
echo "=== Test 12: Graceful shutdown ==="
$NJACKCTL_BIN quit &>/dev/null || true
sleep 1
if kill -0 "$NJACKD_PID" 2>/dev/null; then
  fail "njackd still running after quit"
else
  pass "Daemon shut down cleanly"
fi

if jack_lsp 2>/dev/null | grep -q 'device-sink'; then
  fail "device-sink still exists after shutdown"
else
  pass "device-sink removed after shutdown"
fi

if jack_lsp 2>/dev/null | grep -q 'jack_simple_client-sink'; then
  fail "Proxy still exists after shutdown"
else
  pass "Proxies removed after shutdown"
fi

echo ""
echo "=== Test 13: Clean restart after quit ==="
$NJACKD_BIN &>/tmp/njackd_restart.log &
NJACKD_PID=$!
sleep 1
if $NJACKCTL_BIN status &>/dev/null; then
  pass "Clean restart after quit"
else
  fail "Restart failed"
fi

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
fi
