# Mass AI 시스템 개요

> **문서 목적**: Mass AI의 기본 개념과 전통적 Actor 기반 AI와의 차이점 이해

---

## 1. Mass AI란?

Mass AI는 언리얼 엔진 5에서 도입된 **데이터 지향 설계(Data-Oriented Design, DOD)** 기반의 AI 프레임워크입니다. 전통적인 객체 지향 프로그래밍(OOP) 기반의 Actor 시스템과 달리, **Entity Component System (ECS)** 패턴을 채택하여 대량의 AI 엔티티를 효율적으로 관리합니다.

### 핵심 특징

1. **데이터 중심 설계**: 행동(코드)과 데이터(상태)를 분리
2. **배치 처리**: 동일 유형의 엔티티를 한 번에 처리
3. **캐시 친화적**: 연속 메모리 배치로 CPU 캐시 효율 극대화
4. **확장성**: 수천~수만 개의 엔티티 동시 처리 가능

---

## 2. ECS (Entity Component System) 패턴

Mass AI는 순수한 ECS 패턴을 따릅니다:

### 구성 요소

```
┌─────────────────────────────────────────────────────────────┐
│                     ENTITY (엔티티)                          │
│  - 고유 식별자 (FMassEntityHandle)                          │
│  - 데이터 없음, Fragment들의 조합을 가리키는 핸들           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   FRAGMENT (프래그먼트)                      │
│  - 순수 데이터 구조체 (FMassFragment)                        │
│  - 예: 위치, 속도, 체력, 타겟 정보 등                       │
│  - 행동 로직 없음                                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   PROCESSOR (프로세서)                       │
│  - 로직/행동 담당 (UMassProcessor)                          │
│  - Fragment 데이터를 읽고/수정                              │
│  - 배치 단위로 엔티티 처리                                  │
└─────────────────────────────────────────────────────────────┘
```

### 데이터 흐름

```
매 프레임:
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│  Movement    │ -> │  Combat      │ -> │  Animation   │
│  Processor   │    │  Processor   │    │  Processor   │
└──────────────┘    └──────────────┘    └──────────────┘
       │                   │                   │
       ▼                   ▼                   ▼
┌──────────────────────────────────────────────────────┐
│              Entity Data (Fragments)                  │
│  [Pos1][Vel1][HP1] [Pos2][Vel2][HP2] [Pos3][Vel3]... │
│         Entity 1         Entity 2       Entity 3     │
└──────────────────────────────────────────────────────┘
```

---

## 3. 전통적 Actor 기반 AI vs Mass AI

### 메모리 레이아웃 비교

**Actor 기반 (객체 지향)**
```
Memory:
┌────────┬────────┬────────┬────────┬────────┐
│Actor1  │ ?Gap?  │Actor2  │ ?Gap?  │Actor3  │  <- 분산된 메모리
│ Pos    │        │ Pos    │        │ Pos    │
│ Vel    │        │ Vel    │        │ Vel    │
│ HP     │        │ HP     │        │ HP     │
│ ...    │        │ ...    │        │ ...    │
└────────┴────────┴────────┴────────┴────────┘
❌ 캐시 미스 빈번
❌ 불필요한 데이터도 로드
```

**Mass AI (데이터 지향)**
```
Memory:
Position Array: [Pos1][Pos2][Pos3][Pos4][Pos5]...  <- 연속 메모리
Velocity Array: [Vel1][Vel2][Vel3][Vel4][Vel5]...  <- 연속 메모리
Health Array:   [HP1] [HP2] [HP3] [HP4] [HP5] ...  <- 연속 메모리

✅ 캐시 히트율 극대화
✅ 필요한 데이터만 로드
✅ SIMD 최적화 가능
```

### 성능 비교표

| 항목 | Actor 기반 | Mass AI | 차이 |
|------|------------|---------|------|
| **엔티티당 메모리** | ~2KB+ (AActor 오버헤드) | ~100B (Fragment만) | ~20배 감소 |
| **Tick 오버헤드** | 개별 가상 함수 호출 | 배치 처리 | ~10배 감소 |
| **캐시 효율성** | 30-50% 히트율 | 90%+ 히트율 | ~2배 향상 |
| **드로우 콜** | 개별 호출 | ISM 배치 | ~100배 감소 |
| **동시 처리 가능 수** | 수십~수백 | 수천~수만 | ~100배 증가 |

### 처리 방식 비교

**Actor 기반**
```cpp
// 각 Actor가 개별적으로 Tick
void AMonster::Tick(float DeltaTime)
{
    // 위치 업데이트
    FVector Direction = (PlayerLocation - GetActorLocation()).GetSafeNormal();
    AddMovementInput(Direction, Speed * DeltaTime);

    // 공격 체크
    if (CanAttack()) { Attack(); }
}
// 1000마리 = 1000번의 개별 Tick 호출 (가상 함수 오버헤드 포함)
```

