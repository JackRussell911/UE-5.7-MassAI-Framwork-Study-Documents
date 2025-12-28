# 최적화 전략 및 구현 가이드

> **문서 목적**: 1000-5000 마리 규모 몬스터 시스템의 실전 최적화 전략 및 뱀파이어 서바이벌 스타일 구현 가이드
>
> **난이도**: ★★★★☆ (고급)
>
> **핵심 질문**: "어떻게 하면 5000마리 몬스터를 60fps로 돌릴 수 있을까?"

---

## 1. 먼저 목표를 명확히 하자

### 우리가 원하는 것

뱀파이어 서바이벌 같은 게임을 만든다고 해볼게요:

```
목표 스펙:
─────────────────────────────────────
항목              │  목표         │  최소
─────────────────────────────────────
몬스터 수         │  5000마리     │  1000마리
프레임 레이트     │  60 FPS       │  30 FPS
CPU 시간 (Mass)   │  < 3ms        │  < 5ms
메모리            │  < 100MB      │  < 200MB
드로우 콜         │  < 100        │  < 300
─────────────────────────────────────
```

### 프레임 예산 이해하기

**60fps를 유지하려면 한 프레임에 16.67ms밖에 없어요.**

이걸 어떻게 나눠 써야 할까요?

```
1프레임 예산 분배 (60fps = 16.67ms)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

게임 스레드:
├── 렌더링 준비 ................ 3-4ms
├── 게임 로직 .................. 5-6ms
│   ├── 플레이어 ............... 0.5ms
│   ├── 물리 ................... 1-2ms
│   ├── Mass AI ................ 2-3ms ◄── 우리 목표!
│   └── 기타 ................... 1-2ms
└── 여유 버퍼 .................. 2-3ms

렌더 스레드:
├── 컬링 ....................... 1-2ms
├── 드로우 콜 제출 ............. 2-3ms
└── 기타 ....................... 2-3ms
```

**여기서 핵심**: Mass AI에게 주어진 예산은 **2-3ms**예요.
이 안에서 5000마리를 처리해야 합니다!

---

## 2. 성능 측정부터 시작하자 (프로파일링)

> **"측정 없이 최적화 없다"** - 성능 최적화의 황금률

### 2.1 Unreal Insights 사용하기

Unreal Insights는 UE5의 가장 강력한 프로파일링 도구예요.
Mass AI 최적화에 필수입니다.

**시작 방법:**

```bash
# 방법 1: 에디터에서 활성화
콘솔에 입력: trace.start cpu,gpu,frame -channels=default,mass

# 방법 2: 명령줄 인자로 실행
"UnrealEditor.exe" MyProject.uproject -trace=cpu,gpu,frame

# 방법 3: PIE 플레이 중 캡처
콘솔: trace.start default
(테스트 후)
콘솔: trace.stop
```

**Insights 열기:**
- `UnrealInsights.exe` 실행 (Engine\Binaries\Win64\)
- `.utrace` 파일 로드
- 타이밍 탭에서 분석

**찾아야 할 것들:**

```
┌────────────────────────────────────────────────────────────────────┐
│                    Unreal Insights 체크리스트                       │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. Mass Entity 관련 타이머 찾기:                                  │
│     - UMassProcessor::Execute (각 Processor별)                     │
│     - FMassEntityManager::FlushCommands                            │
│     - MassRepresentation (렌더링 관련)                             │
│                                                                     │
│  2. 병목 지점 확인:                                                │
│     - 가장 오래 걸리는 Processor는?                                │
│     - 특정 프레임에서 스파이크 발생?                               │
│     - CPU/GPU 중 어디가 병목?                                      │
│                                                                     │
│  3. 프레임 패턴 분석:                                              │
│     - GC 스파이크 있나?                                            │
│     - 주기적인 히치 패턴?                                          │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 2.2 stat 명령어 활용

콘솔에서 바로 확인할 수 있는 빠른 방법이에요.

```bash
# Mass Entity 전용 통계
stat MassEntity          # Entity/Archetype 수, 쿼리 시간
stat MassRepresentation  # 렌더링 표현 통계
stat MassLOD             # LOD 전환 통계

# 일반 성능 통계
stat fps                 # 기본 FPS
stat unit               # 게임/렌더/GPU 스레드 시간
stat unitgraph          # 시간 경과 그래프
stat game               # 게임 로직 상세
stat scenerendering     # 렌더링 상세

# GPU 관련
stat gpu                # GPU 타이밍
stat rhi                # RHI 레벨 통계
stat drawcount          # 드로우 콜 수

# 메모리
stat memory             # 전체 메모리
stat memoryplatform     # 플랫폼별 메모리
```

### 2.3 커스텀 프로파일링 마커

자신만의 Processor를 만들면 프로파일링 마커를 꼭 추가하세요!

```cpp
// 1. 통계 그룹 정의 (헤더 파일)
DECLARE_STATS_GROUP(TEXT("MassMonster"), STATGROUP_MassMonster, STATCAT_Advanced);
DECLARE_CYCLE_STAT(TEXT("Monster Chase"), STAT_MonsterChase, STATGROUP_MassMonster);
DECLARE_CYCLE_STAT(TEXT("Monster Attack"), STAT_MonsterAttack, STATGROUP_MassMonster);
DECLARE_CYCLE_STAT(TEXT("Monster Separation"), STAT_MonsterSeparation, STATGROUP_MassMonster);

// 2. Processor에서 사용
UCLASS()
class UMonsterChaseProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 이 블록의 시간이 측정됨!
        SCOPE_CYCLE_COUNTER(STAT_MonsterChase);

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [](FMassExecutionContext& ChunkContext)
            {
                // 처리 로직
            });
    }
};

// 3. 콘솔에서 확인
// stat MassMonster 입력하면 보임!
```

### 2.4 프로파일링 팁

**자주 하는 실수들:**

```
❌ 에디터에서만 프로파일링
   → 에디터 오버헤드가 결과를 왜곡해요
   → 반드시 Development 또는 Shipping 빌드로 테스트!

