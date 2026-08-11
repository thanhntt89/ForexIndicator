# DCA Strategy — Flowcharts & Sequence Diagrams

## 1. Tổng quan OnTick() Flow với DCA

```mermaid
flowchart TD
    A[OnTick] --> B[ManageTrailing - existing TP2 trailing]
    B --> C[ManageDCA]
    C --> D[UpdateDailyLossTracking]
    D --> E{New bar?}
    E -->|No| Z[Return]
    E -->|Yes| F[Read indicator buffers]
    F --> G[9-Gate Decision Pipeline]
    G -->|FAIL| Z
    G -->|PASS| H[Calculate lot, adjust SL/TP]
    H --> I[Place order - TP1/TP2 split]
    I --> J[Initialize DCA State]
    J --> K[SaveDCAState]
    K --> Z
```

## 2. ManageDCA() Wrapper Flow

```mermaid
flowchart TD
    A[ManageDCA] --> B{DCA features enabled?}
    B -->|No| Z[Return]
    B -->|Yes| C{g_dcaActive?}
    C -->|No| Z
    C -->|Yes| D{Any positions remain?}
    D -->|No| E[ClearDCAState - auto reset]
    E --> Z
    D -->|Yes| F[ManagePositiveDCA]
    F --> G[ManageNegativeDCA]
    G --> Z
```

## 3. Positive DCA — Full Lifecycle

```mermaid
sequenceDiagram
    participant Signal as Indicator Signal
    participant EA as EA OnTick
    participant Market as Market
    participant State as DCA State

    Note over Signal,State: Phase 1: Signal Entry
    Signal->>EA: BUY signal detected (Case 6)
    EA->>Market: Place TP1 lot (0.06) + TP2 lot (0.04)
    EA->>State: g_dcaActive=true, entry=2000, TP1=2100, SL=1950

    Note over Signal,State: Phase 2: Positive DCA Grid
    Note right of EA: Grid: spacing=(2100-2000)/5 = 20pts<br/>Levels: 2020, 2040, 2060, 2080
    Market->>EA: Price reaches 2020
    EA->>Market: DCA+1: BUY 0.10 lot @ 2020 (magic+200001)
    Market->>EA: Price reaches 2040
    EA->>Market: DCA+2: BUY 0.10 lot @ 2040 (magic+200002)

    Note over Signal,State: Phase 3: 50% Cutoff
    Market->>EA: Price reaches 2050 (50% of Entry→TP1)
    EA->>EA: Stop adding positive DCA orders
    Note right of EA: DCA+3 (2060) and DCA+4 (2080)<br/>will NOT be placed

    Note over Signal,State: Phase 4: TP1 Hit → Half Close
    Market->>EA: Price reaches 2100 (TP1)
    Note right of EA: TP1 leg auto-closed by broker (SL/TP on order)<br/>DCA orders: sort by entry desc → [2040, 2020]
    EA->>Market: Close DCA+2 (entry 2040, least profitable)
    EA->>Market: Keep DCA+1 (entry 2020, most profitable)
    EA->>Market: Modify DCA+1 SL → 2050 (50% of 2000↔2100)
    EA->>State: g_dcaTP1HalfClosed=true

    Note over Signal,State: Phase 5: TP2 Trailing continues
    Note right of EA: TP2 leg (magic+100000) continues<br/>with ATR trailing stop.<br/>Remaining DCA+1 rides with locked SL=2050
```

## 4. Positive DCA — Edge Case: Giá chạm TP1 nhanh (ít DCA orders)

```mermaid
sequenceDiagram
    participant EA as EA OnTick
    participant Market as Market

    Note over EA,Market: Chỉ có 1 DCA order kịp mở
    Market->>EA: Price rushes from 2000 to 2100 nhanh
    EA->>Market: DCA+1 placed @ 2020
    Note right of EA: DCA+2,3,4 chưa kịp trigger
    Market->>EA: Price hits 2100 (TP1)
    Note right of EA: count=1, ceil(1/2)=1 → close ALL DCA
    EA->>Market: Close DCA+1
    Note right of EA: Không còn DCA order → không cần move SL
```

## 5. Negative DCA — Full Lifecycle

