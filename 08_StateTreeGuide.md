# StateTree 완전 가이드

> **문서 목적**: StateTree의 기초부터 Mass AI 통합까지 완전 정복
>
> **난이도**: ★★★☆☆ (중급)
>
> **핵심 질문**: "Mass AI 몬스터에게 어떻게 지능적인 행동을 부여할까?"

---

## 1. StateTree가 뭔가요?

### 한 줄 요약

**StateTree는 "비주얼 상태 머신 + 행동 트리"의 하이브리드**예요.

기존에 쓰던 것들과 비교해볼게요:

```
┌────────────────────────────────────────────────────────────────────┐
│                   AI 행동 제어 방식 비교                            │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Behavior Tree (BT)                                                │
│  ├── 장점: 복잡한 행동 흐름, 재사용성                              │
│  ├── 단점: 상태 관리 어려움, 무겁다                                │
│  └── 적합: 복잡한 보스 AI, 동료 AI                                 │
│                                                                     │
│  Finite State Machine (FSM)                                        │
│  ├── 장점: 직관적, 상태 전이 명확                                  │
│  ├── 단점: 복잡해지면 스파게티, 재사용 어려움                      │
│  └── 적합: 간단한 상태 전환                                        │
│                                                                     │
│  StateTree (NEW!)                                                  │
│  ├── 장점: FSM의 직관성 + BT의 유연성                              │
│  ├── 특징: 데이터 지향, Mass AI 네이티브 지원!                     │
│  └── 적합: 대량 AI, 상태 기반 행동                                 │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 왜 StateTree를 써야 하나요?

Mass AI와 함께 쓸 때 이런 장점이 있어요:

1. **Mass 네이티브 지원**: `MassStateTreeTrait`로 바로 연결
2. **데이터 지향 설계**: Fragment 데이터 직접 접근
3. **에디터 친화적**: 비주얼 편집, 블루프린트 Task 지원
4. **성능 최적화**: 배치 평가 가능

---

## 2. StateTree 기본 개념

### 2.1 핵심 구성 요소

StateTree는 이런 것들로 구성됩니다:

```
StateTree
├── State (상태)
│   ├── 진입 조건 (Enter Conditions)
│   ├── 실행 Task (Tasks)
│   ├── 전이 조건 (Transitions)
│   └── 하위 State (Sub-States)
├── Task (작업)
│   └── 실제 행동 로직
├── Condition (조건)
│   └── 전이 가능 여부 판단
├── Evaluator (평가자)
│   └── 데이터 계산/캐싱
└── Schema (스키마)
    └── 사용 가능한 컨텍스트 정의
```

### 2.2 시각적으로 이해하기

```
┌────────────────────────────────────────────────────────────────────┐
│                    StateTree 예시: 몬스터 AI                        │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌─────────────┐                                                   │
│  │   Root      │ ◄── 최상위 상태                                   │
│  └──────┬──────┘                                                   │
│         │                                                          │
│    ┌────┴────┬────────────┐                                       │
│    ▼         ▼            ▼                                       │
│  ┌─────┐  ┌──────┐    ┌────────┐                                  │
│  │Idle │  │Chase │    │ Attack │                                  │
│  │대기 │  │추적  │    │ 공격   │                                  │
│  └──┬──┘  └──┬───┘    └───┬────┘                                  │
│     │        │            │                                        │
│     │ 플레이어│ 공격 범위  │                                       │
│     │ 발견?   │ 진입?      │ 공격 완료?                            │
│     ▼        ▼            ▼                                        │
│  [조건 체크] [조건 체크]  [Task 실행]                              │
│                                                                     │
│  전이 흐름:                                                        │
│  Idle ──(플레이어 발견)──▶ Chase                                  │
│  Chase ──(공격 범위)──▶ Attack                                    │
│  Attack ──(공격 완료)──▶ Chase                                    │
│  Chase ──(플레이어 사라짐)──▶ Idle                                │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 2.3 용어 정리