❌ 몬스터 100마리로만 테스트
   → 스케일링 문제는 큰 수에서만 보여요
   → 최소 1000마리, 목표 수치로 테스트!

❌ 한 번 측정하고 끝
   → 프레임 간 변동이 있어요
   → 최소 10초 이상 캡처 후 평균/최대값 확인!

❌ 최적화 전 프로파일링 안 함
   → "느린 것 같아서" 최적화하면 안 됨
   → 측정 → 분석 → 최적화 → 측정 반복!
```

---

## 3. LOD가 모든 것의 핵심이다

### 왜 LOD가 중요한가?

솔직히 말해서, **LOD 설정만 잘해도 80%는 해결**이에요.

```
5000마리를 전부 High LOD로 처리하면?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
엔티티당 처리 시간: 0.05ms
총 시간: 0.05ms × 5000 = 250ms
결과: 4fps... 게임 불가능!

LOD를 적용하면?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
High (100개)  × 0.05ms   = 5.0ms
Medium (400개) × 0.005ms  = 2.0ms
Low (4500개)  × 0.0005ms = 2.25ms
총: 9.25ms → 아직 많지만 60fps 가능 영역!
```

### 권장 LOD 설정

```cpp
// 1000-5000 마리 규모 최적화 LOD 설정
void SetupOptimizedLOD(UMassVisualizationTrait* VisTrait)
{
    auto& Params = VisTrait->LODParams;

    //===============================================================
    //  거리 설정 (단위: cm, 언리얼 기본)
    //===============================================================
    //
    //  가까움 ◀─────────────────────────────────────▶ 멂
    //
    //    High    │    Medium    │     Low      │    Off
    //  (Actor)   │ (LowActor)  │    (ISM)     │  (렌더X)
    //            │              │              │
    //    0m     50m          150m           300m
    //
    Params.BaseLODDistance[EMassLOD::High] = 0.0f;        // 시작점
    Params.BaseLODDistance[EMassLOD::Medium] = 5000.0f;   // 50m부터
    Params.BaseLODDistance[EMassLOD::Low] = 15000.0f;     // 150m부터
    Params.BaseLODDistance[EMassLOD::Off] = 30000.0f;     // 300m 이상 안보임

    //===============================================================
    //  개수 제한 (이게 진짜 중요!)
    //===============================================================
    //
    //  "거리가 가까워도 너무 많으면 승격 안 함"
    //
    Params.LODMaxCount[EMassLOD::High] = 100;     // Actor 최대 100개
    Params.LODMaxCount[EMassLOD::Medium] = 400;   // Low Actor 최대 400개
    Params.LODMaxCount[EMassLOD::Low] = 5000;     // ISM은 사실상 무제한
    Params.LODMaxCount[EMassLOD::Off] = INT32_MAX;

    //===============================================================
    //  히스테리시스 (LOD 떨림 방지)
    //===============================================================
    //
    //  49m → 51m → 49m 왔다갔다 할 때
    //  매번 LOD 전환하면 깜빡거려요!
    //
    //  15% 버퍼를 두면:
    //  - High → Medium: 50m * 1.15 = 57.5m에서 전환
    //  - Medium → High: 50m * 0.85 = 42.5m에서 전환
    //
    Params.BufferHysteresisOnDistancePercentage = 15.0f;
}
```

### LOD 거리 튜닝 가이드

게임마다 최적의 거리가 달라요. 이런 기준으로 조정하세요:

```
┌────────────────────────────────────────────────────────────────────┐
│                    LOD 거리 결정 체크리스트                         │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  High LOD 거리 (Actor + 풀 애니메이션):                            │
│  ├── 플레이어가 몬스터 디테일을 인식할 수 있는 거리?               │
│  ├── 공격 범위보다 넓어야 함 (공격 시 Actor 필요)                  │
│  └── 권장: 플레이어 공격 범위의 1.5-2배                            │
│                                                                     │
│  Medium LOD 거리 (간소화 Actor):                                   │
│  ├── 몬스터가 화면에 보이지만 디테일 불필요한 거리?                │
│  ├── 카메라 FOV 고려 (넓을수록 더 많이 보임)                       │
│  └── 권장: 화면 1/4 크기로 보이는 거리                             │
│                                                                     │
│  Low LOD 거리 (ISM):                                               │
│  ├── 몬스터가 점처럼 작게 보이는 거리?                             │
│  ├── 이 거리에서는 애니메이션이 거의 안 보임                       │
│  └── 권장: 개별 몬스터 식별 어려운 거리                            │
│                                                                     │
│  Off 거리:                                                         │
│  ├── 어차피 안 보이는 거리                                         │
│  └── 권장: 지형 가려져서 안 보이는 거리 + 여유                     │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

---

## 4. Processor 최적화의 기술

### 4.1 기본 최적화: 캐싱

**매 프레임 반복 계산하지 마세요!**

```cpp
// ❌ 나쁜 예: 매 엔티티마다 플레이어 위치 계산
EntityQuery.ForEachEntityChunk(EntityManager, Context,
    [](FMassExecutionContext& Context)
    {
        for (int32 i = 0; i < Context.GetNumEntities(); ++i)
        {
            // 이거 5000번 호출됨!!
            FVector PlayerPos = GetWorld()->GetFirstPlayerController()
                                          ->GetPawn()
                                          ->GetActorLocation();
            // ...
        }
    });

// ✅ 좋은 예: 프레임당 한 번만 계산
UCLASS()
class UOptimizedChaseProcessor : public UMassProcessor
{
    // 캐시된 데이터
    FVector CachedPlayerPos;
    float CachedDeltaTime;

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 프레임 시작 시 한 번만 계산
        CacheFrameData(Context);

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& ChunkContext)
            {
                // 캐시된 값 사용 - 빠름!
                ProcessChunk(ChunkContext, CachedPlayerPos, CachedDeltaTime);
            });
    }

    void CacheFrameData(const FMassExecutionContext& Context)
    {
        CachedDeltaTime = Context.GetDeltaTimeSeconds();

        // 플레이어 위치는 서브시스템에서 캐시해두면 더 좋아요
        if (UPlayerCacheSubsystem* PlayerCache = GetWorld()->GetSubsystem<UPlayerCacheSubsystem>())
        {
            CachedPlayerPos = PlayerCache->GetPlayerLocation();
        }
    }
};
```

