# Latency Review: SessionFilter.mqh

**File**: `Include/RSI_Advanced/SessionFilter.mqh` (~47 lines)
**Role**: Session quality scoring by time-of-day and case type
**Severity**: LOW

---

## Critical Bugs: NONE

---

## Observations

### 1. `DetectInstrumentType()` Called Every Invocation
**Location**: Line 26

```mql
if(DetectInstrumentType() == INST_CRYPTO) return(0.5);
```

**Problem**: `DetectInstrumentType()` does string matching on Symbol() every time. This function is called from signal scoring which runs during signal detection loops.

**Impact**: LOW — string matching is fast, but the result is invariant per session.

**Fix**: Use cached instrument type (see Normalize.mqh review).

### 2. Hardcoded Session Quality Values
- Values like 0.7, 0.5, 0.4 are static — could be data-driven from SessionStatistics
- **Not a bug** — these serve as fallback when insufficient measured data exists

### 3. `GetUTCHour()` Dependency
- Relies on `GetUTCHour()` from Normalize.mqh for timezone conversion
- Correctly uses UTC-based session blocks

---

## Verdict: PASS — No action required