| 용어 | 역할 | 블루프린트 비유 |
|------|------|----------------|
| **State** | 현재 상태 (Idle, Chase, Attack 등) | Enum + 로직 |
| **Task** | 상태에서 실행할 행동 | Custom Event |
| **Condition** | 전이 조건 판단 | Branch 노드 |
| **Evaluator** | 데이터 계산/캐싱 | 변수 계산 |
| **Transition** | 상태 간 전이 규칙 | Flow Control |
| **Schema** | 사용 맥락 정의 | Interface |

---

## 3. StateTree 에디터 사용법

### 3.1 StateTree 에셋 생성

```
1. 콘텐츠 브라우저에서 우클릭
2. AI → StateTree 선택
3. 이름 지정 (예: ST_MonsterBehavior)
4. 더블클릭하여 에디터 열기
```

### 3.2 에디터 인터페이스

```
┌────────────────────────────────────────────────────────────────────┐
│  StateTree 에디터 레이아웃                                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────────┬─────────────────────────────────────────┐   │
│  │                  │                                          │   │
│  │   Tree View      │         State Details                    │   │
│  │   (상태 계층)    │         (선택된 상태 설정)               │   │
│  │                  │                                          │   │
│  │   └─ Root        │   ┌─────────────────────────────────┐    │   │
│  │      ├─ Idle     │   │  State: Chase                   │    │   │
│  │      ├─ Chase    │   │                                 │    │   │
│  │      │  └─ ...   │   │  Enter Conditions:              │    │   │
│  │      └─ Attack   │   │  ├─ Is Player In Range          │    │   │
│  │                  │   │                                 │    │   │
│  │                  │   │  Tasks:                         │    │   │
│  │                  │   │  ├─ Move To Target              │    │   │
│  │                  │   │                                 │    │   │
│  │                  │   │  Transitions:                   │    │   │
│  │                  │   │  ├─ To Attack (if in range)     │    │   │
│  │                  │   │  └─ To Idle (if target lost)    │    │   │
│  │                  │   └─────────────────────────────────┘    │   │
│  └──────────────────┴─────────────────────────────────────────┘   │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │   Parameters (전역 파라미터)                                 │   │
│  │   ├─ ChaseSpeed: 400.0                                      │   │
│  │   ├─ AttackRange: 100.0                                     │   │
│  │   └─ DetectionRange: 1000.0                                 │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 3.3 State 만들기

```
1. Tree View에서 우클릭
2. "Add State" 선택
3. 상태 이름 입력 (예: Chase)
4. Details 패널에서 설정:
   - Enter Conditions: 이 상태로 진입할 조건
   - Tasks: 이 상태에서 실행할 작업
   - Transitions: 다른 상태로 전이할 조건
```

### 3.4 Schema 설정

Mass AI와 함께 쓰려면 올바른 Schema를 선택해야 해요:

```
StateTree Settings → Schema 선택:

  □ StateTreeActorSchema         ← 일반 Actor용
  □ StateTreeComponentSchema     ← Component 기반
  ■ MassStateTreeSchema          ← Mass AI용 (이거 선택!)

MassStateTreeSchema를 선택하면:
- Mass Entity의 Fragment 접근 가능
- Mass Processor와 연동
- 배치 평가 지원
```

---

## 4. Task 만들기

### 4.1 Blueprint Task (초보자용)

가장 쉬운 방법! 블루프린트로 Task를 만들 수 있어요.

**생성 방법:**

```
1. 콘텐츠 브라우저 우클릭
2. Blueprint Class 선택
3. 부모 클래스 검색: "StateTreeTaskBlueprintBase"
4. 생성 (예: BP_Task_ChaseTarget)
```

**블루프린트 Task 구조:**

```
┌────────────────────────────────────────────────────────────────────┐
│  BP_Task_ChaseTarget                                               │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  오버라이드 가능한 이벤트:                                         │
│                                                                     │
│  ┌───────────────────┐                                             │
│  │ Enter State       │ ← 상태 진입 시 한 번 호출                   │
│  │ (처음 실행)       │                                             │
│  └───────────────────┘                                             │
│          │                                                          │
│          ▼                                                          │
│  ┌───────────────────┐                                             │
│  │ Tick              │ ← 매 프레임 호출 (선택)                     │
│  │ (반복 실행)       │   Return: Running / Succeeded / Failed      │
│  └───────────────────┘                                             │
│          │                                                          │
│          ▼                                                          │
│  ┌───────────────────┐                                             │
│  │ Exit State        │ ← 상태 종료 시 한 번 호출                   │
│  │ (정리)            │                                             │
│  └───────────────────┘                                             │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