### 4.2 Fragment 접근 최적화

```cpp
// ❌ 나쁜 예: 매번 Fragment 뷰 요청
for (int32 i = 0; i < Context.GetNumEntities(); ++i)
{
    auto& Transform = Context.GetMutableFragmentView<FTransformFragment>()[i];  // 매번 호출!
    auto& Movement = Context.GetMutableFragmentView<FMassMovementFragment>()[i];
    // ...
}

// ✅ 좋은 예: 루프 밖에서 한 번만 획득
auto Transforms = Context.GetMutableFragmentView<FTransformFragment>();  // 한 번!
auto Movements = Context.GetMutableFragmentView<FMassMovementFragment>();

for (int32 i = 0; i < Context.GetNumEntities(); ++i)
{
    FVector& Pos = Transforms[i].GetMutableTransform().GetLocation();
    FVector& Vel = Movements[i].DesiredVelocity;
    // ... 이제 빠름!
}
```

### 4.3 분기 최소화

CPU는 분기(if문)를 싫어해요. 분기 예측 실패하면 파이프라인이 깨져서 느려집니다.

```cpp
// ❌ 나쁜 예: 루프 안에 많은 if문
for (int32 i = 0; i < NumEntities; ++i)
{
    if (Healths[i].IsDead())
    {
        // 사망 처리
    }
    else if (Healths[i].CurrentHealth < 30.0f)
    {
        // 빈사 상태
    }
    else if (IsInRange(Transforms[i], PlayerPos, AttackRange))
    {
        // 공격 범위
    }
    else if (IsInRange(Transforms[i], PlayerPos, ChaseRange))
    {
        // 추격
    }
    // ... 계속되는 if문들
}

// ✅ 좋은 예: 상태별로 쿼리를 분리
// 각 쿼리는 특정 태그가 있는 엔티티만 처리
void Execute(FMassEntityManager& EntityManager, FMassExecutionContext& Context) override
{
    // 죽은 몬스터 처리 (FDeadTag 있는 것만)
    DeadQuery.ForEachEntityChunk(EntityManager, Context, ProcessDead);

    // 공격 중인 몬스터 처리 (FAttackingTag 있는 것만)
    AttackingQuery.ForEachEntityChunk(EntityManager, Context, ProcessAttacking);

    // 추격 중인 몬스터 처리 (FChaseTag 있는 것만)
    ChasingQuery.ForEachEntityChunk(EntityManager, Context, ProcessChasing);
}
```

### 4.4 LOD별 처리 분리 (중요!)

```cpp
UCLASS()
class ULODOptimizedProcessor : public UMassProcessor
{
    // LOD별 별도 쿼리
    FMassEntityQuery HighLODQuery;
    FMassEntityQuery MediumLODQuery;
    FMassEntityQuery LowLODQuery;

    virtual void ConfigureQueries() override
    {
        // High LOD: 복잡한 로직 허용
        HighLODQuery.AddRequirement<FMassRepresentationLODFragment>(EMassFragmentAccess::ReadOnly);
        HighLODQuery.AddChunkRequirement<FMassVisualizationChunkFragment>(
            EMassFragmentAccess::ReadOnly,
            EMassFragmentPresence::All);
        // LOD 태그로 필터링
        HighLODQuery.AddTagRequirement<FMassHighLODTag>(EMassFragmentPresence::All);

        // Low LOD: 최소 로직만
        LowLODQuery.AddTagRequirement<FMassLowLODTag>(EMassFragmentPresence::All);
    }

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // High LOD: 풀 로직
        HighLODQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& ChunkContext)
            {
                ProcessHighLOD(ChunkContext);  // 복잡한 처리 OK
            });

        // Medium LOD: 간소화
        MediumLODQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& ChunkContext)
            {
                ProcessMediumLOD(ChunkContext);  // 중간 복잡도
            });

        // Low LOD: 최소한만
        LowLODQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& ChunkContext)
            {
                ProcessLowLOD(ChunkContext);  // 방향 계산만
            });
    }

    void ProcessHighLOD(FMassExecutionContext& Context)
    {
        // 풀 로직
        // - StateTree 연동
        // - GAS 동기화
        // - 복잡한 회피 로직
        // - 애니메이션 상태 업데이트
    }

    void ProcessLowLOD(FMassExecutionContext& Context)
    {
        auto Transforms = Context.GetMutableFragmentView<FTransformFragment>();
        auto Movements = Context.GetMutableFragmentView<FMassMovementFragment>();

        // 딱 이것만!
        for (int32 i = 0; i < Context.GetNumEntities(); ++i)
        {
            FVector Dir = (CachedPlayerPos - Transforms[i].GetTransform().GetLocation())
                          .GetSafeNormal();
            Movements[i].DesiredVelocity = Dir * MoveSpeed;
        }
    }
};
```

### 4.5 틱 분산 (Variable Tick Rate)

모든 몬스터가 매 프레임 처리될 필요 없어요!

```cpp
// 틱 분산 Fragment
USTRUCT()
struct FVariableTickFragment : public FMassFragment
{
    GENERATED_BODY()

    float TimeUntilNextTick = 0.0f;
    float TickInterval = 0.1f;  // 기본 100ms (10fps)

    bool ShouldTickThisFrame(float DeltaTime)
    {
        TimeUntilNextTick -= DeltaTime;
        if (TimeUntilNextTick <= 0.0f)
        {
            TimeUntilNextTick = TickInterval;
            return true;
        }
        return false;
    }
};

// 사용 예
UCLASS()
class UVariableTickProcessor : public UMassProcessor
{
    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const float DeltaTime = Context.GetDeltaTimeSeconds();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [DeltaTime](FMassExecutionContext& ChunkContext)
            {
                auto Ticks = ChunkContext.GetMutableFragmentView<FVariableTickFragment>();

                for (int32 i = 0; i < ChunkContext.GetNumEntities(); ++i)
                {
                    if (!Ticks[i].ShouldTickThisFrame(DeltaTime))
                    {
                        continue;  // 이번 프레임은 스킵!
                    }

                    // 실제 처리 (100ms마다만 실행)
                    DoExpensiveLogic(ChunkContext, i);
                }
            });
    }
};
```