```mermaid
sequenceDiagram
    participant EA as EA OnTick
    participant Market as Market
    participant State as DCA State

    Note over EA,State: Phase 1: Entry đã có
    Note right of EA: BUY entry=2000, SL=1950, TP1=2100

    Note over EA,State: Phase 2: Price drops — Trigger Check
    Market->>EA: Price drops to 1980
    EA->>EA: 50% of Entry→SL = 2000+(1950-2000)*0.5 = 1975
    EA->>EA: Price 1980 > 1975 → NOT triggered yet

    Market->>EA: Price drops to 1974
    EA->>EA: Price 1974 ≤ 1975 → TRIGGERED!
    EA->>State: g_dcaNegTriggered=true, triggerPrice=1975

    Note over EA,State: Phase 3: Place Negative DCA orders
    Note right of EA: Spacing = ATR(14) * 0.5<br/>Giả sử ATR = 20 → spacing = 10
    Note right of EA: Levels from triggerPrice:<br/>DCA-1: 1975 (trigger point)<br/>DCA-2: 1965<br/>DCA-3: 1955<br/>DCA-4: 1945<br/>DCA-5: 1935
    Market->>EA: Price at 1974 ≤ 1975
    EA->>Market: DCA-1: BUY 0.075 lot (75%) @ 1974, no SL/TP
    Market->>EA: Price drops to 1964
    EA->>Market: DCA-2: BUY 0.050 lot (50%) @ 1964, no SL/TP
    Market->>EA: Price drops to 1954
    EA->>Market: DCA-3: BUY 0.025 lot (25%) @ 1954, no SL/TP

    Note over EA,State: Phase 4: Drawdown Cap Check (every tick)
    EA->>EA: basketPnL = sum of all floating P&L
    EA->>EA: Check: |basketPnL| < balance * 5%
    EA->>EA: OK → continue

    Note over EA,State: Phase 5: Price Recovery → Breakeven
    Market->>EA: Price starts recovering
    Note right of EA: Average entry calculation:<br/>Original: 0.10 lot @ 2000<br/>DCA-1: 0.075 @ 1974<br/>DCA-2: 0.050 @ 1964<br/>DCA-3: 0.025 @ 1954<br/>Weighted avg = (0.10*2000 + 0.075*1974<br/>+ 0.050*1964 + 0.025*1954) / 0.250<br/>= 1985.6
    Market->>EA: Price reaches 1986 (≥ avg entry 1985.6)
    EA->>EA: BREAKEVEN reached!
    EA->>Market: Close original TP1 (magic) @ 1986 → loss -14pts
    EA->>Market: Close original TP2 (magic+100000) @ 1986 → loss -14pts
    EA->>Market: Close DCA-1 (magic+300001) @ 1986 → profit +12pts
    EA->>Market: Close DCA-2 (magic+300002) @ 1986 → profit +22pts
    EA->>Market: Close DCA-3 (magic+300003) @ 1986 → profit +32pts
    Note right of EA: Net ≈ 0 (breakeven after spread/commission)
    EA->>State: ClearDCAState()
```

## 6. Negative DCA — Drawdown Cap Hit

```mermaid
sequenceDiagram
    participant EA as EA OnTick
    participant Market as Market

    Note over EA,Market: Balance = $10,000, Cap = 5% = $500
    EA->>Market: Original BUY 0.10 @ 2000
    EA->>Market: DCA-1 BUY 0.075 @ 1974
    EA->>Market: DCA-2 BUY 0.050 @ 1964
    EA->>Market: DCA-3 BUY 0.025 @ 1954

    Market->>EA: Price crashes to 1910
    EA->>EA: basketPnL calculation:
    Note right of EA: Original: (1910-2000)*0.10 = -$90<br/>DCA-1: (1910-1974)*0.075 = -$48<br/>DCA-2: (1910-1964)*0.050 = -$27<br/>DCA-3: (1910-1954)*0.025 = -$11<br/>Total basket = -$176<br/>TP2 trailing: (1910-2000)*0.04 = -$36<br/>Grand total ≈ -$212

    Market->>EA: Price crashes to 1800
    EA->>EA: Total floating loss ≈ -$520
    EA->>EA: $520 > $500 cap → DRAWDOWN CAP HIT!
    EA->>Market: CloseEntireBasket() — close ALL positions
    EA->>EA: ClearDCAState()
    Note right of EA: Loss capped at ~$520<br/>Without cap: could be $1000+ if price<br/>continues to 1700
```

## 7. Positive + Negative DCA Combined Scenario