**예시: Chase Task (블루프린트)**

```
BP_Task_ChaseTarget:

Variables:
- TargetActor: Actor Reference
- ChaseSpeed: Float = 400.0

Enter State:
└─ 타겟 찾기 → TargetActor에 저장

Tick:
├─ 타겟 방향 계산
├─ 이동 입력 설정 (DesiredVelocity)
└─ Return: Running (계속 실행)

Exit State:
└─ 정리 (필요시)
```

### 4.2 C++ Task (고급)

더 복잡한 로직이나 성능이 중요하면 C++로 만들어요.

```cpp
// 헤더 파일
#pragma once
#include "StateTreeTaskBase.h"
#include "MyChaseTask.generated.h"

// Task 데이터 (인스턴스 데이터)
USTRUCT()
struct FMyChaseTaskInstanceData
{
    GENERATED_BODY()

    // 각 엔티티별로 따로 저장되는 데이터
    UPROPERTY()
    FVector LastTargetPosition = FVector::ZeroVector;
};

// Task 정의
USTRUCT(meta = (DisplayName = "My Chase Task"))
struct FMyChaseTask : public FStateTreeTaskCommonBase
{
    GENERATED_BODY()

    // Task 설정 (에디터에서 설정 가능)
    UPROPERTY(EditAnywhere, Category = "Parameters")
    float ChaseSpeed = 400.0f;

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float AcceptanceRadius = 50.0f;

    // 인스턴스 데이터 타입 지정
    using FInstanceDataType = FMyChaseTaskInstanceData;

    // 상태 진입 시
    virtual EStateTreeRunStatus EnterState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        // 초기화 로직
        return EStateTreeRunStatus::Running;
    }

    // 매 틱
    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        // 인스턴스 데이터 접근
        FMyChaseTaskInstanceData& InstanceData =
            Context.GetInstanceData<FMyChaseTaskInstanceData>(*this);

        // 타겟 위치 가져오기 (컨텍스트에서)
        // ...

        // 이동 로직
        // ...

        // 도착했으면 성공
        if (bReachedTarget)
        {
            return EStateTreeRunStatus::Succeeded;
        }

        return EStateTreeRunStatus::Running;
    }

    // 상태 종료 시
    virtual void ExitState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        // 정리 로직
    }
};
```

### 4.3 Task 반환값 이해하기

Task의 `Tick()`은 반환값으로 상태를 알려줘요:

```
┌────────────────────────────────────────────────────────────────────┐
│                   EStateTreeRunStatus                              │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Running                                                           │
│  └─ "아직 진행 중이야, 계속 틱 해줘"                               │
│     → 다음 프레임에도 Tick 호출됨                                  │
│                                                                     │
│  Succeeded                                                         │
│  └─ "성공적으로 완료했어!"                                         │
│     → 전이 조건 평가 → 다음 상태로                                │
│                                                                     │
│  Failed                                                            │
│  └─ "실패했어..."                                                  │
│     → 전이 조건 평가 (Failed 조건) → 다른 상태로                  │
│                                                                     │
│  Stopped                                                           │
│  └─ "외부에서 중단됐어"                                            │
│     → 정리 후 종료                                                 │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

---

## 5. Condition 만들기

### 5.1 Condition이란?

상태 전이를 결정하는 조건이에요.
"이 조건이 참이면 다른 상태로 전이"

### 5.2 Blueprint Condition

```cpp
// 블루프린트로 만들 수 있어요
// 부모 클래스: UStateTreeConditionBlueprintBase