**틱 분산 전략:**

```
로직별 권장 틱 주기:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

이동 (방향 계산)       │ 매 프레임 (필수)
충돌/피격 체크        │ 매 프레임 (필수)
공격 타이밍 체크      │ 100ms (10fps)
타겟 선택             │ 200ms (5fps)
경로 재계산           │ 500ms (2fps)
군집 분리 계산        │ 100-200ms (5-10fps)
상태 머신 전이        │ 100ms (10fps)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 5. 메모리 최적화

### 5.1 Fragment 크기가 중요하다

Fragment가 작을수록 캐시 효율이 높아져요!

```cpp
// ❌ 나쁜 예: 불필요하게 큰 Fragment
USTRUCT()
struct FBadMonsterFragment : public FMassFragment
{
    FVector Position;           // 24 bytes
    FRotator Rotation;          // 12 bytes
    FString Name;               // 16+ bytes (힙 할당!)
    TArray<FVector> Path;       // 16+ bytes (힙 할당!)
    UObject* Reference;         // 8 bytes (GC 추적 대상!)
    float UnusedData[10];       // 40 bytes (안 쓰는데 왜 있음?)
};
// 총: 100+ bytes, 동적 할당 포함 → 캐시 효율 매우 나쁨

// ✅ 좋은 예: 최소화된 Fragment
USTRUCT()
struct FGoodMonsterFragment : public FMassFragment
{
    FVector Position;           // 24 bytes (필수)
    FQuat Rotation;             // 16 bytes (FRotator보다 작음)
    uint8 NameIndex;            // 1 byte (이름 테이블 인덱스)
    uint8 PathIndex;            // 1 byte (공유 경로 인덱스)
    uint8 Padding[2];           // 2 bytes (정렬용)
};
// 총: 44 bytes, 힙 할당 없음 → 캐시 친화적!
```

**Fragment 최적화 팁:**

```
┌────────────────────────────────────────────────────────────────────┐
│                    Fragment 최적화 체크리스트                       │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  □ 동적 할당 피하기                                                │
│    ├── FString → uint8 (인덱스)                                    │
│    ├── TArray → 고정 크기 배열 또는 인덱스                         │
│    └── UObject* → FMassEntityHandle 또는 인덱스                    │
│                                                                     │
│  □ 적절한 데이터 타입 사용                                         │
│    ├── 불필요한 정밀도 피하기: double → float                      │
│    ├── 범위 제한된 값: float → uint8/int8                          │
│    └── 플래그: 개별 bool → uint32 비트플래그                       │
│                                                                     │
│  □ 불필요한 데이터 제거                                            │
│    ├── "나중에 쓸 것 같은" 데이터 추가 금지                        │
│    └── 계산 가능한 값은 저장 대신 계산                             │
│                                                                     │
│  □ 메모리 정렬                                                     │
│    ├── 큰 멤버부터 선언 (자연 정렬)                                │
│    └── 필요시 패딩 명시적 추가                                     │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 5.2 Shared Fragment 적극 활용

같은 종류 몬스터가 공유하는 데이터는 Shared Fragment로!

```cpp
// ✅ 공유 설정 (몬스터 타입당 하나)
USTRUCT()
struct FMonsterConfig : public FMassConstSharedFragment
{
    GENERATED_BODY()

    // 이 값들은 같은 타입 몬스터가 다 같음
    UPROPERTY(EditAnywhere)
    float MoveSpeed = 400.0f;

    UPROPERTY(EditAnywhere)
    float AttackRange = 100.0f;

    UPROPERTY(EditAnywhere)
    float AttackDamage = 10.0f;

    UPROPERTY(EditAnywhere)
    float AttackCooldown = 1.5f;

    UPROPERTY(EditAnywhere)
    TObjectPtr<UAnimMontage> AttackMontage;
};

// 5000마리가 있어도 FMonsterConfig는
// 몬스터 종류 수 만큼만 존재 (예: 10종류 = 10개)

// Processor에서 사용
void ProcessChunk(FMassExecutionContext& Context)
{
    // Shared Fragment는 청크 전체가 공유
    const FMonsterConfig& Config = Context.GetConstSharedFragment<FMonsterConfig>();

    auto Movements = Context.GetMutableFragmentView<FMassMovementFragment>();

    for (int32 i = 0; i < Context.GetNumEntities(); ++i)
    {
        // 모든 엔티티가 같은 Config 사용
        Movements[i].DesiredVelocity *= Config.MoveSpeed;
    }
}
```

### 5.3 Actor 풀 사이징

Actor 풀이 너무 작으면 생성/파괴 오버헤드가 발생해요.
너무 크면 메모리 낭비고요.

```cpp
void SetupActorPools()
{
    UMassRepresentationSubsystem* RepSubsystem =
        GetWorld()->GetSubsystem<UMassRepresentationSubsystem>();

    //===============================================================
    //  풀 크기 계산 공식
    //===============================================================
    //
    //  필요 풀 크기 = LODMaxCount × (1 + 버퍼율)
    //
    //  버퍼율 권장:
    //  - High LOD: 20% (LOD 전환 중 일시적 초과 대비)
    //  - Medium LOD: 15%
    //

    // High Res Actor 풀
    int16 HighResIndex = RepSubsystem->FindOrAddTemplateActor(BP_Monster_HighRes);
    int32 HighResPoolSize = FMath::CeilToInt(100 * 1.2f);  // 120개
    RepSubsystem->SetActorPoolSize(HighResIndex, HighResPoolSize);

    // Low Res Actor 풀
    int16 LowResIndex = RepSubsystem->FindOrAddTemplateActor(BP_Monster_LowRes);
    int32 LowResPoolSize = FMath::CeilToInt(400 * 1.15f);  // 460개
    RepSubsystem->SetActorPoolSize(LowResIndex, LowResPoolSize);

    UE_LOG(LogMassMonster, Log,
        TEXT("Actor pools: HighRes=%d, LowRes=%d"),
        HighResPoolSize, LowResPoolSize);
}
```

