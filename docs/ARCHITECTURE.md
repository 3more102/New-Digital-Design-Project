# Architecture - Multi-Channel Timer/Counter Subsystem

## 1. System Overview

```mermaid
graph TB
    subgraph "Timer Subsystem"
        subgraph "Register Block"
            RB[Register Block<br/>APB Interface]
        end
        
        subgraph "Clock Domain"
            PS[Prescaler]
            
            subgraph "Channel 0"
                C0[Counter 0]
                CC0[Compare Unit 0]
                PWM0[PWM Gen 0]
                IC0[Input Capture 0]
                CAS0[Cascade Unit 0]
            end
            
            subgraph "Channel 1"
                C1[Counter 1]
                CC1[Compare Unit 1]
                PWM1[PWM Gen 1]
                IC1[Input Capture 1]
                CAS1[Cascade Unit 1]
            end
            
            subgraph "Channel 2"
                C2[Counter 2]
                CC2[Compare Unit 2]
                PWM2[PWM Gen 2]
                IC2[Input Capture 2]
                CAS2[Cascade Unit 2]
            end
            
            subgraph "Channel 3"
                C3[Counter 3]
                CC3[Compare Unit 3]
                PWM3[PWM Gen 3]
                IC3[Input Capture 3]
                CAS3[Cascade Unit 3]
            end
        end
        
        subgraph "Interrupt"
            IRQ[Interrupt Controller]
        end
    end
    
    CPU[CPU/SoC] <-->|APB| RB
    RB --> PS
    RB --> C0 & C1 & C2 & C3
    RB --> CC0 & CC1 & CC2 & CC3
    RB --> PWM0 & PWM1 & PWM2 & PWM3
    RB --> IC0 & IC1 & IC2 & IC3
    RB --> CAS0 & CAS1 & CAS2 & CAS3
    
    PS -->|tick| C0 & C1 & C2 & C3
    
    C0 --> CC0 & PWM0
    C1 --> CC1 & PWM1
    C2 --> CC2 & PWM2
    C3 --> CC3 & PWM3
    
    CC0 & CC1 & CC2 & CC3 --> IRQ
    CAS0 -->|cascade| C1
    CAS1 -->|cascade| C2
    CAS2 -->|cascade| C3
    
    CAP0[Capture In 0] --> IC0
    CAP1[Capture In 1] --> IC1
    CAP2[Capture In 2] --> IC2
    CAP3[Capture In 3] --> IC3
    
    PWM0 --> PWM_OUT0[PWM Out 0]
    PWM1 --> PWM_OUT1[PWM Out 1]
    PWM2 --> PWM_OUT2[PWM Out 2]
    PWM3 --> PWM_OUT3[PWM Out 3]
    
    IRQ --> IRQ_OUT[IRQ]
```

## 2. Channel Architecture

Each timer channel follows this internal structure:

```mermaid
graph LR
    subgraph "Timer Channel"
        direction TB
        
        subgraph "Counter"
            UP[Up Logic]
            DN[Down Logic]
            MUX[Mode Mux]
            FF[Count Register<br/>WIDTH bits]
        end
        
        subgraph "Compare"
            CMP[Comparator]
            CR[Compare Register]
        end
        
        subgraph "PWM"
            PCM[PWM Compare Reg]
            DUTY[Duty Calculation]
            PWM_FF[PWM Output FF]
        end
        
        subgraph "Capture"
            CAP_FF[Capture Register]
            EDGE[Edge Detector]
            DEB[Debounce Filter]
        end
        
        subgraph "Cascade"
            CAS_IN[Cascade In]
            DET[Edge Detect]
            CAS_OUT[Cascade Out]
        end
    end
    
    CLK_IN[Prescaler Tick] --> MUX
    EN_IN[Channel Enable] --> MUX
    MODE_IN[Mode 1:0] --> MUX
    
    MUX --> UP & DN
    UP & DN --> FF
    
    FF --> CMP
    CR --> CMP
    CMP --> MATCH[Match Event]
    
    FF --> PCM
    PCM --> DUTY
    DUTY --> PWM_FF
    PWM_FF --> PWM_OUT[PWM Out]
    
    EXT_IN[Capture In] --> DEB
    DEB --> EDGE
    EDGE --> CAP_FF
    FF --> CAP_FF
    CAP_FF --> CAP_VAL[Captured Value]
    
    OV[Overflow] --> DET
    UN[Underflow] --> DET
    DET --> CAS_OUT
```

## 3. APB Bus Protocol

```mermaid
sequenceDiagram
    participant CPU
    participant APB as APB Slave
    participant REG as Register Block
    
    Note over CPU,REG: Write Transaction
    CPU->>APB: psel=1, penable=0, pwrite=1, paddr, pwdata
    Note right of CPU: Setup Phase
    CPU->>APB: penable=1
    Note right of CPU: Access Phase
    APB->>REG: Write to register
    APB-->>CPU: pready=1
    
    Note over CPU,REG: Read Transaction
    CPU->>APB: psel=1, penable=0, pwrite=0, paddr
    Note right of CPU: Setup Phase
    CPU->>APB: penable=1
    Note right of CPU: Access Phase
    REG->>APB: Read register value
    APB-->>CPU: prdata, pready=1
```

## 4. Cascade Flow