// 오버라이드할 함수:
// - TestCondition(): bool 반환
```

### 5.3 C++ Condition

```cpp
// 거리 체크 Condition 예시
USTRUCT(meta = (DisplayName = "Is In Range"))
struct FIsInRangeCondition : public FStateTreeConditionCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float Range = 100.0f;

    virtual bool TestCondition(FStateTreeExecutionContext& Context) const override
    {
        // 컨텍스트에서 필요한 데이터 가져오기
        const FVector& MyPosition = /* ... */;
        const FVector& TargetPosition = /* ... */;

        float Distance = FVector::Dist(MyPosition, TargetPosition);
        return Distance <= Range;
    }
};
```

### 5.4 내장 Condition 활용

StateTree에는 기본 Condition이 많이 있어요:

```
내장 Condition 목록:
├── Compare Int           ← 정수 비교
├── Compare Float         ← 실수 비교
├── Compare Bool          ← 불리언 체크
├── Compare Enum          ← Enum 비교
├── Compare Object        ← 오브젝트 null 체크
├── Compare GameplayTag   ← 태그 비교
├── Random               ← 확률 기반
└── Time Elapsed         ← 시간 경과 체크
```

---

## 6. Mass AI와 StateTree 통합

### 6.1 MassStateTreeTrait 설정

Mass Entity가 StateTree를 사용하려면 Trait를 추가해야 해요:

```
MassEntityConfigAsset 설정:
├── Traits
│   ├── ... (다른 Trait)
│   └── MassStateTreeTrait  ◄── 추가!
│       ├── StateTree: ST_MonsterBehavior
│       └── ...
```

### 6.2 MassStateTreeSchema

Mass AI 전용 Schema를 사용하면 Fragment에 직접 접근할 수 있어요:

```cpp
// Mass StateTree Schema 설정
// StateTree 에셋의 Schema를 MassStateTreeSchema로 설정하면
// 다음 컨텍스트 데이터에 접근 가능:

Context에서 접근 가능한 것들:
├── FMassEntityHandle Entity       ← 현재 엔티티
├── FMassEntityManager* Manager    ← 엔티티 매니저
├── FTransformFragment             ← 위치/회전
├── 기타 Fragment들...
└── 커스텀 데이터
```

### 6.3 Mass 전용 Task 작성

```cpp
// Mass Entity Fragment에 접근하는 Task 예시
USTRUCT(meta = (DisplayName = "Mass Move To Target"))
struct FMassMoveToTargetTask : public FStateTreeTaskCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float MoveSpeed = 400.0f;

    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        // Mass Entity 컨텍스트에서 데이터 가져오기
        const FMassStateTreeExecutionContext& MassContext =
            static_cast<const FMassStateTreeExecutionContext&>(Context);

        FMassEntityHandle Entity = MassContext.GetEntity();
        FMassEntityManager& Manager = MassContext.GetEntityManager();

        // Fragment 접근
        FTransformFragment* Transform =
            Manager.GetFragmentDataPtr<FTransformFragment>(Entity);

        FMassMovementFragment* Movement =
            Manager.GetFragmentDataPtr<FMassMovementFragment>(Entity);

        if (Transform && Movement)
        {
            // 타겟 방향 계산
            FVector TargetPos = /* 타겟 위치 */;
            FVector MyPos = Transform->GetTransform().GetLocation();
            FVector Direction = (TargetPos - MyPos).GetSafeNormal();

            // 이동 속도 설정
            Movement->DesiredVelocity = Direction * MoveSpeed;
        }

        return EStateTreeRunStatus::Running;
    }
};
```

### 6.4 전체 통합 흐름

```
┌────────────────────────────────────────────────────────────────────┐
│              Mass AI + StateTree 통합 흐름                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. 설정 단계                                                      │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│  MassEntityConfigAsset                                             │
│  ├── Traits                                                        │
│  │   ├── FTransformTrait                                          │
│  │   ├── FMassMovementTrait                                       │
│  │   ├── FMassRepresentationTrait                                 │
│  │   └── FMassStateTreeTrait    ◄── StateTree 에셋 연결           │
│  │       └── StateTree: ST_MonsterBehavior                        │
│  │                                                                 │
│  └── SharedFragments                                              │
│      └── FMonsterConfig                                           │
│                                                                     │
│  2. 런타임 흐름                                                    │
│  ─────────────────────────────────────────────────────────────────  │
│                                                                     │
│  [Mass Entity 스폰]                                                │
│         │                                                          │
│         ▼                                                          │
│  [StateTree 인스턴스 생성]                                         │
│         │                                                          │
│         ▼                                                          │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  매 프레임 (MassStateTreeProcessor)                          │  │
│  │                                                               │  │
│  │  for each Entity with StateTreeFragment:                     │  │
│  │      1. StateTree 틱                                         │  │
│  │      2. 현재 상태의 Task 실행                                │  │
│  │      3. 전이 조건 평가                                       │  │
│  │      4. 필요시 상태 전환                                     │  │
│  │      5. Fragment 업데이트 (이동 속도 등)                     │  │
│  │                                                               │  │
│  └──────────────────────────────────────────────────────────────┘  │
│         │                                                          │
│         ▼                                                          │
│  [Movement Processor가 이동 처리]                                  │
│         │                                                          │
│         ▼                                                          │
│  [Representation Processor가 렌더링]                               │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