**Mass AI**
```cpp
// Processor가 모든 엔티티를 배치 처리
void UMonsterMovementProcessor::Execute(FMassEntityManager& EntityManager,
                                         FMassExecutionContext& Context)
{
    // 모든 몬스터의 위치/속도를 한 번에 처리
    EntityQuery.ForEachEntityChunk(EntityManager, Context,
        [](FMassExecutionContext& Context)
        {
            auto Positions = Context.GetMutableFragmentView<FTransformFragment>();
            auto Velocities = Context.GetFragmentView<FMassVelocityFragment>();

            for (int32 i = 0; i < Context.GetNumEntities(); ++i)
            {
                // 캐시 친화적 순차 접근
                Positions[i].Transform.AddToTranslation(
                    Velocities[i].Value * Context.GetDeltaTimeSeconds());
            }
        });
}
// 1000마리 = 1번의 Processor 호출 + 최적화된 루프
```

---

## 4. 성능 이점의 원리

### 4.1 CPU 캐시 효율성

현대 CPU는 캐시 라인(보통 64바이트) 단위로 메모리를 읽습니다:

```
Actor 기반:
캐시 라인 로드 -> [Actor1 일부] -> 대부분 불필요한 데이터
다음 Actor 접근 -> 캐시 미스 -> 메모리 재로드 (100+ 사이클)

Mass AI:
캐시 라인 로드 -> [Pos1][Pos2][Pos3][Pos4]... -> 모두 필요한 데이터
순차 접근 -> 캐시 히트 -> 즉시 사용 가능 (~1 사이클)
```

### 4.2 분기 예측 최적화

```cpp
// Actor 기반: 다양한 타입, 예측 어려움
for (AActor* Actor : Actors)
{
    Actor->Tick(DeltaTime);  // 가상 함수 - 분기 예측 실패 가능
}

// Mass AI: 동일 타입 배치 처리
for (int32 i = 0; i < NumEntities; ++i)
{
    Positions[i] += Velocities[i] * DeltaTime;  // 직접 연산 - 분기 없음
}
```

### 4.3 SIMD 벡터화

Mass AI의 연속 메모리 배치는 컴파일러 자동 벡터화를 가능하게 합니다:

```cpp
// 컴파일러가 자동으로 SIMD 명령어 생성 가능
// 한 번에 4-8개 엔티티 동시 처리
for (int32 i = 0; i < NumEntities; i += 4)
{
    // AVX/SSE 명령어로 4개 엔티티 동시 처리
    _mm_store_ps(&Positions[i],
                 _mm_add_ps(_mm_load_ps(&Positions[i]),
                            _mm_mul_ps(_mm_load_ps(&Velocities[i]), DeltaTime4)));
}
```

---

## 5. Mass AI 적용 시나리오

### 적합한 경우

| 시나리오 | 이유 |
|----------|------|
| 대량 몬스터 (뱀파이어 서바이벌) | 수천 개 동시 처리 필요 |
| 군중 시뮬레이션 | 단순 행동의 대량 엔티티 |
| RTS 유닛 | 수백 유닛 동시 제어 |
| 탄막 슈팅 | 수천 발사체 처리 |
| 파티클 시스템 대체 | 상호작용 가능한 파티클 |

### 부적합한 경우

| 시나리오 | 이유 |
|----------|------|
| 복잡한 개별 AI | 상태 기계가 복잡할 때 |
| 소수 보스 몬스터 | Actor 기반이 더 직관적 |
| 플레이어 캐릭터 | 개별 처리가 필요 |
| 물리 기반 상호작용 | 엔진 물리 시스템 필요 |

---

## 6. 핵심 클래스 요약

### 엔진 코어 (`Engine\Source\Runtime\MassEntity`)

| 클래스 | 역할 | 주요 파일 |
|--------|------|-----------|
| `FMassEntityManager` | 엔티티 생성/삭제/관리의 중앙 허브 | `MassEntityManager.h` |
| `FMassEntityHandle` | 엔티티 식별 핸들 | `MassEntityHandle.h` |
| `FMassFragment` | 데이터 구조체 기본 클래스 | `MassEntityElementTypes.h` |
| `UMassProcessor` | 로직 처리기 기본 클래스 | `MassProcessor.h` |
| `FMassEntityQuery` | 엔티티 필터링 쿼리 | `MassEntityQuery.h` |

### MassGameplay 플러그인 (`Engine\Plugins\Runtime\MassGameplay`)

| 모듈 | 역할 |
|------|------|
| `MassSpawner` | 대량 엔티티 스폰 |
| `MassRepresentation` | 시각적 표현 (ISM, Actor) |
| `MassLOD` | LOD 관리 |
| `MassMovement` | 이동 처리 |
| `MassSignals` | 이벤트 통신 |
| `MassSmartObjects` | 상호작용 오브젝트 |
| `MassActors` | Actor 통합 |

---

## 7. 다음 단계

Mass AI의 기본 개념을 이해했다면, 다음 문서에서 코어 아키텍처를 상세히 살펴보겠습니다:

- **다음**: [02_CoreArchitecture.md](02_CoreArchitecture.md) - Entity, Fragment, Processor, Archetype 시스템 상세 분석