```mermaid
sequenceDiagram
    participant PS as Prescaler
    participant C0 as Counter 0
    participant C1 as Counter 1
    participant C2 as Counter 2
    
    Note over PS,C2: Channel 0 overflows
    PS->>C0: tick
    Note right of C0: count reaches max
    C0-->>C1: overflow trigger
    Note right of C1: cascade_in rising edge
    C0->>C0: reload
    C1->>C1: increment
    
    Note over PS,C2: Channel 1 overflows
    PS->>C0: tick
    C0-->>C1: (cascade continues)
    Note right of C1: count reaches max
    C1-->>C2: overflow trigger
    Note right of C2: cascade_in rising edge
    C1->>C1: reload
    C2->>C2: increment
```

## 5. Interrupt Flow

```mermaid
graph TB
    subgraph "Channel Sources"
        OV0[CH0 Overflow]
        UN0[CH0 Underflow]
        MT0[CH0 Match]
        CP0[CH0 Capture]
        OV1[CH1 Overflow]
        UN1[CH1 Underflow]
        MT1[CH1 Match]
        CP1[CH1 Capture]
    end
    
    subgraph "Interrupt Controller"
        MASK[Enable Masks]
        OR[Priority OR Tree]
        PEND[Pending Registers]
        CLR[Clear Logic]
    end
    
    OV0 & UN0 & MT0 & CP0 --> OR
    OV1 & UN1 & MT1 & CP1 --> OR
    MASK --> OR
    OR --> PEND
    CLR --> PEND
    
    PEND --> GIRQ[Global IRQ]
    GIRQ --> CPU[CPU Interrupt]
```

## 6. Data Flow Diagram

```mermaid
flowchart TD
    CLK[Clock Source] --> PRESCALER
    
    PRESCALER -->|tick| CH0[Channel 0 Counter]
    PRESCALER -->|tick| CH1[Channel 1 Counter]
    PRESCALER -->|tick| CH2[Channel 2 Counter]
    PRESCALER -->|tick| CH3[Channel 3 Counter]
    
    CH0 -->|compare| CMP0[Match 0]
    CH1 -->|compare| CMP1[Match 1]
    CH2 -->|compare| CMP2[Match 2]
    CH3 -->|compare| CMP3[Match 3]
    
    CH0 -->|count| PWM0[PWM 0]
    CH1 -->|count| PWM1[PWM 1]
    CH2 -->|count| PWM2[PWM 2]
    CH3 -->|count| PWM3[PWM 3]
    
    CAP_IN0 -->|capture| CAP0[Capture 0]
    CAP_IN1 -->|capture| CAP1[Capture 1]
    CAP_IN2 -->|capture| CAP2[Capture 2]
    CAP_IN3 -->|capture| CAP3[Capture 3]
    
    CMP0 & CMP1 & CMP2 & CMP3 --> IRQ[IRQ Controller]
    CAP0 & CAP1 & CAP2 & CAP3 --> IRQ
    
    IRQ --> IRQ_OUT[Interrupt Output]
    
    PWM0 --> PWM0_OUT[PWM Out 0]
    PWM1 --> PWM1_OUT[PWM Out 1]
    PWM2 --> PWM2_OUT[PWM Out 2]
    PWM3 --> PWM3_OUT[PWM Out 3]
```

## 7. State Diagram (Counter Modes)

```mermaid
stateDiagram-v2
    [*] --> Stop: rst_n = 0
    
    Stop --> Up: mode = 01
    Stop --> Down: mode = 10
    Stop --> UpDown: mode = 11
    
    Up --> Stop: mode = 00
    Down --> Stop: mode = 00
    UpDown --> Stop: mode = 00
    
    Up --> Up: count < max
    Up --> Up: overflow → reload
    
    Down --> Down: count > 0
    Down --> Down: underflow → reload
    
    UpDown --> UpDown: counting up
    UpDown --> UpDown: counting down
    note right of UpDown: Bounces between 0 and max
```

## 8. Module Dependency Graph

```mermaid
graph TD
    TOP[timer_top] --> PRESCALER[prescaler]
    TOP --> COUNTER[counter]
    TOP --> COMPARE[compare_unit]
    TOP --> PWM[pwm_generator]
    TOP --> CAPTURE[input_capture]
    TOP --> CASCADE[cascade_unit]
    TOP --> REG[register_block]
    TOP --> IRQ[interrupt_controller]
    
    COUNTER -->|overflow/underflow| CASCADE
    COMPARE -->|match| IRQ
    CAPTURE -->|capture_event| IRQ
    COUNTER -->|count| COMPARE
    COUNTER -->|count| PWM
    COUNTER -->|count| CAPTURE
    
    REG -->|config| COUNTER
    REG -->|config| COMPARE
    REG -->|config| PWM
    REG -->|config| CAPTURE
    REG -->|config| CASCADE
    REG -->|int_en, int_clr| IRQ
    
    style TOP fill:#f9f,stroke:#333
    style REG fill:#bbf,stroke:#333
    style IRQ fill:#fbb,stroke:#333
```

## 9. Timing Diagrams

### 9.1 Up-Count with Overflow

```mermaid
gantt
    title Up-Count Timer with Overflow
    dateFormat X
    axisFormat %s
    
    section Clock
    clk : 0, 1
    clk : 1, 2
    clk : 2, 3
    clk : 3, 4
    clk : 4, 5
    
    section Counter
    count=0 : 0, 1
    count=1 : 1, 2
    count=2 : 2, 3
    count=max : 3, 4
    count=reload : 4, 5
```

### 9.2 PWM Output

```mermaid
gantt
    title PWM 50% Duty Cycle
    dateFormat X
    axisFormat %s
    
    section Counter
    counting up : 0, 5
    
    section PWM Output
    HIGH : 0, 3
    LOW : 3, 5
```