---

## 7. 실전 예시: 몬스터 AI

### 7.1 목표

```
간단한 몬스터 AI:
1. Idle: 제자리 대기
2. Chase: 플레이어 발견 시 추적
3. Attack: 공격 범위에 들어오면 공격
4. Dead: 죽으면 처리
```

### 7.2 StateTree 구조 설계

```
ST_MonsterBehavior
└── Root
    ├── Idle (기본 상태)
    │   ├── Task: PlayIdleAnimation
    │   └── Transition → Chase (플레이어 발견)
    │
    ├── Chase
    │   ├── Task: MoveToTarget
    │   ├── Transition → Attack (공격 범위 진입)
    │   └── Transition → Idle (플레이어 사라짐)
    │
    ├── Attack
    │   ├── Task: PerformAttack
    │   ├── Transition → Chase (공격 완료)
    │   └── Transition → Dead (체력 0)
    │
    └── Dead
        └── Task: HandleDeath (마지막 상태)
```

### 7.3 C++ 구현 예시

```cpp
//==========================================================
// Task: Idle (대기)
//==========================================================
USTRUCT(meta = (DisplayName = "Monster Idle"))
struct FMonsterIdleTask : public FStateTreeTaskCommonBase
{
    GENERATED_BODY()

    virtual EStateTreeRunStatus EnterState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        // Idle 애니메이션 상태 설정
        SetAnimationState(Context, EMonsterAnimState::Idle);
        return EStateTreeRunStatus::Running;
    }

    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        // 이동 속도 0으로 설정
        SetVelocity(Context, FVector::ZeroVector);
        return EStateTreeRunStatus::Running;
    }
};

//==========================================================
// Task: Chase (추적)
//==========================================================
USTRUCT(meta = (DisplayName = "Monster Chase"))
struct FMonsterChaseTask : public FStateTreeTaskCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float ChaseSpeed = 400.0f;

    virtual EStateTreeRunStatus EnterState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        SetAnimationState(Context, EMonsterAnimState::Moving);
        return EStateTreeRunStatus::Running;
    }

    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        // 타겟(플레이어) 방향 계산
        FVector MyPos = GetMyPosition(Context);
        FVector TargetPos = GetTargetPosition(Context);
        FVector Direction = (TargetPos - MyPos).GetSafeNormal();

        // 이동 속도 설정
        SetVelocity(Context, Direction * ChaseSpeed);

        return EStateTreeRunStatus::Running;
    }
};

//==========================================================
// Task: Attack (공격)
//==========================================================
USTRUCT(meta = (DisplayName = "Monster Attack"))
struct FMonsterAttackTask : public FStateTreeTaskCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float AttackDuration = 0.5f;

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float AttackDamage = 10.0f;

    // 인스턴스 데이터
    struct FInstanceData
    {
        float ElapsedTime = 0.0f;
        bool bDamageApplied = false;
    };
    using FInstanceDataType = FInstanceData;

    virtual EStateTreeRunStatus EnterState(
        FStateTreeExecutionContext& Context,
        const FStateTreeTransitionResult& Transition) const override
    {
        FInstanceData& Data = Context.GetInstanceData<FInstanceData>(*this);
        Data.ElapsedTime = 0.0f;
        Data.bDamageApplied = false;

        SetAnimationState(Context, EMonsterAnimState::Attacking);
        SetVelocity(Context, FVector::ZeroVector);  // 공격 중 정지

        return EStateTreeRunStatus::Running;
    }

    virtual EStateTreeRunStatus Tick(
        FStateTreeExecutionContext& Context,
        const float DeltaTime) const override
    {
        FInstanceData& Data = Context.GetInstanceData<FInstanceData>(*this);
        Data.ElapsedTime += DeltaTime;

        // 공격 타이밍에 데미지 적용 (애니메이션 중간쯤)
        if (!Data.bDamageApplied && Data.ElapsedTime >= AttackDuration * 0.5f)
        {
            ApplyDamageToTarget(Context, AttackDamage);
            Data.bDamageApplied = true;
        }

        // 공격 완료?
        if (Data.ElapsedTime >= AttackDuration)
        {
            return EStateTreeRunStatus::Succeeded;
        }

        return EStateTreeRunStatus::Running;
    }
};

//==========================================================
// Condition: 플레이어가 범위 내에 있는가?
//==========================================================
USTRUCT(meta = (DisplayName = "Is Player In Range"))
struct FIsPlayerInRangeCondition : public FStateTreeConditionCommonBase
{
    GENERATED_BODY()

    UPROPERTY(EditAnywhere, Category = "Parameters")
    float Range = 100.0f;

    virtual bool TestCondition(FStateTreeExecutionContext& Context) const override
    {
        FVector MyPos = GetMyPosition(Context);
        FVector PlayerPos = GetPlayerPosition(Context);

        float Distance = FVector::Dist(MyPos, PlayerPos);
        return Distance <= Range;
    }
};
```