---

## 6. 렌더링 최적화

### 6.1 ISM이 왜 빠른지 다시 확인

```
┌────────────────────────────────────────────────────────────────────┐
│                    Actor vs ISM 비교                                │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  5000 Actor 렌더링:                                                │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Draw Call 1: Monster_001 → GPU                              │  │
│  │  Draw Call 2: Monster_002 → GPU                              │  │
│  │  Draw Call 3: Monster_003 → GPU                              │  │
│  │  ...                                                          │  │
│  │  Draw Call 5000: Monster_5000 → GPU                          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  결과: 5000 Draw Calls = 💀                                        │
│                                                                     │
│  ISM 렌더링:                                                       │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  Draw Call 1: ISM (5000개 트랜스폼 데이터) → GPU             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  결과: 1 Draw Call = 😊                                            │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 6.2 ISM 메시 최적화

```cpp
// 저폴리 메시 사용이 핵심
void ConfigureISMSettings(FStaticMeshInstanceVisualizationMeshDesc& Desc)
{
    // 1. 저폴리 메시 (500 삼각형 이하 권장)
    Desc.Mesh = LowPolyMonsterMesh;  // < 500 tris

    // 2. 원거리에서는 그림자 비활성화
    Desc.bCastShadow = false;  // ISM 그림자는 비용이 커요

    // 3. 단순 머티리얼
    Desc.Materials.Add(SimpleMaterial);  // 텍스처 1장, 라이팅 단순화

    // 4. LOD 범위
    Desc.MinLODSignificance = 2.0f;  // Low LOD부터 사용
}
```

### 6.3 그림자 최적화

그림자는 렌더링에서 가장 비싼 부분 중 하나예요.

```cpp
// LOD별 그림자 설정
void ConfigureShadows(AActor* Actor, EMassLOD::Type LOD)
{
    UMeshComponent* Mesh = Actor->FindComponentByClass<UMeshComponent>();
    if (!Mesh) return;

    switch (LOD)
    {
    case EMassLOD::High:
        // 가까운 몬스터만 그림자
        Mesh->SetCastShadow(true);
        Mesh->bCastDynamicShadow = true;
        break;

    case EMassLOD::Medium:
        // 중거리: 그림자 끔 (또는 저품질)
        Mesh->SetCastShadow(false);
        break;

    case EMassLOD::Low:
        // ISM: 자동으로 그림자 없음
        break;
    }
}
```

**그림자 최적화 팁:**

```
그림자가 필요한 상황                │ 권장 설정
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
플레이어 근처 몬스터              │ Dynamic Shadow ON
중거리 몬스터                     │ Shadow OFF
원거리 (ISM)                     │ Shadow OFF (기본)
보스 몬스터                       │ Dynamic Shadow ON (항상)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

추가 최적화:
- r.Shadow.MaxResolution 조정 (기본 2048 → 1024)
- 그림자 거리 제한 (r.Shadow.DistanceScale)
- Cascaded Shadow Maps 개수 조정
```

---

## 7. 흔한 실수와 해결법

### 7.1 실수 모음집

```
┌────────────────────────────────────────────────────────────────────┐
│                    "왜 안 되지?" 모음집                             │
├────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  실수 1: LODMaxCount를 설정 안 함                                  │
│  ─────────────────────────────────────────────────────────────────  │
│  증상: 가까운 몬스터가 너무 많으면 프레임 드랍                     │
│  원인: 모든 가까운 몬스터가 High LOD Actor가 됨                    │
│  해결: LODMaxCount[EMassLOD::High] = 100; 꼭 설정!                │
│                                                                     │
│  실수 2: Fragment에 UObject* 포인터 저장                           │
│  ─────────────────────────────────────────────────────────────────  │
│  증상: GC 시 프레임 스파이크, 크래시                               │
│  원인: Mass Entity는 GC 추적 안 됨                                 │
│  해결: FMassEntityHandle이나 인덱스 사용                           │
│                                                                     │
│  실수 3: Execute()에서 월드 쿼리                                   │
│  ─────────────────────────────────────────────────────────────────  │
│  증상: Processor가 엄청 느림                                       │
│  원인: GetWorld()->SomeQuery() 호출이 5000번 발생                  │
│  해결: 프레임 시작 시 캐싱                                         │
│                                                                     │
│  실수 4: 에디터에서만 테스트                                       │
│  ─────────────────────────────────────────────────────────────────  │
│  증상: "에디터에선 됐는데 빌드하면 느림"                           │
│  원인: 에디터 오버헤드가 실제 성능 마스킹                          │
│  해결: Development 빌드로 프로파일링                               │
│                                                                     │
│  실수 5: Deferred 명령 너무 많이 사용                              │
│  ─────────────────────────────────────────────────────────────────  │
│  증상: FlushCommands에서 스파이크                                  │
│  원인: 매 프레임 수천 개의 AddTag/RemoveTag                        │
│  해결: 정말 필요한 것만 Defer, 나머지는 Fragment 직접 수정        │
│                                                                     │
│  실수 6: 동일한 쿼리 여러 Processor에서 반복                       │
│  ─────────────────────────────────────────────────────────────────  │
│  증상: 비슷한 Processor들이 각각 느림                              │
│  원인: 같은 엔티티를 여러 번 순회                                  │
│  해결: 하나의 Processor로 통합하거나, Query 결과 캐싱              │
│                                                                     │
└────────────────────────────────────────────────────────────────────┘
```

### 7.2 디버깅 팁

```cpp
// 1. 엔티티 수 모니터링
void DebugEntityCounts()
{
    UMassEntitySubsystem* EntitySubsystem = GetWorld()->GetSubsystem<UMassEntitySubsystem>();
    FMassEntityManager& Manager = EntitySubsystem->GetMutableEntityManager();

    UE_LOG(LogMassMonster, Log, TEXT("Entity Stats:"));
    UE_LOG(LogMassMonster, Log, TEXT("  Total Entities: %d"), Manager.GetNumEntities());
    UE_LOG(LogMassMonster, Log, TEXT("  Archetypes: %d"), Manager.GetNumArchetypes());
}