```mermaid
flowchart TD
    A[Signal: BUY @ 2000<br/>SL=1950, TP1=2100] --> B{Price direction?}
    
    B -->|Up ↑| C[Positive DCA Zone<br/>Grid: 2020, 2040, 2060, 2080]
    C --> D{Price > 2050?<br/>50% of Entry→TP1}
    D -->|No| E[Continue placing DCA+]
    D -->|Yes| F[Stop positive DCA]
    F --> G{Price hits 2100?}
    G -->|Yes| H[Half-close DCA+ orders<br/>Lock SL at 2050]
    
    B -->|Down ↓| I{Price < 1975?<br/>50% of Entry→SL}
    I -->|No| J[Wait - no action]
    I -->|Yes| K[Trigger Negative DCA<br/>ATR-spaced: 1975, 1965, 1955...]
    K --> L{Basket loss > 5%?}
    L -->|Yes| M[DRAWDOWN CAP<br/>Close ALL immediately]
    L -->|No| N{Price ≥ avg entry?}
    N -->|Yes| O[BREAKEVEN<br/>Close original + neg DCA]
    N -->|No| P[Continue neg DCA<br/>max 5 orders]
    
    B -->|Oscillate ↔| Q[Both systems may activate<br/>sequentially - not simultaneously]
    
    style M fill:#ff6b6b,color:#fff
    style H fill:#51cf66,color:#fff
    style O fill:#ffd43b,color:#000
```

## 8. State Machine Diagram

```mermaid
stateDiagram-v2
    [*] --> IDLE: EA starts / all positions closed

    IDLE --> DCA_ACTIVE: Signal fires + order placed
    note right of DCA_ACTIVE: g_dcaActive = true<br/>DCA state initialized

    DCA_ACTIVE --> POS_DCA_ADDING: Price moves toward TP1
    POS_DCA_ADDING --> POS_DCA_STOPPED: Price > 50% to TP1
    POS_DCA_ADDING --> POS_DCA_HALFCLOSE: Price hits TP1
    POS_DCA_STOPPED --> POS_DCA_HALFCLOSE: Price hits TP1

    DCA_ACTIVE --> NEG_DCA_TRIGGERED: Price moves 50% toward SL
    NEG_DCA_TRIGGERED --> NEG_DCA_ADDING: ATR levels reached
    NEG_DCA_ADDING --> BASKET_BREAKEVEN: Price returns to avg entry
    NEG_DCA_ADDING --> DRAWDOWN_CAP: Basket loss > X%

    POS_DCA_HALFCLOSE --> DCA_ACTIVE: Remaining orders ride with locked SL
    BASKET_BREAKEVEN --> IDLE: Close original + neg DCA
    DRAWDOWN_CAP --> IDLE: Close ALL positions

    DCA_ACTIVE --> IDLE: All positions closed externally
    note right of IDLE: ClearDCAState() called
```

## 9. Order Lifecycle per Type

```mermaid
flowchart LR
    subgraph Original["Original Order (TP1 leg)"]
        O1[Placed with SL+TP1] --> O2[Auto-close by broker at TP1]
        O1 --> O3[Auto-close by broker at SL]
        O1 --> O4[Closed by neg DCA breakeven]
        O1 --> O5[Closed by drawdown cap]
        O1 --> O6[Closed by panel button]
    end

    subgraph TP2["Original Order (TP2 leg)"]
        T1[Placed with SL+TP2] --> T2[ATR trailing modifies SL]
        T2 --> T3[Auto-close by trailing SL]
        T2 --> T4[Auto-close by broker at TP2]
        T1 --> T5[Closed by neg DCA breakeven]
        T1 --> T6[Closed by drawdown cap]
    end

    subgraph PosDCA["Positive DCA Order"]
        P1[Placed with SL, no TP] --> P2[Half-closed at TP1 level]
        P1 --> P3[Kept with locked SL after half-close]
        P3 --> P4[Hit locked SL = exit with profit]
        P1 --> P5[Closed by drawdown cap]
        P1 --> P6[Auto-close by SL = g_dcaOriginalSL]
    end

    subgraph NegDCA["Negative DCA Order"]
        N1[Placed with no SL, no TP] --> N2[Closed at basket breakeven]
        N1 --> N3[Closed by drawdown cap]
        N1 --> N4[Closed by panel button]
    end
```