### 7.4 에디터에서 조립

StateTree 에디터에서:

```
1. Schema를 MassStateTreeSchema로 설정

2. States 생성:
   - Idle (기본)
   - Chase
   - Attack
   - Dead

3. Idle 상태 설정:
   - Tasks: [Monster Idle]
   - Transitions:
     └─ To Chase: IsPlayerInRange(Range=1000)

4. Chase 상태 설정:
   - Tasks: [Monster Chase (Speed=400)]
   - Transitions:
     ├─ To Attack: IsPlayerInRange(Range=100)
     └─ To Idle: NOT IsPlayerInRange(Range=1500)

5. Attack 상태 설정:
   - Tasks: [Monster Attack (Duration=0.5)]
   - Transitions:
     └─ To Chase: OnTaskSucceeded

6. Dead 상태 설정:
   - Tasks: [Handle Death]
   - (종료 상태, 전이 없음)
```

---

## 8. 성능 최적화 팁

### 8.1 LOD 기반 StateTree 비활성화

멀리 있는 몬스터는 StateTree가 필요 없어요!

```cpp
// LOD에 따라 StateTree 틱 빈도 조절
void AdjustStateTreeTickRate(EMassLOD::Type LOD)
{
    switch (LOD)
    {
    case EMassLOD::High:
        // 풀 틱 (매 프레임)
        TickInterval = 0.0f;
        break;

    case EMassLOD::Medium:
        // 느린 틱 (5fps)
        TickInterval = 0.2f;
        break;

    case EMassLOD::Low:
    case EMassLOD::Off:
        // StateTree 비활성화
        bEnableStateTree = false;
        break;
    }
}
```