// 2. LOD 분포 확인
void DebugLODDistribution()
{
    int32 HighCount = 0, MediumCount = 0, LowCount = 0;

    // ... 쿼리로 카운트 ...

    UE_LOG(LogMassMonster, Log,
        TEXT("LOD Distribution: High=%d, Medium=%d, Low=%d"),
        HighCount, MediumCount, LowCount);

    // 예상과 다르면 LOD 설정 확인!
    // High가 너무 많으면? → LODMaxCount 또는 거리 확인
}

// 3. 시각적 디버깅
#if WITH_EDITOR
void DrawLODDebug()
{
    // LOD별 다른 색상으로 점 표시
    // High: 빨강, Medium: 노랑, Low: 초록
}
#endif
```

### 7.3 성능 문제 진단 플로우차트

```
                      [성능 문제 발생!]
                             │
                             ▼
                 ┌───────────────────────┐
                 │  stat unit 확인       │
                 │  Game/Render/GPU      │
                 └───────────────────────┘
                             │
           ┌─────────────────┼─────────────────┐
           ▼                 ▼                 ▼
      Game 높음          Render 높음       GPU 높음
           │                 │                 │
           ▼                 ▼                 ▼
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │ stat game   │   │ stat scene  │   │ stat gpu    │
    │ 확인        │   │ rendering   │   │ 확인        │
    └─────────────┘   └─────────────┘   └─────────────┘
           │                 │                 │
           ▼                 ▼                 ▼
    ┌─────────────┐   ┌─────────────┐   ┌─────────────┐
    │ Processor   │   │ Draw Call   │   │ 버텍스/     │
    │ 시간 확인   │   │ 수 확인     │   │ 픽셀 병목   │
    └─────────────┘   └─────────────┘   └─────────────┘
           │                 │                 │
           ▼                 ▼                 ▼
     LOD별 처리      LODMaxCount      메시 LOD
     분리 필요?      줄이기          최적화 필요?
```

---

## 8. 뱀파이어 서바이벌 스타일 구현

이제 실제로 게임을 만들어봅시다!

### 8.1 웨이브 스폰 시스템

```cpp
UCLASS()
class UMonsterWaveSpawner : public UObject
{
    GENERATED_BODY()

public:
    // 웨이브 시작
    void StartWave(int32 WaveNumber)
    {
        // 1. 스폰 수 계산
        int32 SpawnCount = CalculateWaveSize(WaveNumber);

        // 2. 스폰 위치 생성 (플레이어 주변 원형)
        TArray<FTransform> SpawnTransforms;
        GenerateSpawnLocations(SpawnCount, SpawnTransforms);

        // 3. Mass Spawner로 대량 스폰!
        UMassSpawnerSubsystem* Spawner =
            GetWorld()->GetSubsystem<UMassSpawnerSubsystem>();

        FMassSpawnDataBurstConfig SpawnConfig;
        SpawnConfig.Transform = SpawnTransforms;
        SpawnConfig.EntityConfig = MonsterEntityConfig;

        Spawner->SpawnEntities(SpawnConfig);

        UE_LOG(LogGame, Log, TEXT("Wave %d: Spawned %d monsters"),
            WaveNumber, SpawnCount);
    }

private:
    // 웨이브 크기 계산 (점점 증가)
    int32 CalculateWaveSize(int32 WaveNumber)
    {
        // 공식: 기본 + (웨이브 × 증가량), 최대값 제한
        int32 Size = BaseWaveSize + WaveNumber * WaveGrowth;
        return FMath::Min(Size, MaxMonstersPerWave);
    }

    // 스폰 위치 생성 (화면 밖 원형 분포)
    void GenerateSpawnLocations(int32 Count, TArray<FTransform>& OutTransforms)
    {
        FVector PlayerPos = GetPlayerLocation();

        OutTransforms.Reserve(Count);

        for (int32 i = 0; i < Count; ++i)
        {
            // 원형 분포
            float Angle = FMath::RandRange(0.0f, 2.0f * PI);
            float Distance = FMath::RandRange(SpawnMinDistance, SpawnMaxDistance);

            FVector SpawnPos = PlayerPos + FVector(
                FMath::Cos(Angle) * Distance,
                FMath::Sin(Angle) * Distance,
                0.0f);  // 2D 게임 가정

            OutTransforms.Add(FTransform(SpawnPos));
        }
    }

    // 설정
    UPROPERTY(EditAnywhere, Category = "Wave")
    int32 BaseWaveSize = 50;

    UPROPERTY(EditAnywhere, Category = "Wave")
    int32 WaveGrowth = 10;

    UPROPERTY(EditAnywhere, Category = "Wave")
    int32 MaxMonstersPerWave = 200;

    UPROPERTY(EditAnywhere, Category = "Spawn")
    float SpawnMinDistance = 1500.0f;  // 15m (화면 밖)

    UPROPERTY(EditAnywhere, Category = "Spawn")
    float SpawnMaxDistance = 3000.0f;  // 30m
};
```

### 8.2 추적 + 군집 회피 Processor

뱀서의 핵심: 몬스터가 플레이어를 쫓되 서로 겹치지 않음!

```cpp
UCLASS()
class USwarmChaseProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float ChaseSpeed = 350.0f;

    UPROPERTY(EditAnywhere)
    float SeparationRadius = 80.0f;  // 이 거리 안에 있으면 밀어냄

    UPROPERTY(EditAnywhere)
    float SeparationWeight = 0.3f;   // 분리 힘의 강도

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        // 1. 공간 해시 그리드 구축 (이웃 탐색 최적화)
        BuildSpatialGrid(EntityManager);

        // 2. 플레이어 위치 캐싱
        const FVector PlayerPos = GetCachedPlayerLocation();

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=](FMassExecutionContext& ChunkContext)
            {
                auto Transforms = ChunkContext.GetFragmentView<FTransformFragment>();
                auto Movements = ChunkContext.GetMutableFragmentView<FMassMovementFragment>();

                for (int32 i = 0; i < ChunkContext.GetNumEntities(); ++i)
                {
                    FVector MyPos = Transforms[i].GetTransform().GetLocation();

                    // 1. 플레이어 방향 (추적)
                    FVector ChaseDir = (PlayerPos - MyPos).GetSafeNormal();

                    // 2. 분리 방향 (겹침 방지)
                    FVector SeparationDir = CalculateSeparation(MyPos);

                    // 3. 최종 방향 합성
                    FVector FinalDir =
                        (ChaseDir + SeparationDir * SeparationWeight).GetSafeNormal();

                    Movements[i].DesiredVelocity = FinalDir * ChaseSpeed;
                }
            });
    }

private:
    // 공간 해시 그리드 (이웃 탐색 O(n²) → O(n))
    struct FSpatialGrid
    {
        TMap<int32, TArray<FVector>> Cells;
        float CellSize = 100.0f;

        int32 GetCellKey(const FVector& Pos)
        {
            int32 X = FMath::FloorToInt(Pos.X / CellSize);
            int32 Y = FMath::FloorToInt(Pos.Y / CellSize);
            return X + Y * 10000;  // 간단한 해시
        }
    };

    FSpatialGrid Grid;

    void BuildSpatialGrid(FMassEntityManager& EntityManager)
    {
        Grid.Cells.Reset();

        // 모든 엔티티를 그리드에 등록
        FMassEntityQuery GridQuery;
        GridQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);

        GridQuery.ForEachEntityChunk(EntityManager, Context,
            [this](FMassExecutionContext& ChunkContext)
            {
                auto Transforms = ChunkContext.GetFragmentView<FTransformFragment>();

                for (int32 i = 0; i < ChunkContext.GetNumEntities(); ++i)
                {
                    FVector Pos = Transforms[i].GetTransform().GetLocation();
                    int32 Key = Grid.GetCellKey(Pos);
                    Grid.Cells.FindOrAdd(Key).Add(Pos);
                }
            });
    }

    FVector CalculateSeparation(const FVector& MyPos)
    {
        FVector SeparationForce = FVector::ZeroVector;

        // 주변 셀만 검사 (9개 셀)
        for (int32 dx = -1; dx <= 1; ++dx)
        {
            for (int32 dy = -1; dy <= 1; ++dy)
            {
                int32 NeighborKey = Grid.GetCellKey(MyPos + FVector(
                    dx * Grid.CellSize, dy * Grid.CellSize, 0.0f));

                if (TArray<FVector>* Cell = Grid.Cells.Find(NeighborKey))
                {
                    for (const FVector& OtherPos : *Cell)
                    {
                        FVector Diff = MyPos - OtherPos;
                        float Dist = Diff.Size();

                        if (Dist > SMALL_NUMBER && Dist < SeparationRadius)
                        {
                            // 거리가 가까울수록 강하게 밀어냄
                            float Strength = 1.0f - (Dist / SeparationRadius);
                            SeparationForce += Diff.GetSafeNormal() * Strength;
                        }
                    }
                }
            }
        }

        return SeparationForce.GetSafeNormal();
    }
};
```

### 8.3 접촉 데미지 시스템

```cpp
UCLASS()
class UContactDamageProcessor : public UMassProcessor
{
    GENERATED_BODY()

public:
    UPROPERTY(EditAnywhere)
    float ContactRadius = 50.0f;  // 접촉 판정 거리

    UPROPERTY(EditAnywhere)
    float DamagePerSecond = 10.0f;

    virtual void Execute(FMassEntityManager& EntityManager,
                         FMassExecutionContext& Context) override
    {
        const FVector PlayerPos = GetCachedPlayerLocation();
        const float ContactRadiusSq = FMath::Square(ContactRadius);
        const float DeltaTime = Context.GetDeltaTimeSeconds();

        // 여러 몬스터가 동시에 닿으면 데미지 누적
        float TotalDamage = 0.0f;

        EntityQuery.ForEachEntityChunk(EntityManager, Context,
            [=, &TotalDamage](FMassExecutionContext& ChunkContext)
            {
                auto Transforms = ChunkContext.GetFragmentView<FTransformFragment>();

                for (int32 i = 0; i < ChunkContext.GetNumEntities(); ++i)
                {
                    float DistSq = FVector::DistSquared(
                        Transforms[i].GetTransform().GetLocation(),
                        PlayerPos);

                    if (DistSq <= ContactRadiusSq)
                    {
                        // 닿았다!
                        TotalDamage += DamagePerSecond * DeltaTime;
                    }
                }
            });

        // 한 번에 플레이어에게 적용
        if (TotalDamage > 0.0f)
        {
            ApplyDamageToPlayer(TotalDamage);
        }
    }
};
```

### 8.4 플레이어 공격 → 몬스터 데미지

```cpp
// 플레이어의 영역 공격이 Mass 몬스터에게 데미지
void ApplyAreaDamageToMonsters(const FVector& Center, float Radius, float Damage)
{
    UMassEntitySubsystem* EntitySubsystem = GetWorld()->GetSubsystem<UMassEntitySubsystem>();
    FMassEntityManager& EntityManager = EntitySubsystem->GetMutableEntityManager();

    FMassExecutionContext Context;  // 적절히 초기화

    FMassEntityQuery DamageQuery;
    DamageQuery.AddRequirement<FTransformFragment>(EMassFragmentAccess::ReadOnly);
    DamageQuery.AddRequirement<FMonsterHealthFragment>(EMassFragmentAccess::ReadWrite);
    DamageQuery.AddTagRequirement<FAliveTag>(EMassFragmentPresence::All);

    const float RadiusSq = FMath::Square(Radius);
    int32 KillCount = 0;

    DamageQuery.ForEachEntityChunk(EntityManager, Context,
        [=, &KillCount](FMassExecutionContext& ChunkContext)
        {
            auto Transforms = ChunkContext.GetFragmentView<FTransformFragment>();
            auto Healths = ChunkContext.GetMutableFragmentView<FMonsterHealthFragment>();

            for (int32 i = 0; i < ChunkContext.GetNumEntities(); ++i)
            {
                float DistSq = FVector::DistSquared(
                    Transforms[i].GetTransform().GetLocation(),
                    Center);

                if (DistSq <= RadiusSq)
                {
                    // 데미지 적용
                    Healths[i].CurrentHealth -= Damage;

                    if (Healths[i].CurrentHealth <= 0.0f)
                    {
                        // 사망 처리 예약
                        ChunkContext.Defer().RemoveTag<FAliveTag>(
                            ChunkContext.GetEntity(i));
                        ChunkContext.Defer().AddTag<FDeadTag>(
                            ChunkContext.GetEntity(i));

                        // 아이템 드랍 큐잉
                        if (FMath::FRand() < DropChance)
                        {
                            QueueItemDrop(Transforms[i].GetTransform().GetLocation());
                        }

                        ++KillCount;
                    }
                }
            }
        });

    // UI 업데이트
    if (KillCount > 0)
    {
        AddScore(KillCount * PointsPerKill);
    }
}
```

---

## 9. 최적화 체크리스트

### 프로젝트 셋업

```
□ 플러그인 활성화
  ├── MassEntity
  ├── MassGameplay
  ├── MassRepresentation
  └── StateTree (행동 로직용)