### 8.2 Evaluator로 계산 캐싱

비싼 계산은 Evaluator에서 한 번만!

```cpp
// 플레이어까지 거리 계산 Evaluator
USTRUCT(meta = (DisplayName = "Cache Distance To Player"))
struct FDistanceToPlayerEvaluator : public FStateTreeEvaluatorCommonBase
{
    GENERATED_BODY()

    // 출력 (다른 곳에서 사용)
    UPROPERTY()
    float CachedDistance = 0.0f;

    virtual void Tick(FStateTreeExecutionContext& Context, const float DeltaTime) const override
    {
        // 프레임당 한 번만 계산
        FVector MyPos = GetMyPosition(Context);
        FVector PlayerPos = GetPlayerPosition(Context);
        CachedDistance = FVector::Dist(MyPos, PlayerPos);
    }
};

// Condition에서 캐시된 값 사용
USTRUCT(meta = (DisplayName = "Is Cached Distance In Range"))
struct FIsCachedDistanceInRangeCondition : public FStateTreeConditionCommonBase
{
    // Evaluator 참조
    UPROPERTY()
    TStateTreePropertyRef<float> DistanceRef;

    UPROPERTY(EditAnywhere)
    float MaxRange = 100.0f;

    virtual bool TestCondition(FStateTreeExecutionContext& Context) const override
    {
        // 캐시된 값 사용 (재계산 없음!)
        float Distance = DistanceRef.Get(Context);
        return Distance <= MaxRange;
    }
};
```

### 8.3 상태 전이 최소화

```
나쁜 예:
Idle → Chase → Attack → Chase → Attack → Chase → Attack → ...
(매 프레임 전이 가능)

좋은 예:
Idle → Chase → Attack (cooldown) → Chase → ...
(쿨다운으로 전이 빈도 제한)
```

---

## 9. 디버깅

### 9.1 StateTree 디버거

```
에디터에서:
Window → Developer Tools → StateTree Debugger

기능:
- 현재 활성 상태 표시
- 전이 히스토리
- Task 실행 상태
- 조건 평가 결과
```

### 9.2 로깅

```cpp
// Task에서 로깅
virtual EStateTreeRunStatus Tick(FStateTreeExecutionContext& Context, const float DeltaTime) const override
{
    UE_LOG(LogStateTree, Verbose,
        TEXT("ChaseTask Tick - Entity: %s, Distance: %.1f"),
        *GetEntityDebugString(Context),
        GetDistanceToTarget(Context));

    // ...
}
```

### 9.3 시각적 디버깅

```cpp
#if WITH_EDITOR
// 현재 상태를 3D 텍스트로 표시
void DrawDebugStateTree(const FMassEntityHandle& Entity, const FStateTreeInstanceData& StateData)
{
    FString StateName = GetCurrentStateName(StateData);
    DrawDebugString(GetWorld(),
        GetEntityPosition(Entity) + FVector(0, 0, 100),
        StateName,
        nullptr,
        FColor::Yellow);
}
#endif
```

---

## 10. 요약

### StateTree 핵심 개념

```
State: 현재 상태 (Idle, Chase, Attack)
Task: 상태에서 실행할 행동
Condition: 전이 조건 판단
Evaluator: 데이터 계산/캐싱
Schema: 사용 맥락 정의 (Mass용은 MassStateTreeSchema)
```

### Mass AI 통합 체크리스트

```
□ MassStateTreeTrait 추가
□ Schema를 MassStateTreeSchema로 설정
□ Mass 전용 Task 작성 (Fragment 접근)
□ LOD별 최적화 적용
□ 디버거로 테스트
```

### 다음 단계

- [05_BehaviorLogic.md](05_BehaviorLogic.md) - Signal 시스템과 Processor 기반 행동
- [09_QuickStartTutorial.md](09_QuickStartTutorial.md) - 처음부터 따라하기