□ Build.cs 의존성 추가
  PublicDependencyModuleNames.AddRange(new string[] {
      "MassEntity",
      "MassCommon",
      "MassActors",
      "MassRepresentation",
      "MassLOD",
      "MassMovement",
      "MassSpawner",
      "StructUtils"
  });

□ Entity Config Asset 생성
  ├── 필요한 Trait 추가
  ├── 템플릿 Actor 설정
  └── 공유 Fragment 설정
```

### LOD 설정

```
□ LOD 거리 설정
  ├── High: 0-50m (플레이어 근처)
  ├── Medium: 50-150m
  ├── Low: 150-300m
  └── Off: 300m+

□ LODMaxCount 설정 (중요!)
  ├── High: 100 (Actor 수 제한)
  ├── Medium: 400
  └── Low: 5000+

□ 히스테리시스 설정 (15% 권장)
```

### Processor 최적화

```
□ 프레임 데이터 캐싱
  ├── 플레이어 위치
  ├── DeltaTime
  └── 자주 쓰는 계산 결과

□ Fragment 접근 최적화
  └── 루프 밖에서 뷰 획득

□ LOD별 처리 분리
  ├── High: 풀 로직
  ├── Medium: 간소화
  └── Low: 최소한

□ 분기 최소화
  └── 상태별 쿼리 분리
```

### 메모리 최적화

```
□ Fragment 크기 최소화
  ├── 동적 할당 피하기
  ├── 적절한 타입 사용
  └── 불필요한 데이터 제거

□ Shared Fragment 활용
  └── 공통 설정은 공유

□ Actor 풀 크기 설정
  └── LODMaxCount × 1.2
```

### 렌더링 최적화

```
□ ISM 메시 최적화
  └── < 500 삼각형

□ 그림자 설정
  ├── High LOD만 그림자
  └── ISM 그림자 OFF

□ 머티리얼 단순화
  └── ISM용 저비용 머티리얼
```

### 테스트

```
□ 단계별 테스트
  ├── 1000마리 테스트
  ├── 3000마리 테스트
  └── 5000마리 테스트

□ 프로파일링
  ├── Unreal Insights 캡처
  ├── stat 명령어 확인
  └── 병목 지점 식별

□ 빌드 테스트
  └── Development 빌드로 최종 확인
```

---

## 10. 성능 튜닝 가이드

### 증상별 해결책

**CPU 병목일 때:**

| 증상 | 원인 | 해결 |
|------|------|------|
| Processor 시간 높음 | 복잡한 로직 | LOD별 분리 |
| FlushCommands 스파이크 | Defer 과다 | 직접 수정으로 변경 |
| 캐시 미스 | Fragment 너무 큼 | Fragment 최소화 |

**GPU 병목일 때:**

| 증상 | 원인 | 해결 |
|------|------|------|
| 드로우 콜 많음 | Actor 과다 | LODMaxCount 줄이기 |
| 버텍스 처리 느림 | 메시 복잡 | 저폴리 메시 |
| 그림자 느림 | 그림자 과다 | 거리별 그림자 OFF |

**메모리 병목일 때:**

| 증상 | 원인 | 해결 |
|------|------|------|
| GC 스파이크 | UObject 과다 | Fragment 사용 |
| OOM | 데이터 과다 | Fragment 최소화 |

---

## 11. 마무리

### 핵심 요약

1. **측정 먼저**: 프로파일링 없이 최적화 없다
2. **LOD가 핵심**: 적절한 LOD 설정이 성능의 80%
3. **배치 처리**: 개별 처리 대신 청크 단위
4. **데이터 지향**: Fragment 최소화, Shared 활용
5. **점진적 최적화**: 측정 → 분석 → 최적화 → 반복

### 기대 성과

올바르게 구현하면:

```
목표 달성 가능!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

몬스터 수: 1000-5000마리 ✓
프레임: 60 FPS 유지 ✓
CPU 시간: < 5ms ✓
메모리: < 100MB ✓

기존 Actor 방식 대비: 10-20배 성능 향상!
```

---

## 부록: 참조 소스 경로

```
엔진 코어:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Source\Runtime\MassEntity\

MassGameplay 플러그인:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\MassGameplay\

StateTree 플러그인:
C:\Program Files\Epic Games\UE_5.7.1\UE_5.7\Engine\Plugins\Runtime\GameplayStateTree\
```

---

**문서 끝** - 이제 실전에서 Mass AI로 수천 마리 몬스터를 돌려보세요!
